@tool
extends Control

signal closed

const FAULT_KEYS := [
	"attention",
	"meditation",
	"signal",
	"delta",
	"theta",
	"low_alpha",
	"high_alpha",
	"low_beta",
	"high_beta",
	"low_gamma",
	"high_gamma",
]

var _from_pause: bool = false
var _block_signals: bool = false
var _fault_view: String = "base_fault"
var _base_fault_spins: Dictionary = {}
var _multi_fault_spins: Dictionary = {}

@onready var _title: Label = $Panel/Margin/VBox/Header/Title
@onready var _close_btn: Button = $Panel/Margin/VBox/Header/CloseBtn
@onready var _status: Label = $Panel/Margin/VBox/Status
@onready var _feedback: Label = $Panel/Margin/VBox/Feedback
@onready var _tabs: TabContainer = $Panel/Margin/VBox/Tabs
@onready var _btn_connect: Button = $Panel/Margin/VBox/Tabs/Connection/Connect
@onready var _btn_launch: Button = $Panel/Margin/VBox/Tabs/Connection/Launch
@onready var _btn_disconnect: Button = $Panel/Margin/VBox/Tabs/Connection/Disconnect
@onready var _bl_keyboard: CheckBox = $Panel/Margin/VBox/Tabs/Options/BlKeyboard
@onready var _bl_history: CheckBox = $Panel/Margin/VBox/Tabs/Options/BlHistory
@onready var _bl_ml: CheckBox = $Panel/Margin/VBox/Tabs/Options/BlMl
@onready var _bl_events: CheckBox = $Panel/Margin/VBox/Tabs/Options/BlEvents
@onready var _pred_mode: OptionButton = $Panel/Margin/VBox/Tabs/Options/PredModeRow/PredMode
@onready var _conf_threshold_label: Label = $Panel/Margin/VBox/Tabs/Options/ConfThresholdLabel
@onready var _conf_threshold: SpinBox = $Panel/Margin/VBox/Tabs/Options/ConfThreshold
@onready var _min_conf_label: Label = $Panel/Margin/VBox/Tabs/Options/MinConfLabel
@onready var _min_conf: SpinBox = $Panel/Margin/VBox/Tabs/Options/MinConf
@onready var _full_conf_label: Label = $Panel/Margin/VBox/Tabs/Options/FullConfLabel
@onready var _full_conf: SpinBox = $Panel/Margin/VBox/Tabs/Options/FullConf
@onready var _weights_row: HBoxContainer = $Panel/Margin/VBox/Tabs/Options/WeightsRow
@onready var _weights_edit: LineEdit = $Panel/Margin/VBox/Tabs/Options/WeightsRow/WeightsEdit
@onready var _model_path: LineEdit = $Panel/Margin/VBox/Tabs/Paths/ModelPath
@onready var _history_path: LineEdit = $Panel/Margin/VBox/Tabs/Paths/HistoryPath
@onready var _btn_save_paths: Button = $Panel/Margin/VBox/Tabs/Paths/SavePaths
@onready var _fault_mode_base: Button = $Panel/Margin/VBox/Tabs/Faults/FaultModeRow/FaultModeBase
@onready var _fault_mode_ml: Button = $Panel/Margin/VBox/Tabs/Faults/FaultModeRow/FaultModeMl
@onready var _multi_count_row: HBoxContainer = $Panel/Margin/VBox/Tabs/Faults/MultiCountRow
@onready var _multi_count: SpinBox = $Panel/Margin/VBox/Tabs/Faults/MultiCountRow/MultiCount
@onready var _base_title: Label = $Panel/Margin/VBox/Tabs/Faults/BaseTitle
@onready var _base_fault_grid: GridContainer = $Panel/Margin/VBox/Tabs/Faults/BaseGrid
@onready var _multi_title: Label = $Panel/Margin/VBox/Tabs/Faults/MultiTitle
@onready var _multi_fault_grid: GridContainer = $Panel/Margin/VBox/Tabs/Faults/MultiGrid
@onready var _btn_apply_faults: Button = $Panel/Margin/VBox/Tabs/Faults/ApplyFaults
@onready var _btn_apply_base_fault_cmd: Button = $Panel/Margin/VBox/Tabs/Commands/ApplyBaseFault


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
	_close_btn.pressed.connect(close_menu)
	_btn_connect.pressed.connect(_on_connect)
	_btn_launch.pressed.connect(_on_launch)
	_btn_disconnect.pressed.connect(_on_disconnect)
	_bl_keyboard.toggled.connect(func(v): _on_bl_toggle("send_keyboard_events", v))
	_bl_history.toggled.connect(func(v): _on_bl_toggle("send_to_history", v))
	_bl_ml.toggled.connect(func(v): _on_bl_toggle("send_to_ml", v))
	_bl_events.toggled.connect(func(v): _on_bl_toggle("send_brainlink_events", v))
	_pred_mode.item_selected.connect(_on_pred_mode_selected)
	_setup_fault_view_toggle()
	_conf_threshold.value_changed.connect(func(v): _on_float_setting("confidence_threshold", v))
	_min_conf.value_changed.connect(func(v): _on_float_setting("min_confidence", v))
	_full_conf.value_changed.connect(func(v): _on_float_setting("full_confidence", v))
	_weights_edit.text_submitted.connect(_on_weights_submitted)
	_weights_edit.focus_exited.connect(func(): _on_weights_submitted(_weights_edit.text))
	_btn_save_paths.pressed.connect(_on_save_paths)
	_multi_count.value_changed.connect(_on_multi_count_changed)
	_btn_apply_faults.pressed.connect(_on_apply_faults_saved)
	_btn_apply_base_fault_cmd.pressed.connect(_on_apply_base_fault_command)
	$Panel/Margin/VBox/Tabs/Commands/SaveModel.pressed.connect(func(): _send_command(3))
	$Panel/Margin/VBox/Tabs/Commands/LoadModel.pressed.connect(func(): _send_command(6))
	$Panel/Margin/VBox/Tabs/Commands/ResetModel.pressed.connect(func(): _send_command(7))
	$Panel/Margin/VBox/Tabs/Commands/LoadHistory.pressed.connect(func(): _send_command(8))
	$Panel/Margin/VBox/Tabs/Commands/ExportSettings.pressed.connect(func(): _send_command(9))
	$Panel/Margin/VBox/Tabs/Commands/TogglePredMode.pressed.connect(_on_toggle_pred_mode_command)
	if not BrainLinkBridge.connection_changed.is_connected(_refresh_status):
		BrainLinkBridge.connection_changed.connect(_refresh_status)
	if not I18n.locale_changed.is_connected(_refresh_locale):
		I18n.locale_changed.connect(_refresh_locale)
	_build_fault_grids()
	_init_pred_mode_options()
	_setup_spin_ranges()
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
	if _base_fault_grid.get_child_count() == 0:
		_build_fault_grids()
		_init_pred_mode_options()
		_setup_spin_ranges()
	_setup_fault_view_toggle()
	var mode := str(ConfigLoader.game_config.get("brainlink", {}).get("prediction_mode", "base"))
	_apply_prediction_mode(mode, false, false)
	_set_fault_view("base_fault")


func _setup_fault_view_toggle() -> void:
	if _fault_mode_base.button_group != null:
		return
	var fault_view_group := ButtonGroup.new()
	_fault_mode_base.button_group = fault_view_group
	_fault_mode_ml.button_group = fault_view_group
	if not _fault_mode_base.toggled.is_connected(_on_fault_view_base_toggled):
		_fault_mode_base.toggled.connect(_on_fault_view_base_toggled)
	if not _fault_mode_ml.toggled.is_connected(_on_fault_view_multi_toggled):
		_fault_mode_ml.toggled.connect(_on_fault_view_multi_toggled)
	GameUiTheme.menu_button_settings(_fault_mode_base)
	GameUiTheme.menu_button_settings(_fault_mode_ml)


func _apply_tabs_theme() -> void:
	GameUiTheme.apply_tab_container_styles(_tabs)


func open(from_pause: bool) -> void:
	_from_pause = from_pause
	_fault_view = "base_fault"
	visible = true
	move_to_front()
	GameUiTheme.style_interactive_tree(self)
	GameUiTheme.apply_tab_container_styles(_tabs)
	_feedback.text = ""
	_refresh_all()


func close_menu() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _setup_spin_ranges() -> void:
	for sb: SpinBox in [_conf_threshold, _min_conf, _full_conf]:
		sb.min_value = 0.0
		sb.max_value = 1.0
		sb.step = 0.05


func _init_pred_mode_options() -> void:
	_pred_mode.clear()
	_pred_mode.add_item(I18n.tr_key("settings.bl_mode_base", "Base"))
	_pred_mode.set_item_metadata(0, "base")
	_pred_mode.add_item(I18n.tr_key("settings.bl_mode_ml", "ML"))
	_pred_mode.set_item_metadata(1, "ml")


func _build_fault_grids() -> void:
	_base_fault_grid.columns = 4
	_multi_fault_grid.columns = 4
	for key in FAULT_KEYS:
		_add_fault_row(_base_fault_grid, key, _base_fault_spins)
		_add_fault_row(_multi_fault_grid, key, _multi_fault_spins)


func _add_fault_row(grid: GridContainer, key: String, store: Dictionary) -> void:
	var label := Label.new()
	label.text = I18n.tr_key("settings.bl_fault_%s" % key, key)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 15)
	var spin := SpinBox.new()
	spin.min_value = -999
	spin.max_value = 999
	spin.step = 1
	spin.custom_minimum_size = Vector2(76, 32)
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(func(_v): _on_fault_dict_changed())
	store[key] = spin
	grid.add_child(label)
	grid.add_child(spin)


func _refresh_locale(_loc: String = "") -> void:
	if not visible:
		return
	_refresh_all()


func _refresh_all() -> void:
	_title.text = I18n.tr_key("settings.brainlink_title", "BrainLink Settings")
	_close_btn.text = I18n.tr_key("settings.close", "Close")
	_tabs.set_tab_title(0, I18n.tr_key("brainlink_status.label", "Status"))
	_tabs.set_tab_title(1, I18n.tr_key("settings.tab_brainlink", "General"))
	_tabs.set_tab_title(2, I18n.tr_key("settings.tab_client_commands", "Client commands"))
	_tabs.set_tab_title(3, I18n.tr_key("settings.tab_paths", "Paths"))
	_tabs.set_tab_title(4, I18n.tr_key("settings.tab_faults", "Faults"))
	_btn_connect.text = I18n.tr_key("brainlink_status.looking_for_client", "Connect")
	_btn_launch.text = I18n.tr_key("brainlink_status.starting_client", "Launch client")
	_btn_disconnect.text = I18n.tr_key("settings.bl_disconnect", "Disconnect SHM")
	_bl_keyboard.text = I18n.tr_key("settings.bl_send_keyboard", "Send keyboard")
	_bl_history.text = I18n.tr_key("settings.bl_send_history", "Send to history")
	_bl_ml.text = I18n.tr_key("settings.bl_send_ml", "Send to ML")
	_bl_events.text = I18n.tr_key("settings.bl_send_events", "Send BrainLink events")
	$Panel/Margin/VBox/Tabs/Options/PredModeRow/PredLabel.text = I18n.tr_key("settings.bl_prediction_mode", "Prediction mode")
	$Panel/Margin/VBox/Tabs/Options/ConfThresholdLabel.text = I18n.tr_key("settings.bl_conf_threshold", "Threshold")
	$Panel/Margin/VBox/Tabs/Options/MinConfLabel.text = I18n.tr_key("settings.bl_min_confidence", "Min conf")
	$Panel/Margin/VBox/Tabs/Options/FullConfLabel.text = I18n.tr_key("settings.bl_full_confidence", "Full conf")
	$Panel/Margin/VBox/Tabs/Faults/FaultModeRow/FaultModeLabel.text = I18n.tr_key(
		"settings.bl_fault_section",
		"Fault set",
	)
	_fault_mode_base.text = I18n.tr_key("settings.bl_fault_view_base", "Base fault")
	_fault_mode_ml.text = I18n.tr_key("settings.bl_fault_view_multi", "Multi-Level")
	_base_title.text = I18n.tr_key("settings.bl_base_fault_title", "Base fault")
	_multi_title.text = I18n.tr_key("settings.bl_multi_fault_title", "Multi fault")
	$Panel/Margin/VBox/Tabs/Options/WeightsRow/WeightsLabel.text = I18n.tr_key("settings.bl_weights", "Weights")
	$Panel/Margin/VBox/Tabs/Paths/ModelLabel.text = I18n.tr_key("settings.bl_model_path", "Model")
	$Panel/Margin/VBox/Tabs/Paths/HistoryLabel.text = I18n.tr_key("settings.bl_history_path", "History")
	_btn_save_paths.text = I18n.tr_key("settings.apply", "Apply")
	$Panel/Margin/VBox/Tabs/Faults/MultiCountRow/MultiCountLabel.text = I18n.tr_key("settings.bl_multi_count", "Multi count")
	_btn_apply_faults.text = I18n.tr_key("settings.apply", "Apply")
	_btn_apply_base_fault_cmd.text = I18n.tr_key("settings.bl_apply_base_fault", "Apply to BrainLink")
	$Panel/Margin/VBox/Tabs/Commands/SaveModel.text = I18n.tr_key("settings.save_model", "Save model")
	$Panel/Margin/VBox/Tabs/Commands/LoadModel.text = I18n.tr_key("settings.load_model", "Load model")
	$Panel/Margin/VBox/Tabs/Commands/ResetModel.text = I18n.tr_key("settings.reset_model", "Reset model")
	$Panel/Margin/VBox/Tabs/Commands/LoadHistory.text = I18n.tr_key("settings.load_history", "Load history")
	$Panel/Margin/VBox/Tabs/Commands/ExportSettings.text = I18n.tr_key(
		"settings.bl_export_settings",
		"Export BL settings",
	)
	$Panel/Margin/VBox/Tabs/Commands/TogglePredMode.text = I18n.tr_key("settings.bl_prediction_mode", "Toggle pred mode")
	_refresh_status()
	_refresh_options_tab()
	_refresh_paths_tab()
	_refresh_faults_tab()
	_refresh_fault_labels()
	_set_fault_view(_fault_view)


func _refresh_fault_labels() -> void:
	for idx in range(FAULT_KEYS.size()):
		var key: String = FAULT_KEYS[idx]
		var label_key := "settings.bl_fault_%s" % key
		var base_label: Label = _base_fault_grid.get_child(idx * 2) as Label
		var multi_label: Label = _multi_fault_grid.get_child(idx * 2) as Label
		if base_label:
			base_label.text = I18n.tr_key(label_key, key)
		if multi_label:
			multi_label.text = I18n.tr_key(label_key, key)


func _refresh_status(_connected: bool = false) -> void:
	var enabled := bool(ConfigLoader.game_config.get("brainlink", {}).get("enabled", false))
	if not enabled:
		_status.text = I18n.tr_key("hud.brainlink_off", "BrainLink: off")
	elif BrainLinkBridge.connected:
		_status.text = I18n.tr_key("brainlink_status.ready", "Connected")
	elif BrainLinkBridge.shm_attached:
		_status.text = I18n.tr_key("brainlink_status.waiting_client", "Waiting for BrainLink Client")
	else:
		_status.text = I18n.tr_key("brainlink_status.waiting_shared_memory", "Waiting...")
	_btn_disconnect.disabled = not BrainLinkBridge.connected


func _refresh_options_tab() -> void:
	var bl: Dictionary = ConfigLoader.game_config.get("brainlink", {})
	_block_signals = true
	_bl_keyboard.button_pressed = bool(bl.get("send_keyboard_events", true))
	_bl_history.button_pressed = bool(bl.get("send_to_history", true))
	_bl_ml.button_pressed = bool(bl.get("send_to_ml", false))
	_bl_events.button_pressed = bool(bl.get("send_brainlink_events", true))
	_conf_threshold.value = float(bl.get("confidence_threshold", 0.1))
	_min_conf.value = float(bl.get("min_confidence", 0.1))
	_full_conf.value = float(bl.get("full_confidence", 0.4))
	var mode := str(bl.get("prediction_mode", "base"))
	_apply_prediction_mode(mode, false, false)
	var weights: Array = bl.get("prediction_weights", [1.0, 1.0, 1.0, 1.0])
	var wparts: PackedStringArray = []
	for w in weights:
		wparts.append(str(w))
	_weights_edit.text = ",".join(wparts)
	_block_signals = false


func _refresh_paths_tab() -> void:
	var bl: Dictionary = ConfigLoader.game_config.get("brainlink", {})
	_model_path.text = str(bl.get("model_path", ""))
	_history_path.text = str(bl.get("history_path", ""))


func _refresh_faults_tab() -> void:
	var bl: Dictionary = ConfigLoader.game_config.get("brainlink", {})
	var base_f: Dictionary = bl.get("base_fault", {})
	var multi_f: Dictionary = bl.get("multi_fault", {})
	_block_signals = true
	_multi_count.value = int(bl.get("multi_count", 8))
	for key in FAULT_KEYS:
		if _base_fault_spins.has(key):
			(_base_fault_spins[key] as SpinBox).value = float(base_f.get(key, 0))
		if _multi_fault_spins.has(key):
			(_multi_fault_spins[key] as SpinBox).value = float(multi_f.get(key, 0))
	_block_signals = false


func _on_connect() -> void:
	BrainLinkBridge.try_connect()
	_set_feedback(I18n.tr_key("brainlink_status.connecting", "Connecting..."))


func _on_launch() -> void:
	BrainLinkBridge.launch_client()
	_set_feedback(I18n.tr_key("brainlink_status.starting_client", "Launching..."))


func _on_disconnect() -> void:
	BrainLinkBridge.disconnect_shm()
	_set_feedback(I18n.tr_key("brainlink_status.restarting", "Disconnected"))


func _on_bl_toggle(key: String, value: bool) -> void:
	if _block_signals:
		return
	var bl: Dictionary = ConfigLoader.game_config.get("brainlink", {}).duplicate(true)
	bl[key] = value
	ConfigLoader.save_user_settings({"brainlink": bl})
	InputManager._load_brainlink_send_flags()


func _on_toggle_pred_mode_command() -> void:
	var mode := str(ConfigLoader.game_config.get("brainlink", {}).get("prediction_mode", "base"))
	_apply_prediction_mode("ml" if mode == "base" else "base", true, true)


func _on_pred_mode_selected(index: int) -> void:
	if _block_signals:
		return
	_apply_prediction_mode(str(_pred_mode.get_item_metadata(index)), true, true)


func _on_fault_view_base_toggled(pressed: bool) -> void:
	if _block_signals or not pressed:
		return
	_set_fault_view("base_fault")


func _on_fault_view_multi_toggled(pressed: bool) -> void:
	if _block_signals or not pressed:
		return
	_set_fault_view("multi_fault")


func _set_fault_view(view: String) -> void:
	_fault_view = "multi_fault" if view == "multi_fault" else "base_fault"
	_block_signals = true
	_fault_mode_base.button_pressed = _fault_view == "base_fault"
	_fault_mode_ml.button_pressed = _fault_view == "multi_fault"
	_block_signals = false
	_update_fault_sections_visibility()


func _apply_prediction_mode(mode: String, notify_client: bool, save_config: bool) -> void:
	var normalized := "ml" if mode == "ml" else "base"
	_block_signals = true
	for i in _pred_mode.item_count:
		if str(_pred_mode.get_item_metadata(i)) == normalized:
			_pred_mode.select(i)
			break
	_block_signals = false
	_update_options_fields_visibility(normalized)
	if save_config:
		var bl: Dictionary = ConfigLoader.game_config.get("brainlink", {}).duplicate(true)
		bl["prediction_mode"] = normalized
		ConfigLoader.save_user_settings({"brainlink": bl})
	if notify_client and BrainLinkBridge.connected:
		BrainLinkBridge.send_config_command(4)


func _update_fault_sections_visibility() -> void:
	var is_base_fault := _fault_view == "base_fault"
	_base_title.visible = is_base_fault
	_base_fault_grid.visible = is_base_fault
	_multi_title.visible = not is_base_fault
	_multi_count_row.visible = not is_base_fault
	_multi_fault_grid.visible = not is_base_fault


func _update_options_fields_visibility(pred_mode: String) -> void:
	var is_ml := pred_mode == "ml"
	_conf_threshold_label.visible = true
	_conf_threshold.visible = true
	_min_conf_label.visible = is_ml
	_min_conf.visible = is_ml
	_full_conf_label.visible = is_ml
	_full_conf.visible = is_ml
	_weights_row.visible = is_ml


func _on_float_setting(key: String, value: float) -> void:
	if _block_signals:
		return
	var bl: Dictionary = ConfigLoader.game_config.get("brainlink", {}).duplicate(true)
	bl[key] = value
	ConfigLoader.save_user_settings({"brainlink": bl})


func _on_weights_submitted(text: String) -> void:
	if _block_signals:
		return
	var parts: PackedStringArray = text.split(",", false)
	var weights: Array = []
	for p in parts:
		weights.append(float(p.strip_edges()))
	while weights.size() < 4:
		weights.append(1.0)
	if weights.size() > 4:
		weights = weights.slice(0, 4)
	var bl: Dictionary = ConfigLoader.game_config.get("brainlink", {}).duplicate(true)
	bl["prediction_weights"] = weights
	ConfigLoader.save_user_settings({"brainlink": bl})


func _on_save_paths() -> void:
	var bl: Dictionary = ConfigLoader.game_config.get("brainlink", {}).duplicate(true)
	bl["model_path"] = _model_path.text.strip_edges()
	bl["history_path"] = _history_path.text.strip_edges()
	ConfigLoader.save_user_settings({"brainlink": bl})
	_set_feedback(I18n.tr_key("settings.apply", "Saved"))


func _on_multi_count_changed(value: float) -> void:
	if _block_signals:
		return
	var bl: Dictionary = ConfigLoader.game_config.get("brainlink", {}).duplicate(true)
	bl["multi_count"] = int(value)
	ConfigLoader.save_user_settings({"brainlink": bl})


func _on_fault_dict_changed() -> void:
	pass


func _collect_fault_dict(store: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in FAULT_KEYS:
		if store.has(key):
			out[key] = int((store[key] as SpinBox).value)
	return out


func _on_apply_faults_saved() -> void:
	var bl: Dictionary = ConfigLoader.game_config.get("brainlink", {}).duplicate(true)
	bl["base_fault"] = _collect_fault_dict(_base_fault_spins)
	bl["multi_fault"] = _collect_fault_dict(_multi_fault_spins)
	bl["multi_count"] = int(_multi_count.value)
	ConfigLoader.save_user_settings({"brainlink": bl})
	_set_feedback(I18n.tr_key("settings.apply", "Applied"))


func _on_apply_base_fault_command() -> void:
	if not BrainLinkBridge.connected:
		_set_feedback(I18n.tr_key("settings.bl_not_connected", "Not connected"))
		return
	_on_apply_faults_saved()
	BrainLinkBridge.send_config_command(5)
	_set_feedback(I18n.tr_key("settings.bl_command_sent", "Command sent"))


func _send_command(command_type: int) -> void:
	if not BrainLinkBridge.connected:
		_set_feedback(I18n.tr_key("settings.bl_not_connected", "Not connected"))
		return
	BrainLinkBridge.send_config_command(command_type)
	_set_feedback(I18n.tr_key("settings.bl_command_sent", "Command sent"))


func _set_feedback(text: String) -> void:
	_feedback.text = text


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close_menu()
		get_viewport().set_input_as_handled()
