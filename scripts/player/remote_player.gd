extends Node2D

var facing: String = "down"
var is_sitting: bool = false
var is_defeated: bool = false
var player_id: int = 1
var _target: Vector2 = Vector2.ZERO
var _textures: Dictionary = {}

@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	for d in ["up", "down", "left", "right"]:
		var p := "res://assets/sprites/player/walk/%s.png" % d
		if ResourceLoader.exists(p):
			_textures[d] = load(p)
	var idle_p := "res://assets/sprites/player/idle/down.png"
	if ResourceLoader.exists(idle_p):
		_textures["idle"] = load(idle_p)
	sprite.modulate = Color(0.7, 0.9, 1.0)
	WorldVisuals.scale_sprite_to_units(sprite, 1.0)


func _process(delta: float) -> void:
	global_position = global_position.lerp(_target, clampf(delta * 15.0, 0.0, 1.0))
	_update_sprite()


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
	_update_sprite()


func _update_sprite() -> void:
	if _textures.is_empty():
		return
	var key := facing if _textures.has(facing) else "idle"
	if _textures.has(key):
		sprite.texture = _textures[key]
	if is_defeated:
		sprite.modulate = Color(0.55, 0.65, 0.75, 1.0)
		sprite.rotation = deg_to_rad(90.0)
		sprite.scale = Vector2(0.85, 0.85)
	elif is_sitting:
		sprite.modulate = Color(0.7, 0.9, 1.0)
		sprite.rotation = 0.0
		sprite.scale = Vector2(1.0, 0.7)
	else:
		sprite.modulate = Color(0.7, 0.9, 1.0)
		sprite.rotation = 0.0
		sprite.scale = Vector2.ONE
