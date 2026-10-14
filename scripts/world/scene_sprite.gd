@tool
extends Sprite2D
class_name SceneSprite

## Размер спрайта в игровых единицах (при расчёте в редакторе: 24 px/ед.).
@export var size_units: Vector2 = Vector2(1.0, 1.0):
	set(v):
		size_units = v
		_apply_scale()

## Пол и стены: текстура повторяется, а не растягивается на всю площадь.
@export var tiled: bool = false:
	set(v):
		tiled = v
		_apply_scale()


func _ready() -> void:
	_apply_scale()


func _apply_scale() -> void:
	if texture == null:
		return
	var ppu := BaseLocation.DESIGN_PPU
	if tiled:
		region_enabled = true
		region_rect = Rect2(0, 0, size_units.x * ppu, size_units.y * ppu)
		texture_repeat = CanvasItem.TEXTURE_REPEAT_MIRROR
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		scale = Vector2.ONE
		centered = true
		return
	region_enabled = false
	texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
	var tw := maxf(1.0, float(texture.get_width()))
	var th := maxf(1.0, float(texture.get_height()))
	scale = Vector2(size_units.x * ppu / tw, size_units.y * ppu / th)
