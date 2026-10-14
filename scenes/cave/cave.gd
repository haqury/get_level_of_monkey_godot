extends BaseLocation

## Локация редактируется в cave.tscn: пол, стены, выходы (ExitArea), NPC.


func _ready() -> void:
	super._ready()
	scene_id = "cave"


func enter(_extra: Dictionary = {}) -> void:
	pass


func update_world(_delta: float) -> void:
	pass


func get_bounds() -> Dictionary:
	return {"min_x": -36.5, "max_x": 36.5, "min_y": -19.5, "max_y": 19.5}


func get_view_bounds() -> Dictionary:
	return {"min_x": -35.0, "max_x": 35.0, "min_y": -18.0, "max_y": 18.0}
