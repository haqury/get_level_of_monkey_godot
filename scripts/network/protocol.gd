class_name NetProtocol
extends RefCounted

const PROTOCOL_VERSION := 1

class MsgType:
	const HELLO := "hello"
	const WELCOME := "welcome"
	const GOODBYE := "goodbye"
	const START_GAME := "start_game"
	const PLAYER_STATE := "player_state"
	const SCENE_CHANGE := "scene_change"
	const DIALOG_EVENT := "dialog_event"
	const MINIGAME_STATE := "minigame_state"
	const PING := "ping"
	const PONG := "pong"


static func encode_message(msg: Dictionary) -> PackedByteArray:
	var line := JSON.stringify(msg)
	return (line + "\n").to_utf8_buffer()


static func decode_line(line: String) -> Variant:
	line = line.strip_edges()
	if line.is_empty():
		return null
	var parsed = JSON.parse_string(line)
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed
	return null


static func make_hello(player_name: String) -> Dictionary:
	return {
		"type": MsgType.HELLO,
		"protocol_version": PROTOCOL_VERSION,
		"player_name": player_name.substr(0, 64),
	}


static func make_welcome(session_id: String, player_id: int, host_name: String) -> Dictionary:
	return {
		"type": MsgType.WELCOME,
		"protocol_version": PROTOCOL_VERSION,
		"session_id": session_id,
		"player_id": player_id,
		"host_name": host_name.substr(0, 64),
	}


static func make_goodbye(reason: String = "") -> Dictionary:
	return {"type": MsgType.GOODBYE, "reason": reason.substr(0, 256)}


static func make_start_game() -> Dictionary:
	return {"type": MsgType.START_GAME}


static func make_player_state(
	player_id: int,
	scene_id: String,
	x: float,
	z: float,
	facing: String,
	is_sitting: bool,
	seq: int,
) -> Dictionary:
	return {
		"type": MsgType.PLAYER_STATE,
		"player_id": player_id,
		"scene_id": scene_id,
		"x": snappedf(x, 0.001),
		"z": snappedf(z, 0.001),
		"facing": facing,
		"is_sitting": is_sitting,
		"seq": seq,
	}


static func make_scene_change(
	scene_id: String,
	spawn_x: float,
	spawn_z: float,
	remote_spawn_x: float,
	remote_spawn_z: float,
	reason: String = "",
	monkey_mode: String = "",
) -> Dictionary:
	var msg := {
		"type": MsgType.SCENE_CHANGE,
		"scene_id": scene_id,
		"spawn_x": spawn_x,
		"spawn_z": spawn_z,
		"remote_spawn_x": remote_spawn_x,
		"remote_spawn_z": remote_spawn_z,
		"reason": reason.substr(0, 128),
	}
	if monkey_mode != "":
		msg["monkey_mode"] = monkey_mode
	return msg


static func make_minigame_state(payload: Dictionary) -> Dictionary:
	var out := {"type": MsgType.MINIGAME_STATE}
	for k in payload.keys():
		out[k] = payload[k]
	return out
