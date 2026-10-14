@tool
extends Control

@onready var title_label: Label = $Panel/Margin/VBox/Title
@onready var subtitle_label: Label = $Panel/Margin/VBox/Subtitle
@onready var status_label: Label = $Panel/Margin/VBox/StatusLabel
@onready var host_info: Label = $Panel/Margin/VBox/HostInfo
@onready var join_host_edit: LineEdit = $Panel/Margin/VBox/JoinHost
@onready var network_panel: VBoxContainer = $Panel/Margin/VBox/NetworkPanel
@onready var solo_btn: Button = $Panel/Margin/VBox/Solo
@onready var solo_load_btn: Button = $Panel/Margin/VBox/SoloLoad
@onready var network_btn: Button = $Panel/Margin/VBox/Network
@onready var host_btn: Button = $Panel/Margin/VBox/NetworkPanel/Host
@onready var host_start_btn: Button = $Panel/Margin/VBox/NetworkPanel/HostStart
@onready var join_btn: Button = $Panel/Margin/VBox/Join
@onready var config_btn: Button = $Panel/Margin/VBox/Config
@onready var brainlink_btn: Button = $Panel/Margin/VBox/BrainLink
@onready var quit_btn: Button = $Panel/Margin/VBox/Quit


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		call_deferred("ensure_editor_preview_content")


func _ready() -> void:
	if Engine.is_editor_hint():
		call_deferred("ensure_editor_preview_content")
		return
	$Panel.add_to_group("main_menu_panel")
	_style_menu()
	get_tree().paused = false
	if GameUI.has_method("close_pause"):
		GameUI.close_pause()
	network_panel.hide()
	I18n.locale_changed.connect(_on_locale_changed)
	_apply_ui_locale()
	_update_brainlink_status()
	BrainLinkBridge.connection_changed.connect(_on_brainlink_connection_changed)
	if bool(ConfigLoader.game_config.get("brainlink", {}).get("enabled", false)):
		BrainLinkBridge.ensure_ready()
	NetworkManager.client_connected.connect(_on_client_connected)
	NetworkManager.disconnected.connect(_on_disconnected)


func ensure_editor_preview_content() -> void:
	if not Engine.is_editor_hint():
		return
	GameUiTheme.apply_main_menu_style(self)
	var network := get_node_or_null("Panel/Margin/VBox/NetworkPanel") as CanvasItem
	if network:
		network.hide()


func _style_menu() -> void:
	GameUiTheme.apply_main_menu_style(self)


func _apply_ui_locale() -> void:
	var win_title := str(ConfigLoader.game_config.get("window", {}).get("title", ""))
	title_label.text = win_title if win_title != "" else I18n.tr_key("menu.title", "Get Level of Monkey")
	subtitle_label.text = I18n.tr_key("menu.subtitle", "")
	solo_btn.text = I18n.tr_key("menu.play_solo", "Solo")
	solo_load_btn.text = I18n.tr_key("menu.play_solo_load", "Solo (Load)")
	network_btn.text = I18n.tr_key("menu.network_game", "Network")
	host_btn.text = I18n.tr_key("menu.host", "Host")
	host_start_btn.text = I18n.tr_key("menu.host_start", "Start game")
	join_host_edit.placeholder_text = I18n.tr_key("menu.host_ip", "Host IP")
	join_btn.text = I18n.tr_key("menu.join", "Join")
	config_btn.text = I18n.tr_key("menu.config", "Config")
	brainlink_btn.text = I18n.tr_key("menu.brainlink_settings", "BrainLink")
	quit_btn.text = I18n.tr_key("menu.quit", "Quit")
	_update_brainlink_status()


func _on_locale_changed(_locale: String) -> void:
	_apply_ui_locale()


func _update_brainlink_status() -> void:
	var enabled := bool(ConfigLoader.game_config.get("brainlink", {}).get("enabled", false))
	if not enabled:
		status_label.text = I18n.tr_key("hud.brainlink_off", "BrainLink: off")
	elif BrainLinkBridge.connected:
		status_label.text = I18n.tr_key("hud.brainlink_connected", "BrainLink: connected")
	else:
		status_label.text = I18n.tr_key("brainlink_status.waiting_shared_memory", "Waiting for Shared Memory...")


func _on_brainlink_connection_changed(_connected: bool) -> void:
	_update_brainlink_status()


func _on_solo_pressed() -> void:
	NetworkManager.shutdown()
	SceneManager.start_solo_game(false)


func _on_solo_load_pressed() -> void:
	NetworkManager.shutdown()
	SceneManager.start_solo_game(true)


func _on_network_pressed() -> void:
	network_panel.visible = not network_panel.visible


func _on_host_pressed() -> void:
	var result: Dictionary = NetworkManager.start_host()
	if result.get("ok", false):
		host_info.text = I18n.tr_format(
			"menu.mp_host_waiting",
			"Host: {addr}",
			{"addr": str(result.get("address", ""))},
		)
	else:
		host_info.text = I18n.tr_key("menu.mp_host_failed", "Host failed")


func _on_client_connected() -> void:
	host_info.text = host_info.text + " — OK"


func _on_host_start_pressed() -> void:
	SceneManager.start_host_game()
	NetworkManager.host_start_game_from_menu()


func _on_join_pressed() -> void:
	var host := join_host_edit.text.strip_edges()
	if host.is_empty():
		host = "127.0.0.1"
	if NetworkManager.join_host(host):
		host_info.text = I18n.tr_format(
			"menu.mp_joining",
			"Connecting…",
			{"host": host},
		)
	else:
		host_info.text = I18n.tr_format(
			"menu.mp_join_failed",
			"Join failed",
			{"host": host},
		)


func _on_config_pressed() -> void:
	GameUI.show_settings()


func _on_brainlink_pressed() -> void:
	GameUI.show_brainlink_settings()


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_disconnected(reason: String) -> void:
	host_info.text = I18n.tr_format(
		"menu.mp_disconnected",
		"Disconnected",
		{"reason": reason if reason else "—"},
	)
