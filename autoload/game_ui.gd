@tool
extends CanvasLayer

enum EditorUiPreview { HUD, PAUSE, DIALOG, SETTINGS, BRAINLINK }

@export var editor_ui_preview: EditorUiPreview = EditorUiPreview.HUD:
	set(value):
		editor_ui_preview = value
		if Engine.is_editor_hint():
			call_deferred("update_editor_ui_preview")

var pause_open: bool = false
var minigame_game_over_open: bool = false
var dialog_open: bool = false
var settings_open: bool = false
var brainlink_settings_open: bool = false

var _settings_from_pause: bool = false
var _brainlink_from_pause: bool = false
var _pause_hidden_for_dialog: bool = false

@onready var hud: Control = $HUD
@onready var dialog: Control = $Dialog
@onready var pause: Control = $Pause
@onready var settings_menu: Control = $SettingsMenu
@onready var brainlink_settings_menu: Control = $BrainlinkSettingsMenu
@onready var hp_label: Label = $HUD/HudPanel/Margin/VBox/HPLabel
@onready var energy_label: Label = $HUD/HudPanel/Margin/VBox/EnergyLabel
@onready var level_label: Label = $HUD/HudPanel/Margin/VBox/LevelLabel
@onready var ml_label: Label = $HUD/HudPanel/Margin/VBox/MLLabel
@onready var timer_label: Label = $HUD/HudPanel/Margin/VBox/TimerLabel
@onready var top10_panel: Control = $HUD/Top10
@onready var dialog_name: Label = $Dialog/Panel/Margin/VBox/NameLabel
@onready var dialog_text: Label = $Dialog/Panel/Margin/VBox/TextLabel
@onready var dialog_buttons: VBoxContainer = $Dialog/Panel/Margin/VBox/Buttons

var _dialog_callback: Callable


func update_editor_ui_preview() -> void:
	if not Engine.is_editor_hint():
		return
	var edited := get_tree().get_edited_scene_root()
	if edited != self:
		return
	var hud_n := get_node_or_null("HUD") as Control
	var pause_n := get_node_or_null("Pause") as Control
	var dialog_n := get_node_or_null("Dialog") as Control
	var settings_n := get_node_or_null("SettingsMenu") as Control
	var brainlink_n := get_node_or_null("BrainlinkSettingsMenu") as Control
	for n in [hud_n, pause_n, dialog_n, settings_n, brainlink_n]:
		if n:
			n.hide()
	match editor_ui_preview:
		EditorUiPreview.HUD:
			if hud_n:
				hud_n.show()
		EditorUiPreview.PAUSE:
			if pause_n:
				pause_n.show()
				_refresh_pause_menu()
		EditorUiPreview.DIALOG:
			if dialog_n:
				dialog_n.show()
		EditorUiPreview.SETTINGS:
			if settings_n:
				settings_n.show()
				if settings_n.has_method("prepare_editor_preview_visible"):
					settings_n.prepare_editor_preview_visible()
		EditorUiPreview.BRAINLINK:
			if brainlink_n:
				brainlink_n.show()
				if brainlink_n.has_method("prepare_editor_preview_visible"):
					brainlink_n.prepare_editor_preview_visible()
	GameUiTheme.apply_editor_preview(self)


func _ready() -> void:
	if Engine.is_editor_hint():
		call_deferred("update_editor_ui_preview")
		return
	layer = 100
	GameUiTheme.apply_to_node(self)
	GameUiTheme.apply_modal_overlay(pause.get_node("PauseBackdrop"))
	if dialog.has_node("DialogBackdrop"):
		GameUiTheme.apply_modal_overlay(dialog.get_node("DialogBackdrop") as ColorRect)
	GameUiTheme.style_hud_panel(hud.get_node("HudPanel") as PanelContainer)
	GameUiTheme.style_hud_panel(top10_panel)
	hud.hide()
	dialog.hide()
	pause.hide()
	top10_panel.hide()
	timer_label.hide()
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not BrainLinkBridge.connection_changed.is_connected(_on_brainlink_connection_changed):
		BrainLinkBridge.connection_changed.connect(_on_brainlink_connection_changed)
	if not I18n.locale_changed.is_connected(_on_locale_changed):
		I18n.locale_changed.connect(_on_locale_changed)
	settings_menu.closed.connect(_on_settings_closed)
	brainlink_settings_menu.closed.connect(_on_brainlink_settings_closed)
	_refresh_pause_menu()


func _on_brainlink_connection_changed(_connected: bool) -> void:
	if hud.visible:
		refresh_hud()


func _on_locale_changed(_locale: String) -> void:
	if minigame_game_over_open:
		_refresh_minigame_game_over_menu()
	else:
		_refresh_pause_menu()
	if hud.visible:
		refresh_hud()


func _unhandled_input(event: InputEvent) -> void:
	if settings_open or brainlink_settings_open or minigame_game_over_open:
		return
	if not GameState.in_game:
		return
	if event.is_action_pressed("ui_cancel"):
		toggle_pause()
	if event.is_action_pressed("sit_pause") and not dialog_open:
		toggle_pause()


func show_hud() -> void:
	hud.show()
	refresh_hud()


func hide_hud() -> void:
	hud.hide()


func refresh_hud() -> void:
	var player := _get_player()
	if player:
		if player.is_defeated and GameState.current_scene_id == "minigame" and not minigame_game_over_open:
			hp_label.text = I18n.tr_key("minigame.defeated_wait", "Down — waiting for revival")
		else:
			hp_label.text = "HP: %d/%d" % [player.hp, player.max_hp]
		energy_label.text = "%s: %.0f/%.0f" % [I18n.tr_key("hud.energy", "Energy"), player.energy, player.max_energy]
	level_label.text = "%s: %d  XP: %d" % [I18n.tr_key("hud.level", "Level"), ProgressionSystem.level, ProgressionSystem.current_xp]
	if not BrainLinkBridge.connected:
		ml_label.text = I18n.tr_key("hud.brainlink_off", "BrainLink: off")
		return
	var pred := InputManager.brainlink_last_event
	if pred.is_empty() and not InputManager.brainlink_probs.is_empty():
		var best_k := ""
		var best_v := -1.0
		for k in InputManager.brainlink_probs.keys():
			var pv := float(InputManager.brainlink_probs[k])
			if pv > best_v:
				best_v = pv
				best_k = str(k)
		pred = best_k
	var conf := InputManager.brainlink_confidence
	if conf > 0.0:
		ml_label.text = I18n.tr_format(
			"hud.pred_conf",
			"pred: {pred}  conf: {conf}",
			{"pred": pred if pred else "—", "conf": "%.2f" % conf},
		)
	else:
		ml_label.text = I18n.tr_format(
			"hud.pred_conf_dash",
			"pred: {pred}  conf: —",
			{"pred": pred if pred else "—"},
		)


func set_survival_timer(seconds: float, visible: bool) -> void:
	timer_label.visible = visible
	if visible:
		timer_label.text = "%s: %.1f" % [I18n.tr_key("minigame.survival", "Survival"), seconds]


func show_top10(mode: String) -> void:
	if GameState.is_client():
		top10_panel.hide()
		return
	top10_panel.show()
	var list: Label = top10_panel.get_node("Margin/List") as Label
	var lines: PackedStringArray = []
	var i := 1
	for run in SaveManager.get_top10(mode, false):
		lines.append("%d. %s — %.1fs" % [i, run.get("username", "?"), float(run.get("time", 0))])
		i += 1
	list.text = "\n".join(lines) if lines.size() > 0 else I18n.tr_key("minigame.no_scores", "No scores")


func hide_top10() -> void:
	top10_panel.hide()


func show_dialog(npc_name: String, text: String, options: Array = []) -> void:
	dialog_open = true
	_pause_hidden_for_dialog = pause_open and pause.visible
	if _pause_hidden_for_dialog:
		pause.hide()
	dialog.show()
	dialog_name.text = npc_name
	GameUiTheme.title_label_settings(dialog_name)
	dialog_text.text = text
	for c in dialog_buttons.get_children():
		c.queue_free()
	if options.is_empty():
		var btn := Button.new()
		btn.text = I18n.tr_key("dialog.continue", "Continue")
		GameUiTheme.menu_button_settings(btn)
		btn.pressed.connect(_close_dialog)
		dialog_buttons.add_child(btn)
	else:
		for opt in options:
			var btn2 := Button.new()
			btn2.text = str(opt.get("text", "OK"))
			GameUiTheme.menu_button_settings(btn2)
			var cb: Callable = opt.get("callback", Callable())
			btn2.pressed.connect(func(): _on_dialog_option(cb))
			dialog_buttons.add_child(btn2)


func _on_dialog_option(cb: Callable) -> void:
	dialog_open = false
	dialog.hide()
	_restore_pause_after_dialog()
	if cb.is_valid():
		cb.call()
	if not dialog_open:
		dialog.hide()


func _close_dialog() -> void:
	dialog_open = false
	dialog.hide()
	_restore_pause_after_dialog()


func _restore_pause_after_dialog() -> void:
	if _pause_hidden_for_dialog and pause_open and not settings_open:
		pause.show()
	_pause_hidden_for_dialog = false


func toggle_pause() -> void:
	if dialog_open or minigame_game_over_open:
		return
	if _local_player_defeated_in_minigame():
		return
	pause_open = not pause_open
	pause.visible = pause_open
	get_tree().paused = pause_open
	if pause_open:
		_refresh_pause_menu()


func open_pause() -> void:
	pause_open = true
	pause.visible = true
	get_tree().paused = true


func close_pause() -> void:
	pause_open = false
	minigame_game_over_open = false
	pause.visible = false
	get_tree().paused = false
	_set_pause_extra_buttons_visible(true)


func show_minigame_game_over() -> void:
	minigame_game_over_open = true
	pause_open = true
	pause.visible = true
	get_tree().paused = true
	_refresh_minigame_game_over_menu()


func close_minigame_game_over() -> void:
	if not minigame_game_over_open:
		return
	close_pause()


func _on_pause_restart_pressed() -> void:
	var from_game_over := minigame_game_over_open
	close_pause()
	if GameState.current_scene_id != "minigame":
		return
	if GameState.is_client() and from_game_over:
		return
	(get_node("/root/SceneManager") as Node).call("switch_to", "minigame", {"monkey_mode": GameState.monkey_mode})


func _on_pause_load_pressed() -> void:
	close_minigame_game_over()
	close_pause()
	var data: Variant = SaveManager.load_game()
	if data != null and typeof(data) == TYPE_DICTIONARY:
		var save_data: Dictionary = data
		ProgressionSystem.from_save_dict(save_data)
		var scene_id: String = str(save_data.get("current_scene", "cave"))
		(get_node("/root/SceneManager") as Node).call("switch_to", scene_id, {})


func _on_pause_settings_pressed() -> void:
	show_settings(true)


func _on_pause_brainlink_pressed() -> void:
	show_brainlink_settings(true)


func _refresh_pause_menu() -> void:
	_set_pause_extra_buttons_visible(true)
	var box: VBoxContainer = pause.get_node("Panel/Margin/VBox")
	var title: Label = box.get_node("PauseTitle") as Label
	GameUiTheme.title_label_settings(title)
	title.text = I18n.tr_key("pause.title", "Menu")
	box.get_node("Restart").text = I18n.tr_key("pause.restart", "Restart")
	box.get_node("Load").text = I18n.tr_key("pause.load", "Load")
	box.get_node("Settings").text = I18n.tr_key("pause.settings", "Settings")
	box.get_node("BrainLink").text = I18n.tr_key("pause.brainlink_settings", "BrainLink")
	box.get_node("ExitMenu").text = I18n.tr_key("pause.exit", "Exit")


func _refresh_minigame_game_over_menu() -> void:
	_set_pause_extra_buttons_visible(false)
	var box: VBoxContainer = pause.get_node("Panel/Margin/VBox")
	var title: Label = box.get_node("PauseTitle") as Label
	GameUiTheme.title_label_settings(title)
	title.text = I18n.tr_key("minigame.game_over_title", "Game over")
	box.get_node("Restart").text = I18n.tr_key("minigame.restart", "Restart minigame")
	box.get_node("Load").text = I18n.tr_key("pause.load", "Load")
	box.get_node("ExitMenu").text = I18n.tr_key("minigame.new_game", "New game")
	var restart_btn: Button = box.get_node("Restart") as Button
	restart_btn.disabled = GameState.is_client()


func _set_pause_extra_buttons_visible(visible_extra: bool) -> void:
	var box: VBoxContainer = pause.get_node("Panel/Margin/VBox")
	box.get_node("Settings").visible = visible_extra
	box.get_node("BrainLink").visible = visible_extra
	var restart_btn: Button = box.get_node("Restart") as Button
	restart_btn.disabled = false


func _local_player_defeated_in_minigame() -> bool:
	if GameState.current_scene_id != "minigame":
		return false
	var player := _get_player()
	return player != null and bool(player.get("is_defeated"))


func show_settings(from_pause: bool = false) -> void:
	settings_open = true
	_settings_from_pause = from_pause or pause_open
	if _settings_from_pause:
		pause.hide()
	if not GameState.in_game:
		_set_main_menu_underlay(false)
	dialog.hide()
	dialog_open = false
	settings_menu.open(_settings_from_pause)


func _on_settings_closed() -> void:
	settings_open = false
	if brainlink_settings_open:
		_settings_from_pause = false
		return
	if _settings_from_pause and pause_open and not dialog_open:
		pause.show()
	elif not GameState.in_game:
		_set_main_menu_underlay(true)
	_settings_from_pause = false


func _on_brainlink_settings_closed() -> void:
	brainlink_settings_open = false
	if _brainlink_from_pause and pause_open and not dialog_open and not settings_open:
		pause.show()
	elif not GameState.in_game:
		_set_main_menu_underlay(true)
	_brainlink_from_pause = false


func _set_main_menu_underlay(visible_menu: bool) -> void:
	for node in get_tree().get_nodes_in_group("main_menu_panel"):
		if node is CanvasItem:
			(node as CanvasItem).visible = visible_menu


func show_brainlink_settings(from_pause: bool = false) -> void:
	brainlink_settings_open = true
	_brainlink_from_pause = from_pause or pause_open
	if settings_open:
		settings_menu.close_menu()
		settings_open = false
	if _brainlink_from_pause:
		pause.hide()
	if not GameState.in_game:
		_set_main_menu_underlay(false)
	dialog.hide()
	dialog_open = false
	brainlink_settings_menu.open(_brainlink_from_pause)


func _on_pause_exit_pressed() -> void:
	close_pause()
	NetworkManager.shutdown()
	(get_node("/root/SceneManager") as Node).call("go_to_main_menu")


func _get_player() -> Node:
	var root := get_tree().current_scene
	if root and root.has_method("get_player"):
		return root.get_player()
	return null
