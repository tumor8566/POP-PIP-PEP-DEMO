# VersusBattle.gd - 对战场景主控制器
# 负责初始化对战场景、加载角色、连接信号
extends Node2D

@onready var round_manager: RoundManager = $RoundManager
@onready var hud: BattleHUD = $BattleHUD
@onready var camera: Camera2D = $Camera2D

var p1_fighter: Fighter
var p2_fighter: Fighter

# 暂停菜单状态
var _paused := false
var _pause_menu: CanvasLayer

# 打击反馈: 屏幕震动
var _shake_strength := 0.0
var _shake_decay := 700.0   # 像素/秒, 震动衰减速率
var _hit_spark_scene: PackedScene = preload("res://resources/effects/hit_spark.tscn")


func _ready() -> void:
	_load_characters()
	_setup_arena()

	# 连接命中反馈信号(双方角色)
	if p1_fighter:
		p1_fighter.hit_landed.connect(_on_fighter_hit_landed)
	if p2_fighter:
		p2_fighter.hit_landed.connect(_on_fighter_hit_landed)

	# 连接比赛结束信号
	if round_manager:
		round_manager.match_end.connect(_on_match_end)


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
	
	# 延迟返回选人界面
	var timer := get_tree().create_timer(5.0)
	timer.timeout.connect(_return_to_select)


func _return_to_select() -> void:
	get_tree().change_scene_to_file("res://scenes/select/character_select.tscn")


# ---------- 打击反馈 ----------

func _process(delta: float) -> void:
	_update_camera(delta)

	# 震动衰减: 每帧朝随机方向偏移相机, 强度按时间衰减归零
	if camera and _shake_strength > 0.0:
		camera.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake_strength
		_shake_strength = max(0.0, _shake_strength - _shake_decay * delta)
	elif camera:
		camera.offset = Vector2.ZERO


# ---------- 摄像机 ----------
# 固定基准大小(1.0); 双方拉开时略微拉远以框住两人;
# 超过 CAM_MAX_DIST 后不再继续缩放(取消缩放), 仅继续跟随。
func _update_camera(delta: float) -> void:
	if not camera or not p1_fighter or not p2_fighter or _paused:
		return

	var p1p: Vector2 = p1_fighter.global_position
	var p2p: Vector2 = p2_fighter.global_position
	var mid := (p1p + p2p) * 0.5
	var dist := absf(p1p.x - p2p.x)

	# 缩放: 距离越大越接近 CAM_MIN_ZOOM, 超出阈值后保持不变
	var span := maxf(GlobalConfig.CAM_MAX_DIST - GlobalConfig.CAM_MIN_DIST, 1.0)
	var t := clampf((dist - GlobalConfig.CAM_MIN_DIST) / span, 0.0, 1.0)
	var target_zoom := lerpf(1.0, GlobalConfig.CAM_MIN_ZOOM, t)
	var zf := 1.0 - exp(-GlobalConfig.CAM_ZOOM_SMOOTH * delta)
	camera.zoom.x = lerpf(camera.zoom.x, target_zoom, zf)
	camera.zoom.y = camera.zoom.x

	# 位置: 跟随中点, 并把可视范围限制在舞台内, 避免露出舞台之外
	var view := Vector2(GlobalConfig.GAME_WIDTH, GlobalConfig.GAME_HEIGHT) / camera.zoom.x
	var target := Vector2(
		_clamp_axis(mid.x, view.x, GlobalConfig.STAGE_WIDTH),
		_clamp_axis(mid.y, view.y, GlobalConfig.STAGE_HEIGHT)
	)
	var pf := 1.0 - exp(-GlobalConfig.CAM_FOLLOW_SMOOTH * delta)
	camera.global_position = camera.global_position.lerp(target, pf)


# 把镜头中心限制在舞台内: 可视范围小于舞台时按可视半宽夹取, 否则居中
func _clamp_axis(v: float, view_size: float, stage_size: float) -> float:
	if view_size >= stage_size:
		return stage_size * 0.5
	return clampf(v, view_size * 0.5, stage_size - view_size * 0.5)


# 命中结算回调: 统一驱动 命中定格 / 火花 / 震动 / 闪光 / 连击 / 音效
func _on_fighter_hit_landed(target: Fighter, attacker: Fighter, seg: AttackData.Segment, blocked: bool) -> void:
	_apply_hitstop(_hitstop_frames_for(seg, blocked))

	var spark_pos := target.global_position + Vector2(0, -40)
	_spawn_hit_spark(spark_pos, _hit_spark_color(seg, blocked), blocked)

	_shake_camera(_shake_strength_for(seg, blocked))

	_flash_target(target, blocked)

	if blocked:
		AudioManager.play_hit(0.5, true)
		hud.update_combo(0)
	else:
		if is_instance_valid(attacker):
			hud.update_combo(attacker.combo_count)
		AudioManager.play_hit(_hit_power(seg), false)


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


func _hitstop_frames_for(seg: AttackData.Segment, blocked: bool) -> int:
	if blocked:
		return 3
	if not seg:
		return 4
	var dmg: int = seg.damage
	if dmg >= 200:
		return 12   # 必杀技
	if dmg >= 100:
		return 9    # 重击 / 特殊技
	if dmg >= 80:
		return 7    # 中击二段
	return 5        # 轻击


func _hit_spark_color(seg: AttackData.Segment, blocked: bool) -> Color:
	if blocked:
		return Color(0.4, 0.7, 1.0)        # 蓝色格挡火花
	if not seg:
		return Color(1, 1, 1)
	var dmg: int = seg.damage
	if dmg >= 200:
		return Color(1.0, 0.5, 0.1)       # 橙红 必杀
	if dmg >= 100:
		return Color(1.0, 0.8, 0.2)       # 金黄 强击
	return Color(1.0, 1.0, 0.9)           # 白 轻击


func _shake_strength_for(seg: AttackData.Segment, blocked: bool) -> float:
	if blocked:
		return 4.0
	if not seg:
		return 6.0
	var dmg: int = seg.damage
	if dmg >= 200:
		return 22.0
	if dmg >= 100:
		return 16.0
	return 10.0


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
