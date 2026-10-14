extends Node

signal connection_changed(connected: bool)

var connected: bool = false
var _poll_accum: float = 0.0
var _shim_pid: int = -1
var _connect_requested: bool = false
var _reconnect_cooldown: float = 0.0


func _ready() -> void:
	if OS.get_name() != "Windows":
		return
	if _is_enabled():
		_connect_requested = true
		call_deferred("ensure_ready")


func _process(delta: float) -> void:
	if OS.get_name() != "Windows" or not _is_enabled():
		return
	_start_shim_if_needed()
	if _connect_requested and _shim_pid > 0:
		_request_connect()
	_reconnect_cooldown = maxf(0.0, _reconnect_cooldown - delta)
	var interval := float(ConfigLoader.game_config.get("brainlink", {}).get("check_interval", 0.016))
	_poll_accum += delta
	if _poll_accum < interval:
		return
	_poll_accum = 0.0
	_poll_shim()
	if not connected and _reconnect_cooldown <= 0.0 and _shim_pid > 0:
		_request_connect()
		_reconnect_cooldown = 2.0


func _is_enabled() -> bool:
	return bool(ConfigLoader.game_config.get("brainlink", {}).get("enabled", false))


func ensure_ready() -> void:
	if OS.get_name() != "Windows" or not _is_enabled():
		return
	_connect_requested = true
	_start_shim_if_needed()


func try_connect() -> bool:
	if OS.get_name() != "Windows":
		return false
	_connect_requested = true
	_start_shim_if_needed()
	_request_connect()
	return true


func disconnect_shm() -> void:
	_connect_requested = false
	_write_shim({"cmd": "disconnect"})
	_set_connected(false)


func send_event(event_code: String, command_type: int = 1) -> void:
	if not connected or event_code.is_empty():
		return
	_write_shim({
		"cmd": "send_event",
		"event_code": event_code,
		"command_type": command_type,
	})


func send_minigame_event(_event_name: String) -> void:
	if not connected:
		return
	var bl: Dictionary = ConfigLoader.game_config.get("brainlink", {})
	if not bool(bl.get("send_to_ml", false)):
		return
	var ev := InputManager.get_current_keyboard_event()
	if ev.is_empty() or ev not in ["ml", "mr", "mu", "md"]:
		return
	if InputManager.is_using_brainlink():
		return
	_write_shim({"cmd": "minigame_event", "keyboard_event": ev})


func send_config_command(command_type: int) -> void:
	if not connected:
		return
	if command_type < 3 or command_type > 9:
		return
	_write_shim({"cmd": "config_command", "command_type": command_type})


func launch_client() -> void:
	var exe := _resolve_client_exe()
	if exe.is_empty():
		push_warning("BrainLink client executable not found")
		return
	OS.create_process(exe, [], false)


func _resolve_client_exe() -> String:
	var paths: Dictionary = ConfigLoader.brainlink_paths
	var direct := str(paths.get("client_exe", ""))
	if direct != "" and FileAccess.file_exists(direct):
		return direct
	var dir := str(paths.get("brainlink_path", "")).strip_edges()
	if dir.is_empty():
		return ""
	dir = dir.replace("\\", "/")
	for exe_name: String in [
		"BrainLinkClient.exe",
		"brainlink_client.exe",
		"BrainLink.exe",
		"main.exe",
	]:
		var candidate: String = dir.path_join(exe_name)
		if FileAccess.file_exists(candidate):
			return candidate
		var candidate2: String = dir + "/" + exe_name
		if FileAccess.file_exists(candidate2):
			return candidate2
	return ""


func _start_shim_if_needed() -> void:
	if _shim_pid > 0:
		return
	var script_path := ProjectSettings.globalize_path("res://tools/brainlink_shim.py")
	if not FileAccess.file_exists(script_path):
		return
	_shim_pid = OS.create_process("python", PackedStringArray([script_path]), false)


func _request_connect() -> void:
	_write_shim({
		"cmd": "connect",
		"memory_name": str(ConfigLoader.game_config.get("brainlink", {}).get("memory_name", "brainlink_data")),
		"status_path": ProjectSettings.globalize_path("user://brainlink_status.json"),
		"cmd_path": ProjectSettings.globalize_path("user://brainlink_cmd.json"),
	})


func _poll_shim() -> void:
	if _shim_pid <= 0:
		return
	if not FileAccess.file_exists("user://brainlink_status.json"):
		return
	var f := FileAccess.open("user://brainlink_status.json", FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		apply_shim_status(parsed)


func _write_shim(payload: Dictionary) -> void:
	if not FileAccess.file_exists(ProjectSettings.globalize_path("res://tools/brainlink_shim.py")):
		return
	var f := FileAccess.open("user://brainlink_cmd.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(payload))


func apply_shim_status(data: Dictionary) -> void:
	var was := connected
	_set_connected(bool(data.get("connected", false)))
	InputManager.brainlink_confidence = float(data.get("confidence", 0.0))
	InputManager.brainlink_probs = data.get("probs", {}) if typeof(data.get("probs", {})) == TYPE_DICTIONARY else {}
	InputManager.set_brainlink_event(str(data.get("event", "")))
	if was != connected:
		connection_changed.emit(connected)


func _set_connected(value: bool) -> void:
	if connected == value:
		return
	connected = value
	if connected:
		_connect_requested = false
