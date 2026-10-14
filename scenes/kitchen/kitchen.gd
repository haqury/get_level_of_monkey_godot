extends BaseLocation

## Локация редактируется в kitchen.tscn: пол, декор, выход, NPC.


func _ready() -> void:
	super._ready()
	scene_id = "kitchen"


func enter(_extra: Dictionary = {}) -> void:
	pass


func update_world(_delta: float) -> void:
	pass


func get_bounds() -> Dictionary:
	return {"min_x": -51.0, "max_x": 51.0, "min_y": -31.0, "max_y": 31.0}


func get_view_bounds() -> Dictionary:
	return {"min_x": -50.0, "max_x": 50.0, "min_y": -30.0, "max_y": 30.0}
