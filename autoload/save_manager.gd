extends Node

const SAVE_PATH := "user://saves/game_save.json"
const STATS_PATH := "user://saves/minigame_stats.json"


func _ready() -> void:
	_ensure_dir()


func _ensure_dir() -> void:
	var dir_path := "user://saves"
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)


func save_game(data: Dictionary) -> bool:
	_ensure_dir()
	var payload := {
		"version": "1.0",
		"timestamp": Time.get_datetime_string_from_system(),
		"game": data,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(payload, "\t"))
	return true


func load_game() -> Variant:
	if not FileAccess.file_exists(SAVE_PATH):
		return null
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return null
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	return parsed.get("game", null)


func save_minigame_run(time_seconds: float, cheater: bool, username: String, mode: String) -> void:
	var runs: Array = _load_stats_runs()
	runs.append({
		"time": snappedf(time_seconds, 0.1),
		"cheater": cheater,
		"username": username if username != "" else "Player",
		"mode": mode if mode != "" else "NorthSouth",
		"timestamp": Time.get_datetime_string_from_system(),
	})
	_save_stats_runs(runs)


func _load_stats_runs() -> Array:
	if not FileAccess.file_exists(STATS_PATH):
		return []
	var f := FileAccess.open(STATS_PATH, FileAccess.READ)
	if f == null:
		return []
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return []
	return parsed.get("runs", [])


func _save_stats_runs(runs: Array) -> void:
	_ensure_dir()
	var f := FileAccess.open(STATS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"runs": runs}, "\t"))


func get_top10(mode: String, include_cheater: bool = false) -> Array:
	var filtered: Array = []
	for run in _load_stats_runs():
		if typeof(run) != TYPE_DICTIONARY:
			continue
		if str(run.get("mode", "")) != mode:
			continue
		if not include_cheater and bool(run.get("cheater", false)):
			continue
		filtered.append(run)
	filtered.sort_custom(func(a, b): return float(a.get("time", 0)) > float(b.get("time", 0)))
	if filtered.size() > 10:
		return filtered.slice(0, 10)
	return filtered


func get_leader_name(mode: String) -> String:
	var top := get_top10(mode, false)
	if top.is_empty():
		return ""
	return str(top[0].get("username", ""))
