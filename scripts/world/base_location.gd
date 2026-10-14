extends Node2D
class_name BaseLocation

const DESIGN_PPU := 24.0

var exits: Array = []
var npcs: Array = []
var scene_id: String = ""

@onready var exits_root: Node2D = $Exits
@onready var npcs_root: Node2D = $NPCs


func _ready() -> void:
	if not Engine.is_editor_hint():
		var ratio := GameState.PIXELS_PER_UNIT / DESIGN_PPU
		scale = Vector2(ratio, ratio)
	if has_node("Background"):
		$Background.z_index = -10
	if has_node("Entities"):
		$Entities.z_index = 5
	_collect_npcs_from_scene()


func _collect_npcs_from_scene() -> void:
	npcs.clear()
	if npcs_root == null:
		return
	for child in npcs_root.get_children():
		if child.has_method("interact"):
			npcs.append(child)


func setup_exits(defs: Array) -> void:
	exits = defs
	for c in exits_root.get_children():
		c.queue_free()
	for e in defs:
		var area := Area2D.new()
		area.name = str(e.get("name", "exit"))
		var cs := CollisionShape2D.new()
		var shape := CircleShape2D.new()
		shape.radius = GameState.EXIT_RADIUS * GameState.PIXELS_PER_UNIT
		cs.shape = shape
		area.add_child(cs)
		var pos: Vector2 = e.get("pos", Vector2.ZERO)
		area.position = GameState.units_to_px(pos)
		area.set_meta("exit_info", e)
		exits_root.add_child(area)
		var marker_path: String = str(e.get("marker", ""))
		if marker_path != "":
			var marker := WorldVisuals.prop_sprite(marker_path, 4.0)
			marker.position = area.position
			marker.z_index = -5
			exits_root.add_child(marker)


func get_nearby_npc(player_pos: Vector2) -> Node:
	for npc in npcs:
		if npc.has_method("is_in_range") and npc.is_in_range(player_pos):
			return npc
	return null


func check_exit(player_pos: Vector2) -> Dictionary:
	var player_px := GameState.units_to_px(player_pos)
	for child in exits_root.get_children():
		if child is Area2D and _player_touches_exit(child, player_px):
			return child.get_meta("exit_info", {})
	return {}


func _player_touches_exit(area: Area2D, player_px: Vector2) -> bool:
	var shape_node := area.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null or shape_node.shape == null:
		return false
	var local_pt: Vector2 = shape_node.global_transform.affine_inverse() * player_px
	var body_pad := 0.5 * DESIGN_PPU
	var shape := shape_node.shape
	if shape is CircleShape2D:
		return local_pt.length() <= (shape as CircleShape2D).radius + body_pad
	if shape is RectangleShape2D:
		var half: Vector2 = (shape as RectangleShape2D).size * 0.5
		return abs(local_pt.x) <= half.x + body_pad and abs(local_pt.y) <= half.y + body_pad
	return false


func get_bounds() -> Dictionary:
	return {}


## Область пола/фона для масштаба под окно (по умолчанию = границы игрока).
func get_view_bounds() -> Dictionary:
	return get_bounds()
