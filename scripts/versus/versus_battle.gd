# VersusBattle.gd - 对战场景主控制器
# 负责初始化对战场景、加载角色、连接信号
extends Node2D

@onready var round_manager: RoundManager = $RoundManager
@onready var hud: BattleHUD = $BattleHUD
@onready var camera: BattleCamera = $Camera2D

var p1_fighter: Fighter
var p2_fighter: Fighter

# 暂停菜单状态
var _paused := false
var _pause_menu: CanvasLayer

# 打击反馈: 屏幕震动
var _shake_strength := 0.0
var _shake_decay := 700.0   # 像素/秒, 震动衰减速率
var _hit_spark_scene: PackedScene = preload("res://resources/effects/hit_spark.tscn")
# 显式 preload, 不依赖 Godot 全局类缓存(新增脚本首次运行/headless 均可解析)
const ComboTrackerScript := preload("res://scripts/versus/combo_tracker.gd")

# 连击计数器: 下标 0 = P1 作为攻击者的连击, 下标 1 = P2 作为攻击者的连击
#   双方各自独立; 显示在攻击者自己的血量条下方
var _combo_trackers: Array = []
# 回合结束后停止记录(比赛结束/回合间隙的命中不计入, 也不显示)
var _combo_enabled := true


func _ready() -> void:
	_load_characters()
	_setup_arena()
	_combo_trackers = [ComboTrackerScript.new(), ComboTrackerScript.new()]

	# 连接命中反馈信号(双方角色)
	#   combo_hit_landed: 抓取结算等不产生打击演出的有效命中, 只驱动连击计数
	if p1_fighter:
		p1_fighter.hit_landed.connect(_on_fighter_hit_landed)
		p1_fighter.wall_bounced.connect(_on_wall_bounced)
		p1_fighter.combo_hit_landed.connect(_register_combo_hit)
	if p2_fighter:
		p2_fighter.hit_landed.connect(_on_fighter_hit_landed)
		p2_fighter.wall_bounced.connect(_on_wall_bounced)
		p2_fighter.combo_hit_landed.connect(_register_combo_hit)

	# 摄像机跟随双方(双向缩放/纵向拟合/受击方优先/边框限制)
	if camera and p1_fighter and p2_fighter:
		camera.setup(p1_fighter, p2_fighter)

	# 连接回合信号: 回合结束停止记录, 新回合恢复记录(均清空双方计数)
	if round_manager:
		round_manager.match_end.connect(_on_match_end)
		round_manager.round_end.connect(_on_round_end)
		round_manager.round_start.connect(_on_round_start)


func _load_characters() -> void:
	# 出生点: 以舞台中心对称分布
	var spawn_p1 := GlobalConfig.STAGE_WIDTH * 0.5 - 340.0
	var spawn_p2 := GlobalConfig.STAGE_WIDTH * 0.5 + 340.0

	# 获取 P1 角色资源路径
	var char1 := MatchData.get_character(MatchData.p1_character_index)

	# 玩家1(固定为本机玩家)
	var p1_scene := _load_fighter_scene(char1.id)
	if p1_scene:
		p1_fighter = p1_scene.instantiate()
		p1_fighter.player_id = 1
		p1_fighter.position = Vector2(spawn_p1, 500)
		p1_fighter.add_to_group("fighters")
		$Fighters.add_child(p1_fighter)

	# 对手: 训练模式加载训练假人, 否则按选人结果加载
	if MatchData.current_mode == MatchData.GameMode.TRAINING:
		var dummy_scene := _load_dummy_scene()
		if dummy_scene:
			p2_fighter = dummy_scene.instantiate()
			p2_fighter.player_id = 2
			p2_fighter.position = Vector2(spawn_p2, 500)
			p2_fighter.add_to_group("fighters")
			$Fighters.add_child(p2_fighter)
	else:
		var char2 := MatchData.get_character(MatchData.p2_character_index)
		var p2_scene := _load_fighter_scene(char2.id)
		if p2_scene:
			p2_fighter = p2_scene.instantiate()
			p2_fighter.player_id = 2
			p2_fighter.position = Vector2(spawn_p2, 500)
			p2_fighter.add_to_group("fighters")
			$Fighters.add_child(p2_fighter)

	# 设置相互引用
	if p1_fighter and p2_fighter:
		p1_fighter.opponent = p2_fighter
		p2_fighter.opponent = p1_fighter


func _load_fighter_scene(char_id: String) -> PackedScene:
	var path := "res://resources/characters/%s.tscn" % char_id
	if ResourceLoader.exists(path):
		return load(path)
	
	# 回退到通用角色场景
	path = "res://resources/characters/default_fighter.tscn"
	if ResourceLoader.exists(path):
		return load(path)
	
	return null


# 训练模式: 加载派生自 TrainingDummy 的假人场景
func _load_dummy_scene() -> PackedScene:
	var path := "res://resources/characters/default_training_dummy.tscn"
	if ResourceLoader.exists(path):
		return load(path)
	return null


func _setup_arena() -> void:
	# 设置战斗场地背景
	var stage_path := "res://resources/stages/default_stage.tscn"
	if ResourceLoader.exists(stage_path):
		var stage: Node = load(stage_path).instantiate()
		add_child(stage)
		move_child(stage, 0)  # 移到最底层


func _on_match_end(winner_id: int) -> void:
	var winner_text := "Player %d Wins!" % winner_id
	print(winner_text)
	# 比赛结束: 停止连击记录(结算/演出期间的命中不计入)
	_combo_enabled = false
	_clear_combos()

	# 延迟返回选人界面
	var timer := get_tree().create_timer(5.0)
	timer.timeout.connect(_return_to_select)


func _return_to_select() -> void:
	get_tree().change_scene_to_file("res://scenes/select/character_select.tscn")


# ---------- 打击反馈 ----------

func _process(delta: float) -> void:
	# 摄像机跟随/缩放/边框限制(暂停时冻结)
	if camera and not _paused:
		camera.update_camera(delta)

	# 连击滞留计时(暂停时冻结, 与战斗暂停一致)
	if not _paused:
		_update_combo_trackers(delta)

	# 震动衰减: 每帧朝随机方向偏移相机, 强度按时间衰减归零
	if camera and _shake_strength > 0.0:
		camera.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake_strength
		_shake_strength = max(0.0, _shake_strength - _shake_decay * delta)
	elif camera:
		camera.offset = Vector2.ZERO


# 版边反弹演出: 撞墙点火花 + 震屏(强度随入射力度)
#   注意: 不加 hitstop(未在设计内), 需要时再接入
func _on_wall_bounced(strength: float, wall_pos: Vector2) -> void:
	_spawn_hit_spark(wall_pos, Color(0.9, 0.9, 1.0), false)
	_shake_camera(clampf(strength * 0.05, 4.0, 14.0))


# ---------- 摄像机 ----------
# 跟随/缩放/边框限制逻辑已移至 scripts/versus/battle_camera.gd(BattleCamera),
#   由本脚本 _process 每帧驱动 camera.update_camera(delta)。


# 命中结算回调: 统一驱动 命中定格 / 火花 / 震动 / 闪光 / 连击 / 音效
#   spot 为判定区: NONE 普通 / SWEET 甜点(强化演出) / SOUR 酸点(削弱演出)
func _on_fighter_hit_landed(target: Fighter, attacker: Fighter, seg: AttackData.Segment, blocked: bool, spot: int = Hitbox.Spot.NONE) -> void:
	_apply_hitstop(_hitstop_frames_for(seg, blocked, spot))

	var spark_pos := target.global_position + Vector2(0, -40)
	_spawn_hit_spark(spark_pos, _hit_spark_color(seg, blocked, spot), blocked)

	_shake_camera(_shake_strength_for(seg, blocked, spot))

	_flash_target(target, blocked)

	if blocked:
		AudioManager.play_hit(0.5, true)
		# 格挡不是"命中", 不计入连击; 记录状态不变(仍在硬直内则继续, 已结束则照常显示滞留)
	else:
		if is_instance_valid(attacker):
			_register_combo_hit(attacker, target)
		AudioManager.play_hit(_hit_power(seg), false)
		# 甜点: 额外演出(角色闪白 + 提示文本)
		if spot == Hitbox.Spot.SWEET:
			_spawn_spot_banner(spark_pos, "SWEET 甜点", Color(1.0, 0.85, 0.2))
		elif spot == Hitbox.Spot.SOUR:
			_spawn_spot_banner(spark_pos, "SOUR 酸点", Color(0.6, 0.6, 0.7))


# ---------- 连击计数器 ----------

# 有效命中(非格挡, 含抓取结算) -> 登记到攻击者的计数器并立即刷新其血条下方数字
#   回合结束后直接忽略; 记录范围/重置由 ComboTracker 判定
#   1 秒显示滞留不影响这里: 滞留期间的命中同样走此函数, 由记录器判为新连击
func _register_combo_hit(attacker: Fighter, target: Fighter) -> void:
	if not _combo_enabled:
		return
	var idx: int = attacker.player_id - 1
	if idx < 0 or idx >= _combo_trackers.size():
		return
	var hits: int = _combo_trackers[idx].register_hit(target)
	if hud:
		hud.update_combo(attacker.player_id, hits)


# 每帧驱动: 对手脱离受击硬直时立即结束并重置记录; 1 秒后只隐藏显示
#   1 秒是纯显示时长, 不构成记录窗口: 期间命中由 _register_combo_hit 开新连击
func _update_combo_trackers(delta: float) -> void:
	if not _combo_enabled:
		return
	for i in _combo_trackers.size():
		if _combo_trackers[i].update(delta) and hud:
			hud.update_combo(i + 1, 0)


# 清空双方连击记录与显示(回合开始/结束/比赛结束共用)
func _clear_combos() -> void:
	for i in _combo_trackers.size():
		_combo_trackers[i].reset()
		if hud:
			hud.update_combo(i + 1, 0)


# 回合结束: 停止记录并清空(KO/超时之后的命中不计入连击)
func _on_round_end(_winner_id: int) -> void:
	_combo_enabled = false
	_clear_combos()


# 新回合开始: 恢复记录(计数从空开始, 不沿用上一回合)
func _on_round_start(_round_number: int) -> void:
	_combo_enabled = true
	_clear_combos()


# 甜点/酸点的额外演出: 在命中处显示提示文本
func _spawn_spot_banner(pos: Vector2, text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.global_position = pos + Vector2(-60, -70)
	label.size = Vector2(120, 24)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 18)
	label.z_index = 100
	add_child(label)
	var tw := create_tween()
	tw.tween_property(label, "position:y", label.position.y - 30.0, 0.5)
	tw.parallel().tween_property(label, "modulate:a", 0.0, 0.5)
	tw.tween_callback(label.queue_free)


# 双方同时施加命中定格(攻击方也被冻住, 强化冲击定格感)
func _apply_hitstop(frames: int) -> void:
	if p1_fighter:
		p1_fighter.apply_hitstop(frames)
	if p2_fighter:
		p2_fighter.apply_hitstop(frames)


func _spawn_hit_spark(pos: Vector2, color: Color, blocked: bool) -> void:
	var spark: Node2D = _hit_spark_scene.instantiate()
	spark.global_position = pos
	spark.setup(color, 1.0 if not blocked else 0.8)
	add_child(spark)


func _shake_camera(strength: float) -> void:
	_shake_strength = max(_shake_strength, strength)


func _flash_target(target: Fighter, blocked: bool) -> void:
	if not target or not is_instance_valid(target.sprite):
		return
	var spr: Sprite2D = target.sprite
	var flash := Color(1.4, 1.4, 1.4) if not blocked else Color(0.6, 0.8, 1.4)
	spr.modulate = flash
	var tween := target.create_tween()
	tween.tween_property(spr, "modulate", Color(1, 1, 1), 0.12)


func _hitstop_frames_for(seg: AttackData.Segment, blocked: bool, spot: int = Hitbox.Spot.NONE) -> int:
	if blocked:
		return 3
	var base: int = 4
	if seg:
		var dmg: int = seg.damage
		if dmg >= 200:
			base = 12   # 必杀技
		elif dmg >= 100:
			base = 9    # 重击 / 必杀技
		elif dmg >= 80:
			base = 7    # 中击二段
		else:
			base = 5        # 轻击
	# 甜点: 停帧更长(打击感更强); 酸点: 停帧更短
	if spot == Hitbox.Spot.SWEET:
		base += 4
	elif spot == Hitbox.Spot.SOUR:
		base = maxi(1, base - 2)
	return base


func _hit_spark_color(seg: AttackData.Segment, blocked: bool, spot: int = Hitbox.Spot.NONE) -> Color:
	if blocked:
		return Color(0.4, 0.7, 1.0)        # 蓝色格挡火花
	# 甜点: 金色火花; 酸点: 暗灰火花
	if spot == Hitbox.Spot.SWEET:
		return Color(1.0, 0.95, 0.4)
	if spot == Hitbox.Spot.SOUR:
		return Color(0.55, 0.55, 0.6)
	if not seg:
		return Color(1, 1, 1)
	var dmg: int = seg.damage
	if dmg >= 200:
		return Color(1.0, 0.5, 0.1)       # 橙红 必杀
	if dmg >= 100:
		return Color(1.0, 0.8, 0.2)       # 金黄 强击
	return Color(1.0, 1.0, 0.9)           # 白 轻击


func _shake_strength_for(seg: AttackData.Segment, blocked: bool, spot: int = Hitbox.Spot.NONE) -> float:
	if blocked:
		return 4.0
	var base: float = 6.0
	if seg:
		var dmg: int = seg.damage
		if dmg >= 200:
			base = 22.0
		elif dmg >= 100:
			base = 16.0
		else:
			base = 10.0
	# 甜点: 额外震屏; 酸点: 震屏打折
	if spot == Hitbox.Spot.SWEET:
		base += GlobalConfig.SWEET_SHAKE_BONUS
	elif spot == Hitbox.Spot.SOUR:
		base *= GlobalConfig.SOUR_SHAKE_MULT
	return base


func _hit_power(seg: AttackData.Segment) -> float:
	if not seg:
		return 0.6
	return clampf(float(seg.damage) / 220.0, 0.3, 1.0)


# ---------- 暂停菜单 ----------

func _open_pause() -> void:
	_paused = true
	# 暂停后本节点保持 ALWAYS, 以便继续接收 ESC 等输入
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true

	_pause_menu = CanvasLayer.new()
	_pause_menu.layer = 10          # 置于 HUD 之上
	_pause_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_pause_menu)
	_build_pause_menu()


func _close_pause() -> void:
	get_tree().paused = false
	_paused = false
	process_mode = Node.PROCESS_MODE_INHERIT
	if _pause_menu:
		_pause_menu.queue_free()
		_pause_menu = null


func _build_pause_menu() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_menu.add_child(dim)

	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -170.0
	panel.offset_top = -160.0
	panel.offset_right = 170.0
	panel.offset_bottom = 160.0
	_pause_menu.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 24.0
	vbox.offset_top = 24.0
	vbox.offset_right = -24.0
	vbox.offset_bottom = -24.0
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "暂 停"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)

	var resume := Button.new()
	resume.text = "继续"
	resume.pressed.connect(_close_pause)
	vbox.add_child(resume)

	var to_select := Button.new()
	to_select.text = "返回角色选择"
	to_select.pressed.connect(_on_pause_confirm.bind("select"))
	vbox.add_child(to_select)

	var to_menu := Button.new()
	to_menu.text = "返回主菜单"
	to_menu.pressed.connect(_on_pause_confirm.bind("menu"))
	vbox.add_child(to_menu)

	resume.grab_focus()


# 返回类操作带二次确认, 防止误触离开对战
func _on_pause_confirm(target: String) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = "离开对战"
	dlg.dialog_text = "确定要离开当前对战吗？对战进度将不会保存。"
	dlg.process_mode = Node.PROCESS_MODE_ALWAYS
	dlg.connect("confirmed", func() -> void:
		if target == "select":
			_pause_to_scene("res://scenes/select/character_select.tscn")
		else:
			_pause_to_scene("res://scenes/menu/main_menu.tscn")
	)
	_pause_menu.add_child(dlg)
	dlg.popup_centered()


func _pause_to_scene(path: String) -> void:
	# 先解除暂停再切换, 避免暂停态带入新场景
	get_tree().paused = false
	_paused = false
	process_mode = Node.PROCESS_MODE_INHERIT
	get_tree().change_scene_to_file(path)


# 训练场专用控制: 切换假人模式 / 无限开关 / 重置 / 退出
func _unhandled_key_input(event: InputEvent) -> void:
	# 对战中按 ESC: 暂停 / 恢复
	if MatchData.current_mode == MatchData.GameMode.LOCAL_VERSUS:
		if event.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
			if _paused:
				_close_pause()
			else:
				_open_pause()
			return

	if MatchData.current_mode != MatchData.GameMode.TRAINING:
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var dummy := p2_fighter as TrainingDummy
	if not dummy:
		return

	match event.keycode:
		KEY_1:
			dummy.set_dummy_mode(TrainingDummy.DummyMode.STAND)
		KEY_2:
			dummy.set_dummy_mode(TrainingDummy.DummyMode.CROUCH)
		KEY_3:
			dummy.set_dummy_mode(TrainingDummy.DummyMode.WALK)
		KEY_4:
			dummy.set_dummy_mode(TrainingDummy.DummyMode.BLOCK_ALL)
		KEY_5:
			dummy.set_dummy_mode(TrainingDummy.DummyMode.RANDOM)
		KEY_H:
			MatchData.training_health_infinite = not MatchData.training_health_infinite
		KEY_M:
			MatchData.training_meter_infinite = not MatchData.training_meter_infinite
		KEY_R:
			dummy.reset_dummy()
		KEY_ESCAPE:
			get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")
