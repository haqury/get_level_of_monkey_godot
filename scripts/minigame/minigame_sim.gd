extends Node
class_name MinigameSim

const CLEARING_HALF_W := 30.0
const CLEARING_HALF_H := 15.0
const ROAD_WIDTH := 2.5
const PERPENDICULAR_THRESHOLD := 15.0

var monkey_mode: String = "NorthSouth"
var monkeys: Array = []
var poops: Array = []
var game_time: float = 0.0
var is_game_over: bool = false
var _spawn_group_size: int = 1
var _poop_base_speed: float = 20.0
var _balance: Dictionary = {}


func configure(mode: String, balance: Dictionary) -> void:
	monkey_mode = mode
	_balance = balance
	var poop_cfg: Dictionary = balance.get("poop", {})
	_poop_base_speed = float(poop_cfg.get("speed", 300)) / 15.0
	reset()


func reset() -> void:
	monkeys.clear()
	poops.clear()
	game_time = 0.0
	is_game_over = false
	_spawn_group_size = 1
	_spawn_group()


func get_playable_bounds() -> Dictionary:
	return {
		"min_x": -CLEARING_HALF_W + ROAD_WIDTH,
		"max_x": CLEARING_HALF_W - ROAD_WIDTH,
		"min_y": -CLEARING_HALF_H + ROAD_WIDTH,
		"max_y": CLEARING_HALF_H - ROAD_WIDTH,
	}


func update_sim(delta: float, player_pos: Vector2, on_hit: Callable, on_dodge: Callable) -> void:
	if is_game_over:
		return
	game_time += delta
	if monkeys.is_empty():
		_spawn_group()
	var to_remove: Array = []
	for i in monkeys.size():
		var m: Dictionary = monkeys[i]
		var result = _update_monkey(m, delta, player_pos)
		if typeof(result) == TYPE_STRING and str(result) == "despawn":
			to_remove.append(i)
			_spawn_group_size = mini(5, _spawn_group_size + 1)
		elif typeof(result) == TYPE_DICTIONARY:
			poops.append(result)
	for i in range(to_remove.size() - 1, -1, -1):
		monkeys.remove_at(to_remove[i])
	var dead_p: Array = []
	for j in poops.size():
		var p: Dictionary = poops[j]
		_update_poop(p, delta)
		if not p.get("alive", true):
			dead_p.append(j)
		elif _poop_hits_player(p, player_pos):
			p["alive"] = false
			dead_p.append(j)
			on_hit.call()
			BrainLinkBridge.send_minigame_event("damage_taken")
		elif p.get("missed", false):
			on_dodge.call()
			BrainLinkBridge.send_minigame_event("dodge_success")
	for k in range(dead_p.size() - 1, -1, -1):
		poops.remove_at(dead_p[k])


func _spawn_group() -> void:
	for _i in _spawn_group_size:
		monkeys.append(_create_monkey())


func _create_monkey() -> Dictionary:
	var stats_by_age: Dictionary = _balance.get("monkeys", {}).get("stats_by_age", {})
	var age := _pick_age()
	var stats: Dictionary = stats_by_age.get(str(age), {"throw_speed": 1.0, "accuracy": 0.5, "cooldown": 2.0})
	var pos := Vector2.ZERO
	var move_dir := Vector2.ZERO
	if monkey_mode == "NorthSouth":
		pos.y = CLEARING_HALF_H if randf() > 0.5 else -CLEARING_HALF_H
		pos.x = -CLEARING_HALF_W + randf() * (CLEARING_HALF_W * 2.0)
		move_dir = Vector2(1 if randf() > 0.5 else -1, 0)
	else:
		pos.x = CLEARING_HALF_W if randf() > 0.5 else -CLEARING_HALF_W
		pos.y = -CLEARING_HALF_H + randf() * (CLEARING_HALF_H * 2.0)
		move_dir = Vector2(0, 1 if randf() > 0.5 else -1)
	return {
		"age": age,
		"pos": pos,
		"move_dir": move_dir.normalized(),
		"move_speed": randf_range(3.0, 6.0),
		"cooldown": 0.0,
		"max_cooldown": maxf(0.5, float(stats.get("cooldown", 2.0)) * 0.4),
		"stats": stats,
	}


func _pick_age() -> int:
	var dist: Dictionary = _balance.get("monkeys", {}).get("age_distribution", {"1": 0.4, "2": 0.3, "3": 0.2, "4": 0.1})
	var r := randf()
	var acc := 0.0
	for age_key in ["1", "2", "3", "4"]:
		acc += float(dist.get(age_key, 0.0))
		if r <= acc:
			return int(age_key)
	return 1


func _update_monkey(m: Dictionary, delta: float, player_pos: Vector2) -> Variant:
	var pos: Vector2 = m["pos"]
	var move: Vector2 = m["move_dir"] * float(m["move_speed"]) * delta
	pos += move
	if monkey_mode == "NorthSouth":
		if m["move_dir"].x > 0 and pos.x > CLEARING_HALF_W:
			return "despawn"
		if m["move_dir"].x < 0 and pos.x < -CLEARING_HALF_W:
			return "despawn"
	else:
		if m["move_dir"].y > 0 and pos.y > CLEARING_HALF_H:
			return "despawn"
		if m["move_dir"].y < 0 and pos.y < -CLEARING_HALF_H:
			return "despawn"
	m["pos"] = pos
	m["cooldown"] = float(m["cooldown"]) - delta
	var pb: Dictionary = get_playable_bounds()
	var in_playable: bool = (
		player_pos.x >= pb["min_x"] and player_pos.x <= pb["max_x"]
		and player_pos.y >= pb["min_y"] and player_pos.y <= pb["max_y"]
	)
	var can_throw := false
	if in_playable:
		if monkey_mode == "NorthSouth":
			can_throw = abs(pos.y - player_pos.y) < PERPENDICULAR_THRESHOLD
		else:
			can_throw = abs(pos.x - player_pos.x) < PERPENDICULAR_THRESHOLD
	if can_throw and float(m["cooldown"]) <= 0.0:
		m["cooldown"] = float(m["max_cooldown"])
		return _throw_poop(m, player_pos)
	return null


func _throw_poop(m: Dictionary, player_pos: Vector2) -> Dictionary:
	var stats: Dictionary = m["stats"]
	var spread := randf_range(-3.0, 3.0) * (1.0 - float(stats.get("accuracy", 0.5)))
	var speed := _poop_base_speed * float(stats.get("throw_speed", 1.0)) * 0.8
	var pos: Vector2 = m["pos"]
	var target := Vector2.ZERO
	if monkey_mode == "NorthSouth":
		target = Vector2(pos.x, player_pos.y + spread)
	else:
		target = Vector2(player_pos.x + spread, pos.y)
	var dir := (target - pos).normalized()
	if dir.length_squared() < 0.001:
		dir = Vector2.UP
	return {
		"pos": pos,
		"vel": dir * speed,
		"lifetime": float(_balance.get("poop", {}).get("lifetime", 5.0)),
		"alive": true,
		"missed": false,
	}


func _update_poop(p: Dictionary, delta: float) -> void:
	if not p.get("alive", true):
		return
	p["pos"] = p["pos"] + p["vel"] * delta
	p["lifetime"] = float(p["lifetime"]) - delta
	var pos: Vector2 = p["pos"]
	if abs(pos.x) > CLEARING_HALF_W or abs(pos.y) > CLEARING_HALF_H:
		p["alive"] = false
		p["missed"] = true
	elif float(p["lifetime"]) <= 0.0:
		p["alive"] = false


func _poop_hits_player(p: Dictionary, player_pos: Vector2) -> bool:
	return p["pos"].distance_to(player_pos) < 0.5


func build_snapshot(host_hp: int, client_hp: int) -> Dictionary:
	var mk: Array = []
	for m in monkeys:
		mk.append({"x": m["pos"].x, "z": m["pos"].y, "age": m["age"]})
	var pp: Array = []
	for p in poops:
		if p.get("alive", false):
			pp.append({"x": p["pos"].x, "z": p["pos"].y})
	return {
		"game_time": game_time,
		"monkeys": mk,
		"poops": pp,
		"hp": {"0": host_hp, "1": client_hp},
		"game_over": is_game_over,
	}
