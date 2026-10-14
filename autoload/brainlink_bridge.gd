extends Node

signal connection_changed(connected: bool)

const CMD_QUEUE_USER_PATH := "user://brainlink_cmd_queue.json"
const SHIM_PID_USER_PATH := "user://brainlink_shim.pid"
const HEARTBEAT_STALE_MS := 3000
const SHIM_STARTUP_GRACE_MS := 5000

var connected: bool = false
var shm_attached: bool = false
var client_active: bool = false
var _poll_accum: float = 0.0
var _shim_pid: int = -1
var _shim_we_spawned: bool = false
var _shim_spawn_unix_ms: int = 0
var _connect_requested: bool = false
var _connect_enqueued: bool = false
var _reconnect_cooldown: float = 0.0
var _last_heartbeat_ms: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.get_name() != "Windows":
		return
	if _is_enabled():
		_connect_requested = true
		call_deferred("ensure_ready")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_shutdown_shim()
	elif what == NOTIFICATION_PREDELETE:
		_shutdown_shim()


func _process(delta: float) -> void:
	if OS.get_name() != "Windows" or not _is_enabled():
		return
	_poll_shim()
	_ensure_shim_alive()
	_start_shim_if_needed()
	if _connect_requested and not _connect_enqueued:
		_enqueue_connect_command()
		_connect_enqueued = true
	_reconnect_cooldown = maxf(0.0, _reconnect_cooldown - delta)
	var interval := float(ConfigLoader.game_config.get("brainlink", {}).get("check_interval", 0.016))
	_poll_accum += delta
	if _poll_accum < interval:
		return
	_poll_accum = 0.0
	if not connected and _reconnect_cooldown <= 0.0:
		if _is_shim_heartbeat_fresh():
			_connect_requested = true
			_connect_enqueued = false
		_reconnect_cooldown = 2.0


func _is_enabled() -> bool:
	return bool(ConfigLoader.game_config.get("brainlink", {}).get("enabled", false))


func can_send_ground_truth() -> bool:
	return _is_enabled() and OS.get_name() == "Windows"


func ensure_ready() -> void:
	if OS.get_name() != "Windows" or not _is_enabled():
		return
	_connect_requested = true
	_connect_enqueued = false
	_start_shim_if_needed()


func try_connect() -> bool:
	if OS.get_name() != "Windows":
		return false
	_connect_requested = true
	_connect_enqueued = false
	_start_shim_if_needed()
	return true


func disconnect_shm() -> void:
	_connect_requested = false
	_connect_enqueued = false
	_enqueue_shim_command({"cmd": "disconnect"})
	_set_connected(false)


func send_ground_truth(event_code: String) -> void:
	if not can_send_ground_truth() or event_code.is_empty():
		return
	if event_code not in ["ml", "mr", "mu", "md", "stop", "ne"]:
		return
	_start_shim_if_needed()
	_enqueue_shim_command({"cmd": "send_ground_truth", "event_code": event_code})


func send_event(event_code: String, command_type: int = 1) -> void:
	if command_type == 2:
		send_ground_truth(event_code)
		return
	if not can_send_ground_truth() or event_code.is_empty():
		return
	_enqueue_shim_command({
		"cmd": "send_event",
		"event_code": event_code,
		"command_type": command_type,
	})


func send_minigame_event(_event_name: String) -> void:
	if not can_send_ground_truth():
		return
	var bl: Dictionary = ConfigLoader.game_config.get("brainlink", {})
	if not bool(bl.get("send_to_ml", false)):
		return
	var ev := InputManager.get_current_keyboard_event()
	if ev.is_empty() or ev not in ["ml", "mr", "mu", "md"]:
		return
	if InputManager.is_using_brainlink():
		return
	send_ground_truth(ev)


func send_config_command(command_type: int) -> void:
	if not can_send_ground_truth():
		return
	if command_type < 3 or command_type > 9:
		return
	_enqueue_shim_command({"cmd": "config_command", "command_type": command_type})


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
	if _is_shim_heartbeat_fresh():
		return
	if _in_shim_startup_grace():
		return
	if _shim_we_spawned and _shim_pid > 0:
		return
	_cleanup_stale_shim_pid_file()
	var script_path := ProjectSettings.globalize_path("res://tools/brainlink_shim.py")
	if not FileAccess.file_exists(script_path):
		push_warning("BrainLink shim script missing")
		return
	var status_global := ProjectSettings.globalize_path("user://brainlink_status.json")
	var memory_name := str(ConfigLoader.game_config.get("brainlink", {}).get("memory_name", "brainlink_data"))
	var args := PackedStringArray([script_path, status_global, memory_name])
	var pid := OS.create_process("python", args, false)
	if pid <= 0:
		pid = OS.create_process("py", PackedStringArray(["-3"]) + args, false)
	if pid <= 0:
		return
	_shim_pid = pid
	_shim_we_spawned = true
	_shim_spawn_unix_ms = int(Time.get_unix_time_from_system() * 1000.0)
	_connect_requested = true
	_connect_enqueued = false


func _ensure_shim_alive() -> void:
	if _is_shim_heartbeat_fresh():
		return
	if _in_shim_startup_grace():
		return
	if not _shim_we_spawned:
		return
	_kill_recorded_shim()
	_shim_pid = -1
	_shim_we_spawned = false
	_shim_spawn_unix_ms = 0
	_set_connected(false)
	_connect_requested = true
	_connect_enqueued = false


func _in_shim_startup_grace() -> bool:
	if _shim_spawn_unix_ms <= 0:
		return false
	var now_ms := int(Time.get_unix_time_from_system() * 1000.0)
	return now_ms - _shim_spawn_unix_ms < SHIM_STARTUP_GRACE_MS


func _is_shim_heartbeat_fresh() -> bool:
	if _last_heartbeat_ms <= 0:
		return false
	var now_ms := int(Time.get_unix_time_from_system() * 1000.0)
	return now_ms - _last_heartbeat_ms <= HEARTBEAT_STALE_MS


func _enqueue_connect_command() -> void:
	_enqueue_shim_command({
		"cmd": "connect",
		"memory_name": str(ConfigLoader.game_config.get("brainlink", {}).get("memory_name", "brainlink_data")),
		"status_path": ProjectSettings.globalize_path("user://brainlink_status.json"),
	})


func _enqueue_shim_command(payload: Dictionary) -> void:
	if not FileAccess.file_exists(ProjectSettings.globalize_path("res://tools/brainlink_shim.py")):
		return
	var queue: Array = []
	if FileAccess.file_exists(CMD_QUEUE_USER_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CMD_QUEUE_USER_PATH))
		if typeof(parsed) == TYPE_ARRAY:
			queue = parsed
	queue.append(payload)
	const MAX_QUEUE := 128
	if queue.size() > MAX_QUEUE:
		queue = queue.slice(queue.size() - MAX_QUEUE)
	var f := FileAccess.open(CMD_QUEUE_USER_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(queue))


func _poll_shim() -> void:
	if not FileAccess.file_exists("user://brainlink_status.json"):
		return
	var f := FileAccess.open("user://brainlink_status.json", FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		apply_shim_status(parsed)


func apply_shim_status(data: Dictionary) -> void:
	_last_heartbeat_ms = int(data.get("heartbeat_ms", 0))
	var was := connected
	shm_attached = bool(data.get("shm_attached", false))
	client_active = bool(data.get("client_active", false)) and _is_shim_heartbeat_fresh()
	_set_connected(client_active)
	if client_active:
		InputManager.brainlink_confidence = float(data.get("confidence", 0.0))
		InputManager.brainlink_probs = (
			data.get("probs", {}) if typeof(data.get("probs", {})) == TYPE_DICTIONARY else {}
		)
		InputManager.set_brainlink_event(str(data.get("event", "")))
	else:
		InputManager.brainlink_confidence = 0.0
		InputManager.brainlink_probs = {}
		InputManager.set_brainlink_event("")
	if was != connected:
		connection_changed.emit(connected)


func _set_connected(value: bool) -> void:
	if connected == value:
		return
	connected = value
	if connected:
		_connect_requested = false
		_connect_enqueued = false


func _shutdown_shim() -> void:
	if not _shim_we_spawned:
		return
	_kill_recorded_shim()
	_shim_pid = -1
	_shim_we_spawned = false
	_shim_spawn_unix_ms = 0
	_remove_shim_pid_file()


func _kill_recorded_shim() -> void:
	var pid := _read_shim_pid_file()
	if pid <= 0:
		pid = _shim_pid
	if pid <= 0:
		return
	if OS.get_name() == "Windows":
		OS.execute("taskkill", PackedStringArray(["/F", "/PID", str(pid)]), [], true, true)
	else:
		OS.kill(pid)


func _read_shim_pid_file() -> int:
	if not FileAccess.file_exists(SHIM_PID_USER_PATH):
		return -1
	var text := FileAccess.get_file_as_string(SHIM_PID_USER_PATH).strip_edges()
	if text.is_empty():
		return -1
	return int(text)


func _remove_shim_pid_file() -> void:
	if FileAccess.file_exists(SHIM_PID_USER_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SHIM_PID_USER_PATH))


func _cleanup_stale_shim_pid_file() -> void:
	if _is_shim_heartbeat_fresh():
		return
	var pid := _read_shim_pid_file()
	if pid <= 0:
		return
	_kill_recorded_shim()
	_remove_shim_pid_file()
