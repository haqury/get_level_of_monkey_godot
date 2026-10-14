extends CharacterBody2D

@export var move_speed: float = 5.0

var facing: String = "down"
var is_sitting: bool = false
var player_id: int = 0
var is_local: bool = true

var max_hp: int = 3
var hp: int = 3
var max_energy: float = 100.0
var energy: float = 100.0
var energy_regen: float = 5.0
var move_cost: float = 100.0
var cheater_mode: bool = false
var is_defeated: bool = false

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D

var _textures: Dictionary = {}
var _bounds: Dictionary = {}
var _scene_ref: Node = null


func _ready() -> void:
	var cfg: Dictionary = ConfigLoader.game_config.get("player", {})
	max_hp = int(cfg.get("initial_hp", 3))
	hp = max_hp
	max_energy = float(cfg.get("initial_energy", 100))
	energy = max_energy
	energy_regen = float(cfg.get("energy_regen_rate", 5.0))
	move_speed = float(cfg.get("move_speed", 5.0))
	move_cost = float(cfg.get("move_cost", 100.0))
	cheater_mode = GameState.cheater_mode or bool(cfg.get("cheater_mode", false))
	_load_textures()
	ProgressionSystem.apply_to_player(self)
	apply_viewport_scale()


func apply_viewport_scale() -> void:
	if collision.shape is CircleShape2D:
		(collision.shape as CircleShape2D).radius = 0.5 * GameState.PIXELS_PER_UNIT
	if sprite != null and sprite.texture != null:
		WorldVisuals.scale_sprite_to_units(sprite, 1.0)


func _physics_process(delta: float) -> void:
	if not is_local:
		return
	if GameUI.pause_open or GameUI.minigame_game_over_open:
		return
	if is_defeated:
		velocity = Vector2.ZERO
		_update_sprite()
		return
	var dir := InputManager.get_movement_vector()
	is_sitting = InputManager.is_sitting()
	if is_sitting:
		_regen_energy(delta * 2.0)
		velocity = Vector2.ZERO
	else:
		_regen_energy(delta)
		if dir.length_squared() > 0.01:
			if not _try_spend_move_energy(delta, not InputManager.is_using_brainlink()):
				dir = Vector2.ZERO
			velocity = dir * move_speed * GameState.PIXELS_PER_UNIT
			facing = _dir_to_facing(dir)
		else:
			velocity = Vector2.ZERO
	move_and_slide()
	_clamp_to_bounds()
	_update_sprite()


func set_world_bounds(bounds: Dictionary, scene_ref: Node) -> void:
	_bounds = bounds
	_scene_ref = scene_ref


func set_position_units(pos: Vector2) -> void:
	global_position = GameState.units_to_px(pos)


func get_position_units() -> Vector2:
	return GameState.px_to_units(global_position)


func get_network_state() -> Dictionary:
	var p: Vector2 = get_position_units()
	return {
		"x": p.x,
		"y": p.y,
		"facing": facing,
		"is_sitting": is_sitting,
		"defeated": is_defeated,
		"hp": hp,
	}


func set_max_hp(v: int) -> void:
	max_hp = v
	hp = mini(hp, max_hp)


func set_max_energy(v: float) -> void:
	max_energy = v
	energy = minf(energy, max_energy)


func set_energy_regen(v: float) -> void:
	energy_regen = v


func set_move_speed(v: float) -> void:
	move_speed = v


func apply_damage(amount: int) -> void:
	if is_defeated:
		return
	hp = maxi(0, hp - amount)
	GameUI.refresh_hud()
	if hp <= 0:
		set_defeated(true)


func set_defeated(on: bool) -> void:
	is_defeated = on
	if is_defeated:
		is_sitting = false
		velocity = Vector2.ZERO
	_update_sprite()


func heal_full() -> void:
	hp = max_hp
	set_defeated(false)


func _regen_energy(delta: float) -> void:
	if cheater_mode:
		energy = max_energy
		return
	energy = minf(max_energy, energy + energy_regen * delta)
	GameUI.refresh_hud()


func _try_spend_move_energy(delta: float, charge_energy: bool = true) -> bool:
	if not charge_energy or cheater_mode or GameState.cheater_mode:
		return true
	var cost := move_cost * delta / 10.0
	if energy < cost:
		return false
	energy -= cost
	return true


func _clamp_to_bounds() -> void:
	if _bounds.is_empty():
		return
	var pos: Vector2 = get_position_units()
	pos.x = clampf(pos.x, float(_bounds.get("min_x", -9999)), float(_bounds.get("max_x", 9999)))
	pos.y = clampf(pos.y, float(_bounds.get("min_y", -9999)), float(_bounds.get("max_y", 9999)))
	set_position_units(pos)


func _load_textures() -> void:
	for d in ["up", "down", "left", "right"]:
		var p := "res://assets/sprites/player/walk/%s.png" % d
		if ResourceLoader.exists(p):
			_textures[d] = load(p)
	var idle_p := "res://assets/sprites/player/idle/down.png"
	if ResourceLoader.exists(idle_p):
		_textures["idle"] = load(idle_p)
	WorldVisuals.scale_sprite_to_units(sprite, 1.0)


func _update_sprite() -> void:
	if _textures.is_empty():
		return
	var key := facing if velocity.length_squared() > 1.0 and _textures.has(facing) else "idle"
	if _textures.has(key):
		sprite.texture = _textures[key]
	if is_defeated:
		sprite.modulate = Color(0.65, 0.65, 0.7, 1.0)
		sprite.rotation = deg_to_rad(90.0)
		sprite.scale = Vector2(0.85, 0.85)
	elif is_sitting:
		sprite.modulate = Color.WHITE
		sprite.rotation = 0.0
		sprite.scale = Vector2(1.0, 0.7)
	else:
		sprite.modulate = Color.WHITE
		sprite.rotation = 0.0
		sprite.scale = Vector2.ONE


func _dir_to_facing(dir: Vector2) -> String:
	if abs(dir.x) >= abs(dir.y):
		return "left" if dir.x < 0 else "right"
	return "up" if dir.y < 0 else "down"
