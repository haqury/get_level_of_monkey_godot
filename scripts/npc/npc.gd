extends Node2D

@export var npc_id: String = "npc"
@export var display_name: String = "NPC"
@export var display_name_i18n_key: String = ""
@export var dialog_keys: Array[String] = []
@export var portrait_path: String = ""
@export_file("*.png") var texture_path: String = ""
@export var sprite_size_units: float = 1.2
@export var cooking_texture_paths: PackedStringArray = []
@export var cooking_frame_interval: float = 0.5

var _dialog_index: int = 0


func _ready() -> void:
	if display_name_i18n_key != "":
		display_name = I18n.tr_key(display_name_i18n_key, display_name)
	if texture_path != "":
		setup_texture(texture_path, sprite_size_units, BaseLocation.DESIGN_PPU)
	if cooking_texture_paths.size() > 0:
		setup_cooking_textures(Array(cooking_texture_paths), cooking_frame_interval)


func set_dialog_keys(keys: Array) -> void:
	dialog_keys.clear()
	for k in keys:
		dialog_keys.append(str(k))


func setup_texture(path: String, size_units: float = 1.0, pixels_per_unit: float = -1.0) -> void:
	var sprite: Sprite2D = $Sprite2D
	if sprite == null:
		return
	if ResourceLoader.exists(path):
		sprite.texture = load(path)
	var ppu := pixels_per_unit if pixels_per_unit > 0.0 else GameState.PIXELS_PER_UNIT
	if sprite.texture != null:
		var tw := maxf(1.0, float(sprite.texture.get_width()))
		var s := size_units * ppu / tw
		sprite.scale = Vector2(s, s)


func is_in_range(player_pos: Vector2) -> bool:
	return GameState.px_to_units(global_position).distance_to(player_pos) <= GameState.NPC_INTERACT_RADIUS


func interact() -> void:
	if dialog_keys.is_empty():
		return
	var key := dialog_keys[_dialog_index % dialog_keys.size()]
	_dialog_index += 1
	GameUI.show_dialog(display_name, I18n.tr_key(key, key))


func setup_cooking_textures(paths: Array, interval: float = 0.5) -> void:
	var sprite: Sprite2D = $Sprite2D
	if sprite == null or paths.is_empty():
		return
	var texs: Array[Texture2D] = []
	for p in paths:
		if ResourceLoader.exists(p):
			texs.append(load(p))
	if texs.is_empty():
		return
	var timer := Timer.new()
	timer.wait_time = interval
	timer.autostart = true
	timer.timeout.connect(func():
		if texs.size() > 0:
			sprite.texture = texs[int(Time.get_ticks_msec() / int(interval * 1000)) % texs.size()]
			var tw := maxf(1.0, float(sprite.texture.get_width()))
			var s := 1.2 * BaseLocation.DESIGN_PPU / tw
			sprite.scale = Vector2(s, s)
	)
	add_child(timer)
