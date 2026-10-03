# CharacterSelect.gd - 角色选择界面
# 玩家选择角色和颜色，确认后进入对战
extends Control

# 请求返回主菜单(供测试/外部监听)
signal back_requested

const COLOR_COUNT := 6
const GRID_COLUMNS := 4

var p1_index := 0
var p1_color := 0
var p1_ready := false

var p2_index := 1
var p2_color := 0
var p2_ready := false

var _p1_cursor_timer := 0.0
var _p2_cursor_timer := 0.0
const CURSOR_COOLDOWN := 0.15


func _ready() -> void:
	_setup_grid()
	_update_display()


# ESC: 取消当前选择并返回主菜单
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back_pressed()


func _setup_grid() -> void:
	# 角色网格由场景中的 GridContainer 负责
	# 此处在代码中标记角色槽位
	var grid := get_node_or_null("CenterContainer/CharacterGrid")
	if not grid:
		return
	
	var characters := MatchData.character_list
	for i in range(grid.get_child_count()):
		var slot := grid.get_child(i)
		if i < characters.size():
			var char_data: MatchData.CharacterData = characters[i]
			# 设置角色名标签
			var name_label := slot.get_node_or_null("NameLabel")
			if name_label:
				name_label.text = char_data.display_name


func _process(delta: float) -> void:
	_p1_cursor_timer -= delta
	_p2_cursor_timer -= delta
	
	_handle_p1_input()
	_handle_p2_input()
	
	if p1_ready and p2_ready:
		_start_match()


func _handle_p1_input() -> void:
	if p1_ready:
		# 可按取消键撤销准备
		if InputHandler.is_just_pressed(1, InputHandler.InputButton.E):
			p1_ready = false
		return
	
	if _p1_cursor_timer > 0:
		return
	
	var moved := false
	if InputHandler.is_pressed(1, InputHandler.InputButton.LEFT):
		p1_index = wrapi(p1_index - 1, 0, MatchData.character_list.size())
		moved = true
	elif InputHandler.is_pressed(1, InputHandler.InputButton.RIGHT):
		p1_index = wrapi(p1_index + 1, 0, MatchData.character_list.size())
		moved = true
	elif InputHandler.is_pressed(1, InputHandler.InputButton.UP):
		p1_index = wrapi(p1_index - GRID_COLUMNS, 0, MatchData.character_list.size())
		moved = true
	elif InputHandler.is_pressed(1, InputHandler.InputButton.DOWN):
		p1_index = wrapi(p1_index + GRID_COLUMNS, 0, MatchData.character_list.size())
		moved = true
	
	if moved:
		_p1_cursor_timer = CURSOR_COOLDOWN
		_update_display()
	
	# 颜色选择
	if InputHandler.is_just_pressed(1, InputHandler.InputButton.A):
		p1_color = wrapi(p1_color - 1, 0, COLOR_COUNT)
		_update_display()
	elif InputHandler.is_just_pressed(1, InputHandler.InputButton.B):
		p1_color = wrapi(p1_color + 1, 0, COLOR_COUNT)
		_update_display()
	
	# 确认选择
	if InputHandler.is_just_pressed(1, InputHandler.InputButton.START):
		p1_ready = true
		_update_display()


func _handle_p2_input() -> void:
	if p2_ready:
		if InputHandler.is_just_pressed(2, InputHandler.InputButton.E):
			p2_ready = false
		return
	
	if _p2_cursor_timer > 0:
		return
	
	var moved := false
	if InputHandler.is_pressed(2, InputHandler.InputButton.LEFT):
		p2_index = wrapi(p2_index - 1, 0, MatchData.character_list.size())
		moved = true
	elif InputHandler.is_pressed(2, InputHandler.InputButton.RIGHT):
		p2_index = wrapi(p2_index + 1, 0, MatchData.character_list.size())
		moved = true
	elif InputHandler.is_pressed(2, InputHandler.InputButton.UP):
		p2_index = wrapi(p2_index - GRID_COLUMNS, 0, MatchData.character_list.size())
		moved = true
	elif InputHandler.is_pressed(2, InputHandler.InputButton.DOWN):
		p2_index = wrapi(p2_index + GRID_COLUMNS, 0, MatchData.character_list.size())
		moved = true
	
	if moved:
		_p2_cursor_timer = CURSOR_COOLDOWN
		_update_display()
	
	if InputHandler.is_just_pressed(2, InputHandler.InputButton.A):
		p2_color = wrapi(p2_color - 1, 0, COLOR_COUNT)
		_update_display()
	elif InputHandler.is_just_pressed(2, InputHandler.InputButton.B):
		p2_color = wrapi(p2_color + 1, 0, COLOR_COUNT)
		_update_display()
	
	if InputHandler.is_just_pressed(2, InputHandler.InputButton.START):
		p2_ready = true
		_update_display()


func _update_display() -> void:
	# 更新P1立绘
	_update_portrait("P1Portrait", p1_index, p1_color)
	# 更新P2立绘
	_update_portrait("P2Portrait", p2_index, p2_color)
	
	# 更新就绪状态
	_update_ready_text("P1ReadyLabel", p1_ready)
	_update_ready_text("P2ReadyLabel", p2_ready)
	
	# 更新颜色指示
	_update_color_label("P1ColorLabel", p1_color)
	_update_color_label("P2ColorLabel", p2_color)
	
	# 更新角色名
	_update_name_label("P1NameLabel", p1_index)
	_update_name_label("P2NameLabel", p2_index)
	
	# 高亮选中格子
	_update_grid_highlight()


func _update_portrait(node_name: String, char_index: int, _color_index: int) -> void:
	var portrait: TextureRect = get_node_or_null(node_name)
	if not portrait:
		return
	var char_data := MatchData.get_character(char_index)
	if char_data.portrait_path != "" and ResourceLoader.exists(char_data.portrait_path):
		portrait.texture = load(char_data.portrait_path)
	else:
		# 使用占位颜色
		portrait.modulate = _get_color_modulate(_color_index)


func _update_ready_text(node_name: String, ready: bool) -> void:
	var label: Label = get_node_or_null(node_name)
	if label:
		label.text = "准备就绪!" if ready else "选择角色..."
		label.add_theme_color_override("font_color", Color(0, 1, 0, 1) if ready else Color(1, 1, 1, 0.6))


func _update_color_label(node_name: String, color_index: int) -> void:
	var label: Label = get_node_or_null(node_name)
	if label:
		label.text = "颜色: " + MatchData.get_color_name(color_index)


func _update_name_label(node_name: String, char_index: int) -> void:
	var label: Label = get_node_or_null(node_name)
	if label:
		label.text = MatchData.get_character(char_index).display_name


func _update_grid_highlight() -> void:
	var grid := get_node_or_null("CenterContainer/CharacterGrid")
	if not grid:
		return
	
	for i in range(grid.get_child_count()):
		var slot := grid.get_child(i)
		var bg := slot.get_node_or_null("Background")
		if bg:
			if i == p1_index and i == p2_index:
				bg.modulate = Color(0.8, 0.4, 0.8, 0.5)  # 紫色 = 两个玩家都选了
			elif i == p1_index:
				bg.modulate = Color(0.2, 0.4, 0.8, 0.5)   # 蓝色 = P1
			elif i == p2_index:
				bg.modulate = Color(0.8, 0.2, 0.2, 0.5)   # 红色 = P2
			else:
				bg.modulate = Color(0.3, 0.3, 0.3, 0.3)


func _get_color_modulate(color_index: int) -> Color:
	var colors := [
		Color(1, 1, 1, 1),
		Color(0.4, 0.6, 1, 1),
		Color(1, 0.3, 0.3, 1),
		Color(0.3, 1, 0.3, 1),
		Color(1, 1, 0.3, 1),
		Color(0.8, 0.3, 1, 1),
	]
	return colors[color_index % colors.size()]


func _start_match() -> void:
	# 存储选择
	MatchData.p1_character_index = p1_index
	MatchData.p1_color_index = p1_color
	MatchData.p2_character_index = p2_index
	MatchData.p2_color_index = p2_color
	MatchData.reset_rounds()
	
	# 切换场景
	get_tree().change_scene_to_file("res://scenes/versus/versus_battle.tscn")


func _on_back_pressed() -> void:
	emit_signal("back_requested")
	get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")
