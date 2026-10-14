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
	var kb: Dictionary = cfg.get("controls", {}).get("keyboard", {})
	if kb.is_empty():
		return
	for config_key in CONFIG_KEY_TO_ACTION.keys():
		var action_name: String = CONFIG_KEY_TO_ACTION[config_key]
		_bind_action(action_name, str(kb.get(config_key, _default_alias(config_key))))


static func keyboard_from_config(cfg: Dictionary = ConfigLoader.game_config) -> Dictionary:
	var kb: Dictionary = cfg.get("controls", {}).get("keyboard", {})
	if kb.is_empty():
		return _default_keyboard()
	return kb.duplicate(true)


static func save_keyboard_binding(config_key: String, alias: String) -> void:
	var kb := keyboard_from_config()
	kb[config_key] = alias.strip_edges().to_lower()
	ConfigLoader.save_user_settings({"controls": {"keyboard": kb}})
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


static func _bind_action(action_name: String, key_name: String) -> void:
	if not InputMap.has_action(action_name):
		return
	InputMap.action_erase_events(action_name)
	if key_name.is_empty():
		return
	var keycode: int = int(KEY_ALIASES.get(key_name.to_lower(), KEY_NONE))
	if keycode == KEY_NONE:
		return
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action_name, ev)
