# InputHandler.gd - 输入处理单例
# 统一管理双人输入，支持键盘按键重映射(自定义绑定持久化到 user://input.cfg)
extends Node

# 按钮映射枚举 (Godot 4 内置了 Button 控件类，故此处命名为 InputButton)
enum InputButton {
	LEFT, RIGHT, UP, DOWN,
	A, B, C, D, E, F, START
}

# 玩家输入前缀
const P1_PREFIX := "p1_"
const P2_PREFIX := "p2_"

# 输入缓冲(帧数)
const INPUT_BUFFER := 8

# 自定义按键配置
const INPUT_CFG := "user://input.cfg"

# 默认按键映射(动作名 -> 按键数组, 第一个为主键, 用于显示)
# 每个动作可绑定多个按键: 小键盘 + 主键盘易达键, 避免无小键盘时 2P 无法操作
const DEFAULT_MAP := {
	"p1_left": [KEY_A],
	"p1_right": [KEY_D],
	"p1_up": [KEY_W],
	"p1_down": [KEY_S],
	"p1_a": [KEY_J],
	"p1_b": [KEY_K],
	"p1_c": [KEY_L],
	"p1_d": [KEY_I],
	"p1_e": [KEY_O],
	"p1_f": [KEY_U],
	"p1_start": [KEY_ENTER],
	"p2_left": [KEY_LEFT],
	"p2_right": [KEY_RIGHT],
	"p2_up": [KEY_UP],
	"p2_down": [KEY_DOWN],
	"p2_a": [KEY_KP_1, KEY_COMMA],
	"p2_b": [KEY_KP_2, KEY_PERIOD],
	"p2_c": [KEY_KP_3, KEY_SLASH],
	"p2_d": [KEY_KP_4, KEY_APOSTROPHE],
	"p2_e": [KEY_KP_6, KEY_P],
	"p2_f": [KEY_KP_5, KEY_BACKSLASH],
	"p2_start": [KEY_KP_ENTER, KEY_ENTER],
	"ui_up": [KEY_UP],
	"ui_down": [KEY_DOWN],
	"ui_left": [KEY_LEFT],
	"ui_right": [KEY_RIGHT],
	"ui_accept": [KEY_ENTER],
	"ui_cancel": [KEY_ESCAPE],
}

# 按钮 -> 动作名后缀
const BUTTON_SUFFIX := {
	InputButton.LEFT: "left",
	InputButton.RIGHT: "right",
	InputButton.UP: "up",
	InputButton.DOWN: "down",
	InputButton.A: "a",
	InputButton.B: "b",
	InputButton.C: "c",
	InputButton.D: "d",
	InputButton.E: "e",
	InputButton.F: "f",
	InputButton.START: "start",
}

# 可在设置中重绑定的按钮(显示顺序)
const BINDABLE_BUTTONS := [
	InputButton.UP, InputButton.DOWN, InputButton.LEFT, InputButton.RIGHT,
	InputButton.A, InputButton.B, InputButton.C, InputButton.D,
	InputButton.E, InputButton.F, InputButton.START,
]

# 每帧调用的输入状态
var p1_state: Dictionary = {}
var p2_state: Dictionary = {}

# 输入历史(用于指令识别)
var _p1_history: Array = []
var _p2_history: Array = []

# 玩家自定义覆盖: action -> keycode (覆盖后该动作只保留这一枚按键)
var _custom: Dictionary = {}


func _ready() -> void:
	_load_custom()
	_register_input_actions()
	_reset_state(p1_state)
	_reset_state(p2_state)


# ---------- 按键映射 / 重绑定 ----------

# 动作名, 如 "p1_left"
static func get_action_name(player: int, btn: int) -> String:
	var prefix := P1_PREFIX if player == 1 else P2_PREFIX
	return prefix + BUTTON_SUFFIX[btn]


# 该按钮当前生效的主按键
func get_keycode(player: int, btn: int) -> int:
	var action := get_action_name(player, btn)
	if _custom.has(action):
		return int(_custom[action])
	var def: Array = DEFAULT_MAP.get(action, [])
	return int(def[0]) if def.size() > 0 else KEY_NONE


# 是否已被玩家自定义过
func has_custom(player: int, btn: int) -> bool:
	return _custom.has(get_action_name(player, btn))


# 重绑定: 立即生效并持久化
func rebind(player: int, btn: int, keycode: int) -> void:
	var action := get_action_name(player, btn)
	_custom[action] = keycode
	_register_input_actions()
	_save_custom()


# 清除某玩家的全部自定义(回到默认)
func reset_player(player: int) -> void:
	var prefix := P1_PREFIX if player == 1 else P2_PREFIX
	for action in _custom.keys():
		if String(action).begins_with(prefix):
			_custom.erase(action)
	_register_input_actions()
	_save_custom()


# 清除所有自定义(回到默认)
func reset_all() -> void:
	_custom.clear()
	_register_input_actions()
	_save_custom()


# 按键显示名(常用键给中文/符号, 小键盘统一前缀)
static func key_label(keycode: int) -> String:
	var s := OS.get_keycode_string(keycode)
	match keycode:
		KEY_ENTER:
			s = "Enter"
		KEY_ESCAPE:
			s = "Esc"
		KEY_SPACE:
			s = "空格"
		KEY_LEFT:
			s = "←"
		KEY_RIGHT:
			s = "→"
		KEY_UP:
			s = "↑"
		KEY_DOWN:
			s = "↓"
		KEY_COMMA:
			s = ","
		KEY_PERIOD:
			s = "."
		KEY_SLASH:
			s = "/"
		KEY_APOSTROPHE:
			s = "'"
		KEY_BACKSLASH:
			s = "\\"
		KEY_SEMICOLON:
			s = ";"
		KEY_MINUS:
			s = "-"
		KEY_EQUAL:
			s = "="
		_:
			if s.begins_with("Kp "):
				s = "小键盘 " + s.substr(3)
	return s


# ---------- InputMap 注册 ----------

# 当前生效的按键列表: 自定义优先, 否则用默认
func _effective_keys(action: String) -> Array:
	if _custom.has(action):
		return [_custom[action]]
	return DEFAULT_MAP.get(action, [])


# 用 InputMap 注册输入动作 (Godot 4 的 KEY_* 常量跨版本稳定)
func _register_input_actions() -> void:
	for action in DEFAULT_MAP.keys():
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
		else:
			InputMap.add_action(action)
		for kc in _effective_keys(action):
			var ev := InputEventKey.new()
			ev.keycode = kc
			InputMap.action_add_event(action, ev)


func _load_custom() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(INPUT_CFG) != OK:
		return
	# 恢复默认后配置可能为空, 此时没有 keys 段
	if not cfg.has_section("keys"):
		return
	for action in cfg.get_section_keys("keys"):
		_custom[action] = int(cfg.get_value("keys", action))


func _save_custom() -> void:
	var cfg := ConfigFile.new()
	for action in _custom.keys():
		cfg.set_value("keys", action, _custom[action])
	cfg.save(INPUT_CFG)


# ---------- 每帧状态 ----------

func _process(_delta: float) -> void:
	_update_player_state(1, P1_PREFIX, p1_state, _p1_history)
	_update_player_state(2, P2_PREFIX, p2_state, _p2_history)


func _reset_state(state: Dictionary) -> void:
	state.clear()
	for btn in InputButton.values():
		state[btn] = {"pressed": false, "just_pressed": false, "just_released": false}


func _update_player_state(player: int, prefix: String, state: Dictionary, history: Array) -> void:
	for btn in InputButton.values():
		var action: String = prefix + BUTTON_SUFFIX[btn]
		var prev: bool = state[btn]["pressed"]
		var curr: bool = Input.is_action_pressed(action)
		state[btn]["pressed"] = curr
		state[btn]["just_pressed"] = curr and not prev
		state[btn]["just_released"] = not curr and prev

	# 更新输入历史
	var input_entry := _build_input_entry(state)
	history.push_back(input_entry)
	while history.size() > INPUT_BUFFER:
		history.pop_front()


func _build_input_entry(state: Dictionary) -> Dictionary:
	return {
		"left": state[InputButton.LEFT]["pressed"],
		"right": state[InputButton.RIGHT]["pressed"],
		"up": state[InputButton.UP]["pressed"],
		"down": state[InputButton.DOWN]["pressed"],
		"a": state[InputButton.A]["just_pressed"],
		"b": state[InputButton.B]["just_pressed"],
		"c": state[InputButton.C]["just_pressed"],
		"d": state[InputButton.D]["just_pressed"],
		"e": state[InputButton.E]["just_pressed"],
		"f": state[InputButton.F]["just_pressed"],
	}


# 获取玩家水平输入方向 (-1左, 0无, 1右)
func get_horizontal(player: int) -> int:
	var state := p1_state if player == 1 else p2_state
	if state[InputButton.LEFT]["pressed"] and not state[InputButton.RIGHT]["pressed"]:
		return -1
	if state[InputButton.RIGHT]["pressed"] and not state[InputButton.LEFT]["pressed"]:
		return 1
	return 0


# 获取玩家垂直输入方向 (-1上, 0无, 1下)
func get_vertical(player: int) -> int:
	var state := p1_state if player == 1 else p2_state
	if state[InputButton.UP]["pressed"] and not state[InputButton.DOWN]["pressed"]:
		return -1
	if state[InputButton.DOWN]["pressed"] and not state[InputButton.UP]["pressed"]:
		return 1
	return 0


# 检查某按钮是否刚按下
func is_just_pressed(player: int, btn: int) -> bool:
	var state := p1_state if player == 1 else p2_state
	return state[btn]["just_pressed"]


# 检查某按钮是否按住
func is_pressed(player: int, btn: int) -> bool:
	var state := p1_state if player == 1 else p2_state
	return state[btn]["pressed"]


# 检查某按钮是否刚释放
func is_just_released(player: int, btn: int) -> bool:
	var state := p1_state if player == 1 else p2_state
	return state[btn]["just_released"]


# 获取输入历史(用于识别必杀技指令)
func get_history(player: int) -> Array:
	return _p1_history if player == 1 else _p2_history
