# BattleHUD.gd - 对战HUD (Godot 4 适配)
# 显示双方血量条、气槽、计时器、连击数等
extends CanvasLayer
class_name BattleHUD

var p1: Fighter
var p2: Fighter

@onready var p1_health_bar: ProgressBar = $HUDContainer/P1Side/HealthBar
@onready var p2_health_bar: ProgressBar = $HUDContainer/P2Side/HealthBar
@onready var p1_meter_bar: ProgressBar = $HUDContainer/P1Side/MeterBar
@onready var p2_meter_bar: ProgressBar = $HUDContainer/P2Side/MeterBar
@onready var p1_name_label: Label = $HUDContainer/P1Side/NameLabel
@onready var p2_name_label: Label = $HUDContainer/P2Side/NameLabel
@onready var p1_rounds: HBoxContainer = $HUDContainer/P1Side/RoundIndicators
@onready var p2_rounds: HBoxContainer = $HUDContainer/P2Side/RoundIndicators
@onready var timer_label: Label = $HUDContainer/CenterInfo/TimerLabel
@onready var combo_label: Label = $HUDContainer/CenterInfo/ComboLabel

# 训练模式信息面板
var _training_panel: Panel
var _training_dummy_label: Label
var _training_toggle_label: Label


func _ready() -> void:
	var fighters := get_tree().get_nodes_in_group("fighters")
	for f in fighters:
		if f is Fighter:
			if f.player_id == 1:
				p1 = f
			elif f.player_id == 2:
				p2 = f

	_connect_signals()
	_setup_names()

	if MatchData.current_mode == MatchData.GameMode.TRAINING:
		_setup_training_panel()


func _process(_delta: float) -> void:
	if _training_panel and _training_panel.visible:
		_update_training_panel()


func _connect_signals() -> void:
	if p1:
		p1.health_changed.connect(_on_p1_health_changed)
		p1.meter_changed.connect(_on_p1_meter_changed)
	if p2:
		p2.health_changed.connect(_on_p2_health_changed)
		p2.meter_changed.connect(_on_p2_meter_changed)


func _setup_names() -> void:
	var char1 := MatchData.get_character(MatchData.p1_character_index)
	if p1_name_label:
		p1_name_label.text = char1.display_name
	# 训练模式: P2 是假人
	if MatchData.current_mode == MatchData.GameMode.TRAINING:
		if p2_name_label:
			p2_name_label.text = "训练假人"
	else:
		var char2 := MatchData.get_character(MatchData.p2_character_index)
		if p2_name_label:
			p2_name_label.text = char2.display_name


func _setup_training_panel() -> void:
	_training_panel = Panel.new()
	_training_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_training_panel.anchor_left = 0.0
	_training_panel.anchor_top = 1.0
	_training_panel.anchor_right = 0.0
	_training_panel.anchor_bottom = 1.0
	_training_panel.offset_left = 16
	_training_panel.offset_top = -190
	_training_panel.offset_right = 360
	_training_panel.offset_bottom = -16
	_training_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_training_panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 12
	vbox.offset_top = 10
	vbox.offset_right = -12
	vbox.offset_bottom = -10
	vbox.add_theme_constant_override("separation", 6)
	_training_panel.add_child(vbox)

	var title := Label.new()
	title.text = "训练模式 TRAINING"
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.2, 1))
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)

	_training_dummy_label = Label.new()
	vbox.add_child(_training_dummy_label)

	_training_toggle_label = Label.new()
	vbox.add_child(_training_toggle_label)

	var hints := Label.new()
	hints.text = "1~5 切换假人模式 · H 血量无限 · M 气无限 · R 重置 · ESC 返回"
	hints.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
	hints.add_theme_font_size_override("font_size", 13)
	vbox.add_child(hints)

	var hint2 := Label.new()
	hint2.text = "指令: 半圈↓→(236)+轻击=特殊技 · 半圈+重击=必杀技 · F=推进(耗气)"
	hint2.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
	hint2.add_theme_font_size_override("font_size", 13)
	vbox.add_child(hint2)


func _update_training_panel() -> void:
	var dummy := p2 as TrainingDummy
	if not dummy:
		return
	_training_dummy_label.text = "假人模式: " + _dummy_mode_name(dummy.dummy_mode)
	_training_toggle_label.text = "假人血量无限: %s    假人气无限: %s" % [
		"开" if MatchData.training_health_infinite else "关",
		"开" if MatchData.training_meter_infinite else "关",
	]


func _dummy_mode_name(mode: int) -> String:
	match mode:
		TrainingDummy.DummyMode.STAND:
			return "站立"
		TrainingDummy.DummyMode.CROUCH:
			return "蹲下"
		TrainingDummy.DummyMode.WALK:
			return "走动"
		TrainingDummy.DummyMode.BLOCK_ALL:
			return "全防御"
		TrainingDummy.DummyMode.RANDOM:
			return "随机"
	return "未知"


func _on_p1_health_changed(current: int, max_hp: int) -> void:
	if p1_health_bar:
		p1_health_bar.max_value = max_hp
		p1_health_bar.value = current
		_update_health_color(p1_health_bar, float(current) / max_hp)


func _on_p2_health_changed(current: int, max_hp: int) -> void:
	if p2_health_bar:
		p2_health_bar.max_value = max_hp
		p2_health_bar.value = current
		_update_health_color(p2_health_bar, float(current) / max_hp)


func _on_p1_meter_changed(current: int, max_meter: int) -> void:
	if p1_meter_bar:
		p1_meter_bar.max_value = max_meter
		p1_meter_bar.value = current


func _on_p2_meter_changed(current: int, max_meter: int) -> void:
	if p2_meter_bar:
		p2_meter_bar.max_value = max_meter
		p2_meter_bar.value = current


func _update_health_color(bar: ProgressBar, ratio: float) -> void:
	if ratio > 0.5:
		bar.tint_progress = Color(0, 1, 0, 1)      # 绿色
	elif ratio > 0.25:
		bar.tint_progress = Color(1, 1, 0, 1)      # 黄色
	else:
		bar.tint_progress = Color(1, 0, 0, 1)      # 红色


func update_combo(count: int) -> void:
	if combo_label:
		if count >= 2:
			combo_label.text = "%d HITS" % count
			combo_label.visible = true
		else:
			combo_label.visible = false


func update_timer(time_sec: int) -> void:
	if timer_label:
		timer_label.text = "%02d" % time_sec
