extends BaseLocation

@onready var entities: Node2D = $Entities

var _sim: MinigameSim
var _monkey_sprites: Array = []
var _poop_sprites: Array = []
var _monkey_tex: Dictionary = {}
var _client_hp_mirror: int = 3
var _game_over_handled: bool = false

const MONKEY_WALK_FPS := 6.0
const MONKEY_HEIGHT_UNITS := {1: 1.15, 2: 1.35, 3: 1.6, 4: 1.5}


func _ready() -> void:
	super._ready()
	scene_id = "minigame"
	_sim = MinigameSim.new()
	add_child(_sim)
	_load_monkey_textures()
	_build_background()
	setup_exits([{"name": "to_cave", "pos": Vector2(0, -25), "target_scene": "cave"}])


func enter(extra: Dictionary = {}) -> void:
	var mode := str(extra.get("monkey_mode", GameState.monkey_mode))
	GameState.monkey_mode = mode
	_sim.configure(mode, ConfigLoader.balance.get("minigame", {}))
	_clear_visuals()
	_game_over_handled = false
	GameUI.close_minigame_game_over()
	var session := get_tree().current_scene
	if session and session.has_method("get_player"):
		var pl = session.get_player()
		if pl:
			pl.heal_full()
			_client_hp_mirror = pl.max_hp
		if GameState.is_online() and session.has_node("RemotePlayer"):
			var rp = session.get_node("RemotePlayer")
			if rp.has_method("set_defeated"):
				rp.set_defeated(false)
	GameUI.set_survival_timer(0, true)
	GameUI.show_top10(mode)


func update_world(delta: float) -> void:
	var session := get_tree().current_scene
	if session == null or not session.has_method("get_player"):
		return
	if GameUI.minigame_game_over_open:
		return
	var player: Node = session.get_player()
	if GameState.is_client():
		return
	if _sim.is_game_over:
		return
	var aim_pos: Vector2 = _monkey_aim_position(session, player)
	var extras: Array = _extra_hit_positions(session, player)
	_sim.update_sim(
		delta,
		aim_pos,
		func(poop_pos: Vector2): _apply_poop_hit(session, player, poop_pos),
		func(): ProgressionSystem.add_xp(int(ConfigLoader.balance.get("progression", {}).get("xp_per_dodge", 5))),
		extras,
	)
	ProgressionSystem.add_xp(int(float(ConfigLoader.balance.get("progression", {}).get("xp_per_second_survived", 10)) * delta))
	GameUI.set_survival_timer(_sim.game_time, true)
	GameUI.refresh_hud()
	_sync_visuals()
	if _all_players_defeated(session, player):
		_trigger_full_game_over(session)


func get_bounds() -> Dictionary:
	return _sim.get_playable_bounds()


func get_view_bounds() -> Dictionary:
	return {"min_x": -35.0, "max_x": 35.0, "min_y": -18.0, "max_y": 18.0}


func apply_network_snapshot(msg: Dictionary) -> void:
	var was_over := _sim.is_game_over
	_sim.game_time = float(msg.get("game_time", 0))
	_sim.is_game_over = bool(msg.get("game_over", false))
	var hp_map: Dictionary = msg.get("hp", {})
	var session := get_tree().current_scene
	if session and session.has_method("get_player"):
		var pl = session.get_player()
		var key := str(GameState.local_player_id)
		if hp_map.has(key):
			pl.hp = int(hp_map[key])
			pl.set_defeated(pl.hp <= 0)
	_client_hp_mirror = int(hp_map.get("1", _client_hp_mirror))
	if session and GameState.is_client() and session.has_node("RemotePlayer"):
		var rp = session.get_node("RemotePlayer")
		if rp.has_method("set_defeated") and hp_map.has("0"):
			rp.set_defeated(int(hp_map["0"]) <= 0)
	var monkeys: Array = msg.get("monkeys", [])
	while _monkey_sprites.size() < monkeys.size():
		_add_monkey_sprite(Vector2.ZERO, 1)
	while _monkey_sprites.size() > monkeys.size():
		var extra_monkey: Node = _monkey_sprites.pop_back()
		extra_monkey.queue_free()
	for i in monkeys.size():
		var m: Variant = monkeys[i]
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var monkey: Dictionary = m
		var spr: Sprite2D = _monkey_sprites[i]
		spr.position = GameState.units_to_px(Vector2(float(monkey.get("x", 0)), float(monkey.get("z", 0))))
		_apply_monkey_visual(
			spr,
			int(monkey.get("age", 1)),
			Vector2(float(monkey.get("dx", 0)), float(monkey.get("dy", 0))),
			_sim.game_time,
			float(i),
		)
	var poops: Array = msg.get("poops", [])
	while _poop_sprites.size() < poops.size():
		_add_poop_sprite(Vector2.ZERO)
	while _poop_sprites.size() > poops.size():
		var extra_poop: Node = _poop_sprites.pop_back()
		extra_poop.queue_free()
	for j in poops.size():
		var p: Variant = poops[j]
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var poop: Dictionary = p
		var poop_spr: Sprite2D = _poop_sprites[j]
		poop_spr.position = GameState.units_to_px(Vector2(float(poop.get("x", 0)), float(poop.get("z", 0))))
	GameUI.set_survival_timer(_sim.game_time, true)
	GameUI.refresh_hud()
	if _sim.is_game_over and not was_over and not _game_over_handled:
		_trigger_full_game_over(session)


func build_network_snapshot() -> Dictionary:
	var session := get_tree().current_scene
	var host_hp := 3
	var client_hp := _client_hp_mirror
	if session and session.has_method("get_player"):
		host_hp = session.get_player().hp
	return _sim.build_snapshot(host_hp, client_hp)


func _monkey_aim_position(session: Node, player: Node) -> Vector2:
	if not player.is_defeated:
		return player.get_position_units()
	if GameState.is_online() and session.has_node("RemotePlayer") and _client_hp_mirror > 0:
		var rp = session.get_node("RemotePlayer")
		if not rp.is_defeated:
			return rp.get_position_units()
	return player.get_position_units()


func _extra_hit_positions(session: Node, player: Node) -> Array:
	var out: Array = []
	if GameState.is_online() and session.has_node("RemotePlayer") and _client_hp_mirror > 0:
		var rp = session.get_node("RemotePlayer")
		if not rp.is_defeated:
			out.append(rp.get_position_units())
	if not player.is_defeated:
		return out
	return out


func _apply_poop_hit(session: Node, player: Node, poop_pos: Vector2) -> void:
	var host_pos: Vector2 = player.get_position_units()
	var hit_host: bool = (not bool(player.is_defeated)) and poop_pos.distance_to(host_pos) < 0.5
	if hit_host:
		var was_alive: bool = int(player.hp) > 0
		player.apply_damage(1)
		if was_alive and player.hp <= 0:
			BrainLinkBridge.send_minigame_event("player_died")
		return
	if not GameState.is_online() or _client_hp_mirror <= 0:
		return
	var rp = session.get_node("RemotePlayer")
	if rp.is_defeated:
		return
	if poop_pos.distance_to(rp.get_position_units()) >= 0.5:
		return
	_client_hp_mirror = maxi(0, _client_hp_mirror - 1)
	if rp.has_method("set_defeated") and _client_hp_mirror <= 0:
		rp.set_defeated(true)
		BrainLinkBridge.send_minigame_event("player_died")
	GameUI.refresh_hud()


func _all_players_defeated(session: Node, player: Node) -> bool:
	if not GameState.is_online():
		return player.hp <= 0 or player.is_defeated
	return (player.hp <= 0 or player.is_defeated) and _client_hp_mirror <= 0


func _trigger_full_game_over(session: Node) -> void:
	if _game_over_handled:
		return
	_game_over_handled = true
	_sim.is_game_over = true
	if not GameState.is_client() and session.has_method("on_minigame_game_over"):
		session.on_minigame_game_over(_sim.game_time, GameState.monkey_mode)
	GameUI.show_minigame_game_over()


func _build_background() -> void:
	var forest_path := "res://assets/sprites/minigame/forest_floor.png"
	var forest := _make_tiled_floor(forest_path, Vector2(70, 36), Color(0.2, 0.35, 0.15))
	forest.name = "Forest"
	$Background.add_child(forest)
	var clearing_path := "res://assets/sprites/minigame/clearing.png"
	var clearing := _make_tiled_floor(clearing_path, Vector2(60, 30), Color(0.45, 0.55, 0.25))
	clearing.name = "Clearing"
	$Background.add_child(clearing)
	var road_path := "res://assets/sprites/minigame/road.png"
	var road_n := _make_tiled_floor(road_path, Vector2(60, 2.5), Color(0.45, 0.4, 0.32))
	road_n.position = GameState.units_to_px(Vector2(0, 15 - 1.25))
	$Background.add_child(road_n)
	var road_s := _make_tiled_floor(road_path, Vector2(60, 2.5), Color(0.45, 0.4, 0.32))
	road_s.position = GameState.units_to_px(Vector2(0, -15 + 1.25))
	$Background.add_child(road_s)
	var road_e := _make_tiled_floor(road_path, Vector2(2.5, 30), Color(0.45, 0.4, 0.32))
	road_e.position = GameState.units_to_px(Vector2(30 - 1.25, 0))
	$Background.add_child(road_e)
	var road_w := _make_tiled_floor(road_path, Vector2(2.5, 30), Color(0.45, 0.4, 0.32))
	road_w.position = GameState.units_to_px(Vector2(-30 + 1.25, 0))
	$Background.add_child(road_w)


func _make_tiled_floor(path: String, size_units: Vector2, fallback: Color) -> Sprite2D:
	if ResourceLoader.exists(path):
		return WorldVisuals.tiled_sprite(path, size_units)
	return WorldVisuals.solid_sprite(size_units, fallback)


func _sync_visuals() -> void:
	while _monkey_sprites.size() < _sim.monkeys.size():
		var m: Dictionary = _sim.monkeys[_monkey_sprites.size()]
		_add_monkey_sprite(m["pos"], int(m["age"]))
	while _monkey_sprites.size() > _sim.monkeys.size():
		var n: Node = _monkey_sprites.pop_back()
		n.queue_free()
	for i in _sim.monkeys.size():
		var spr: Sprite2D = _monkey_sprites[i]
		var m: Dictionary = _sim.monkeys[i]
		spr.position = GameState.units_to_px(m["pos"])
		_apply_monkey_visual(spr, int(m["age"]), m["move_dir"], _sim.game_time, float(i))
	while _poop_sprites.size() < _sim.poops.size():
		var p: Dictionary = _sim.poops[_poop_sprites.size()]
		_add_poop_sprite(p["pos"])
	while _poop_sprites.size() > _sim.poops.size():
		var n2: Node = _poop_sprites.pop_back()
		n2.queue_free()
	for j in _sim.poops.size():
		var spr2: Sprite2D = _poop_sprites[j]
		spr2.position = GameState.units_to_px(_sim.poops[j]["pos"])


func _add_monkey_sprite(pos: Vector2, age: int, move: Vector2 = Vector2.ZERO) -> void:
	var spr := Sprite2D.new()
	spr.centered = true
	spr.position = GameState.units_to_px(pos)
	_apply_monkey_visual(spr, age, move, _sim.game_time, float(_monkey_sprites.size()))
	entities.add_child(spr)
	_monkey_sprites.append(spr)


func _load_monkey_textures() -> void:
	_monkey_tex.clear()
	for age in [1, 2, 3, 4]:
		for facing in ["down", "left", "up"]:
			for frame_name in ["idle", "1", "2"]:
				var path := "res://assets/sprites/monkey/age%d/%s_%s.png" % [age, facing, frame_name]
				var tex := _load_sprite_texture(path)
				if tex != null:
					_monkey_tex["%d_%s_%s" % [age, facing, frame_name]] = tex


func _load_sprite_texture(res_path: String) -> Texture2D:
	var imported := load(res_path) as Texture2D
	if imported != null:
		return imported
	var abs_path := ProjectSettings.globalize_path(res_path)
	if not FileAccess.file_exists(abs_path):
		return null
	var img := Image.load_from_file(abs_path)
	if img == null:
		return null
	return ImageTexture.create_from_image(img)


func _apply_monkey_visual(spr: Sprite2D, age: int, move: Vector2, time: float, slot: float) -> void:
	age = clampi(age, 1, 4)
	var facing := "down"
	var flip := false
	if move.length_squared() > 0.0001 and absf(move.x) >= absf(move.y):
		facing = "left"
		flip = move.x > 0.0
	elif move.y < 0.0:
		facing = "up"
	var frame := "idle"
	if move.length_squared() > 0.0001:
		var step := int((time + slot * 0.35) * MONKEY_WALK_FPS) % 2
		frame = "1" if step == 0 else "2"
	var key := "%d_%s_%s" % [age, facing, frame]
	if not _monkey_tex.has(key):
		key = "%d_down_idle" % age
	if _monkey_tex.has(key):
		spr.texture = _monkey_tex[key]
	spr.flip_h = flip
	if spr.texture == null:
		return
	var units := float(MONKEY_HEIGHT_UNITS.get(age, 1.3))
	var s := units * GameState.PIXELS_PER_UNIT / maxf(1.0, float(spr.texture.get_height()))
	spr.scale = Vector2(s, s)


func _add_poop_sprite(pos: Vector2) -> void:
	var spr := WorldVisuals.prop_sprite("res://assets/sprites/minigame/poop.png", 0.5)
	spr.position = GameState.units_to_px(pos)
	entities.add_child(spr)
	_poop_sprites.append(spr)


func _clear_visuals() -> void:
	for n in _monkey_sprites + _poop_sprites:
		n.queue_free()
	_monkey_sprites.clear()
	_poop_sprites.clear()
