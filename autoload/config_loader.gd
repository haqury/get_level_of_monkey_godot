extends Node

var game_config: Dictionary = {}
var balance: Dictionary = {}
var brainlink_paths: Dictionary = {}


func _ready() -> void:
	reload()


const USER_CONFIG_PATH := "user://user_game_config.json"


func reload() -> void:
	game_config = _load_json("res://config/game_config.json", _default_game_config())
	var user_cfg := _load_json(USER_CONFIG_PATH, {})
	if not user_cfg.is_empty():
		game_config = _deep_merge(game_config, user_cfg)
	balance = _load_json("res://config/balance.json", {})
	brainlink_paths = _load_json("res://config/brainlink_path.json", {})
	GameControls.apply_from_config(game_config)


func save_user_settings(patch: Dictionary) -> void:
	var user_cfg := _load_json(USER_CONFIG_PATH, {})
	user_cfg = _deep_merge(user_cfg, patch)
	var f := FileAccess.open(USER_CONFIG_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(user_cfg, "\t"))
	reload()
	if patch.has("controls"):
		GameControls.apply_from_config(game_config)


func _deep_merge(base: Dictionary, over: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for k in over.keys():
		var v = over[k]
		if typeof(v) == TYPE_DICTIONARY and typeof(out.get(k)) == TYPE_DICTIONARY:
			out[k] = _deep_merge(out[k], v)
		else:
			out[k] = v
	return out


func _load_json(path: String, fallback: Dictionary) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("Missing config: %s" % path)
		return fallback
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return fallback
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return fallback
	return parsed


func _default_game_config() -> Dictionary:
	return {
		"window": {"title": "Get Level of Monkey", "width": 1280, "height": 720, "fullscreen": false},
		"player": {
			"name": "Player",
			"initial_hp": 3,
			"initial_energy": 100,
			"energy_regen_rate": 5.0,
			"move_cost": 100,
			"move_speed": 5.0,
			"cheater_mode": false,
		},
		"brainlink": {"enabled": false, "memory_name": "brainlink_data", "check_interval": 0.016},
		"controls": {
			"keyboard_enabled": true,
			"gamepad_enabled": false,
			"keyboard": {
				"up": "arrow_up",
				"down": "arrow_down",
				"left": "arrow_left",
				"right": "arrow_right",
				"action": "space",
				"sit_pause": "p",
			},
		},
		"locale": "ru",
		"multiplayer": {
			"enabled": true,
			"default_port": 17777,
			"tick_rate_hz": 20,
			"connect_timeout_sec": 10,
			"minigame_sync_hz": 10,
		},
	}
