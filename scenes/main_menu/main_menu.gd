@tool
extends Control

@onready var title_label: Label = $Panel/Margin/VBox/Title
@onready var subtitle_label: Label = $Panel/Margin/VBox/Subtitle
@onready var status_label: Label = $Panel/Margin/VBox/StatusLabel
@onready var host_info: Label = $Panel/Margin/VBox/NetworkPanel/HostInfo
@onready var join_host_edit: LineEdit = $Panel/Margin/VBox/NetworkPanel/JoinHost
@onready var network_panel: VBoxContainer = $Panel/Margin/VBox/NetworkPanel
@onready var lan_title: Label = $Panel/Margin/VBox/NetworkPanel/LanTitle
@onready var lan_empty: Label = $Panel/Margin/VBox/NetworkPanel/LanEmpty
@onready var host_list: VBoxContainer = $Panel/Margin/VBox/NetworkPanel/HostList
@onready var host_sample: Button = $Panel/Margin/VBox/NetworkPanel/HostList/HostSample
@onready var back_btn: Button = $Panel/Margin/VBox/NetworkPanel/Back
@onready var solo_btn: Button = $Panel/Margin/VBox/Solo
@onready var solo_load_btn: Button = $Panel/Margin/VBox/SoloLoad
@onready var network_btn: Button = $Panel/Margin/VBox/Network
@onready var host_btn: Button = $Panel/Margin/VBox/NetworkPanel/Host
@onready var join_btn: Button = $Panel/Margin/VBox/NetworkPanel/Join
@onready var config_btn: Button = $Panel/Margin/VBox/Config
@onready var brainlink_btn: Button = $Panel/Margin/VBox/BrainLink
@onready var quit_btn: Button = $Panel/Margin/VBox/Quit

var _lan_signature: String = ""


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
	host_sample.hide()
	I18n.locale_changed.connect(_on_locale_changed)
	_apply_ui_locale()
	_update_brainlink_status()
	BrainLinkBridge.connection_changed.connect(_on_brainlink_connection_changed)
	if bool(ConfigLoader.game_config.get("brainlink", {}).get("enabled", false)):
		BrainLinkBridge.ensure_ready()
	NetworkManager.client_connected.connect(_on_client_connected)
	NetworkManager.disconnected.connect(_on_disconnected)
	NetworkManager.lan_hosts_changed.connect(_rebuild_lan_list)
	join_host_edit.text_submitted.connect(func(_text): _on_join_pressed())


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
	join_host_edit.placeholder_text = I18n.tr_key("menu.host_ip", "IP:port")
	join_btn.text = I18n.tr_key("menu.join", "Join")
	lan_title.text = I18n.tr_key("menu.lan_title", "Games on the network")
	lan_empty.text = I18n.tr_key("menu.lan_empty", "Nobody is hosting")
	back_btn.text = I18n.tr_key("menu.mp_back", "Back")
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
	elif BrainLinkBridge.shm_attached:
		status_label.text = I18n.tr_key("brainlink_status.waiting_client", "BrainLink: waiting for client")
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


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	if is_instance_valid(NetworkManager):
		NetworkManager.set_lan_browse(false)


func _on_network_pressed() -> void:
	_set_main_actions_visible(false)
	network_panel.show()
	NetworkManager.set_lan_browse(true)
	_rebuild_lan_list()


func _on_network_back_pressed() -> void:
	NetworkManager.shutdown()
	NetworkManager.set_lan_browse(false)
	network_panel.hide()
	host_info.text = ""
	_set_main_actions_visible(true)


func _set_main_actions_visible(show_actions: bool) -> void:
	for node in [solo_btn, solo_load_btn, network_btn, config_btn, brainlink_btn, status_label, quit_btn]:
		node.visible = show_actions


func _on_host_pressed() -> void:
	var result: Dictionary = NetworkManager.start_host()
	if result.get("ok", false):
		host_info.text = I18n.tr_format(
			"menu.mp_host_waiting",
			"Host: {addr}",
			{"addr": str(result.get("address", ""))},
		)
		if not bool(result.get("firewall_ok", true)):
			host_info.text += "\n" + I18n.tr_key(
				"menu.mp_firewall",
				"Allow the game in Windows Firewall, or the other computer cannot connect.",
			)
	else:
		host_info.text = I18n.tr_key("menu.mp_host_failed", "Host failed")


func _on_client_connected() -> void:
	host_info.text = host_info.text + " — OK"


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


func _on_lan_host_pressed(addr: String) -> void:
	join_host_edit.text = addr
	_on_join_pressed()


func _rebuild_lan_list() -> void:
	if host_list == null or host_sample == null:
		return
	var hosts: Array = NetworkManager.get_lan_hosts()
	var signature := ""
	for item in hosts:
		signature += "%s:%s:%s|" % [item.get("ip", ""), item.get("port", ""), item.get("name", "")]
	if signature == _lan_signature:
		lan_empty.visible = hosts.is_empty()
		return
	_lan_signature = signature
	for child in host_list.get_children():
		if child == host_sample:
			continue
		host_list.remove_child(child)
		child.free()
	host_sample.hide()
	lan_empty.visible = hosts.is_empty()
	for item in hosts:
		var addr := "%s:%d" % [str(item.get("ip", "")), int(item.get("port", 17777))]
		var host_name := str(item.get("name", "")).strip_edges()
		var btn := host_sample.duplicate() as Button
		btn.visible = true
		btn.text = addr if host_name.is_empty() else "%s — %s" % [host_name, addr]
		btn.pressed.connect(_on_lan_host_pressed.bind(addr))
		host_list.add_child(btn)


func _on_config_pressed() -> void:
	GameUI.show_settings()


func _on_brainlink_pressed() -> void:
	GameUI.show_brainlink_settings()


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_disconnected(reason: String) -> void:
	if reason == "timeout":
		host_info.text = I18n.tr_format(
			"menu.mp_join_failed",
			"Join failed",
			{"host": join_host_edit.text.strip_edges()},
		)
		return
	host_info.text = I18n.tr_format(
		"menu.mp_disconnected",
		"Disconnected",
		{"reason": reason if reason else "—"},
	)
