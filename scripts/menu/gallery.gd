# Gallery.gd - 画廊界面 (可用版)
# 浏览角色名册: 程序化占位立绘 + 名称 + 介绍, 支持上一个/下一个切换
extends Control

var _index := 0
var _art_bg: ColorRect
var _name_label: Label
var _desc_label: Label
var _page_label: Label

@onready var back_button: Button = $BackButton


func _ready() -> void:
	_build_ui()
	_show_current()
	back_button.pressed.connect(_on_back_pressed)


func _build_ui() -> void:
	# 立绘外框
	var frame := Panel.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	frame.offset_left = -220.0
	frame.offset_top = -200.0
	frame.offset_right = 220.0
	frame.offset_bottom = 40.0
	add_child(frame)

	_art_bg = ColorRect.new()
	_art_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_art_bg.color = Color(0.3, 0.3, 0.4, 1)
	frame.add_child(_art_bg)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 18.0
	vbox.offset_top = 18.0
	vbox.offset_right = -18.0
	vbox.offset_bottom = -18.0
	vbox.add_theme_constant_override("separation", 10)
	frame.add_child(vbox)

	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 26)
	vbox.add_child(_name_label)

	_desc_label = Label.new()
	_desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_desc_label)

	# 上一个 / 下一个
	var nav := HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 48)
	var prev := Button.new()
	prev.text = "◀ 上一个"
	prev.pressed.connect(_on_prev_pressed)
	var next := Button.new()
	next.text = "下一个 ▶"
	next.pressed.connect(_on_next_pressed)
	nav.add_child(prev)
	nav.add_child(next)
	nav.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	nav.offset_top = 70.0
	nav.offset_bottom = 110.0
	add_child(nav)

	# 页码
	_page_label = Label.new()
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_page_label.offset_top = 120.0
	_page_label.offset_bottom = 150.0
	add_child(_page_label)


func _show_current() -> void:
	var chars := MatchData.character_list
	if chars.is_empty():
		return
	_index = wrapi(_index, 0, chars.size())
	var c: MatchData.CharacterData = chars[_index]
	_name_label.text = c.display_name
	_desc_label.text = c.description if c.description != "" else "（暂无介绍）"
	_page_label.text = "%d / %d" % [_index + 1, chars.size()]

	# 按序号生成稳定颜色作为占位立绘
	var hue := float(_index) / float(maxf(float(chars.size()), 1.0))
	_art_bg.color = Color.from_hsv(hue, 0.45, 0.85)


func _on_prev_pressed() -> void:
	_index -= 1
	_show_current()


func _on_next_pressed() -> void:
	_index += 1
	_show_current()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back_pressed()
	elif event.is_action_pressed("ui_left"):
		get_viewport().set_input_as_handled()
		_on_prev_pressed()
	elif event.is_action_pressed("ui_right"):
		get_viewport().set_input_as_handled()
		_on_next_pressed()
