@tool
extends Control

signal closed

var _from_pause: bool = false
var _rebind_config_key: String = ""
var _rebind_button: Button = null
var _block_cheater_signal: bool = false
var _block_display_signals: bool = false
var _block_bl_signals: bool = false
var _block_control_device_signals: bool = false

@onready var _title: Label = $Panel/Margin/VBox/Header/Title
@onready var _close_btn: Button = $Panel/Margin/VBox/Header/CloseBtn
@onready var _tabs: TabContainer = $Panel/Margin/VBox/Tabs
@onready var _tab_display: Control = $Panel/Margin/VBox/Tabs/Display
@onready var _tab_controls: Control = $Panel/Margin/VBox/Tabs/Controls
@onready var _tab_brainlink: Control = $Panel/Margin/VBox/Tabs/BrainLink
@onready var _lang_en: Button = $Panel/Margin/VBox/Tabs/Display/LangRow/LangEn
@onready var _lang_ru: Button = $Panel/Margin/VBox/Tabs/Display/LangRow/LangRu
@onready var _cheater: CheckBox = $Panel/Margin/VBox/Tabs/Display/CheaterRow/CheaterCheck
@onready var _resolution: OptionButton = $Panel/Margin/VBox/Tabs/Display/ResRow/Resolution
@onready var _fullscreen: CheckBox = $Panel/Margin/VBox/Tabs/Display/FullRow/FullscreenCheck
@onready var _apply_display: Button = $Panel/Margin/VBox/Tabs/Display/ApplyDisplay
@onready var _keyboard_enabled: CheckBox = $Panel/Margin/VBox/Tabs/Controls/KeyboardEnabled
@onready var _gamepad_enabled: CheckBox = $Panel/Margin/VBox/Tabs/Controls/GamepadEnabled
@onready var _controls_grid: GridContainer = $Panel/Margin/VBox/Tabs/Controls/Scroll/Grid
@onready var _rebind_hint: Label = $Panel/Margin/VBox/Tabs/Controls/RebindHint
@onready var _bl_keyboard: CheckBox = $Panel/Margin/VBox/Tabs/BrainLink/BlKeyboard
@onready var _bl_history: CheckBox = $Panel/Margin/VBox/Tabs/BrainLink/BlHistory
@onready var _bl_ml: CheckBox = $Panel/Margin/VBox/Tabs/BrainLink/BlMl
@onready var _bl_events: CheckBox = $Panel/Margin/VBox/Tabs/BrainLink/BlEvents
@onready var _bl_advanced: Button = $Panel/Margin/VBox/Tabs/BrainLink/BlAdvanced


func _ready() -> void:
	if Engine.is_editor_hint():
		mouse_filter = Control.MOUSE_FILTER_STOP
		call_deferred("ensure_editor_preview_content")
		return
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	GameUiTheme.apply_to_node(self)
	GameUiTheme.apply_modal_overlay($Backdrop)
	_close_btn.pressed.connect(_on_close_pressed)
	_lang_en.pressed.connect(func(): I18n.set_locale("en"))
	_lang_ru.pressed.connect(func(): I18n.set_locale("ru"))
	_cheater.toggled.connect(_on_cheater_toggled)
	_apply_display.pressed.connect(_on_apply_display)
	_fullscreen.toggled.connect(_on_fullscreen_toggled)
	_resolution.item_selected.connect(_on_resolution_selected)
	_bl_keyboard.toggled.connect(func(v): _on_bl_toggle("send_keyboard_events", v))
	_bl_history.toggled.connect(func(v): _on_bl_toggle("send_to_history", v))
	_bl_ml.toggled.connect(func(v): _on_bl_toggle("send_to_ml", v))
	_bl_events.toggled.connect(func(v): _on_bl_toggle("send_brainlink_events", v))
	_bl_advanced.pressed.connect(_on_bl_advanced)
	_keyboard_enabled.toggled.connect(_on_keyboard_enabled_toggled)
	_gamepad_enabled.toggled.connect(_on_gamepad_enabled_toggled)
	if not I18n.locale_changed.is_connected(_refresh_locale):
		I18n.locale_changed.connect(_refresh_locale)
	_build_control_rows()
	_init_resolution_options()
	call_deferred("_apply_tabs_theme")


func ensure_editor_preview_content() -> void:
	if not Engine.is_editor_hint():
		return
	if GameUiTheme.is_edited_scene_root(self):
		visible = true
		_build_editor_dynamic_content()
	GameUiTheme.apply_editor_preview(self)
	call_deferred("_apply_tabs_theme")


func prepare_editor_preview_visible() -> void:
	if not Engine.is_editor_hint():
		return
	visible = true
	_build_editor_dynamic_content()
	GameUiTheme.apply_editor_preview(self)
	call_deferred("_apply_tabs_theme")


func _build_editor_dynamic_content() -> void:
	if _resolution.item_count == 0:
		_init_resolution_options()
	if _controls_grid.get_child_count() == 0:
		_build_control_rows()


func _apply_tabs_theme() -> void:
	GameUiTheme.apply_tab_container_styles(_tabs)


func open(from_pause: bool) -> void:
	_from_pause = from_pause
	_rebind_config_key = ""
	visible = true
	move_to_front()
	GameUiTheme.style_interactive_tree(self)
	GameUiTheme.apply_tab_container_styles(_tabs)
	_refresh_all()


func close_menu() -> void:
	if not visible:
		return
	_rebind_config_key = ""
	visible = false
	closed.emit()


func _on_close_pressed() -> void:
	close_menu()


func _refresh_locale(_loc: String = "") -> void:
	if not visible:
		return
	_refresh_all()


func _refresh_all() -> void:
	_title.text = I18n.tr_key("settings.title", "Settings")
	_close_btn.text = I18n.tr_key("settings.close", "Close")
	_tabs.set_tab_title(0, I18n.tr_key("settings.tab_resolution", "Display"))
	_tabs.set_tab_title(1, I18n.tr_key("settings.tab_controls", "Controls"))
	_tabs.set_tab_title(2, I18n.tr_key("settings.tab_brainlink", "BrainLink"))
	_tab_display.get_node("LangLabel").text = I18n.tr_key("settings.language", "Language")
	_lang_en.text = I18n.tr_key("settings.lang_en", "English")
	_lang_ru.text = I18n.tr_key("settings.lang_ru", "Russian")
	_cheater.text = "%s %s" % [
		I18n.tr_key("settings.cheater_mode", "Cheater mode"),
		I18n.tr_key("settings.cheater_hint", ""),
	]
	_tab_display.get_node("ResRow/ResLabel").text = I18n.tr_key("settings.resolution", "Resolution")
	_fullscreen.text = I18n.tr_key("settings.fullscreen", "Fullscreen")
	_apply_display.text = I18n.tr_key("settings.apply_display", "Apply display")
	_rebind_hint.text = I18n.tr_key("settings.rebind_clear_hint", "Backspace to clear")
	_keyboard_enabled.text = I18n.tr_key("settings.keyboard_enabled", "Keyboard")
	_gamepad_enabled.text = I18n.tr_key("settings.gamepad_enabled", "Gamepad / controller")
	_bl_keyboard.text = I18n.tr_key("settings.bl_send_keyboard", "Send keyboard")
	_bl_history.text = I18n.tr_key("settings.bl_send_history", "Send to history")
	_bl_ml.text = I18n.tr_key("settings.bl_send_ml", "Send to ML")
	_bl_events.text = I18n.tr_key("settings.bl_send_events", "Send BrainLink events")
	_bl_advanced.text = I18n.tr_key("menu.brainlink_settings", "BrainLink")
	_refresh_language_buttons()
	_refresh_display_tab()
	_refresh_cheater()
	_refresh_controls_tab()
	_refresh_control_devices()
	_refresh_brainlink_tab()


func _refresh_language_buttons() -> void:
	var loc := I18n.locale()
	_lang_en.disabled = loc == "en"
	_lang_ru.disabled = loc == "ru"


func _refresh_display_tab() -> void:
	var win: Dictionary = ConfigLoader.game_config.get("window", {})
	var w := int(win.get("width", 1280))
	var h := int(win.get("height", 720))
	_block_display_signals = true
	_fullscreen.button_pressed = bool(win.get("fullscreen", false))
	_block_display_signals = false
	for i in _resolution.item_count:
		if _resolution.get_item_metadata(i) == Vector2i(w, h):
			_resolution.select(i)
			break


func _refresh_cheater() -> void:
	var on := bool(ConfigLoader.game_config.get("player", {}).get("cheater_mode", false))
	_block_cheater_signal = true
	_cheater.button_pressed = on
	_block_cheater_signal = false


func _refresh_brainlink_tab() -> void:
	var bl: Dictionary = ConfigLoader.game_config.get("brainlink", {})
	_block_bl_signals = true
	_bl_keyboard.button_pressed = bool(bl.get("send_keyboard_events", true))
	_bl_history.button_pressed = bool(bl.get("send_to_history", true))
	_bl_ml.button_pressed = bool(bl.get("send_to_ml", false))
	_bl_events.button_pressed = bool(bl.get("send_brainlink_events", true))
	_block_bl_signals = false


func _init_resolution_options() -> void:
	_resolution.clear()
	for res: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(1600, 900)]:
		_resolution.add_item("%d x %d" % [res.x, res.y])
		_resolution.set_item_metadata(_resolution.item_count - 1, res)


func _build_control_rows() -> void:
	if _controls_grid.get_child_count() > 0:
		return
	for row in GameControls.CONTROL_ROWS:
		var cfg_key: String = row["config"]
		var label := Label.new()
		label.text = I18n.tr_key(row["label_key"], cfg_key)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var btn := Button.new()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(120, 44)
		GameUiTheme.menu_button_settings(btn)
		btn.pressed.connect(_on_rebind_pressed.bind(cfg_key, btn))
		btn.set_meta("config_key", cfg_key)
		_controls_grid.add_child(label)
		_controls_grid.add_child(btn)


func _refresh_control_devices() -> void:
	var controls: Dictionary = ConfigLoader.game_config.get("controls", {})
	_block_control_device_signals = true
	_keyboard_enabled.button_pressed = bool(controls.get("keyboard_enabled", true))
	_gamepad_enabled.button_pressed = bool(controls.get("gamepad_enabled", false))
	_block_control_device_signals = false


func _on_keyboard_enabled_toggled(on: bool) -> void:
	if _block_control_device_signals:
		return
	GameControls.set_keyboard_enabled(on)
	_refresh_control_devices()


func _on_gamepad_enabled_toggled(on: bool) -> void:
	if _block_control_device_signals:
		return
	GameControls.set_gamepad_enabled(on)
	_refresh_control_devices()


func _refresh_controls_tab() -> void:
	var kb := GameControls.keyboard_from_config()
	var i := 0
	for row in GameControls.CONTROL_ROWS:
		var label: Label = _controls_grid.get_child(i * 2) as Label
		var btn: Button = _controls_grid.get_child(i * 2 + 1) as Button
		label.text = I18n.tr_key(row["label_key"], row["config"])
		var alias := str(kb.get(row["config"], ""))
		if btn == _rebind_button and _rebind_config_key == row["config"]:
			btn.text = I18n.tr_key("settings.rebind_wait", "...")
		else:
			btn.text = GameControls.display_label(alias)
		i += 1


func _on_rebind_pressed(config_key: String, btn: Button) -> void:
	_rebind_config_key = config_key
	_rebind_button = btn
	btn.text = I18n.tr_key("settings.rebind_wait", "...")
	btn.grab_focus()


func _on_cheater_toggled(on: bool) -> void:
	if _block_cheater_signal:
		return
	var p_cfg: Dictionary = ConfigLoader.game_config.get("player", {}).duplicate(true)
	p_cfg["cheater_mode"] = on
	ConfigLoader.save_user_settings({"player": p_cfg})
	GameState.cheater_mode = on
	var root := get_tree().current_scene
	if root and root.has_method("get_player"):
		var p = root.get_player()
		if p:
			p.cheater_mode = on


func _on_fullscreen_toggled(on: bool) -> void:
	if _block_display_signals:
		return
	var win: Dictionary = ConfigLoader.game_config.get("window", {}).duplicate(true)
	win["fullscreen"] = on
	ConfigLoader.save_user_settings({"window": win})


func _on_resolution_selected(_index: int) -> void:
	if _block_display_signals:
		return
	var res: Vector2i = _resolution.get_selected_metadata()
	var win: Dictionary = ConfigLoader.game_config.get("window", {}).duplicate(true)
	win["width"] = res.x
	win["height"] = res.y
	ConfigLoader.save_user_settings({"window": win})


func _on_apply_display() -> void:
	GameBootstrap.apply_window_from_config()


func _on_bl_toggle(key: String, value: bool) -> void:
	if _block_bl_signals:
		return
	var bl: Dictionary = ConfigLoader.game_config.get("brainlink", {}).duplicate(true)
	bl[key] = value
	ConfigLoader.save_user_settings({"brainlink": bl})
	InputManager._load_brainlink_send_flags()


func _on_bl_advanced() -> void:
	var from_pause := _from_pause
	GameUI.show_brainlink_settings(from_pause)
	close_menu()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if _rebind_config_key.is_empty():
		if event.is_action_pressed("ui_cancel"):
			close_menu()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_BACKSPACE or event.physical_keycode == KEY_BACKSPACE:
			GameControls.clear_keyboard_binding(_rebind_config_key)
		else:
			var alias := GameControls.alias_from_input_event(event)
			if not alias.is_empty():
				GameControls.save_keyboard_binding(_rebind_config_key, alias)
		_rebind_config_key = ""
		_rebind_button = null
		_refresh_controls_tab()
		get_viewport().set_input_as_handled()
