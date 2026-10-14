class_name GameUiTheme
extends RefCounted

const FONT_PATH := "res://assets/fonts/segoeui.ttf"

const COLOR_SKY_TOP := Color(0.45, 0.78, 0.98)
const COLOR_SKY_BOTTOM := Color(0.65, 0.92, 0.55)
const COLOR_PANEL := Color(1.0, 0.97, 0.88, 0.96)
const COLOR_PANEL_BORDER := Color(0.95, 0.72, 0.35)
const COLOR_BTN := Color(1.0, 0.68, 0.32)
const COLOR_BTN_HOVER := Color(1.0, 0.78, 0.45)
const COLOR_BTN_PRESSED := Color(0.92, 0.55, 0.22)
const COLOR_BTN_DISABLED := Color(0.75, 0.75, 0.75)
const COLOR_TEXT := Color(0.22, 0.18, 0.12)
const COLOR_TITLE := Color(0.85, 0.35, 0.15)
const COLOR_SUBTITLE := Color(0.35, 0.42, 0.55)
const COLOR_OVERLAY := Color(0.25, 0.42, 0.62, 0.68)
const COLOR_HUD_PANEL := Color(1.0, 0.98, 0.92, 0.88)

const TITLE_NODE_NAMES := ["Title", "NameLabel", "PauseTitle"]
const EDITOR_BACKDROP_NAMES := ["Backdrop", "PauseBackdrop", "DialogBackdrop"]
const EDITOR_HUD_PANEL_NAMES := ["HudPanel", "Top10"]


static func is_edited_scene_root(node: Node) -> bool:
	if node == null:
		return false
	var tree := node.get_tree()
	if tree == null:
		return false
	return tree.get_edited_scene_root() == node


## Applies the same runtime menu theme while editing scenes in the Godot editor (@tool scripts).
static func apply_editor_preview(root: Node) -> void:
	if root == null or not Engine.is_editor_hint():
		return
	apply_to_node(root)
	_apply_editor_preview_extras(root)


## Called by the ui_theme_editor plugin when the edited scene changes.
static func sync_edited_scene_root(root: Node) -> void:
	if root == null or not Engine.is_editor_hint():
		return
	apply_editor_preview(root)
	finalize_editor_scene(root)


static func finalize_editor_scene(root: Node) -> void:
	if root == null or not Engine.is_editor_hint():
		return
	_walk_ensure_editor_content(root)
	if root.name == "GameUI" and root.has_method("update_editor_ui_preview"):
		root.update_editor_ui_preview()
	elif root.has_method("ensure_editor_preview_content"):
		root.ensure_editor_preview_content()


static func _walk_ensure_editor_content(node: Node) -> void:
	if node.has_method("ensure_editor_preview_content"):
		node.ensure_editor_preview_content()
	for child in node.get_children():
		_walk_ensure_editor_content(child)


static func apply_to_root(root: Node) -> void:
	if root == null:
		return
	var theme := build()
	root.theme = theme
	for child in root.get_children():
		_propagate_theme(child, theme)
	style_tab_bars(root)


static func apply_to_node(node: Node) -> void:
	if node == null:
		return
	var theme := build()
	_set_theme_recursive(node, theme)
	style_interactive_tree(node)
	style_tab_bars(node)


static func apply_main_menu_style(root: Node) -> void:
	if root == null:
		return
	apply_to_node(root)
	style_main_menu_background(root)
	var panel := root.get_node_or_null("Panel") as PanelContainer
	if panel:
		panel.add_theme_stylebox_override("panel", _panel_style())


static func style_main_menu_background(root: Node) -> void:
	var bg := root.get_node_or_null("Background") as ColorRect
	if bg:
		bg.color = COLOR_SKY_TOP
	var bg_bottom := root.get_node_or_null("BackgroundBottom") as ColorRect
	if bg_bottom:
		bg_bottom.color = COLOR_SKY_BOTTOM


static func build() -> Theme:
	var theme := Theme.new()
	var font := load(FONT_PATH) as FontFile
	if font:
		theme.default_font = font
	theme.default_font_size = 18
	theme.set_color("font_color", "Label", COLOR_TEXT)
	theme.set_color("font_color", "Button", COLOR_TEXT)
	theme.set_color("font_hover_color", "Button", COLOR_TEXT)
	theme.set_color("font_pressed_color", "Button", COLOR_TEXT)
	theme.set_color("font_disabled_color", "Button", Color(0.45, 0.45, 0.45))
	theme.set_color("font_color", "CheckBox", COLOR_TEXT)
	theme.set_color("font_color", "LineEdit", COLOR_TEXT)
	theme.set_color("font_color", "OptionButton", COLOR_TEXT)
	theme.set_font_size("font_size", "Button", 18)
	theme.set_font_size("font_size", "Label", 18)
	theme.set_constant("margin_left", "PanelContainer", 16)
	theme.set_constant("margin_right", "PanelContainer", 16)
	theme.set_constant("margin_top", "PanelContainer", 14)
	theme.set_constant("margin_bottom", "PanelContainer", 14)
	theme.set_constant("h_separation", "VBoxContainer", 10)
	theme.set_constant("v_separation", "GridContainer", 8)
	theme.set_stylebox("panel", "PanelContainer", _panel_style())
	theme.set_stylebox("normal", "Button", _button_style(COLOR_BTN))
	theme.set_stylebox("hover", "Button", _button_style(COLOR_BTN_HOVER))
	theme.set_stylebox("pressed", "Button", _button_style(COLOR_BTN_PRESSED))
	theme.set_stylebox("disabled", "Button", _button_style(COLOR_BTN_DISABLED))
	theme.set_stylebox("focus", "Button", _button_style(COLOR_BTN_HOVER, 3))
	theme.set_stylebox("normal", "LineEdit", _field_style())
	theme.set_stylebox("focus", "LineEdit", _field_style(true))
	theme.set_stylebox("normal", "OptionButton", _button_style(Color(1.0, 0.92, 0.78)))
	theme.set_stylebox("hover", "OptionButton", _button_style(COLOR_BTN_HOVER))
	theme.set_stylebox("pressed", "OptionButton", _button_style(COLOR_BTN_PRESSED))
	theme.set_stylebox("focus", "OptionButton", _button_style(COLOR_BTN_HOVER, 3))
	theme.set_stylebox("normal", "SpinBox", _field_style())
	theme.set_stylebox("focus", "SpinBox", _field_style(true))
	_register_tab_theme(theme)
	theme.set_stylebox("normal", "CheckBox", _field_style())
	theme.set_stylebox("hover", "CheckBox", _field_style(true))
	theme.set_stylebox("pressed", "CheckBox", _field_style(true))
	return theme


static func style_interactive_tree(root: Node) -> void:
	if root == null:
		return
	if root is Button:
		menu_button_settings(root as Button)
	elif root is Label:
		var label := root as Label
		if label.name in TITLE_NODE_NAMES:
			title_label_settings(label)
		elif label.name == "Subtitle":
			subtitle_label_settings(label)
	elif root is LineEdit:
		(root as LineEdit).custom_minimum_size.y = 42.0
	elif root is OptionButton:
		(root as OptionButton).custom_minimum_size.y = 42.0
	elif root is SpinBox:
		(root as SpinBox).custom_minimum_size.y = 38.0
	for child in root.get_children():
		style_interactive_tree(child)


static func apply_modal_overlay(rect: ColorRect) -> void:
	if rect:
		rect.color = COLOR_OVERLAY


static func style_hud_panel(panel: PanelContainer) -> void:
	if panel == null:
		return
	var box := _panel_style(14)
	box.bg_color = COLOR_HUD_PANEL
	panel.add_theme_stylebox_override("panel", box)


static func title_label_settings(label: Label) -> void:
	label.add_theme_color_override("font_color", COLOR_TITLE)
	label.add_theme_font_size_override("font_size", 26)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


static func subtitle_label_settings(label: Label) -> void:
	label.add_theme_color_override("font_color", COLOR_SUBTITLE)
	label.add_theme_font_size_override("font_size", 16)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


static func menu_button_settings(btn: Button) -> void:
	btn.custom_minimum_size = Vector2(0, 48)
	btn.focus_mode = Control.FOCUS_ALL


static func style_tab_bars(root: Node) -> void:
	if root is TabContainer:
		apply_tab_container_styles(root as TabContainer)
	if root is TabBar:
		apply_tab_bar_styles(root as TabBar)
	for child in root.get_children():
		style_tab_bars(child)


static func apply_tab_container_styles(tabs: TabContainer) -> void:
	if tabs == null:
		return
	tabs.add_theme_stylebox_override("panel", _tab_content_panel_style())
	tabs.add_theme_stylebox_override("tabbar_background", _tabbar_background_style())
	apply_tab_bar_style_overrides(tabs)
	var bar := tabs.get_tab_bar()
	if bar:
		apply_tab_bar_styles(bar)


static func apply_tab_bar_styles(bar: TabBar) -> void:
	if bar == null:
		return
	apply_tab_bar_style_overrides(bar)


static func apply_tab_bar_style_overrides(control: Control) -> void:
	control.add_theme_stylebox_override("tab_selected", _tab_style(COLOR_BTN, true))
	control.add_theme_stylebox_override("tab_unselected", _tab_style(Color(1.0, 0.92, 0.78), false))
	control.add_theme_stylebox_override("tab_hovered", _tab_style(COLOR_BTN_HOVER, false))
	control.add_theme_stylebox_override("tab_focus", _tab_style(COLOR_BTN_HOVER, true))
	control.add_theme_stylebox_override("tab_disabled", _tab_style(COLOR_BTN_DISABLED, false))
	control.add_theme_color_override("font_selected_color", COLOR_TEXT)
	control.add_theme_color_override("font_unselected_color", COLOR_TEXT)
	control.add_theme_color_override("font_hovered_color", COLOR_TEXT)
	control.add_theme_color_override("font_disabled_color", Color(0.45, 0.45, 0.45))
	control.add_theme_font_size_override("font_size", 18)
	control.add_theme_constant_override("h_separation", 8)
	control.add_theme_constant_override("outline_padding", 6)


static func _register_tab_theme(theme: Theme) -> void:
	var selected := _tab_style(COLOR_BTN, true)
	var unselected := _tab_style(Color(1.0, 0.92, 0.78), false)
	var hovered := _tab_style(COLOR_BTN_HOVER, false)
	var focus := _tab_style(COLOR_BTN_HOVER, true)
	var disabled := _tab_style(COLOR_BTN_DISABLED, false)
	for type_name: String in ["TabContainer", "TabBar"]:
		theme.set_stylebox("tab_selected", type_name, selected)
		theme.set_stylebox("tab_unselected", type_name, unselected)
		theme.set_stylebox("tab_hovered", type_name, hovered)
		theme.set_stylebox("tab_focus", type_name, focus)
		theme.set_stylebox("tab_disabled", type_name, disabled)
		theme.set_color("font_selected_color", type_name, COLOR_TEXT)
		theme.set_color("font_unselected_color", type_name, COLOR_TEXT)
		theme.set_color("font_hovered_color", type_name, COLOR_TEXT)
		theme.set_color("font_disabled_color", type_name, Color(0.45, 0.45, 0.45))
		theme.set_font_size("font_size", type_name, 18)
		theme.set_constant("h_separation", type_name, 8)
		theme.set_constant("outline_padding", type_name, 6)
	theme.set_stylebox("panel", "TabContainer", _tab_content_panel_style())
	theme.set_stylebox("tabbar_background", "TabContainer", _tabbar_background_style())


static func _apply_editor_preview_extras(node: Node) -> void:
	if node is ColorRect and node.name in EDITOR_BACKDROP_NAMES:
		apply_modal_overlay(node as ColorRect)
	if node is TabContainer:
		apply_tab_container_styles(node as TabContainer)
	if node is PanelContainer and node.name in EDITOR_HUD_PANEL_NAMES:
		style_hud_panel(node as PanelContainer)
	for child in node.get_children():
		_apply_editor_preview_extras(child)


static func _propagate_theme(node: Node, theme: Theme) -> void:
	if node is Control:
		(node as Control).theme = theme
	for child in node.get_children():
		_propagate_theme(child, theme)


static func _set_theme_recursive(node: Node, theme: Theme) -> void:
	if node is Control:
		(node as Control).theme = theme
	for child in node.get_children():
		_set_theme_recursive(child, theme)


static func _panel_style(radius: int = 18) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = COLOR_PANEL
	box.border_color = COLOR_PANEL_BORDER
	box.set_border_width_all(3)
	box.set_corner_radius_all(radius)
	box.set_content_margin_all(12)
	box.shadow_color = Color(0, 0, 0, 0.18)
	box.shadow_size = 6
	box.shadow_offset = Vector2(0, 3)
	return box


static func _button_style(color: Color, border_w: int = 2) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = COLOR_PANEL_BORDER.darkened(0.15)
	box.set_border_width_all(border_w)
	box.set_corner_radius_all(14)
	box.set_content_margin(Side.SIDE_LEFT, 16)
	box.set_content_margin(Side.SIDE_RIGHT, 16)
	box.set_content_margin(Side.SIDE_TOP, 10)
	box.set_content_margin(Side.SIDE_BOTTOM, 10)
	return box


static func _field_style(focused: bool = false) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(1, 1, 1, 0.95)
	box.border_color = COLOR_PANEL_BORDER if focused else Color(0.8, 0.8, 0.75)
	box.set_border_width_all(2 if focused else 1)
	box.set_corner_radius_all(10)
	box.set_content_margin_all(8)
	return box


static func _tabbar_background_style() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = COLOR_PANEL
	box.border_color = COLOR_PANEL_BORDER
	box.set_border_width_all(0)
	box.set_content_margin(Side.SIDE_LEFT, 8)
	box.set_content_margin(Side.SIDE_RIGHT, 8)
	box.set_content_margin(Side.SIDE_TOP, 8)
	box.set_content_margin(Side.SIDE_BOTTOM, 0)
	return box


static func _tab_content_panel_style() -> StyleBoxFlat:
	var box := _panel_style(14)
	box.bg_color = COLOR_PANEL
	box.set_corner_radius(Corner.CORNER_TOP_LEFT, 0)
	box.set_corner_radius(Corner.CORNER_TOP_RIGHT, 0)
	return box


static func _tab_style(bg: Color, selected: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = COLOR_PANEL_BORDER
	box.set_border_width(Side.SIDE_LEFT, 2)
	box.set_border_width(Side.SIDE_RIGHT, 2)
	box.set_border_width(Side.SIDE_TOP, 2)
	box.set_border_width(Side.SIDE_BOTTOM, 0 if selected else 2)
	box.set_corner_radius(Corner.CORNER_TOP_LEFT, 14)
	box.set_corner_radius(Corner.CORNER_TOP_RIGHT, 14)
	box.set_corner_radius(Corner.CORNER_BOTTOM_LEFT, 0)
	box.set_corner_radius(Corner.CORNER_BOTTOM_RIGHT, 0)
	box.set_content_margin(Side.SIDE_LEFT, 14)
	box.set_content_margin(Side.SIDE_RIGHT, 14)
	box.set_content_margin(Side.SIDE_TOP, 8)
	box.set_content_margin(Side.SIDE_BOTTOM, 8)
	return box
