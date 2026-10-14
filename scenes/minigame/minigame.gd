extends BaseLocation

@onready var entities: Node2D = $Entities

var _sim: MinigameSim
var _monkey_sprites: Array = []
var _poop_sprites: Array = []
var _client_hp_mirror: int = 3


func _ready() -> void:
	super._ready()
	scene_id = "minigame"
	_sim = MinigameSim.new()
	add_child(_sim)
	_build_background()
	setup_exits([{"name": "to_cave", "pos": Vector2(0, -25), "target_scene": "cave"}])


func enter(extra: Dictionary = {}) -> void:
	var mode := str(extra.get("monkey_mode", GameState.monkey_mode))
	GameState.monkey_mode = mode
	_sim.configure(mode, ConfigLoader.balance.get("minigame", {}))
	_clear_visuals()
	var session := get_tree().current_scene
	if session and session.has_method("get_player"):
		var pl = session.get_player()
		if pl:
			pl.heal_full()
	GameUI.set_survival_timer(0, true)
	GameUI.show_top10(mode)


func update_world(delta: float) -> void:
	var session := get_tree().current_scene
	if session == null or not session.has_method("get_player"):
		return
	var player: Node = session.get_player()
	var pos: Vector2 = player.get_position_units()
	if GameState.is_client():
		return
	_sim.update_sim(
		delta,
		pos,
		func(): player.apply_damage(1),
		func(): ProgressionSystem.add_xp(int(ConfigLoader.balance.get("progression", {}).get("xp_per_dodge", 5))),
	)
	ProgressionSystem.add_xp(int(float(ConfigLoader.balance.get("progression", {}).get("xp_per_second_survived", 10)) * delta))
	GameUI.set_survival_timer(_sim.game_time, true)
	GameUI.refresh_hud()
	_sync_visuals()
	if player.hp <= 0 and not _sim.is_game_over:
		_sim.is_game_over = true
		if session.has_method("on_minigame_game_over"):
			session.on_minigame_game_over(_sim.game_time, GameState.monkey_mode)
		BrainLinkBridge.send_minigame_event("player_died")


func get_bounds() -> Dictionary:
	return _sim.get_playable_bounds()


func get_view_bounds() -> Dictionary:
	return {"min_x": -35.0, "max_x": 35.0, "min_y": -18.0, "max_y": 18.0}


func apply_network_snapshot(msg: Dictionary) -> void:
	_sim.game_time = float(msg.get("game_time", 0))
	_sim.is_game_over = bool(msg.get("game_over", false))
	var hp_map: Dictionary = msg.get("hp", {})
	var session := get_tree().current_scene
	if session and session.has_method("get_player"):
		var pl = session.get_player()
		var key := str(GameState.local_player_id)
		if hp_map.has(key):
			pl.hp = int(hp_map[key])
	_client_hp_mirror = int(hp_map.get("1", _client_hp_mirror))
	_clear_visuals()
	for m in msg.get("monkeys", []):
		if typeof(m) != TYPE_DICTIONARY:
			continue
		_add_monkey_sprite(Vector2(float(m.get("x", 0)), float(m.get("z", 0))), int(m.get("age", 1)))
	for p in msg.get("poops", []):
		if typeof(p) != TYPE_DICTIONARY:
			continue
		_add_poop_sprite(Vector2(float(p.get("x", 0)), float(p.get("z", 0))))
	GameUI.set_survival_timer(_sim.game_time, true)


func build_network_snapshot() -> Dictionary:
	var session := get_tree().current_scene
	var host_hp := 3
	var client_hp := _client_hp_mirror
	if session and session.has_method("get_player"):
		host_hp = session.get_player().hp
	return _sim.build_snapshot(host_hp, client_hp)


func _build_background() -> void:
	var forest_path := "res://assets/sprites/minigame/forest_floor.png"
	var forest: Sprite2D
	if ResourceLoader.exists(forest_path):
		forest = WorldVisuals.floor_sprite(forest_path, Vector2(70, 36))
	else:
		forest = WorldVisuals.solid_sprite(Vector2(70, 36), Color(0.2, 0.35, 0.15))
	forest.name = "Forest"
	$Background.add_child(forest)
	var clearing_path := "res://assets/sprites/minigame/clearing.png"
	var clearing: Sprite2D
	if ResourceLoader.exists(clearing_path):
		clearing = WorldVisuals.floor_sprite(clearing_path, Vector2(60, 30))
	else:
		clearing = WorldVisuals.solid_sprite(Vector2(60, 30), Color(0.45, 0.55, 0.25))
	clearing.name = "Clearing"
	$Background.add_child(clearing)
	var road_n := WorldVisuals.solid_sprite(Vector2(60, 2.5), Color(0.45, 0.4, 0.32))
	road_n.position = GameState.units_to_px(Vector2(0, 15 - 1.25))
	$Background.add_child(road_n)
	var road_s := WorldVisuals.solid_sprite(Vector2(60, 2.5), Color(0.45, 0.4, 0.32))
	road_s.position = GameState.units_to_px(Vector2(0, -15 + 1.25))
	$Background.add_child(road_s)
	var road_e := WorldVisuals.solid_sprite(Vector2(2.5, 30), Color(0.45, 0.4, 0.32))
	road_e.position = GameState.units_to_px(Vector2(30 - 1.25, 0))
	$Background.add_child(road_e)
	var road_w := WorldVisuals.solid_sprite(Vector2(2.5, 30), Color(0.45, 0.4, 0.32))
	road_w.position = GameState.units_to_px(Vector2(-30 + 1.25, 0))
	$Background.add_child(road_w)


func _sync_visuals() -> void:
	while _monkey_sprites.size() < _sim.monkeys.size():
		var m: Dictionary = _sim.monkeys[_monkey_sprites.size()]
		_add_monkey_sprite(m["pos"], int(m["age"]))
	while _monkey_sprites.size() > _sim.monkeys.size():
		var n: Node = _monkey_sprites.pop_back()
		n.queue_free()
	for i in _sim.monkeys.size():
		var spr: Sprite2D = _monkey_sprites[i]
		spr.position = GameState.units_to_px(_sim.monkeys[i]["pos"])
	while _poop_sprites.size() < _sim.poops.size():
		var p: Dictionary = _sim.poops[_poop_sprites.size()]
		_add_poop_sprite(p["pos"])
	while _poop_sprites.size() > _sim.poops.size():
		var n2: Node = _poop_sprites.pop_back()
		n2.queue_free()
	for j in _sim.poops.size():
		var spr2: Sprite2D = _poop_sprites[j]
		spr2.position = GameState.units_to_px(_sim.poops[j]["pos"])


func _add_monkey_sprite(pos: Vector2, age: int) -> void:
	var spr := WorldVisuals.prop_sprite("res://assets/sprites/monkey/age%d.png" % age, 1.0)
	spr.position = GameState.units_to_px(pos)
	entities.add_child(spr)
	_monkey_sprites.append(spr)


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
