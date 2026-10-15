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
var _walk_anim: float = 0.0
var _last_anim_facing: String = "down"
var _display_scale: Vector2 = Vector2.ONE

const WALK_FRAME_COUNT := 5
const WALK_ANIM_SPEED := 5.0
const FOOT_HEIGHT_RATIO := 0.92
## Высота персонажа в игровых единицах (масштаб по высоте текстуры).
const SPRITE_SIZE_UNITS := 2.0


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
		_apply_sprite_display_scale()
		_apply_sprite_foot_offset()


func _physics_process(delta: float) -> void:
	if not is_local:
		return
	if GameUI.pause_open or GameUI.minigame_game_over_open:
		return
	if is_defeated:
		velocity = Vector2.ZERO
		_update_sprite(delta, false, facing)
		return
	var intent := InputManager.get_movement_vector()
	is_sitting = InputManager.is_sitting()
	var move_dir := intent
	if is_sitting:
		_regen_energy(delta * 2.0)
		velocity = Vector2.ZERO
	else:
		_regen_energy(delta)
		if intent.length_squared() > 0.01:
			if not _try_spend_move_energy(delta, not InputManager.is_using_brainlink()):
				move_dir = Vector2.ZERO
			velocity = move_dir * move_speed * GameState.PIXELS_PER_UNIT
		else:
			velocity = Vector2.ZERO
	move_and_slide()
	_clamp_to_bounds()
	var face_vec := intent if intent.length_squared() > 0.01 else move_dir
	if face_vec.length_squared() < 0.01 and velocity.length_squared() > 1.0:
		face_vec = velocity
	var is_walking := (
		not is_sitting
		and not is_defeated
		and (intent.length_squared() > 0.01 or move_dir.length_squared() > 0.01)
	)
	var anim_facing := facing
	if face_vec.length_squared() > 0.01:
		anim_facing = _dir_to_facing(face_vec)
		if is_walking:
			facing = anim_facing
	_update_sprite(delta, is_walking, anim_facing)


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
	_update_sprite(0.0, false, facing)


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
	_textures.clear()
	for d in ["up", "down", "left", "right"]:
		for frame in range(1, WALK_FRAME_COUNT + 1):
			var p := "res://assets/sprites/player/walk/%s_%d.png" % [d, frame]
			var walk_tex := _load_sprite_texture(p)
			if walk_tex != null:
				_textures["%s_%d" % [d, frame]] = walk_tex
		var idle_p := "res://assets/sprites/player/idle/%s.png" % d
		var idle_tex := _load_sprite_texture(idle_p)
		if idle_tex != null:
			_textures["idle_%s" % d] = idle_tex


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


func _apply_sprite_display_scale() -> void:
	if sprite.texture == null:
		return
	var size_u := float(
		ConfigLoader.game_config.get("player", {}).get("display_size_units", SPRITE_SIZE_UNITS)
	)
	var th := maxf(1.0, float(sprite.texture.get_height()))
	var s := size_u * GameState.PIXELS_PER_UNIT / th
	sprite.scale = Vector2(s, s)
	_display_scale = sprite.scale


func _apply_sprite_foot_offset() -> void:
	if sprite.texture == null:
		return
	var h := float(sprite.texture.get_height())
	sprite.offset = Vector2(0.0, h * (0.5 - FOOT_HEIGHT_RATIO))


func _update_sprite(delta: float, walking: bool, anim_facing: String) -> void:
	if _textures.is_empty():
		return
	walking = walking and not is_sitting and not is_defeated
	if anim_facing != _last_anim_facing:
		_walk_anim = 0.0
		_last_anim_facing = anim_facing
	var tex_key: String = _pick_sprite_key(anim_facing, walking, delta)
	if tex_key.is_empty():
		return
	sprite.texture = _textures[tex_key]
	_apply_sprite_display_scale()
	_apply_sprite_foot_offset()
	sprite.flip_h = false
	if is_defeated:
		sprite.modulate = Color(0.65, 0.65, 0.7, 1.0)
		sprite.rotation = deg_to_rad(90.0)
		sprite.scale = _display_scale * 0.85
	elif is_sitting:
		sprite.modulate = Color.WHITE
		sprite.rotation = 0.0
		sprite.scale = Vector2(_display_scale.x, _display_scale.y * 0.7)
	else:
		sprite.modulate = Color.WHITE
		sprite.rotation = 0.0
		sprite.scale = _display_scale


func _dir_to_facing(dir: Vector2) -> String:
	if abs(dir.x) >= abs(dir.y):
		return "left" if dir.x < 0 else "right"
	return "up" if dir.y < 0 else "down"


func _pick_sprite_key(anim_facing: String, walking: bool, delta: float) -> String:
	var tex_key: String
	if walking:
		_walk_anim += delta * WALK_ANIM_SPEED
		var frame := (int(_walk_anim) % WALK_FRAME_COUNT) + 1
		tex_key = "%s_%d" % [anim_facing, frame]
		if not _textures.has(tex_key):
			tex_key = "%s_1" % anim_facing
	else:
		_walk_anim = 0.0
		tex_key = "idle_%s" % anim_facing
		if not _textures.has(tex_key):
			tex_key = "idle_down" if _textures.has("idle_down") else ""
	if not _textures.has(tex_key):
		return ""
	return tex_key
