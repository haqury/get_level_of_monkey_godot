extends Node2D

var facing: String = "down"
var is_sitting: bool = false
var is_defeated: bool = false
var player_id: int = 1
var _target: Vector2 = Vector2.ZERO
var _textures: Dictionary = {}
var _walk_anim: float = 0.0
var _last_anim_facing: String = "down"
var _display_scale: Vector2 = Vector2.ONE

const WALK_FRAME_COUNT := 5
const WALK_ANIM_SPEED := 5.0
const FOOT_HEIGHT_RATIO := 0.92
const SPRITE_SIZE_UNITS := 2.0

@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	_load_textures()
	sprite.modulate = Color(0.85, 0.92, 1.0)
	_apply_sprite_display_scale()
	_apply_sprite_foot_offset()


func _process(delta: float) -> void:
	var prev := global_position
	global_position = global_position.lerp(_target, clampf(delta * 15.0, 0.0, 1.0))
	var moved := global_position.distance_squared_to(prev) > 0.5
	_update_sprite(delta, moved)


func apply_state(msg: Dictionary) -> void:
	var x := float(msg.get("x", 0))
	var z := float(msg.get("z", msg.get("y", 0)))
	_target = GameState.units_to_px(Vector2(x, z))
	facing = str(msg.get("facing", "down"))
	is_sitting = bool(msg.get("is_sitting", false))
	is_defeated = bool(msg.get("defeated", false))
	if msg.has("hp"):
		is_defeated = int(msg.get("hp", 1)) <= 0
	var scene_id := str(msg.get("scene_id", ""))
	visible = scene_id == GameState.current_scene_id or scene_id.is_empty()


func set_position_units(pos: Vector2) -> void:
	_target = GameState.units_to_px(pos)
	global_position = _target


func get_position_units() -> Vector2:
	return GameState.px_to_units(global_position)


func set_defeated(on: bool) -> void:
	is_defeated = on
	_update_sprite(0.0, false)


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


func _update_sprite(delta: float, moving: bool) -> void:
	if _textures.is_empty():
		return
	moving = moving and not is_sitting and not is_defeated
	if facing != _last_anim_facing:
		_walk_anim = 0.0
		_last_anim_facing = facing
	var tex_key: String
	if moving:
		_walk_anim += delta * WALK_ANIM_SPEED
		var frame := (int(_walk_anim) % WALK_FRAME_COUNT) + 1
		tex_key = "%s_%d" % [facing, frame]
		if not _textures.has(tex_key):
			tex_key = "%s_1" % facing
	else:
		_walk_anim = 0.0
		tex_key = "idle_%s" % facing
		if not _textures.has(tex_key):
			tex_key = "idle_down"
	if _textures.has(tex_key):
		sprite.texture = _textures[tex_key]
		_apply_sprite_display_scale()
		_apply_sprite_foot_offset()
	sprite.flip_h = false
	if is_defeated:
		sprite.modulate = Color(0.55, 0.65, 0.75, 1.0)
		sprite.rotation = deg_to_rad(90.0)
		sprite.scale = _display_scale * 0.85
	elif is_sitting:
		sprite.modulate = Color(0.85, 0.92, 1.0)
		sprite.rotation = 0.0
		sprite.scale = Vector2(_display_scale.x, _display_scale.y * 0.7)
	else:
		sprite.modulate = Color(0.85, 0.92, 1.0)
		sprite.rotation = 0.0
		sprite.scale = _display_scale
