extends Node

signal scene_changed(scene_id: String)

const SCENE_PATHS := {
	"main_menu": "res://scenes/main_menu/main_menu.tscn",
	"game_session": "res://scenes/game/game_session.tscn",
	"cave": "res://scenes/cave/cave.tscn",
	"kitchen": "res://scenes/kitchen/kitchen.tscn",
	"minigame": "res://scenes/minigame/minigame.tscn",
}

var _session: Node = null


func go_to_main_menu() -> void:
	GameState.in_game = false
	GameState.current_scene_id = "main_menu"
	_unpause_for_scene_change()
	get_tree().change_scene_to_file(SCENE_PATHS["main_menu"])


func start_solo_game(load_save: bool = false) -> void:
	GameState.mp_role = GameState.MpRole.OFFLINE
	GameState.in_game = true
	var start_scene := "cave"
	if load_save:
		var data: Variant = SaveManager.load_game()
		if data != null and typeof(data) == TYPE_DICTIONARY:
			var save_data: Dictionary = data
			ProgressionSystem.from_save_dict(save_data)
			start_scene = str(save_data.get("current_scene", "cave"))
	else:
		_reset_progression_defaults()
	GameState.startup_world_scene = start_scene
	GameState.current_scene_id = start_scene
	_unpause_for_scene_change()
	get_tree().change_scene_to_file(SCENE_PATHS["game_session"])


func start_host_game() -> void:
	GameState.mp_role = GameState.MpRole.HOST
	GameState.local_player_id = 0
	GameState.in_game = true
	_reset_progression_defaults()
	GameState.startup_world_scene = "cave"
	GameState.current_scene_id = "cave"
	_unpause_for_scene_change()
	get_tree().change_scene_to_file(SCENE_PATHS["game_session"])


func client_enter_game() -> void:
	GameState.in_game = true
	if get_tree().current_scene == null or not get_tree().current_scene.has_method("get_world_container"):
		_unpause_for_scene_change()
		get_tree().change_scene_to_file(SCENE_PATHS["game_session"])


func switch_to(scene_id: String, extra: Dictionary = {}) -> void:
	if scene_id == "main_menu":
		go_to_main_menu()
		return
	if GameState.is_client():
		return
	var root := _get_session()
	if root == null:
		push_error("No game session for switch_to(%s)" % scene_id)
		return
	if scene_id != GameState.current_scene_id:
		_auto_save()
	GameState.current_scene_id = scene_id
	if extra.has("monkey_mode"):
		GameState.monkey_mode = str(extra["monkey_mode"])
	GameState.pending_scene_extra = extra
	root.load_world_scene(scene_id, extra)
	if GameState.is_host() and GameState.is_online():
		(get_node("/root/NetworkManager") as Node).call("host_broadcast_scene_change", scene_id, extra)
	scene_changed.emit(scene_id)


func _get_session() -> Node:
	var cs := get_tree().current_scene
	if cs and cs.has_method("load_world_scene"):
		return cs
	return null


func _auto_save() -> void:
	if not GameState.in_game or GameState.is_client():
		return
	if GameState.current_scene_id == "main_menu":
		return
	var data: Dictionary = ProgressionSystem.to_save_dict()
	data["current_scene"] = GameState.current_scene_id
	SaveManager.save_game(data)


func _apply_save() -> void:
	var data: Variant = SaveManager.load_game()
	if data == null or typeof(data) != TYPE_DICTIONARY:
		_reset_progression_defaults()
		return
	ProgressionSystem.from_save_dict(data as Dictionary)


func _unpause_for_scene_change() -> void:
	if GameUI.has_method("close_pause"):
		GameUI.close_pause()
	get_tree().paused = false


func _reset_progression_defaults() -> void:
	ProgressionSystem.level = 1
	ProgressionSystem.current_xp = 0
	ProgressionSystem.upgrade_levels = {
		"max_hp": 0,
		"max_energy": 0,
		"energy_regen": 0,
		"move_speed": 0,
	}
