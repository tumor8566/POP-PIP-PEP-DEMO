# MainMenu.gd - 主菜单界面 (Godot 4 适配)
# 提供"本地对战""训练场""设置""画廊""退出"选项
extends Control

var menu_items := ["本地对战", "训练场", "设置", "画廊", "退出"]
var current_index := 0

@onready var menu_container: VBoxContainer = $VBoxContainer/MenuContainer
@onready var cursor_sprite: Sprite2D = $Cursor


func _ready() -> void:
	_setup_menu()
	_update_cursor()


func _setup_menu() -> void:
	# 清除旧项
	for child in menu_container.get_children():
		child.queue_free()

	# 创建菜单项
	for i in range(menu_items.size()):
		var label := Label.new()
		label.text = menu_items[i]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
		menu_container.add_child(label)


func _process(_delta: float) -> void:
	_handle_input()


func _handle_input() -> void:
	if Input.is_action_just_pressed("ui_up"):
		current_index = wrapi(current_index - 1, 0, menu_items.size())
		_update_cursor()
	elif Input.is_action_just_pressed("ui_down"):
		current_index = wrapi(current_index + 1, 0, menu_items.size())
		_update_cursor()
	elif Input.is_action_just_pressed("ui_accept"):
		_on_menu_selected(current_index)
	elif Input.is_action_just_pressed("ui_cancel"):
		_on_exit()


func _update_cursor() -> void:
	# 高亮当前选项
	for i in range(menu_container.get_child_count()):
		var label: Label = menu_container.get_child(i)
		if i == current_index:
			label.add_theme_color_override("font_color", Color(1, 0.9, 0.2, 1))
		else:
			label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))

	# 移动光标
	if cursor_sprite and menu_container.get_child_count() > 0:
		var target_label: Label = menu_container.get_child(current_index)
		cursor_sprite.position.y = target_label.position.y + target_label.size.y / 2


func _on_menu_selected(index: int) -> void:
	match index:
		0:  # 本地对战
			MatchData.current_mode = MatchData.GameMode.LOCAL_VERSUS
			_change_scene("res://scenes/select/character_select.tscn")
		1:  # 训练场
			MatchData.current_mode = MatchData.GameMode.TRAINING
			_change_scene("res://scenes/select/character_select.tscn")
		2:  # 设置
			_change_scene("res://scenes/menu/settings.tscn")
		3:  # 画廊
			_change_scene("res://scenes/menu/gallery.tscn")
		4:  # 退出
			_on_exit()


func _on_exit() -> void:
	get_tree().quit()


func _change_scene(path: String) -> void:
	if ResourceLoader.exists(path):
		get_tree().change_scene_to_file(path)
	else:
		print("场景不存在: ", path)
