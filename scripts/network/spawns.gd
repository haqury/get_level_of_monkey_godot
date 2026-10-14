class_name MultiplayerSpawns
extends RefCounted

const MULTIPLAYER_SPAWN: Dictionary = {
	"cave": [Vector2(0, 0), Vector2(-4, 0)],
	"kitchen": [Vector2(10, 0), Vector2(6, 0)],
	"minigame": [Vector2(0, 0), Vector2(2, 0)],
	"main_menu": [Vector2.ZERO, Vector2.ZERO],
}


static func spawn_for(scene_id: String, player_id: int) -> Vector2:
	var points: Array = MULTIPLAYER_SPAWN.get(scene_id, [Vector2.ZERO, Vector2.ZERO])
	var idx := 0 if player_id == 0 else 1
	if idx >= points.size():
		idx = 0
	return points[idx] as Vector2
