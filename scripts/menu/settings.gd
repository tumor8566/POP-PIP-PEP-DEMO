# Settings.gd - 设置界面
# 分组: 音量 / 回合时间 / 画面(分辨率+全屏) / 按键设置(1P·2P) / 预留项
# 设置持久化到 user://settings.cfg, 按键绑定到 user://input.cfg
extends Control

const SETTINGS_PATH := "user://settings.cfg"
const DEFAULT_MASTER := 0.8
const DEFAULT_BGM := 0.8
const DEFAULT_SFX := 0.8

# 常见分辨率
const RESOLUTIONS := [
	Vector2i(1280, 720),
	Vector2i(1366, 768),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160),
]

# 按键显示名
const BUTTON_NAMES := {
	InputHandler.InputButton.UP: "上",
	InputHandler.InputButton.DOWN: "下",
	InputHandler.InputButton.LEFT: "左",
	InputHandler.InputButton.RIGHT: "右",
	InputHandler.InputButton.A: "A 轻攻击",
	InputHandler.InputButton.B: "B 中攻击",
	InputHandler.InputButton.C: "C 重攻击",
	InputHandler.InputButton.D: "D 抓取",
	InputHandler.InputButton.E: "E 格挡技",
	InputHandler.InputButton.F: "F 推进",
	InputHandler.InputButton.START: "START 开始/暂停",
}

var _volumes := {
	"master": DEFAULT_MASTER,
	"bgm": DEFAULT_BGM,
	"sfx": DEFAULT_SFX,
}

var _res_index := 0
var _fullscreen := false

# 按键重绑定等待状态
var _waiting_btn := -1
var _waiting_player := 0
var _waiting_button: Button = null

@onready var back_button: Button = $BackButton


func _ready() -> void:
	_load_settings()
	_build_ui()
	_apply_volumes()
	back_button.pressed.connect(_on_back_pressed)


# ---------- 界面构建 ----------

func _build_ui() -> void:
	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -430.0
	panel.offset_top = -290.0
	panel.offset_right = 430.0
	panel.offset_bottom = 250.0
	add_child(panel)

	# 可滚动, 内容较多
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 20.0
	scroll.offset_top = 20.0
	scroll.offset_right = -20.0
	scroll.offset_bottom = -20.0
	panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 14)
	scroll.add_child(vbox)

	# --- 音量 ---
	vbox.add_child(_section_title("音量"))
	vbox.add_child(_make_volume_row("主音量 (Master)", "master"))
	vbox.add_child(_make_volume_row("背景音乐 (BGM)", "bgm"))
	vbox.add_child(_make_volume_row("音效 (SFX)", "sfx"))
	vbox.add_child(HSeparator.new())

	# --- 回合时间 ---
	vbox.add_child(_section_title("对战"))
	vbox.add_child(_make_timer_row())
	vbox.add_child(HSeparator.new())

	# --- 画面 ---
	vbox.add_child(_section_title("画面"))
	vbox.add_child(_make_resolution_row())
	vbox.add_child(_make_fullscreen_row())
	vbox.add_child(HSeparator.new())

	# --- 按键设置 ---
	vbox.add_child(_section_title("按键设置 (点击按键后按新键)"))
	vbox.add_child(_make_keybind_grid())
	var reset_keys := Button.new()
	reset_keys.text = "按键恢复默认"
	reset_keys.pressed.connect(_on_reset_keys_pressed)
	vbox.add_child(reset_keys)
	vbox.add_child(HSeparator.new())

	# --- 预留 ---
	vbox.add_child(_section_title("预留"))
	vbox.add_child(_make_reserved_row("预留选项 1"))
	vbox.add_child(_make_reserved_row("预留选项 2"))
	vbox.add_child(HSeparator.new())

	var reset := Button.new()
	reset.text = "全部恢复默认"
	reset.pressed.connect(_on_reset_pressed)
	vbox.add_child(reset)


func _section_title(text: String) -> Control:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(1, 0.85, 0.3, 1))
	return label


func _make_volume_row(label_text: String, key: String) -> Control:
	var row := VBoxContainer.new()

	var h := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = label_text
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value_label := Label.new()
	value_label.text = "%d%%" % int(_volumes[key] * 100)
	h.add_child(name_label)
	h.add_child(value_label)
	row.add_child(h)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = int(_volumes[key] * 100.0)
	slider.custom_minimum_size = Vector2(0, 24)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(
		func(v: float) -> void:
			_volumes[key] = v / 100.0
			value_label.text = "%d%%" % int(v)
			_apply_volumes()
			_save_settings()
	)
	row.add_child(slider)
	return row


func _make_timer_row() -> Control:
	var row := VBoxContainer.new()

	var h := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = "回合时间 (无限)"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(name_label)
	var check := CheckButton.new()
	check.button_pressed = GlobalConfig.round_time_infinite
	h.add_child(check)
	row.add_child(h)

	var sec_label := Label.new()
	sec_label.text = "%d 秒" % GlobalConfig.round_time_seconds
	sec_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var slider := HSlider.new()
	slider.min_value = 30.0
	slider.max_value = 99.0
	slider.step = 1.0
	slider.value = GlobalConfig.round_time_seconds
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.visible = not GlobalConfig.round_time_infinite
	sec_label.visible = not GlobalConfig.round_time_infinite
	row.add_child(slider)
	row.add_child(sec_label)

	slider.value_changed.connect(
		func(v: float) -> void:
			GlobalConfig.round_time_seconds = int(v)
			sec_label.text = "%d 秒" % int(v)
			_save_settings()
	)
	check.toggled.connect(
		func(on: bool) -> void:
			GlobalConfig.round_time_infinite = on
			slider.visible = not on
			sec_label.visible = not on
			_save_settings()
	)
	return row


func _make_resolution_row() -> Control:
	var h := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = "窗口分辨率"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(name_label)

	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(180, 0)
	for i in range(RESOLUTIONS.size()):
		var r: Vector2i = RESOLUTIONS[i]
		opt.add_item("%d x %d" % [r.x, r.y], i)
	opt.selected = _res_index
	opt.item_selected.connect(_on_resolution_selected)
	h.add_child(opt)
	return h


func _make_fullscreen_row() -> Control:
	var h := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = "全屏模式"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(name_label)

	var check := CheckButton.new()
	check.button_pressed = _fullscreen
	check.toggled.connect(_on_fullscreen_toggled)
	h.add_child(check)
	return h


# 按键设置: 三列网格 [动作 | 1P | 2P]
func _make_keybind_grid() -> Control:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)

	grid.add_child(_grid_header("动作"))
	grid.add_child(_grid_header("1P"))
	grid.add_child(_grid_header("2P"))

	for btn in InputHandler.BINDABLE_BUTTONS:
		var label := Label.new()
		label.text = BUTTON_NAMES[btn]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(label)
		grid.add_child(_make_key_button(1, btn))
		grid.add_child(_make_key_button(2, btn))

	return grid


func _grid_header(text: String) -> Control:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.7, 0.85, 1, 1))
	return label


func _make_key_button(player: int, btn: int) -> Button:
	var b := Button.new()
	b.text = InputHandler.key_label(InputHandler.get_keycode(player, btn))
	b.custom_minimum_size = Vector2(150, 0)
	b.pressed.connect(_on_key_button_pressed.bind(player, btn, b))
	return b


# 预留项: 占位控件, 暂不启用
func _make_reserved_row(title: String) -> Control:
	var h := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = title
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(name_label)

	var disabled := OptionButton.new()
	disabled.custom_minimum_size = Vector2(180, 0)
	disabled.add_item("（预留，暂未启用）")
	disabled.disabled = true
	disabled.selected = 0
	h.add_child(disabled)
	return h


# ---------- 按键重绑定交互 ----------

func _on_key_button_pressed(player: int, btn: int, button: Button) -> void:
	_finish_waiting()
	_waiting_player = player
	_waiting_btn = btn
	_waiting_button = button
	button.text = "按下新键..."
	button.add_theme_color_override("font_color", Color(1, 0.85, 0.2, 1))


func _finish_waiting() -> void:
	if _waiting_button and is_instance_valid(_waiting_button):
		_waiting_button.text = InputHandler.key_label(
			InputHandler.get_keycode(_waiting_player, _waiting_btn))
		_waiting_button.remove_theme_color_override("font_color")
	_waiting_btn = -1
	_waiting_player = 0
	_waiting_button = null


# 等待绑键时优先捕获按键, 否则 ESC 返回
func _unhandled_input(event: InputEvent) -> void:
	if _waiting_btn != -1:
		if event is InputEventKey and event.pressed and not event.echo:
			var kc: int = event.keycode
			if kc == KEY_NONE:
				kc = event.physical_keycode
			if kc != KEY_NONE:
				InputHandler.rebind(_waiting_player, _waiting_btn, kc)
				_finish_waiting()
				get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back_pressed()


func _on_reset_keys_pressed() -> void:
	InputHandler.reset_all()
	_rebuild()


# ---------- 画面设置 ----------

func _on_resolution_selected(index: int) -> void:
	_res_index = index
	var r: Vector2i = RESOLUTIONS[index]
	GlobalConfig.window_width = r.x
	GlobalConfig.window_height = r.y
	_apply_display()
	_save_settings()


func _on_fullscreen_toggled(on: bool) -> void:
	_fullscreen = on
	_apply_display()
	_save_settings()


func _apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		var r: Vector2i = RESOLUTIONS[_res_index]
		DisplayServer.window_set_size(r)
	GlobalConfig.fullscreen = _fullscreen


# ---------- 音量 / 持久化 ----------

func _apply_volumes() -> void:
	_set_bus_volume("Master", _volumes["master"])
	_set_bus_volume("BGM", _volumes["bgm"])
	_set_bus_volume("SFX", _volumes["sfx"])


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	_volumes["master"] = float(cfg.get_value("audio", "master", DEFAULT_MASTER))
	_volumes["bgm"] = float(cfg.get_value("audio", "bgm", DEFAULT_BGM))
	_volumes["sfx"] = float(cfg.get_value("audio", "sfx", DEFAULT_SFX))
	GlobalConfig.round_time_infinite = bool(cfg.get_value("match", "round_time_infinite", true))
	GlobalConfig.round_time_seconds = int(cfg.get_value("match", "round_time_seconds", 99))

	# 画面: 按保存的宽高匹配预设项
	var w := int(cfg.get_value("display", "width", 1280))
	var h := int(cfg.get_value("display", "height", 720))
	_fullscreen = bool(cfg.get_value("display", "fullscreen", false))
	_res_index = 0
	for i in range(RESOLUTIONS.size()):
		var r: Vector2i = RESOLUTIONS[i]
		if r.x == w and r.y == h:
			_res_index = i
			break


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", _volumes["master"])
	cfg.set_value("audio", "bgm", _volumes["bgm"])
	cfg.set_value("audio", "sfx", _volumes["sfx"])
	cfg.set_value("match", "round_time_infinite", GlobalConfig.round_time_infinite)
	cfg.set_value("match", "round_time_seconds", GlobalConfig.round_time_seconds)

	var r: Vector2i = RESOLUTIONS[_res_index]
	cfg.set_value("display", "width", r.x)
	cfg.set_value("display", "height", r.y)
	cfg.set_value("display", "fullscreen", _fullscreen)
	cfg.save(SETTINGS_PATH)


func _on_reset_pressed() -> void:
	_volumes["master"] = DEFAULT_MASTER
	_volumes["bgm"] = DEFAULT_BGM
	_volumes["sfx"] = DEFAULT_SFX
	GlobalConfig.round_time_infinite = true
	GlobalConfig.round_time_seconds = 99
	_res_index = 0
	_fullscreen = false
	_apply_volumes()
	_apply_display()
	_save_settings()
	InputHandler.reset_all()
	_rebuild()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")


# 重建面板以刷新控件状态
func _rebuild() -> void:
	for c in get_children():
		if c is Panel:
			c.queue_free()
	_build_ui()
