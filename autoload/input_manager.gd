extends Node

signal action_pressed
signal sit_pause_pressed

const SOURCE_NONE := "none"
const SOURCE_KEYBOARD := "keyboard"
const SOURCE_BRAINLINK := "brainlink"

const GROUND_TRUTH_RESEND_INTERVAL := 0.35

var keyboard_active: bool = false
var brainlink_vector: Vector2 = Vector2.ZERO
var brainlink_confidence: float = 0.0
var brainlink_probs: Dictionary = {}
var brainlink_last_event: String = ""
var movement_source: String = SOURCE_NONE

var send_keyboard_events: bool = true
var send_brainlink_events: bool = true
var send_to_history: bool = true
var send_to_ml: bool = false

var _last_keyboard_event: String = ""
var _current_keyboard_event: String = ""
var _keyboard_event_recordable: bool = false
var _is_using_brainlink: bool = false
var _cached_move: Vector2 = Vector2.ZERO
var _action_sit_hold: bool = false

var _held_ground_truth: String = ""
var _ground_truth_resend_timer: float = 0.0

const EVENT_MAP := {
	"ml": Vector2.LEFT,
	"mr": Vector2.RIGHT,
	"mu": Vector2.UP,
	"md": Vector2.DOWN,
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_brainlink_send_flags()


func _load_brainlink_send_flags() -> void:
	var bl: Dictionary = ConfigLoader.game_config.get("brainlink", {})
	send_keyboard_events = bool(bl.get("send_keyboard_events", true))
	send_brainlink_events = bool(bl.get("send_brainlink_events", true))
	send_to_history = bool(bl.get("send_to_history", true))
	send_to_ml = bool(bl.get("send_to_ml", false))


func _input(event: InputEvent) -> void:
	if GameControls.gamepad_enabled():
		return
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	keyboard_active = GameControls.get_keyboard_vector().length_squared() > 0.01
	if GameControls.is_config_action_just_pressed("action"):
		action_pressed.emit()
	if GameControls.is_config_action_just_pressed("sit_pause"):
		sit_pause_pressed.emit()
	_update_movement_state()
	_send_player_ground_truth(delta)


func get_movement_vector() -> Vector2:
	return _cached_move


func is_sitting() -> bool:
	return _action_sit_hold


func clear_state() -> void:
	brainlink_vector = Vector2.ZERO
	_last_keyboard_event = ""
	_current_keyboard_event = ""
	_cached_move = Vector2.ZERO
	movement_source = SOURCE_NONE
	_held_ground_truth = ""
	_ground_truth_resend_timer = 0.0


func set_brainlink_event(code: String) -> void:
	brainlink_last_event = code
	if code == "" or code == "ne" or code == "stop":
		brainlink_vector = Vector2.ZERO
		return
	if EVENT_MAP.has(code):
		brainlink_vector = EVENT_MAP[code]


func get_current_keyboard_event() -> String:
	return _current_keyboard_event if _keyboard_event_recordable else ""


func is_using_brainlink() -> bool:
	return _is_using_brainlink


func last_keyboard_event_for_ml() -> String:
	return _last_keyboard_event


func _update_movement_state() -> void:
	var kb := GameControls.get_keyboard_vector()
	var pad := Vector2.ZERO
	if kb.length_squared() <= 0.0001:
		pad = GameControls.get_gamepad_vector()
	_action_sit_hold = (
		GameControls.is_config_action_pressed("action")
		and kb.length_squared() <= 0.0001
		and pad.length_squared() <= 0.0001
	)
	if _action_sit_hold:
		movement_source = SOURCE_NONE
		_is_using_brainlink = false
		_cached_move = Vector2.ZERO
		_current_keyboard_event = ""
		_keyboard_event_recordable = false
		_last_keyboard_event = ""
		return
	if kb.length_squared() > 0.01:
		_track_keyboard_from_vector(kb)
		_keyboard_event_recordable = _is_cardinal(kb)
		_current_keyboard_event = _last_keyboard_event if _keyboard_event_recordable else ""
		movement_source = SOURCE_KEYBOARD
		_is_using_brainlink = false
		_cached_move = kb
	elif pad.length_squared() > 0.01:
		var pn := pad.normalized()
		_track_keyboard_from_vector(pn)
		_keyboard_event_recordable = _is_cardinal(pn)
		_current_keyboard_event = _last_keyboard_event if _keyboard_event_recordable else ""
		movement_source = SOURCE_KEYBOARD
		_is_using_brainlink = false
		_cached_move = pn
	elif keyboard_active:
		movement_source = SOURCE_NONE
		_current_keyboard_event = ""
		_keyboard_event_recordable = false
		_is_using_brainlink = false
		_cached_move = Vector2.ZERO
	elif brainlink_vector.length_squared() > 0.01:
		movement_source = SOURCE_BRAINLINK
		_current_keyboard_event = ""
		_keyboard_event_recordable = false
		_is_using_brainlink = true
		var scale := 1.0
		if brainlink_confidence > 0.0:
			var bl: Dictionary = ConfigLoader.game_config.get("brainlink", {})
			var min_c := float(bl.get("min_confidence", 0.1))
			var full_c := float(bl.get("full_confidence", 0.4))
			scale = clampf(
				(brainlink_confidence - min_c) / maxf(full_c - min_c, 0.001),
				0.2,
				1.0,
			)
		_cached_move = brainlink_vector.normalized() * scale
	else:
		movement_source = SOURCE_NONE
		_current_keyboard_event = ""
		_keyboard_event_recordable = false
		_is_using_brainlink = false
		_cached_move = Vector2.ZERO

	if kb.length_squared() > 0.01:
		_last_keyboard_event = _current_keyboard_event if _keyboard_event_recordable else ""
	else:
		_last_keyboard_event = ""


## Player ground truth for BrainLink (COMMAND_TYPE=2). Never derived from SHM EVENT_CODE.
func _send_player_ground_truth(delta: float) -> void:
	if not BrainLinkBridge.can_send_ground_truth():
		return
	if not send_keyboard_events:
		return
	if not send_to_ml and not send_to_history:
		return

	var label := _manual_player_label()
	if label.is_empty():
		if _held_ground_truth.is_empty():
			return
		var closed := _held_ground_truth
		_held_ground_truth = ""
		_ground_truth_resend_timer = 0.0
		if closed != "ne":
			BrainLinkBridge.send_ground_truth("ne")
		return

	_ground_truth_resend_timer += delta
	var label_changed := label != _held_ground_truth
	if label_changed or _ground_truth_resend_timer >= GROUND_TRUTH_RESEND_INTERVAL:
		_held_ground_truth = label
		_ground_truth_resend_timer = 0.0
		BrainLinkBridge.send_ground_truth(label)


func _manual_player_label() -> String:
	if _action_sit_hold:
		return "stop"
	var kb := GameControls.get_keyboard_vector()
	if kb.length_squared() > 0.01:
		return _direction_label_from_vector(kb)
	if GameControls.gamepad_enabled():
		var pad := GameControls.get_gamepad_vector()
		if pad.length_squared() > 0.01:
			return _direction_label_from_vector(pad)
	return ""


func _direction_label_from_vector(v: Vector2) -> String:
	if v.length_squared() <= 0.0001:
		return ""
	if absf(v.x) >= absf(v.y):
		return "ml" if v.x < 0.0 else "mr"
	return "mu" if v.y < 0.0 else "md"


func _track_keyboard_from_vector(v: Vector2) -> void:
	_last_keyboard_event = _direction_label_from_vector(v)


func _is_cardinal(v: Vector2) -> bool:
	return absf(v.x) < 0.01 or absf(v.y) < 0.01
