class_name WorldVisuals
extends RefCounted

## Спрайты-заглушки 32×32 → размер в игровых единицах через PIXELS_PER_UNIT.


static func solid_sprite(size_units: Vector2, color: Color) -> Sprite2D:
	var px: Vector2 = size_units * GameState.PIXELS_PER_UNIT
	var img := Image.create(maxi(1, int(px.x)), maxi(1, int(px.y)), false, Image.FORMAT_RGBA8)
	img.fill(color)
	var spr := Sprite2D.new()
	spr.texture = ImageTexture.create_from_image(img)
	spr.centered = true
	return spr


static func load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return load("res://icon.svg") as Texture2D


static func tiled_sprite(path: String, size_units: Vector2) -> SceneSprite:
	var spr := SceneSprite.new()
	spr.texture = load_texture(path)
	spr.size_units = size_units
	spr.tiled = true
	return spr


static func floor_sprite(path: String, size_units: Vector2) -> Sprite2D:
	var tex := load_texture(path)
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.centered = true
	var tw := maxf(1.0, float(tex.get_width()))
	var th := maxf(1.0, float(tex.get_height()))
	spr.scale = Vector2(
		size_units.x * GameState.PIXELS_PER_UNIT / tw,
		size_units.y * GameState.PIXELS_PER_UNIT / th,
	)
	return spr


static func wall_sprite(path: String, size_units: Vector2) -> Sprite2D:
	var tex := load_texture(path)
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.centered = true
	var tw := maxf(1.0, float(tex.get_width()))
	var th := maxf(1.0, float(tex.get_height()))
	spr.scale = Vector2(
		size_units.x * GameState.PIXELS_PER_UNIT / tw,
		size_units.y * GameState.PIXELS_PER_UNIT / th,
	)
	return spr


static func prop_sprite(path: String, size_units: float = 1.0) -> Sprite2D:
	var tex := load_texture(path)
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.centered = true
	var tw := maxf(1.0, float(tex.get_width()))
	var s := size_units * GameState.PIXELS_PER_UNIT / tw
	spr.scale = Vector2(s, s)
	return spr


static func scale_sprite_to_units(sprite: Sprite2D, size_units: float) -> void:
	if sprite.texture == null:
		return
	var tw := maxf(1.0, float(sprite.texture.get_width()))
	var s := size_units * GameState.PIXELS_PER_UNIT / tw
	sprite.scale = Vector2(s, s)
