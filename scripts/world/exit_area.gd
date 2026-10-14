extends Area2D
class_name ExitArea

## Триггер выхода — правьте в сцене: позиция, target_scene, маркер-спрайт.
@export var exit_name: String = "exit"
@export var target_scene: String = ""


func _ready() -> void:
	set_meta(
		"exit_info",
		{
			"name": exit_name,
			"target_scene": target_scene,
		},
	)
