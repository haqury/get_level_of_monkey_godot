@tool
extends EditorPlugin

var _sync_queued := false


func _enter_tree() -> void:
	scene_changed.connect(_queue_sync)
	var fs := get_editor_interface().get_resource_filesystem()
	if not fs.filesystem_changed.is_connected(_on_filesystem_changed):
		fs.filesystem_changed.connect(_on_filesystem_changed)
	call_deferred("_queue_sync")


func _exit_tree() -> void:
	if scene_changed.is_connected(_queue_sync):
		scene_changed.disconnect(_queue_sync)
	var fs := get_editor_interface().get_resource_filesystem()
	if fs.filesystem_changed.is_connected(_on_filesystem_changed):
		fs.filesystem_changed.disconnect(_on_filesystem_changed)


func _on_filesystem_changed() -> void:
	_queue_sync()


func _queue_sync() -> void:
	if _sync_queued:
		return
	_sync_queued = true
	call_deferred("_sync_edited_scene")


func _sync_edited_scene() -> void:
	_sync_queued = false
	var root := get_editor_interface().get_edited_scene_root()
	if root == null:
		return
	GameUiTheme.sync_edited_scene_root(root)
