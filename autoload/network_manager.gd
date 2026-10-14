extends Node

signal disconnected(reason: String)
signal client_connected
signal scene_change_received(msg: Dictionary)

var _server: TCPServer
var _client_peer: StreamPeerTCP
var _host_peer: StreamPeerTCP
var _recv_buffer: String = ""
var _state_seq: int = 0
var _send_accum: float = 0.0
var _minigame_accum: float = 0.0
var _applying_remote_scene: bool = false
var _host_waiting: bool = false
var _client_waiting: bool = false
var _connect_deadline: float = 0.0
var _pending_hello: bool = false

var tick_rate_hz: float = 20.0
var minigame_sync_hz: float = 10.0
var default_port: int = 17777


func _ready() -> void:
	var mp: Dictionary = ConfigLoader.game_config.get("multiplayer", {})
	tick_rate_hz = float(mp.get("tick_rate_hz", 20))
	minigame_sync_hz = float(mp.get("minigame_sync_hz", 10))
	default_port = int(mp.get("default_port", 17777))


func _process(delta: float) -> void:
	if _pending_hello and _client_peer and _client_peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		_send_raw(NetProtocol.make_hello(GameState.player_name()))
		_pending_hello = false
	_poll_server_accept()
	_drain_peer(_host_peer, true)
	_drain_peer(_client_peer, false)
	if _client_waiting and _client_peer and _connect_deadline > 0:
		if Time.get_ticks_msec() / 1000.0 > _connect_deadline:
			shutdown()
			disconnected.emit("timeout")
	if not GameState.in_game or not GameState.is_online():
		return
	_send_accum += delta
	var send_dt := 1.0 / tick_rate_hz
	if _send_accum >= send_dt:
		_send_accum = 0.0
		_send_local_player_state()
	_minigame_accum += delta
	if GameState.current_scene_id == "minigame" and GameState.is_host():
		if _minigame_accum >= 1.0 / minigame_sync_hz:
			_minigame_accum = 0.0
			_send_minigame_state()


func shutdown() -> void:
	if _server:
		_server.stop()
		_server = null
	if _host_peer:
		_host_peer.disconnect_from_host()
		_host_peer = null
	if _client_peer:
		_client_peer.disconnect_from_host()
		_client_peer = null
	_recv_buffer = ""
	_host_waiting = false
	_client_waiting = false
	GameState.mp_role = GameState.MpRole.OFFLINE
	GameState.session_id = ""


func start_host(port: int = -1) -> Dictionary:
	shutdown()
	if port < 0:
		port = default_port
	_server = TCPServer.new()
	var err := _server.listen(port, "0.0.0.0")
	if err != OK:
		shutdown()
		return {"ok": false, "error": "bind failed"}
	GameState.mp_role = GameState.MpRole.HOST
	GameState.local_player_id = 0
	GameState.session_id = str(randi()) + "-" + str(Time.get_unix_time_from_system())
	_host_waiting = true
	return {"ok": true, "address": "%s:%d" % [_lan_ip(), port]}


func join_host(host: String, port: int = -1) -> bool:
	shutdown()
	if port < 0:
		port = default_port
	host = host.strip_edges()
	if host.is_empty():
		host = "127.0.0.1"
	_client_peer = StreamPeerTCP.new()
	var err := _client_peer.connect_to_host(host, port)
	if err != OK:
		shutdown()
		return false
	GameState.mp_role = GameState.MpRole.CLIENT
	GameState.local_player_id = 1
	_client_waiting = true
	var timeout := float(ConfigLoader.game_config.get("multiplayer", {}).get("connect_timeout_sec", 10))
	_connect_deadline = Time.get_ticks_msec() / 1000.0 + timeout
	_pending_hello = true
	return true


func host_start_game_from_menu() -> void:
	if not GameState.is_host() or _host_peer == null:
		return
	_send_raw(NetProtocol.make_start_game())
	var scene_id := "cave"
	var lx := MultiplayerSpawns.spawn_for(scene_id, 0)
	var rx := MultiplayerSpawns.spawn_for(scene_id, 1)
	_send_raw(
		NetProtocol.make_scene_change(scene_id, lx.x, lx.y, rx.x, rx.y, "start")
	)


func host_broadcast_scene_change(scene_id: String, extra: Dictionary) -> void:
	if not GameState.is_host():
		return
	var mm := str(extra.get("monkey_mode", ""))
	var lx := MultiplayerSpawns.spawn_for(scene_id, 0)
	var rx := MultiplayerSpawns.spawn_for(scene_id, 1)
	_send_raw(
		NetProtocol.make_scene_change(scene_id, lx.x, lx.y, rx.x, rx.y, "switch", mm)
	)


func client_apply_scene_change(msg: Dictionary) -> void:
	if not GameState.is_client():
		return
	_applying_remote_scene = true
	var scene_id := str(msg.get("scene_id", "cave"))
	var extra := {}
	if msg.has("monkey_mode"):
		extra["monkey_mode"] = str(msg["monkey_mode"])
	var scene_mgr: Node = get_node("/root/SceneManager")
	scene_mgr.call("client_enter_game")
	var root := get_tree().current_scene
	if root and root.has_method("load_world_scene"):
		GameState.current_scene_id = scene_id
		root.load_world_scene(scene_id, extra)
		var sx := float(msg.get("spawn_x", 0))
		var sz := float(msg.get("spawn_z", 0))
		if root.has_method("teleport_local_player"):
			root.teleport_local_player(Vector2(sx, sz))
		if root.has_method("teleport_remote_player"):
			root.teleport_remote_player(
				Vector2(float(msg.get("remote_spawn_x", 0)), float(msg.get("remote_spawn_z", 0)))
			)
	GameState.in_game = true
	if root and root.has_method("show_hud"):
		root.show_hud()
	_applying_remote_scene = false
	scene_change_received.emit(msg)


func should_skip_local_exits() -> bool:
	return GameState.is_client()


func is_applying_remote_scene() -> bool:
	return _applying_remote_scene


func broadcast_minigame(payload: Dictionary) -> void:
	if GameState.is_host():
		_send_raw(NetProtocol.make_minigame_state(payload))


func _poll_server_accept() -> void:
	if _server == null or _host_peer != null:
		return
	if _server.is_connection_available():
		_host_peer = _server.take_connection()
		_host_waiting = false


func _drain_peer(peer: StreamPeerTCP, is_host_side: bool) -> void:
	if peer == null:
		return
	peer.poll()
	var status := peer.get_status()
	if status == StreamPeerTCP.STATUS_NONE or status == StreamPeerTCP.STATUS_ERROR:
		if GameState.is_online() and not _applying_remote_scene:
			shutdown()
			disconnected.emit("connection lost")
		return
	if status != StreamPeerTCP.STATUS_CONNECTED:
		return
	while peer.get_available_bytes() > 0:
		var chunk := peer.get_utf8_string(peer.get_available_bytes())
		_recv_buffer += chunk
		while "\n" in _recv_buffer:
			var parts := _recv_buffer.split("\n", true, 1)
			_recv_buffer = parts[1] if parts.size() > 1 else ""
			var msg = NetProtocol.decode_line(parts[0])
			if msg != null:
				_handle_message(msg, is_host_side)


func _handle_message(msg: Dictionary, is_host_side: bool) -> void:
	var mtype := str(msg.get("type", ""))
	match mtype:
		NetProtocol.MsgType.HELLO:
			if is_host_side and _host_peer:
				var pname := str(msg.get("player_name", "Client"))
				_send_raw(
					NetProtocol.make_welcome(GameState.session_id, 1, GameState.player_name())
				)
				client_connected.emit()
		NetProtocol.MsgType.WELCOME:
			if GameState.is_client():
				GameState.session_id = str(msg.get("session_id", ""))
				GameState.local_player_id = int(msg.get("player_id", 1))
				_client_waiting = false
		NetProtocol.MsgType.START_GAME:
			if GameState.is_client():
				_client_waiting = false
		NetProtocol.MsgType.SCENE_CHANGE:
			if GameState.is_client():
				client_apply_scene_change(msg)
		NetProtocol.MsgType.PLAYER_STATE:
			var root := get_tree().current_scene
			if root and root.has_method("apply_remote_player_state"):
				root.apply_remote_player_state(msg)
		NetProtocol.MsgType.MINIGAME_STATE:
			var root2 := get_tree().current_scene
			if root2 and root2.has_method("apply_minigame_snapshot"):
				root2.apply_minigame_snapshot(msg)
		NetProtocol.MsgType.GOODBYE:
			if not _applying_remote_scene:
				shutdown()
				disconnected.emit(str(msg.get("reason", "")))


func _send_local_player_state() -> void:
	var root := get_tree().current_scene
	if root == null or not root.has_method("get_local_player_state"):
		return
	var st: Dictionary = root.get_local_player_state()
	if st.is_empty():
		return
	_state_seq += 1
	var msg := NetProtocol.make_player_state(
		GameState.local_player_id,
		GameState.current_scene_id,
		float(st.get("x", 0)),
		float(st.get("y", 0)),
		str(st.get("facing", "down")),
		bool(st.get("is_sitting", false)),
		_state_seq,
	)
	_send_raw(msg)


func _send_minigame_state() -> void:
	var root := get_tree().current_scene
	if root and root.has_method("build_minigame_snapshot"):
		var payload: Dictionary = root.build_minigame_snapshot()
		if not payload.is_empty():
			_send_raw(NetProtocol.make_minigame_state(payload))


func _send_raw(msg: Dictionary) -> void:
	var data := NetProtocol.encode_message(msg)
	if _host_peer and _host_peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		_host_peer.put_data(data)
	if _client_peer and _client_peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		_client_peer.put_data(data)


func _lan_ip() -> String:
	var addresses := IP.get_local_addresses()
	for a in addresses:
		if a.begins_with("192.168.") or a.begins_with("10."):
			return a
	return "127.0.0.1"
