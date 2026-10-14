class_name GameControls
extends RefCounted

const KEY_ALIASES := {
	"space": KEY_SPACE,
	"p": KEY_P,
	"arrow_up": KEY_UP,
	"arrow_down": KEY_DOWN,
	"arrow_left": KEY_LEFT,
	"arrow_right": KEY_RIGHT,
	"w": KEY_W,
	"a": KEY_A,
	"s": KEY_S,
	"d": KEY_D,
}

const CONFIG_KEY_TO_ACTION := {
	"up": "move_up",
	"down": "move_down",
	"left": "move_left",
	"right": "move_right",
	"action": "action",
	"sit_pause": "sit_pause",
}

const CONTROL_ROWS := [
	{"config": "up", "label_key": "settings.key_up"},
	{"config": "down", "label_key": "settings.key_down"},
	{"config": "left", "label_key": "settings.key_left"},
	{"config": "right", "label_key": "settings.key_right"},
	{"config": "action", "label_key": "settings.key_sit"},
	{"config": "sit_pause", "label_key": "settings.key_sit_pause"},
]


static func apply_from_config(cfg: Dictionary) -> void:
	var controls: Dictionary = cfg.get("controls", {})
	var kb: Dictionary = controls.get("keyboard", {})
	var keyboard_on := bool(controls.get("keyboard_enabled", true))
	var gamepad_on := bool(controls.get("gamepad_enabled", false))
	for config_key in CONFIG_KEY_TO_ACTION.keys():
		var action_name: String = CONFIG_KEY_TO_ACTION[config_key]
		if not InputMap.has_action(action_name):
			continue
		InputMap.action_erase_events(action_name)
		if keyboard_on:
			_add_keyboard_event(action_name, str(kb.get(config_key, _default_alias(config_key))))
		if gamepad_on:
			_add_gamepad_events(action_name, config_key)
	if not gamepad_on:
		strip_all_joypad_bindings()


static func keyboard_enabled(cfg: Dictionary = ConfigLoader.game_config) -> bool:
	return bool(cfg.get("controls", {}).get("keyboard_enabled", true))


static func gamepad_enabled(cfg: Dictionary = ConfigLoader.game_config) -> bool:
	return bool(cfg.get("controls", {}).get("gamepad_enabled", false))


static func set_keyboard_enabled(value: bool) -> void:
	ConfigLoader.save_user_settings({"controls": {"keyboard_enabled": value}})


static func set_gamepad_enabled(value: bool) -> void:
	ConfigLoader.save_user_settings({"controls": {"gamepad_enabled": value}})


static func strip_all_joypad_bindings() -> void:
	for action_name in InputMap.get_actions():
		var action := str(action_name)
		var to_erase: Array[InputEvent] = []
		for ev in InputMap.action_get_events(action):
			if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
				to_erase.append(ev)
		for ev in to_erase:
			InputMap.action_erase_event(action, ev)


static func get_gamepad_vector() -> Vector2:
	if not gamepad_enabled():
		return Vector2.ZERO
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


static func is_config_action_pressed(config_key: String) -> bool:
	var action_name := str(CONFIG_KEY_TO_ACTION.get(config_key, ""))
	if action_name.is_empty():
		return false
	if not keyboard_enabled() and not gamepad_enabled():
		return false
	if keyboard_enabled() and not gamepad_enabled():
		var kb_cfg := keyboard_from_config()
		return _is_alias_pressed(str(kb_cfg.get(config_key, "")))
	if gamepad_enabled() and not keyboard_enabled():
		return Input.is_action_pressed(action_name)
	if keyboard_enabled():
		var kb_cfg := keyboard_from_config()
		if _is_alias_pressed(str(kb_cfg.get(config_key, ""))):
			return true
	return Input.is_action_pressed(action_name)


static func is_config_action_just_pressed(config_key: String) -> bool:
	var action_name := str(CONFIG_KEY_TO_ACTION.get(config_key, ""))
	if action_name.is_empty():
		return false
	if not keyboard_enabled() and not gamepad_enabled():
		return false
	return Input.is_action_just_pressed(action_name)


static func get_keyboard_vector() -> Vector2:
	if not keyboard_enabled():
		return Vector2.ZERO
	var kb_cfg := keyboard_from_config()
	var x := 0.0
	var y := 0.0
	if _is_alias_pressed(str(kb_cfg.get("left", "arrow_left"))):
		x -= 1.0
	if _is_alias_pressed(str(kb_cfg.get("right", "arrow_right"))):
		x += 1.0
	if _is_alias_pressed(str(kb_cfg.get("up", "arrow_up"))):
		y -= 1.0
	if _is_alias_pressed(str(kb_cfg.get("down", "arrow_down"))):
		y += 1.0
	if x == 0.0 and y == 0.0:
		return Vector2.ZERO
	return Vector2(x, y).normalized()


static func is_action_key_pressed(config_key: String) -> bool:
	return is_config_action_pressed(config_key)


static func keyboard_from_config(cfg: Dictionary = ConfigLoader.game_config) -> Dictionary:
	var kb: Dictionary = cfg.get("controls", {}).get("keyboard", {})
	if kb.is_empty():
		return _default_keyboard()
	return kb.duplicate(true)


static func save_keyboard_binding(config_key: String, alias: String) -> void:
	var kb := keyboard_from_config()
	kb[config_key] = alias.strip_edges().to_lower()
	var controls: Dictionary = ConfigLoader.game_config.get("controls", {}).duplicate(true)
	controls["keyboard"] = kb
	ConfigLoader.save_user_settings({"controls": controls})
	apply_from_config(ConfigLoader.game_config)


static func clear_keyboard_binding(config_key: String) -> void:
	save_keyboard_binding(config_key, "")


static func alias_from_input_event(event: InputEventKey) -> String:
	var code: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	for alias in KEY_ALIASES.keys():
		if KEY_ALIASES[alias] == code:
			return alias
	var label := OS.get_keycode_string(code)
	if label.is_empty():
		return ""
	return label.to_lower()


static func display_label(alias: String) -> String:
	if alias.is_empty():
		return "—"
	match alias:
		"arrow_up":
			return "↑"
		"arrow_down":
			return "↓"
		"arrow_left":
			return "←"
		"arrow_right":
			return "→"
		"space":
			return "Space"
		_:
			return alias.to_upper()


static func _default_keyboard() -> Dictionary:
	return {
		"up": "arrow_up",
		"down": "arrow_down",
		"left": "arrow_left",
		"right": "arrow_right",
		"action": "space",
		"sit_pause": "p",
	}


static func _default_alias(config_key: String) -> String:
	return str(_default_keyboard().get(config_key, ""))


static func _is_alias_pressed(alias: String) -> bool:
	if alias.is_empty():
		return false
	var keycode: int = int(KEY_ALIASES.get(alias.to_lower(), KEY_NONE))
	if keycode == KEY_NONE:
		return false
	return Input.is_physical_key_pressed(keycode)


static func _add_keyboard_event(action_name: String, key_name: String) -> void:
	if key_name.is_empty():
		return
	var keycode: int = int(KEY_ALIASES.get(key_name.to_lower(), KEY_NONE))
	if keycode == KEY_NONE:
		return
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action_name, ev)


static func _add_gamepad_events(action_name: String, config_key: String) -> void:
	match config_key:
		"left":
			_add_joy_button(action_name, JOY_BUTTON_DPAD_LEFT)
			_add_joy_axis(action_name, JOY_AXIS_LEFT_X, -1.0)
		"right":
			_add_joy_button(action_name, JOY_BUTTON_DPAD_RIGHT)
			_add_joy_axis(action_name, JOY_AXIS_LEFT_X, 1.0)
		"up":
			_add_joy_button(action_name, JOY_BUTTON_DPAD_UP)
			_add_joy_axis(action_name, JOY_AXIS_LEFT_Y, -1.0)
		"down":
			_add_joy_button(action_name, JOY_BUTTON_DPAD_DOWN)
			_add_joy_axis(action_name, JOY_AXIS_LEFT_Y, 1.0)
		"action":
			_add_joy_button(action_name, JOY_BUTTON_A)
			_add_joy_button(action_name, JOY_BUTTON_X)
		"sit_pause":
			_add_joy_button(action_name, JOY_BUTTON_START)
			_add_joy_button(action_name, JOY_BUTTON_BACK)


static func _add_joy_button(action_name: String, button_index: JoyButton) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button_index
	InputMap.action_add_event(action_name, ev)


static func _add_joy_axis(action_name: String, axis: JoyAxis, axis_value: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = axis_value
	InputMap.action_add_event(action_name, ev)
