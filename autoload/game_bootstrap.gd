extends Node


func _ready() -> void:
	get_tree().paused = false
	GameControls.apply_from_config(ConfigLoader.game_config)
	apply_window_from_config()


func apply_window_from_config() -> void:
	var win: Dictionary = ConfigLoader.game_config.get("window", {})
	var title := str(win.get("title", "Get Level of Monkey"))
	DisplayServer.window_set_title(title)
	var w := int(win.get("width", 1280))
	var h := int(win.get("height", 720))
	if bool(win.get("fullscreen", false)):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(w, h))
	var root := get_tree().root
	if root:
		root.content_scale_size = Vector2i(w, h)
