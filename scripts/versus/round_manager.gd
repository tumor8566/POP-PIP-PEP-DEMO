# RoundManager.gd - 回合管理器 (Godot 4 适配)
# 管理对战流程: 倒计时、回合判定、胜负判定
extends Node
class_name RoundManager

signal round_start(round_number)
signal round_end(winner_player_id)
signal match_end(winner_player_id)

var round_number := 1
var round_timer := 0.0
var timer_running := false
var pause_between_rounds := false

var p1: Fighter
var p2: Fighter

@onready var timer_label: Label = $"../BattleHUD/HUDContainer/CenterInfo/TimerLabel"
@onready var round_label: Label = $"../BattleHUD/HUDContainer/RoundLabel"


func _ready() -> void:
	# 查找两个玩家
	var fighters := get_tree().get_nodes_in_group("fighters")
	for f in fighters:
		if f is Fighter:
			if f.player_id == 1:
				p1 = f
			elif f.player_id == 2:
				p2 = f
			f.round_lost.connect(_on_fighter_lost)

	_start_round()


# 是否处于训练模式(无限时、不败北、角色可无限复活)
func _is_training() -> bool:
	return MatchData.current_mode == MatchData.GameMode.TRAINING


func _process(delta: float) -> void:
	if not timer_running:
		return

	round_timer -= delta
	_update_timer_display()

	if round_timer <= 0:
		round_timer = 0
		_on_timeout()


func _start_round() -> void:
	round_timer = 0.0
	timer_running = false
	pause_between_rounds = false

	# 重置角色状态: 每局游戏开始, 血量与气槽均默认满值(100 H / 100 P), 虚血清空
	if p1:
		p1.reset_vitals()
		p1.meter = GlobalConfig.MAX_METER
	if p2:
		p2.reset_vitals()
		p2.meter = GlobalConfig.MAX_METER

	# 训练模式: 无限时、不败北, 直接开始
	if _is_training():
		_update_timer_display()
		_show_round_text("训练模式")
		round_start.emit(round_number)
		return

	# 设置计时器(默认无限时间)
	if GlobalConfig.round_time_infinite:
		_update_timer_display()   # 显示 ∞, 不开始倒计时
	else:
		round_timer = float(GlobalConfig.round_time_seconds)
		_update_timer_display()

	# 短暂停顿后开始
	var timer := get_tree().create_timer(1.5)
	timer.timeout.connect(_on_round_begin)

	_show_round_text("Round %d" % round_number)
	round_start.emit(round_number)


func _on_round_begin() -> void:
	# 无限时间则不启动倒计时
	if not GlobalConfig.round_time_infinite:
		timer_running = true


func _on_fighter_lost(loser: Fighter) -> void:
	timer_running = false

	# 训练模式: 不判胜负, 立即复活继续练习
	if _is_training():
		loser.health = GlobalConfig.MAX_HEALTH
		return

	var winner_id := 1 if loser.player_id == 2 else 2

	if winner_id == 1:
		MatchData.p1_rounds_won += 1
	else:
		MatchData.p2_rounds_won += 1

	round_end.emit(winner_id)

	# 检查是否赢得比赛(三局两胜)
	var needed: int = int(ceil(GlobalConfig.MAX_ROUNDS / 2.0))
	if MatchData.p1_rounds_won >= needed:
		_on_match_end(1)
	elif MatchData.p2_rounds_won >= needed:
		_on_match_end(2)
	else:
		round_number += 1
		pause_between_rounds = true
		var timer := get_tree().create_timer(2.0)
		timer.timeout.connect(_start_round)


func _on_timeout() -> void:
	# 训练模式 / 无限时间不会触发; 防御性处理: 重置计时继续
	if _is_training() or GlobalConfig.round_time_infinite:
		round_timer = 0.0
		timer_running = false
		return

	# 超时判定: 血量多的获胜
	timer_running = false
	if p1.health > p2.health:
		_on_fighter_lost(p2)
	elif p2.health > p1.health:
		_on_fighter_lost(p1)
	else:
		# 平局: 双方各记一轮
		MatchData.p1_rounds_won += 1
		MatchData.p2_rounds_won += 1
		_check_match_end()


func _on_match_end(winner_id: int) -> void:
	MatchData.winner = winner_id
	match_end.emit(winner_id)

	# 显示结果，几秒后返回选人
	var timer := get_tree().create_timer(4.0)
	timer.timeout.connect(_return_to_select)


func _check_match_end() -> void:
	var needed: int = int(ceil(GlobalConfig.MAX_ROUNDS / 2.0))
	if MatchData.p1_rounds_won >= needed:
		_on_match_end(1)
	elif MatchData.p2_rounds_won >= needed:
		_on_match_end(2)
	else:
		round_number += 1
		_start_round()


func _return_to_select() -> void:
	get_tree().change_scene_to_file("res://scenes/select/character_select.tscn")


func _update_timer_display() -> void:
	if timer_label:
		if GlobalConfig.round_time_infinite:
			timer_label.text = "∞"
			timer_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		else:
			timer_label.text = "%02d" % int(ceil(round_timer))
			if round_timer <= 10:
				timer_label.add_theme_color_override("font_color", Color(1, 0, 0, 1))


func _show_round_text(text: String) -> void:
	if round_label:
		round_label.text = text
		round_label.visible = true
		var timer := get_tree().create_timer(1.5)
		timer.timeout.connect(round_label.set_visible.bind(false))
