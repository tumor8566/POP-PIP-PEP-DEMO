# MatchData.gd - 比赛数据单例
# 在场景间传递选人和比赛状态
extends Node

# 角色数据定义
class CharacterData:
	var id: String
	var display_name: String
	var portrait_path: String    # 立绘路径
	var icon_path: String        # 头像路径
	var description: String
	
	func _init(p_id: String, p_name: String, p_portrait: String = "", p_icon: String = "", p_desc: String = "") -> void:
		id = p_id
		display_name = p_name
		portrait_path = p_portrait
		icon_path = p_icon
		description = p_desc


# 可用角色列表
var character_list: Array = []

# 玩家选择
var p1_character_index := 0
var p1_color_index := 0
var p2_character_index := 0
var p2_color_index := 0

# 对战结果
var p1_rounds_won := 0
var p2_rounds_won := 0
var winner := 0

# 游戏模式
enum GameMode { LOCAL_VERSUS, TRAINING }
var current_mode: int = GameMode.LOCAL_VERSUS

# 训练场设置
var training_dummy_enabled := true
var training_meter_infinite := true
var training_health_infinite := true


func _ready() -> void:
	_register_default_characters()


func _register_default_characters() -> void:
	character_list = [
		CharacterData.new("fighter", "格斗家", "", "", "均衡型角色，适合初学者"),
		CharacterData.new("swordsman", "剑士", "", "", "中距离牵制型角色"),
		CharacterData.new("brawler", "拳霸", "", "", "近距离力量型角色"),
		CharacterData.new("ninja", "忍者", "", "", "高速技巧型角色"),
	]


func get_character(index: int) -> CharacterData:
	if index >= 0 and index < character_list.size():
		return character_list[index]
	return character_list[0]


func get_color_name(index: int) -> String:
	var colors := ["默认", "蓝色", "红色", "绿色", "黄色", "紫色"]
	if index >= 0 and index < colors.size():
		return colors[index]
	return "默认"


func reset_rounds() -> void:
	p1_rounds_won = 0
	p2_rounds_won = 0
	winner = 0
