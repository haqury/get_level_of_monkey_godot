extends Node

## Logical world units → pixels for rendering (масштаб под окно задаёт fit_pixels_per_unit_to_viewport).
var PIXELS_PER_UNIT: float = 24.0
const PIXELS_PER_UNIT_DEFAULT := 24.0
const EXIT_RADIUS := 3.0
const NPC_INTERACT_RADIUS := 1.6

enum MpRole { OFFLINE, HOST, CLIENT }

var in_game: bool = false
var mp_role: MpRole = MpRole.OFFLINE
var session_id: String = ""
var local_player_id: int = 0
var monkey_mode: String = "NorthSouth"
var current_scene_id: String = "main_menu"
var pending_scene_extra: Dictionary = {}
## Локация для первой загрузки после перехода в game_session (cave/kitchen/…).
var startup_world_scene: String = ""

var cheater_mode: bool = false


func _ready() -> void:
	var p_cfg: Dictionary = ConfigLoader.game_config.get("player", {})
	cheater_mode = bool(p_cfg.get("cheater_mode", false))


func player_name() -> String:
	var n: String = str(ConfigLoader.game_config.get("player", {}).get("name", "Player"))
	return n.substr(0, 64)


func is_host() -> bool:
	return mp_role == MpRole.HOST


func is_client() -> bool:
	return mp_role == MpRole.CLIENT


func is_online() -> bool:
	return mp_role != MpRole.OFFLINE


func units_to_px(v: Vector2) -> Vector2:
	return v * PIXELS_PER_UNIT


func px_to_units(v: Vector2) -> Vector2:
	return v / PIXELS_PER_UNIT


func bounds_size_units(bounds: Dictionary) -> Vector2:
	return Vector2(
		float(bounds.get("max_x", 0.0)) - float(bounds.get("min_x", 0.0)),
		float(bounds.get("max_y", 0.0)) - float(bounds.get("min_y", 0.0)),
	)


func bounds_center_units(bounds: Dictionary) -> Vector2:
	return Vector2(
		(float(bounds.get("min_x", 0.0)) + float(bounds.get("max_x", 0.0))) * 0.5,
		(float(bounds.get("min_y", 0.0)) + float(bounds.get("max_y", 0.0))) * 0.5,
	)


## Вписать локацию (в игровых единицах) в размер viewport по большей стороне без обрезки.
func fit_pixels_per_unit_to_viewport(viewport_px: Vector2, bounds: Dictionary) -> void:
	var size_u := bounds_size_units(bounds)
	if size_u.x < 0.001 or size_u.y < 0.001 or viewport_px.x < 1.0 or viewport_px.y < 1.0:
		PIXELS_PER_UNIT = PIXELS_PER_UNIT_DEFAULT
		return
	PIXELS_PER_UNIT = minf(viewport_px.x / size_u.x, viewport_px.y / size_u.y)
