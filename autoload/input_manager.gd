extends Node

signal action_pressed
signal sit_pause_pressed

const SOURCE_NONE := "none"
const SOURCE_KEYBOARD := "keyboard"
const SOURCE_BRAINLINK := "brainlink"

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
var _last_sent_event: String = ""
var _cached_move: Vector2 = Vector2.ZERO
var _action_sit_hold: bool = false

const EVENT_MAP := {
	"ml": Vector2.LEFT,
	"mr": Vector2.RIGHT,
	"mu": Vector2.UP,
	"md": Vector2.DOWN,
}


func _ready() -> void:
	_load_brainlink_send_flags()


func _load_brainlink_send_flags() -> void:
	var bl: Dictionary = ConfigLoader.game_config.get("brainlink", {})
	send_keyboard_events = bool(bl.get("send_keyboard_events", true))
	send_brainlink_events = bool(bl.get("send_brainlink_events", true))
	send_to_history = bool(bl.get("send_to_history", true))
	send_to_ml = bool(bl.get("send_to_ml", false))


func _process(_delta: float) -> void:
	keyboard_active = (
		Input.is_action_pressed("move_left")
		or Input.is_action_pressed("move_right")
		or Input.is_action_pressed("move_up")
		or Input.is_action_pressed("move_down")
	)
	if Input.is_action_just_pressed("action"):
		action_pressed.emit()
	if Input.is_action_just_pressed("sit_pause"):
		sit_pause_pressed.emit()
	_update_movement_state()
	_send_outbound_brainlink_events()


func get_movement_vector() -> Vector2:
	return _cached_move


func is_sitting() -> bool:
	return _action_sit_hold


func clear_state() -> void:
	brainlink_vector = Vector2.ZERO
	_last_keyboard_event = ""
	_current_keyboard_event = ""
	_last_sent_event = ""
	_cached_move = Vector2.ZERO
	movement_source = SOURCE_NONE


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
	var kb := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	_action_sit_hold = Input.is_action_pressed("action") and kb.length_squared() <= 0.0001
	if _action_sit_hold:
		movement_source = SOURCE_NONE
		_is_using_brainlink = false
		_cached_move = Vector2.ZERO
		_current_keyboard_event = ""
		_keyboard_event_recordable = false
		_last_keyboard_event = ""
		return
	if kb.length_squared() > 0.01:
		kb = kb.normalized()
		_track_keyboard_from_vector(kb)
		_keyboard_event_recordable = _is_cardinal(kb)
		_current_keyboard_event = _last_keyboard_event if _keyboard_event_recordable else ""
		movement_source = SOURCE_KEYBOARD
		_is_using_brainlink = false
		_cached_move = kb
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


func _send_outbound_brainlink_events() -> void:
	if not BrainLinkBridge.connected:
		return
	if not send_to_history and not send_to_ml:
		return
	if _action_sit_hold:
		var stop_allowed := send_keyboard_events or send_brainlink_events
		if stop_allowed and _last_sent_event != "stop":
			_last_sent_event = "stop"
			var stop_type := 2 if send_to_ml else 1
			BrainLinkBridge.send_event("stop", stop_type)
		return
	var mv := _cached_move
	var effective := "ne"
	if mv.x < -0.01 and absf(mv.y) < 0.01:
		effective = "ml"
	elif mv.x > 0.01 and absf(mv.y) < 0.01:
		effective = "mr"
	elif mv.y > 0.01 and absf(mv.x) < 0.01:
		effective = "mu"
	elif mv.y < -0.01 and absf(mv.x) < 0.01:
		effective = "md"
	var allow := false
	if effective == "ne":
		allow = true
	elif movement_source == SOURCE_KEYBOARD and send_keyboard_events and _keyboard_event_recordable:
		allow = true
	elif movement_source == SOURCE_BRAINLINK and send_brainlink_events:
		allow = true
	if not allow or effective == _last_sent_event:
		return
	_last_sent_event = effective
	var command_type := 2 if send_to_ml else 1
	BrainLinkBridge.send_event(effective, command_type)


func _track_keyboard_from_vector(v: Vector2) -> void:
	if abs(v.x) >= abs(v.y):
		_last_keyboard_event = "ml" if v.x < 0 else "mr"
	else:
		_last_keyboard_event = "mu" if v.y < 0 else "md"


func _is_cardinal(v: Vector2) -> bool:
	return absf(v.x) < 0.01 or absf(v.y) < 0.01
