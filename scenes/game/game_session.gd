extends Node2D

@onready var world: Node2D = $World
@onready var player: CharacterBody2D = $Player
@onready var remote_player: Node2D = $RemotePlayer
@onready var camera: Camera2D = $Camera2D

var _current_world: Node = null
var _exit_dialog_active: bool = false
var _pending_exit: Dictionary = {}
var _minigame_exit_armed: bool = false
var _scene_transition_cooldown: float = 0.0
var _active_exit: Dictionary = {}
var _latched_npc: Node = null

const SCENE_VIEW_BOUNDS := {
	"cave": {"min_x": -35.0, "max_x": 35.0, "min_y": -18.0, "max_y": 18.0},
	"kitchen": {"min_x": -50.0, "max_x": 50.0, "min_y": -30.0, "max_y": 30.0},
	"minigame": {"min_x": -35.0, "max_x": 35.0, "min_y": -18.0, "max_y": 18.0},
}


func _ready() -> void:
	camera.make_current()
	camera.zoom = Vector2.ONE
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	NetworkManager.disconnected.connect(_on_mp_disconnected)
	remote_player.visible = GameState.is_online()
	if not GameState.in_game:
		GameState.in_game = true
		if GameState.startup_world_scene.is_empty() and GameState.current_scene_id in ["", "main_menu", "game_session"]:
			GameState.startup_world_scene = "cave"
			GameState.current_scene_id = "cave"
	GameUI.show_hud()
	InputManager._load_brainlink_send_flags()
	if bool(ConfigLoader.game_config.get("brainlink", {}).get("enabled", false)):
		BrainLinkBridge.ensure_ready()
	call_deferred("_bootstrap_world")


func _bootstrap_world() -> void:
	if _current_world != null:
		return
	var scene_id: String = GameState.startup_world_scene
	if scene_id.is_empty():
		scene_id = GameState.current_scene_id
	if scene_id.is_empty() or scene_id in ["main_menu", "game_session"]:
		scene_id = "cave"
	load_world_scene(scene_id, GameState.pending_scene_extra)
	GameState.startup_world_scene = ""


func load_world_scene(scene_id: String, extra: Dictionary = {}, preserve_player_pos: bool = false) -> void:
	_reset_exit_state()
	var saved_pos: Vector2 = player.get_position_units()
	if _current_world:
		_current_world.queue_free()
		_current_world = null
	var path: String = str(SceneManager.SCENE_PATHS.get(scene_id, ""))
	if path.is_empty():
		return
	var view_bounds: Dictionary = _view_bounds_for_scene(scene_id)
	_apply_viewport_fit(view_bounds)
	var packed: PackedScene = load(path)
	_current_world = packed.instantiate()
	world.add_child(_current_world)
	GameState.current_scene_id = scene_id
	player.apply_viewport_scale()
	if preserve_player_pos:
		player.set_position_units(saved_pos)
	else:
		_place_player_spawn(scene_id)
	ProgressionSystem.apply_to_player(player)
	if _current_world.has_method("enter"):
		_current_world.enter(extra)
	_update_player_bounds()
	_fit_camera_to_level(view_bounds)
	GameUI.refresh_hud()
	if scene_id != "minigame":
		GameUI.hide_top10()
		GameUI.set_survival_timer(0, false)


func _place_player_spawn(scene_id: String) -> void:
	var pos := Vector2.ZERO
	if GameState.is_online():
		pos = MultiplayerSpawns.spawn_for(scene_id, GameState.local_player_id)
	player.set_position_units(pos)
	player.heal_full()
	if GameState.is_online():
		remote_player.set_position_units(MultiplayerSpawns.spawn_for(scene_id, 1 - GameState.local_player_id))


func _update_player_bounds() -> void:
	if _current_world and _current_world.has_method("get_bounds"):
		player.set_world_bounds(_current_world.get_bounds(), _current_world)


func _view_bounds_for_scene(scene_id: String) -> Dictionary:
	if _current_world and _current_world.has_method("get_view_bounds"):
		return _current_world.get_view_bounds()
	return SCENE_VIEW_BOUNDS.get(scene_id, SCENE_VIEW_BOUNDS["cave"])


func _apply_viewport_fit(bounds: Dictionary) -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	GameState.fit_pixels_per_unit_to_viewport(vp, bounds)


func _fit_camera_to_level(bounds: Dictionary) -> void:
	_fit_camera_zoom_to_viewport(bounds)
	var center_u: Vector2 = GameState.bounds_center_units(bounds)
	camera.global_position = GameState.units_to_px(center_u)


func _fit_camera_zoom_to_viewport(bounds: Dictionary) -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var size_u: Vector2 = GameState.bounds_size_units(bounds)
	var world_w: float = size_u.x * GameState.PIXELS_PER_UNIT
	var world_h: float = size_u.y * GameState.PIXELS_PER_UNIT
	if world_w < 1.0 or world_h < 1.0 or vp.x < 1.0 or vp.y < 1.0:
		camera.zoom = Vector2.ONE
		return
	var z: float = minf(vp.x / world_w, vp.y / world_h)
	camera.zoom = Vector2(z, z)


func _on_viewport_size_changed() -> void:
	if not GameState.in_game or _current_world == null:
		return
	var bounds: Dictionary = _view_bounds_for_scene(GameState.current_scene_id)
	if _current_world.has_method("get_view_bounds"):
		bounds = _current_world.get_view_bounds()
	_fit_camera_to_level(bounds)


func _physics_process(delta: float) -> void:
	_scene_transition_cooldown = maxf(0.0, _scene_transition_cooldown - delta)
	if not GameState.in_game or GameUI.pause_open or GameUI.dialog_open or GameUI.minigame_game_over_open:
		return
	if _current_world and _current_world.has_method("update_world"):
		_current_world.update_world(delta)
	_check_exits()
	_check_npc_contact()


func _reset_exit_state() -> void:
	_exit_dialog_active = false
	_minigame_exit_armed = false
	_pending_exit = {}
	_active_exit = {}
	_latched_npc = null
	_scene_transition_cooldown = 0.35


func _clear_exit_zone_state() -> void:
	_exit_dialog_active = false
	_minigame_exit_armed = false
	_pending_exit = {}


func _check_exits() -> void:
	if NetworkManager.should_skip_local_exits():
		return
	if _current_world == null or not _current_world.has_method("check_exit"):
		return
	var pinfo: Vector2 = player.get_position_units()
	var exit_info: Dictionary = _current_world.check_exit(pinfo)
	if exit_info.is_empty():
		if not _active_exit.is_empty():
			_clear_exit_zone_state()
		_active_exit = {}
		return
	var exit_name := str(exit_info.get("name", ""))
	if exit_name == str(_active_exit.get("name", "")) and (_minigame_exit_armed or _exit_dialog_active):
		return
	if _scene_transition_cooldown > 0.0:
		return
	_active_exit = exit_info
	_use_active_exit()


func _check_npc_contact() -> void:
	if _current_world == null or not _current_world.has_method("get_nearby_npc"):
		return
	if not _active_exit.is_empty():
		return
	var npc = _current_world.get_nearby_npc(player.get_position_units())
	if npc == null:
		_latched_npc = null
		return
	if npc == _latched_npc or GameUI.dialog_open:
		return
	_latched_npc = npc
	if npc.has_method("interact"):
		npc.interact()


func _handle_minigame_exit(exit_info: Dictionary) -> void:
	if _minigame_exit_armed or _exit_dialog_active:
		return
	_minigame_exit_armed = true
	_exit_dialog_active = true
	_pending_exit = exit_info
	_show_father_exit_dialog()


func _show_father_exit_dialog() -> void:
	GameUI.show_dialog(
		I18n.tr_key("npc.father.name", "Father"),
		I18n.tr_key("npc.father.exit", "Go outside?"),
		[
			{
				"text": I18n.tr_key("npc.father.play_minigame", "Minigame"),
				"callback": Callable(self, "_show_mode_picker"),
			},
			{
				"text": I18n.tr_key("menu.mp_back", "Cancel"),
				"callback": Callable(self, "_cancel_exit"),
			},
		],
	)


func _show_mode_picker() -> void:
	_exit_dialog_active = false
	var leader_ns: String = SaveManager.get_leader_name("NorthSouth")
	var leader_we: String = SaveManager.get_leader_name("WestEast")
	var ns_label := I18n.tr_key("minigame.mode_ns", "NorthSouth")
	var we_label := I18n.tr_key("minigame.mode_we", "WestEast")
	if leader_ns != "":
		ns_label += " (%s)" % leader_ns
	if leader_we != "":
		we_label += " (%s)" % leader_we
	GameUI.show_dialog(
		I18n.tr_key("minigame.mode_title", "Minigame mode"),
		I18n.tr_key("minigame.mode_text", "Choose mode:"),
		[
			{"text": ns_label, "callback": Callable(self, "_pick_minigame_north_south")},
			{"text": we_label, "callback": Callable(self, "_pick_minigame_west_east")},
			{"text": I18n.tr_key("menu.mp_back", "Cancel"), "callback": Callable(self, "_cancel_exit")},
		],
	)


func _pick_minigame_north_south() -> void:
	_start_minigame("NorthSouth")


func _pick_minigame_west_east() -> void:
	_start_minigame("WestEast")


func _start_minigame(mode: String) -> void:
	_reset_exit_state()
	_scene_transition_cooldown = 0.5
	SceneManager.switch_to("minigame", {"monkey_mode": mode})


func _cancel_exit() -> void:
	_exit_dialog_active = false
	_minigame_exit_armed = true
	_pending_exit = {}


func _use_active_exit() -> void:
	var target: String = str(_active_exit.get("target_scene", ""))
	if target == "minigame":
		_handle_minigame_exit(_active_exit)
		return
	if target.is_empty() or target == GameState.current_scene_id:
		return
	_scene_transition_cooldown = 0.5
	SceneManager.switch_to(target, {})


func get_player() -> Node:
	return player


func get_world_container() -> Node:
	return world


func show_hud() -> void:
	GameUI.show_hud()


func teleport_local_player(pos: Vector2) -> void:
	player.set_position_units(pos)


func teleport_remote_player(pos: Vector2) -> void:
	remote_player.set_position_units(pos)


func get_local_player_state() -> Dictionary:
	var st: Dictionary = player.get_network_state()
	return st


func apply_remote_player_state(msg: Dictionary) -> void:
	if int(msg.get("player_id", -1)) == GameState.local_player_id:
		return
	remote_player.apply_state(msg)


func apply_minigame_snapshot(msg: Dictionary) -> void:
	if _current_world and _current_world.has_method("apply_network_snapshot"):
		_current_world.apply_network_snapshot(msg)


func build_minigame_snapshot() -> Dictionary:
	if _current_world and _current_world.has_method("build_network_snapshot"):
		return _current_world.build_network_snapshot()
	return {}


func _on_mp_disconnected(_reason: String) -> void:
	GameUI.show_dialog("", I18n.tr_key("mp_disconnected", "Disconnected"), [])


func on_minigame_game_over(time: float, mode: String) -> void:
	SaveManager.save_minigame_run(time, player.cheater_mode, GameState.player_name(), mode)
	BrainLinkBridge.send_minigame_event("game_over")
