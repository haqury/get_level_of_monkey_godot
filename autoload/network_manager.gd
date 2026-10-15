extends Node

signal disconnected(reason: String)
signal client_connected
signal scene_change_received(msg: Dictionary)
signal lan_hosts_changed

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
var _firewall_asked: bool = false
var _match_sync_done: bool = false

var tick_rate_hz: float = 20.0
var minigame_sync_hz: float = 10.0
var default_port: int = 17777

const DISCOVERY_PORT := 17778
const BEACON_INTERVAL := 1.0
const LAN_HOST_TTL := 3.0

var _udp: PacketPeerUDP
var _browse_enabled: bool = false
var _beacon_enabled: bool = false
var _beacon_accum: float = 0.0
var _lan_hosts: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var mp: Dictionary = ConfigLoader.game_config.get("multiplayer", {})
	tick_rate_hz = float(mp.get("tick_rate_hz", 20))
	minigame_sync_hz = float(mp.get("minigame_sync_hz", 10))
	default_port = int(mp.get("default_port", 17777))


func _process(delta: float) -> void:
	_poll_discovery(delta)
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
	_match_sync_done = false
	_beacon_enabled = false
	if not _browse_enabled:
		_close_udp()
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
	var firewall_ok := _inbound_tcp_allowed()
	if not firewall_ok and not _firewall_asked:
		_firewall_asked = true
		_request_firewall_rule(port)
		firewall_ok = _inbound_tcp_allowed()
	_beacon_enabled = true
	_beacon_accum = BEACON_INTERVAL
	_ensure_udp()
	return {"ok": true, "address": "%s:%d" % [_lan_ip(), port], "firewall_ok": firewall_ok}


func join_host(host: String, port: int = -1) -> bool:
	shutdown()
	if port < 0:
		port = default_port
	var parsed := split_host_port(host, port)
	host = str(parsed[0])
	port = int(parsed[1])
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


func sync_match_to_client() -> void:
	if not GameState.is_host() or _host_peer == null:
		return
	if _match_sync_done:
		return
	_match_sync_done = true
	_beacon_enabled = false
	var scene_id := GameState.current_scene_id
	if GameState.in_game and scene_id != "" and scene_id != "main_menu" and scene_id != "game_session":
		host_broadcast_scene_change(scene_id, GameState.pending_scene_extra)
		return
	get_node("/root/SceneManager").call("start_host_game")
	host_start_game_from_menu()


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
	GameState.current_scene_id = scene_id
	GameState.startup_world_scene = scene_id
	GameState.pending_scene_extra = extra
	var scene_mgr: Node = get_node("/root/SceneManager")
	scene_mgr.call("client_enter_game")
	var root := get_tree().current_scene
	if root and root.has_method("load_world_scene"):
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
			var waiting_for_connect := _client_waiting
			shutdown()
			disconnected.emit("timeout" if waiting_for_connect else "connection lost")
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
				call_deferred("sync_match_to_client")
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


static func split_host_port(raw: String, fallback_port: int) -> Array:
	var text := raw.strip_edges()
	if text.is_empty():
		return ["127.0.0.1", fallback_port]
	if text.begins_with("["):
		var bracket := text.find("]")
		if bracket > 1:
			var ipv6 := text.substr(1, bracket - 1)
			var tail := text.substr(bracket + 1).strip_edges()
			if tail.begins_with(":") and tail.substr(1).is_valid_int():
				return [ipv6, clampi(int(tail.substr(1)), 1, 65535)]
			return [ipv6, fallback_port]
	var colon := text.rfind(":")
	if colon > 0:
		var maybe_port := text.substr(colon + 1).strip_edges()
		var maybe_host := text.substr(0, colon).strip_edges()
		if maybe_port.is_valid_int() and not maybe_host.is_empty() and not maybe_host.contains(":"):
			var parsed_port := int(maybe_port)
			if parsed_port >= 1 and parsed_port <= 65535:
				return [maybe_host, parsed_port]
	return [text, fallback_port]


func _inbound_tcp_allowed() -> bool:
	if OS.get_name() != "Windows":
		return true
	if _firewall_rule_exists("GetLevelOfAMonkey"):
		return true
	var exe_name := OS.get_executable_path().get_file()
	if exe_name.is_empty():
		return false
	var output: Array = []
	var cmd := (
		"$rules = @(Get-NetFirewallRule -DisplayName '%s' -ErrorAction SilentlyContinue); "
		+ "foreach ($r in $rules) { if (-not $r.Enabled) { continue }; "
		+ "$p = $r | Get-NetFirewallPortFilter; "
		+ "if ($r.Action -eq 'Allow' -and $p.Protocol -eq 'TCP') { 'YES'; break } }"
	) % exe_name
	OS.execute(
		_powershell_exe(),
		PackedStringArray(["-NoProfile", "-Command", cmd]),
		output,
		true,
		true,
	)
	for line in output:
		if "YES" in str(line):
			return true
	return false


func _powershell_exe() -> String:
	var system_root := OS.get_environment("SystemRoot")
	if system_root.is_empty():
		system_root = "C:/Windows"
	var candidate := system_root.path_join("System32/WindowsPowerShell/v1.0/powershell.exe")
	if FileAccess.file_exists(candidate):
		return candidate
	return "powershell.exe"


func _request_firewall_rule(port: int) -> void:
	var exe := OS.get_executable_path().replace("/", "\\")
	var bat_path := ProjectSettings.globalize_path("user://allow_lan_port.bat")
	var bat := "netsh advfirewall firewall delete rule name=GetLevelOfAMonkey\r\n"
	bat += "netsh advfirewall firewall add rule name=GetLevelOfAMonkey dir=in action=allow program=\"%s\" protocol=TCP localport=%d profile=any enable=yes\r\n" % [exe, port]
	var file := FileAccess.open("user://allow_lan_port.bat", FileAccess.WRITE)
	if file == null:
		return
	file.store_string(bat)
	file.close()
	var cmd := "Start-Process -FilePath '%s' -Verb RunAs -Wait" % bat_path.replace("/", "\\")
	OS.execute(_powershell_exe(), PackedStringArray(["-NoProfile", "-WindowStyle", "Hidden", "-Command", cmd]), [], true, true)


func _firewall_rule_exists(rule: String) -> bool:
	var code := OS.execute(
		"netsh",
		PackedStringArray(["advfirewall", "firewall", "show", "rule", "name=%s" % rule]),
		[],
		true,
		true,
	)
	return code == 0


func set_lan_browse(enabled: bool) -> void:
	_browse_enabled = enabled
	if not enabled:
		_lan_hosts.clear()
		lan_hosts_changed.emit()
	if enabled or _beacon_enabled:
		_ensure_udp()
	else:
		_close_udp()


func get_lan_hosts() -> Array:
	var out: Array = []
	for key in _lan_hosts.keys():
		out.append(_lan_hosts[key])
	return out


func _poll_discovery(delta: float) -> void:
	if _udp == null:
		return
	if _beacon_enabled:
		_beacon_accum += delta
		if _beacon_accum >= BEACON_INTERVAL:
			_beacon_accum = 0.0
			_send_beacon()
	var added := false
	while _udp.get_available_packet_count() > 0:
		var packet := _udp.get_packet()
		var ip := _udp.get_packet_ip()
		if _take_beacon(ip, packet):
			added = true
	if _drop_stale_lan_hosts() or added:
		lan_hosts_changed.emit()


func _ensure_udp() -> bool:
	if _udp != null:
		return true
	var udp := PacketPeerUDP.new()
	udp.set_broadcast_enabled(true)
	if udp.bind(DISCOVERY_PORT, "*") != OK:
		return false
	_udp = udp
	return true


func _close_udp() -> void:
	if _udp != null:
		_udp.close()
		_udp = null


func _send_beacon() -> void:
	if not _ensure_udp():
		return
	var payload := JSON.stringify({
		"g": "glom",
		"port": default_port,
		"name": GameState.player_name(),
	}).to_utf8_buffer()
	var targets: Array[String] = ["255.255.255.255"]
	var subnet := _subnet_broadcast(_lan_ip())
	if not subnet.is_empty():
		targets.append(subnet)
	for dest in targets:
		_udp.set_dest_address(dest, DISCOVERY_PORT)
		_udp.put_packet(payload)


func _take_beacon(ip: String, packet: PackedByteArray) -> bool:
	if _is_local_ip(ip):
		return false
	var text := packet.get_string_from_utf8().strip_edges()
	if text.length() < 2 or not text.begins_with("{") or not text.ends_with("}"):
		return false
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY or str(data.get("g", "")) != "glom":
		return false
	var port := int(data.get("port", default_port))
	if port < 1 or port > 65535:
		return false
	var key := "%s:%d" % [ip, port]
	var is_new := not _lan_hosts.has(key)
	_lan_hosts[key] = {
		"ip": ip,
		"port": port,
		"name": str(data.get("name", "")),
		"seen": Time.get_ticks_msec() / 1000.0,
	}
	return is_new


func _drop_stale_lan_hosts() -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	var removed := false
	for key in _lan_hosts.keys():
		if now - float(_lan_hosts[key].get("seen", 0.0)) > LAN_HOST_TTL:
			_lan_hosts.erase(key)
			removed = true
	return removed


func _subnet_broadcast(ip: String) -> String:
	var parts := ip.split(".")
	if parts.size() != 4 or ip == "127.0.0.1":
		return ""
	return "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]


func _is_local_ip(ip: String) -> bool:
	if ip == "127.0.0.1" or ip == "::1" or ip == "0.0.0.0":
		return true
	for address in IP.get_local_addresses():
		if str(address) == ip:
			return true
	return false


func _lan_ip() -> String:
	var skip := [
		"loopback", "bluetooth", "tap", "tun", "vpn", "wsl", "hyper-v", "vethernet",
		"virtual", "nekoray", "openvpn", "vmware", "vbox", "pseudo", "npcap", "hamachi",
	]
	var candidates: Array[String] = []
	for iface in IP.get_local_interfaces():
		if typeof(iface) != TYPE_DICTIONARY:
			continue
		var label := (str(iface.get("friendly", "")) + " " + str(iface.get("name", ""))).to_lower()
		var blocked := false
		for word in skip:
			if word in label:
				blocked = true
				break
		if blocked:
			continue
		for address in iface.get("addresses", []):
			var ip := str(address)
			if ip.begins_with("192.168.") or ip.begins_with("10.") or _is_private_172(ip):
				candidates.append(ip)
	for ip in candidates:
		if ip.begins_with("192.168."):
			return ip
	for ip in candidates:
		if ip.begins_with("10."):
			return ip
	if not candidates.is_empty():
		return candidates[0]
	return "127.0.0.1"


func _is_private_172(ip: String) -> bool:
	if not ip.begins_with("172."):
		return false
	var parts := ip.split(".")
	if parts.size() < 2:
		return false
	var second := int(parts[1])
	return second >= 16 and second <= 31
