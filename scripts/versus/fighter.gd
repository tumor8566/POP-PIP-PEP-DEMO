# Fighter.gd - 格斗角色控制器
# 管理角色的所有行为: 移动、攻击、防御、受击、连招等
class_name Fighter
extends CharacterBody2D

signal health_changed(current_health, max_health)
signal gray_life_changed(current_gray, max_gray)
signal meter_changed(current_meter, max_meter)
signal state_changed(new_state)
signal round_lost(fighter)
# 命中结算反馈: target=受击方, attacker=攻击方, seg=命中的段, blocked=是否被防御, spot=判定区(NONE/SWEET/SOUR)
signal hit_landed(target: Fighter, attacker: Fighter, seg: AttackData.Segment, blocked: bool, spot: int)

# 玩家编号
@export var player_id: int = 1

# 角色属性
var char_name := "Fighter"
var health := GlobalConfig.MAX_HEALTH:
	set(value):
		health = clampi(value, 0, GlobalConfig.MAX_HEALTH)

var meter := GlobalConfig.MAX_METER:
	set(value):
		meter = clampi(value, 0, GlobalConfig.MAX_METER)

var rounds_won := 0

# 抓取成立距离: 角色级框架值, 默认取全局 GRAB_RANGE(贴身范围)
#   后续设计具体角色/招式时可覆盖(如某些角色抓取更远或更近, 特定招式单独指定)
var grab_range := GlobalConfig.GRAB_RANGE

# 回气锁定帧: 推进(120f)/脱离(300f)用后一段时间内无法自动回气
var meter_regen_lockout := 0

# 状态
var current_state := FighterState.State.INTRO
var state_time := 0   # 当前状态的帧计数
var facing_right := true

# 攻击相关
var current_attack: AttackData = null
var attack_frame := 0
var combo_count := 0
var attack_level := GlobalConfig.ATTACK_LEVEL_MIN   # 当前攻击等级 LV1 ~ LV5 (F 推进技提升)

# 命中定格(打击顿帧): >0 时本帧完全冻结, 用于强化打击感
var hitstop_frames := 0

# 防御
var is_blocking := false
var block_direction := 0   # -1 防左, 1 防右

# 物理参数 (velocity 继承自 CharacterBody2D)
var gravity := GlobalConfig.GRAVITY

# F 推进技额外动量(逐帧衰减, 仅在执行动作时由 方向键+F 注入)
var advance_velocity := Vector2.ZERO

# ============ 数字方向(小键盘记法)指令 ============
# 朝向相对(以对手方向为前)的指令序列, 用于识别必杀技输入:
#   正半圈 QCF = 下(2) -> 下前(3) -> 前(6) = 236
#   反半圈 QCB = 下(2) -> 下后(1) -> 后(4) = 214
# 无论角色朝左朝右, 6 始终表示"朝对手方向"。
const MOTION_QCF := [2, 3, 6]
const MOTION_QCB := [2, 1, 4]

# 允许被动回气的"自由/中立"状态(受击、攻击、倒地等不回气)
const METER_REGEN_STATES := [
	FighterState.State.IDLE, FighterState.State.WALK_FORWARD, FighterState.State.WALK_BACK,
	FighterState.State.DASH_FORWARD, FighterState.State.DASH_BACK,
	FighterState.State.CROUCH, FighterState.State.CROUCH_BLOCK, FighterState.State.STAND_BLOCK,
	FighterState.State.JUMP_UP, FighterState.State.JUMP_FORWARD, FighterState.State.JUMP_BACK,
	FighterState.State.WAKEUP,
]

# 输入缓冲
var input_buffer := {}
var buffer_timer := 0

# 对手引用
var opponent: Fighter = null

# 被抓取 / 拆投(GRAB BREAK)
var is_being_grabbed := false
var _grab_break_window := 0
var _grab_attacker: Fighter = null
var _grab_segment: AttackData.Segment = null  # 抓取命中段的伤害/击退数据(抓取成立时结算)
var _grab_move_segment: AttackData.Segment = null  # D 键抓取动作使用的段数据(在 _setup_default_attacks 构建)
var _hit_stun_remaining := 0    # 本次受击的有效硬直帧(已按攻击方等级缩放)
var block_stun_timer := 0       # 防御硬直锁定帧(防御中受击后短暂无法脱离防御, 同时是"脱离"的触发窗口)
var _active_seg_index := -1  # 当前攻击正在激活的段索引(用于在切换段时重新配置 hitbox)

# ===== 虚血 (RECOVERABLE LIFE) =====
#   受击时按伤害的 GRAY_LIFE_RATIO 转化为灰色血量(血条灰段), 长时间未受击后逐步恢复
var gray_life := 0# 当前灰色血量(不参与 KO 判定)
var _gray_life_timer := 0      # 未受击计时(帧), 达到阈值后开始恢复

# ===== 追地 (PURSUIT) =====
#   对倒地/起身中的对手成立的追地攻击(命中后强制对手软倒地, 且不产生虚血)
var _pursuit_active := false   # 本次攻击是否为追地攻击

# ===== 相杀 (CRASH) =====
var _crash_timer := 0          # 相杀硬直剩余帧

# 攻击数据(子类或资源可覆盖)
var light_attacks: Array = []
var medium_attacks: Array = []
var heavy_attacks: Array = []
var special_attacks: Array = []

# 节点引用
@onready var sprite: Sprite2D = $Sprite
@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var hitbox: Hitbox = $Hitbox
@onready var state_label: Label = $StateLabel  # 调试用


func _ready() -> void:
	hurtbox.setup(self)
	hitbox.setup(self, null)
	hitbox.deactivate()
	
	# 初始化默认攻击数据
	_setup_default_attacks()
	
	# 设置朝向
	_update_facing()


func _setup_default_attacks() -> void:
	# ============ 轻攻击: 1段，全段防御 + 对胸 ============
	var atk_light := AttackData.new()
	atk_light.attack_name = "轻拳"
	atk_light.attack_type = AttackData.AttackType.LIGHT
	atk_light.attack_level = 1
	atk_light.meter_gain = 6
	# 取消链: 轻/中/重 通常技可取消进必杀技·气拳(不再保留 轻->中->重)
	atk_light.cancel_to_special = true
	var s_light := AttackData.Segment.new()
	s_light.defense_property = AttackData.DefenseProperty.FULL_BLOCK
	s_light.attack_attributes = AttackData.AttackAttribute.CHEST
	s_light.damage = GlobalConfig.LIGHT_DAMAGE
	s_light.hitbox_offset = Vector2(80, -40)
	s_light.hitbox_size = Vector2(120, 60)
	s_light.trigger_frame = 4
	s_light.active_duration = 3
	# 甜点 (SWEET): 判定框最靠近对手的右侧 30%(命中此处伤害提高并有额外演出)
	s_light.sweet_spot = Rect2(0.7, 0.0, 0.3, 1.0)
	atk_light.segments = [s_light]
	light_attacks.append(atk_light)

	# ============ 中攻击: 2段(演示多段独立属性) ============
	#   段1 全段防御·对胸；段2 蹲姿破坏·对臂+对胸
	var atk_medium := AttackData.new()
	atk_medium.attack_name = "中拳·二段"
	atk_medium.attack_type = AttackData.AttackType.MEDIUM
	atk_medium.attack_level = 2
	atk_medium.meter_gain = 8
	atk_medium.cancel_to_special = true
	var m_seg1 := AttackData.Segment.new()
	m_seg1.defense_property = AttackData.DefenseProperty.FULL_BLOCK
	m_seg1.attack_attributes = AttackData.AttackAttribute.CHEST
	m_seg1.damage = GlobalConfig.MEDIUM_DAMAGE / 2
	m_seg1.hitbox_offset = Vector2(90, -40)
	m_seg1.hitbox_size = Vector2(140, 60)
	m_seg1.trigger_frame = 7
	m_seg1.active_duration = 3
	var m_seg2 := AttackData.Segment.new()
	m_seg2.defense_property = AttackData.DefenseProperty.CROUCH_BREAK
	m_seg2.attack_attributes = AttackData.AttackAttribute.ARM | AttackData.AttackAttribute.CHEST
	m_seg2.damage = GlobalConfig.MEDIUM_DAMAGE / 2
	m_seg2.knockback_x = 260.0
	m_seg2.hitbox_offset = Vector2(100, -50)
	m_seg2.hitbox_size = Vector2(150, 50)
	m_seg2.trigger_frame = 14
	m_seg2.active_duration = 4
	# 酸点 (SOUR): 判定框最远离对手的左侧 30%(命中此处伤害降低、演出削弱)
	m_seg2.sour_spot = Rect2(0.0, 0.0, 0.3, 1.0)
	atk_medium.segments = [m_seg1, m_seg2]
	medium_attacks.append(atk_medium)

	# ============ 重攻击: 1段，蹲姿破坏 + 对腹 ============
	#   兼具追地(PURSUIT)性质: 对倒地/起身中的对手成立, 命中强制软倒地
	var atk_heavy := AttackData.new()
	atk_heavy.attack_name = "重拳·追地"
	atk_heavy.attack_type = AttackData.AttackType.HEAVY
	atk_heavy.attack_level = 3
	atk_heavy.meter_gain = 10
	atk_heavy.cancel_to_special = true
	var s_heavy := AttackData.Segment.new()
	s_heavy.defense_property = AttackData.DefenseProperty.CROUCH_BREAK
	s_heavy.attack_attributes = AttackData.AttackAttribute.STOMACH
	s_heavy.damage = GlobalConfig.HEAVY_DAMAGE
	s_heavy.knockback_x = 280.0
	s_heavy.hitbox_offset = Vector2(100, -40)
	s_heavy.hitbox_size = Vector2(160, 60)
	s_heavy.trigger_frame = 10
	s_heavy.active_duration = 5
	# 追地: 仅对倒地类状态成立; 命中后强制对手软倒地, 且不产生虚血
	s_heavy.is_pursuit = true
	# 甜点: 判定框靠对手侧 25%
	s_heavy.sweet_spot = Rect2(0.75, 0.0, 0.25, 1.0)
	atk_heavy.segments = [s_heavy]
	heavy_attacks.append(atk_heavy)

	# ============ 必杀技·气拳: 1段，全段防御 + 对胸(气攻) ============
	#   通常技命中后可取消进必杀技(指令 QCF + A); 气拳为当前取消链链尾(不耗气)
	var atk_special := AttackData.new()
	atk_special.attack_name = "气拳"
	atk_special.attack_type = AttackData.AttackType.SPECIAL
	atk_special.attack_level = 4
	atk_special.meter_gain = 12
	atk_special.meter_cost = 0
	var s_spec := AttackData.Segment.new()
	s_spec.defense_property = AttackData.DefenseProperty.FULL_BLOCK
	s_spec.attack_attributes = AttackData.AttackAttribute.CHEST | AttackData.AttackAttribute.QI
	s_spec.damage = 100
	s_spec.knockback_x = 300.0
	s_spec.hitbox_offset = Vector2(100, -40)
	s_spec.hitbox_size = Vector2(180, 70)
	s_spec.trigger_frame = 6
	s_spec.active_duration = 4
	atk_special.segments = [s_spec]
	special_attacks.append(atk_special)

	# ============ 抓取段(D 键): 需要被拆投(防御属性) + 抓取属性 ============
	_grab_move_segment = AttackData.Segment.new()
	_grab_move_segment.defense_property = AttackData.DefenseProperty.GRAB_BREAK_REQUIRED
	_grab_move_segment.attack_attributes = AttackData.AttackAttribute.GRAB
	_grab_move_segment.damage = GlobalConfig.GRAB_DAMAGE
	_grab_move_segment.knockback_x = 150.0
	_grab_move_segment.hit_stun = 20
	_grab_move_segment.hitbox_offset = Vector2(40, -30)
	_grab_move_segment.hitbox_size = Vector2(70, 50)
	_grab_move_segment.trigger_frame = 0
	_grab_move_segment.active_duration = 3


func _physics_process(_delta: float) -> void:
	# 命中定格: 受击/攻击命中瞬间短暂冻结双方, 强化打击冲击感
	if hitstop_frames > 0:
		hitstop_frames -= 1
		return

	state_time += 1
	
	# 方向+F: 动作中=推进(POP IMPETUS), 防御硬直中=脱离(ESCAPE)
	_try_f_boost()
	
	# 能量条: 中立/自由状态缓慢自动回气(攻击/受击/倒地时不回)
	_tick_meter(_delta)
	
	# 虚血: 长时间未受击后逐步恢复为实际血量
	_tick_gray_life()
	
	match current_state:
		FighterState.State.INTRO:
			_process_intro()
		FighterState.State.IDLE:
			_process_idle()
		FighterState.State.WALK_FORWARD, FighterState.State.WALK_BACK:
			_process_walk()
		FighterState.State.DASH_FORWARD, FighterState.State.DASH_BACK:
			_process_dash()
		FighterState.State.CROUCH, FighterState.State.CROUCH_BLOCK:
			_process_crouch()
		FighterState.State.STAND_BLOCK:
			_process_stand_block()
		FighterState.State.JUMP_UP, FighterState.State.JUMP_FORWARD, FighterState.State.JUMP_BACK:
			_process_jump()
		FighterState.State.ATTACK_LIGHT, FighterState.State.ATTACK_MEDIUM, FighterState.State.ATTACK_HEAVY, FighterState.State.ATTACK_SPECIAL:
			_process_attack()
		FighterState.State.HIT_STUN:
			_process_hit_stun()
		FighterState.State.GRABBED:
			_process_grabbed()
		FighterState.State.ESCAPE:
			_process_escape()
		FighterState.State.KNOCKDOWN:
			_process_knockdown()
		FighterState.State.SOFT_KNOCKDOWN:
			_process_soft_knockdown()
		FighterState.State.CRASHED:
			_process_crashed()
		FighterState.State.WAKEUP:
			_process_wakeup()
		FighterState.State.VICTORY, FighterState.State.DEFEATED:
			pass
	
	# 重力
	if not _is_grounded():
		velocity.y += gravity * _delta
		velocity.y = min(velocity.y, GlobalConfig.MAX_FALL_SPEED)
	
	# 叠加 F 推进动量后移动
	# (攻击中 velocity.x 被置 0, 此处仍会产生突进; 空中则叠加到惯性上)
	velocity += advance_velocity
	
	move_and_slide()
	_clamp_to_stage()
	_update_facing()
	
	# F 推进动量逐帧衰减, 低于阈值清零
	if advance_velocity != Vector2.ZERO:
		advance_velocity *= GlobalConfig.F_ADVANCE_DECAY
		if advance_velocity.length() < 4.0:
			advance_velocity = Vector2.ZERO

	# 调试标签实时刷新(状态/数字方向/等级)
	_update_debug_label()


# 限制在竞技场内, 保证摄像机始终能把双方框住
func _clamp_to_stage() -> void:
	var min_x := GlobalConfig.FIGHTER_BOUND_MARGIN
	var max_x := GlobalConfig.STAGE_WIDTH - GlobalConfig.FIGHTER_BOUND_MARGIN
	if global_position.x < min_x:
		global_position.x = min_x
	elif global_position.x > max_x:
		global_position.x = max_x


# ============ 状态处理 ============

func _process_intro() -> void:
	# 入场动画
	if state_time > 90:
		_change_state(FighterState.State.IDLE)


func _process_idle() -> void:
	velocity.x = 0
	_handle_universal_input()


func _process_walk() -> void:
	var direction := 1 if current_state == FighterState.State.WALK_FORWARD else -1
	velocity.x = GlobalConfig.WALK_SPEED * direction
	
	if _should_face_opponent():
		# 后退时自动面向对手
		pass
	
	_handle_universal_input()
	
	# 停止走路
	if InputHandler.get_horizontal(player_id) == 0:
		_change_state(FighterState.State.IDLE)


func _process_dash() -> void:
	var dash_dir := 1 if current_state == FighterState.State.DASH_FORWARD else -1
	velocity.x = GlobalConfig.DASH_SPEED * dash_dir
	
	if state_time >= GlobalConfig.DASH_DURATION * 60:
		_change_state(FighterState.State.IDLE)


func _process_crouch() -> void:
	velocity.x = 0

	# 防御硬直锁定: 受击后短时间内无法脱离防御/行动
	if block_stun_timer > 0:
		block_stun_timer -= 1
		return

	if not InputHandler.is_pressed(player_id, InputHandler.InputButton.DOWN):
		_change_state(FighterState.State.IDLE)
		return
	
	# 蹲防
	if _check_block(FighterState.State.CROUCH_BLOCK):
		return
	
	_handle_attack_input()


func _process_stand_block() -> void:
	velocity.x = 0

	# 防御硬直锁定: 受击后短时间内无法脱离防御
	if block_stun_timer > 0:
		block_stun_timer -= 1
		return

	if not _check_block(FighterState.State.STAND_BLOCK):
		_change_state(FighterState.State.IDLE)


func _process_jump() -> void:
	# 空中保留起跳时的横向惯性(斜跳/冲跳惯性), 不再按输入每帧覆盖速度
	if _is_grounded() and state_time > 5:
		_change_state(FighterState.State.IDLE)


# ============ F 推进技 ============

# 是否处于"执行动作"状态(推进 / POP IMPETUS 仅在此类状态生效)
#   IDLE / 受击 / 倒地 / 被抓 / 起身 / 胜负 / 入场 等非可控状态按 F 无影响
#   注: 防御硬直中另走"脱离(ESCAPE)"分支, 不在此列
func _is_in_action() -> bool:
	return current_state in [
		FighterState.State.WALK_FORWARD, FighterState.State.WALK_BACK,
		FighterState.State.DASH_FORWARD, FighterState.State.DASH_BACK,
		FighterState.State.JUMP_UP, FighterState.State.JUMP_FORWARD, FighterState.State.JUMP_BACK,
		FighterState.State.ATTACK_LIGHT, FighterState.State.ATTACK_MEDIUM,
		FighterState.State.ATTACK_HEAVY, FighterState.State.ATTACK_SPECIAL,
		FighterState.State.GRAB,
	]


# 方向+F 统一入口:
#   防御硬直中 -> 脱离(ESCAPE, 消耗 50P)
#   动作发生中 -> 推进(POP IMPETUS, 短按消耗 30P)
#   无动作(待机等) -> 完全无影响
func _try_f_boost() -> void:
	if not InputHandler.is_just_pressed(player_id, InputHandler.InputButton.F):
		return
	if _is_in_block_stun():
		_try_escape()
		return
	if _is_in_action():
		_try_pop_impetus()


# 是否处于"防御硬直"中(站防/蹲防被命中后的硬直窗口, 也是脱离的触发窗口)
func _is_in_block_stun() -> bool:
	return block_stun_timer > 0 and current_state in [
		FighterState.State.STAND_BLOCK, FighterState.State.CROUCH_BLOCK,
	]


# 推进(POP IMPETUS): 动作发生中 方向+F, 短按消耗 30P
#   - 保留当前运动状态的同时附加额外动量(动量方向由方向键控制)
#   - 若正处于攻击状态, 攻击等级 +1 (上限 LV5, 提升对手受击/防御硬直)
#   - 用后 120f 内无法自动回气
#   气量不足时本次推进无效
func _try_pop_impetus() -> void:
	if not _spend_meter(GlobalConfig.F_ADVANCE_METER_COST):
		return

	advance_velocity += _f_direction() * GlobalConfig.F_ADVANCE_SPEED
	meter_regen_lockout = GlobalConfig.F_ADVANCE_REGEN_LOCK

	# 处于攻击状态时提升攻击等级(抓取不提升等级)
	if current_state in [
		FighterState.State.ATTACK_LIGHT, FighterState.State.ATTACK_MEDIUM,
		FighterState.State.ATTACK_HEAVY, FighterState.State.ATTACK_SPECIAL,
	]:
		attack_level = min(attack_level + 1, GlobalConfig.ATTACK_LEVEL_MAX)
		_flash_level_up()


# 脱离(ESCAPE): 防御硬直中 方向+F, 消耗 50P
#   - 强制挣脱, 给角色提供一个额外动量(动量方向由方向键控制)
#   - 动作硬直 30f, 结束后角色可自由行动
#   - 用后 300f 内无法自动回气
#   气量不足时无法脱离
func _try_escape() -> void:
	if not _spend_meter(GlobalConfig.ESCAPE_METER_COST):
		return

	block_stun_timer = 0
	advance_velocity += _f_direction() * GlobalConfig.F_ADVANCE_SPEED
	meter_regen_lockout = GlobalConfig.ESCAPE_REGEN_LOCK
	_change_state(FighterState.State.ESCAPE)


# 取当前按住的方向向量(支持 上/下/左/右 及斜向); 未指定方向时默认朝面向方向前冲
func _f_direction() -> Vector2:
	var dir := Vector2(
		float(InputHandler.get_horizontal(player_id)),
		float(InputHandler.get_vertical(player_id))
	)
	if dir == Vector2.ZERO:
		dir = Vector2(1.0 if facing_right else -1.0, 0.0)
	elif dir.length() > 1.0:
		dir = dir.normalized()
	return dir


# 消耗气量(训练模式无限气时免消耗); 气量不足返回 false
func _spend_meter(cost: int) -> bool:
	var training_infinite := (MatchData.current_mode == MatchData.GameMode.TRAINING and MatchData.training_meter_infinite)
	if training_infinite:
		return true
	if meter < cost:
		return false
	meter -= cost
	emit_signal("meter_changed", meter, GlobalConfig.MAX_METER)
	return true


# 脱离动作处理: 保留挣脱动量(velocity.x 置零后由 advance_velocity 提供), 硬直结束可自由行动
func _process_escape() -> void:
	velocity.x = 0
	if state_time >= GlobalConfig.ESCAPE_STUN_FRAMES:
		if _is_grounded():
			_change_state(FighterState.State.IDLE)
		else:
			_change_state(FighterState.State.JUMP_UP)


# ---------- 数字方向(小键盘记法)辅助 ----------

# 当前"朝向相对"数字方向: 6 = 朝对手, 4 = 背对对手, 5 = 中立
func _numpad_direction() -> int:
	var d := InputHandler.get_numpad_direction(player_id)
	if facing_right:
		return d
	return _flip_numpad_horizontal(d)


# 将屏幕绝对数字方向水平翻转(角色朝左时, 右(6)变前(4)等)
static func _flip_numpad_horizontal(d: int) -> int:
	match d:
		1:
			return 3
		3:
			return 1
		4:
			return 6
		6:
			return 4
		7:
			return 9
		9:
			return 7
		_:
			return d   # 2/5/8 无横向分量, 不变


# 子序列判定: needle 是否作为子序列出现在 hay 中(用于指令识别)
static func _is_subsequence(hay: Array, needle: Array) -> bool:
	var i := 0
	for x in hay:
		if x == needle[i]:
			i += 1
			if i >= needle.size():
				return true
	return false


# 检测朝向相对指令是否在最近输入历史中出现(作为子序列)
func _history_has_motion(steps: Array) -> bool:
	var dirs := InputHandler.get_history_dirs(player_id)
	var rel: Array = []
	for d in dirs:
		rel.append(_flip_numpad_horizontal(d) if not facing_right else d)
	return _is_subsequence(rel, steps)


# 升级时的视觉提示(Sprite 轻微放大脉冲 + 调试标签)
func _flash_level_up() -> void:
	_update_debug_label()
	if not sprite:
		return
	if sprite.is_inside_tree() and get_tree():
		var tw := create_tween()
		tw.tween_property(sprite, "scale", Vector2(2.35, 2.35), 0.06)
		tw.tween_property(sprite, "scale", Vector2(2.0, 2.0), 0.12)


# 更新调试标签: 状态名 + 当前数字方向 + 当前攻击等级(仅 >LV1 时显示)
func _update_debug_label() -> void:
	if not is_instance_valid(state_label):
		return
	var names := FighterState.State.keys()
	var s: String = names[current_state] if current_state < names.size() else str(current_state)
	# 数字方向(朝向相对): 仅在不中立时显示, 便于在 Godot 中验证 6/4/2/8 体系
	var nd := _numpad_direction()
	if nd != 5:
		s += " %d" % nd
	if attack_level > GlobalConfig.ATTACK_LEVEL_MIN:
		s += " Lv%d" % attack_level
	# 虚血(RECOVERABLE LIFE): 显示灰色血量, 便于观察恢复过程
	if gray_life > 0:
		s += " G%d" % gray_life
	state_label.text = s


func _process_attack() -> void:
	attack_frame += 1
	velocity.x = 0
	if not current_attack or current_attack.segments.is_empty():
		hitbox.deactivate()
		_end_attack()
		return

	# 找出当前帧对应的激活段
	var active_seg: AttackData.Segment = current_attack.get_active_segment(attack_frame)

	# 仅在段切换时重新配置 hitbox(避免每帧重置命中列表)
	var new_index := -1
	if active_seg:
		new_index = current_attack.segments.find(active_seg)
	if new_index != _active_seg_index:
		_active_seg_index = new_index
		if active_seg:
			hitbox.activate(active_seg)
		else:
			hitbox.deactivate()

	# 攻击判定持续期间主动检测相杀: 双方判定框重叠且均未受击时立即生效
	if active_seg and hitbox.monitoring:
		hitbox._probe_overlaps()

	# 取消检查: 攻击已过第一段触发帧即允许取消
	var first_trigger := (current_attack.segments[0] as AttackData.Segment).trigger_frame
	if _can_cancel() and attack_frame >= first_trigger:
		_check_cancel_input()

	# 攻击结束(全部段的最大结束帧)
	if attack_frame >= current_attack.total_frames():
		_end_attack()


func _process_hit_stun() -> void:
	if state_time >= _hit_stun_remaining:
		if _is_grounded():
			_change_state(FighterState.State.IDLE)
		else:
			_change_state(FighterState.State.JUMP_UP)


func _process_knockdown() -> void:
	velocity.x = lerp(velocity.x, 0.0, 0.1)
	
	if _is_grounded() and state_time > 30:
		_change_state(FighterState.State.WAKEUP)


func _process_wakeup() -> void:
	velocity.x = 0
	if state_time > 20:
		_change_state(FighterState.State.IDLE)


# ============ 相杀 (CRASH) ============

# 是否可参与相杀: 必须处于攻击状态(判定框激活中)且未受击
func can_crash() -> bool:
	return current_state in [
		FighterState.State.ATTACK_LIGHT, FighterState.State.ATTACK_MEDIUM,
		FighterState.State.ATTACK_HEAVY, FighterState.State.ATTACK_SPECIAL,
	]


# 相杀结算: 双方攻击判定重叠(且均未受击)时, 双方产生 10% 停帧并按攻击等级互相推开
#   攻击等级高的一方推得更少(占据优势), 等级低的一方被推得更远
func resolve_crash(other: Fighter) -> void:
	if not is_instance_valid(other):
		return
	# 停帧: 双方同时冻结
	_crash_timer = GlobalConfig.CRASH_HITSTOP_FRAMES

	# 推开距离: 基础值 + 等级系数 * (最高等级 - 本方等级)
	var push: float = GlobalConfig.CRASH_PUSH_BASE \
			+ GlobalConfig.CRASH_PUSH_PER_LEVEL \
			* float(GlobalConfig.ATTACK_LEVEL_MAX - attack_level)
	# 沿远离对手的方向推开
	var dir: int = int(sign(global_position.x - other.global_position.x))
	if dir == 0:
		dir = 1 if other.facing_right else -1
	velocity.x = push * dir

	# 中断当前攻击, 进入相杀硬直
	hitbox.deactivate()
	current_attack = null
	attack_frame = 0
	_active_seg_index = -1
	_change_state(FighterState.State.CRASHED)


func _process_crashed() -> void:
	# 相杀硬直期间只保留推开的速度并逐渐衰减
	velocity.x = lerp(velocity.x, 0.0, 0.2)
	if _crash_timer > 0:
		_crash_timer -= 1
	if _crash_timer <= 0 and state_time >= GlobalConfig.CRASH_HITSTOP_FRAMES:
		_change_state(FighterState.State.IDLE)


# ============ 通用输入处理 ============

func _handle_universal_input() -> void:
	# 跳跃
	if InputHandler.is_just_pressed(player_id, InputHandler.InputButton.UP):
		_do_jump()
		return
	
	# 下蹲
	if InputHandler.is_pressed(player_id, InputHandler.InputButton.DOWN):
		_change_state(FighterState.State.CROUCH)
		return
	
	# 行走
	var h := InputHandler.get_horizontal(player_id)
	if h != 0:
		# 面对对手时：同方向=前进, 反方向=后退
		var toward_opponent := _direction_toward_opponent()
		if h == toward_opponent:
			_change_state(FighterState.State.WALK_FORWARD)
		else:
			_change_state(FighterState.State.WALK_BACK)
		return
	
	# 冲刺
	if InputHandler.is_just_pressed(player_id, InputHandler.InputButton.RIGHT):
		var toward := _direction_toward_opponent()
		if InputHandler.is_pressed(player_id, InputHandler.InputButton.RIGHT) and InputHandler.is_just_pressed(player_id, InputHandler.InputButton.RIGHT):
			pass  # 双击冲刺逻辑
	# 简化冲刺: 快速推两次方向
	_check_dash_input()
	
	# 站防
	if _check_block(FighterState.State.STAND_BLOCK):
		return
	
	# 攻击
	_handle_attack_input()


func _handle_attack_input() -> void:
	# 抓取组合键: A + B (等同于单按 D 抓取)
	if _combo_pressed(InputHandler.InputButton.A, InputHandler.InputButton.B):
		_attempt_grab()
		return
	# 格挡技组合键: B + C (等同于单按 E 格挡技)
	if _combo_pressed(InputHandler.InputButton.B, InputHandler.InputButton.C):
		_attempt_parry()
		return

	# 必杀技(Special Move): 仅由指令输入(半圈 QCF)触发, 不提供组合键快捷施放
	#   半圈 QCF(236) + 轻击(A) = 必杀技·气拳(不耗气)
	#   指令不成立时退化为通常技(轻)
	if InputHandler.is_just_pressed(player_id, InputHandler.InputButton.A) and _history_has_motion(MOTION_QCF):
		if _try_start_special():
			return

	# 通常技(Normal): 直接按攻击键(站 / 蹲 / 跳中均为此类)
	if InputHandler.is_just_pressed(player_id, InputHandler.InputButton.A):
		_start_attack(FighterState.State.ATTACK_LIGHT, light_attacks[0] if light_attacks.size() > 0 else null)
	elif InputHandler.is_just_pressed(player_id, InputHandler.InputButton.B):
		_start_attack(FighterState.State.ATTACK_MEDIUM, medium_attacks[0] if medium_attacks.size() > 0 else null)
	elif InputHandler.is_just_pressed(player_id, InputHandler.InputButton.C):
		_start_attack(FighterState.State.ATTACK_HEAVY, heavy_attacks[0] if heavy_attacks.size() > 0 else null)
	elif InputHandler.is_just_pressed(player_id, InputHandler.InputButton.D):
		_attempt_grab()
	elif InputHandler.is_just_pressed(player_id, InputHandler.InputButton.E):
		# 格挡技(招架)
		_attempt_parry()


func _check_cancel_input() -> void:
	# 取消链: 通常技(轻/中/重) -> 必杀技·气拳(QCF+A, 链尾)
	#   取消时检测指令输入(半圈 QCF) + 轻击, 不依赖组合键(A+B/B+C 已改为抓取/格挡技)
	if current_attack and current_attack.cancel_to_special \
			and InputHandler.is_just_pressed(player_id, InputHandler.InputButton.A) \
			and _history_has_motion(MOTION_QCF):
		if _try_start_special():
			return


# ============ 攻击系统 ============

func _start_attack(state: int, attack: AttackData) -> void:
	if not attack:
		return

	current_attack = attack
	attack_frame = 0
	combo_count = 0
	# 攻击等级由招式动作本身决定(固有基础等级), 而非每次从 LV1 起算
	attack_level = clampi(attack.attack_level, GlobalConfig.ATTACK_LEVEL_MIN, GlobalConfig.ATTACK_LEVEL_MAX)
	advance_velocity = Vector2.ZERO
	hitbox.owner_fighter = self
	hitbox.attack_data = attack
	hitbox.deactivate()
	_active_seg_index = -1
	_change_state(state)


func _end_attack() -> void:
	current_attack = null
	attack_frame = 0
	hitbox.attack_data = null
	hitbox.deactivate()
	_active_seg_index = -1
	combo_count = 0
	if _is_grounded():
		_change_state(FighterState.State.IDLE)
	else:
		_change_state(FighterState.State.JUMP_UP)


func _can_cancel() -> bool:
	# 通常技与必杀技·气拳可被取消; 必杀技·气拳为当前取消链链尾
	return current_state in [
		FighterState.State.ATTACK_LIGHT,
		FighterState.State.ATTACK_MEDIUM,
		FighterState.State.ATTACK_HEAVY,
		FighterState.State.ATTACK_SPECIAL,
	]


# 组合键检测: x 与 y 中有一个刚按下、另一个正按住(用于抓取 A+B / 格挡技 B+C 组合输入)
func _combo_pressed(x: int, y: int) -> bool:
	return (InputHandler.is_just_pressed(player_id, x) and InputHandler.is_pressed(player_id, y)) \
		or (InputHandler.is_just_pressed(player_id, y) and InputHandler.is_pressed(player_id, x))


# 起手/取消 必杀技·气拳: 由指令输入(半圈 QCF + 轻击)触发, 不消耗气
#   指令检测在调用处完成, 此函数只负责起手与防止空数组
func _try_start_special() -> bool:
	if special_attacks.is_empty():
		return false
	_start_attack(FighterState.State.ATTACK_SPECIAL, special_attacks[0] if special_attacks.size() > 0 else null)
	return true


func _attempt_grab() -> void:
	if not opponent:
		return
	if is_being_grabbed:
		return
	var dist := global_position.distance_to(opponent.global_position)
	# 抓取以段(_grab_move_segment)承载防御属性(需要被拆投)与攻击属性(抓取)
	#   成立距离取角色级 grab_range(默认全局贴身框架值, 可按角色/招式覆盖)
	if dist < grab_range and opponent._begin_grabbed(self, _grab_move_segment):
		_change_state(FighterState.State.GRAB)


# 被抓取: 开启拆投窗口；seg 为抓取段(抓取成立时按其伤害/击退结算)
func _begin_grabbed(attacker: Fighter, seg = null) -> bool:
	if is_being_grabbed or not _is_grounded():
		return false
	is_being_grabbed = true
	_grab_attacker = attacker
	_grab_segment = seg
	_grab_break_window = GlobalConfig.GRAB_BREAK_WINDOW
	velocity.x = 0
	_change_state(FighterState.State.GRABBED)
	return true


# 被抓取时每帧处理: 拆投窗口与抓取成立判定
func _process_grabbed() -> void:
	velocity.x = 0
	_grab_break_window -= 1

	# 拆投: 窗口内按下抓取键(D)化解
	if is_instance_valid(_grab_attacker) \
			and InputHandler.is_just_pressed(player_id, InputHandler.InputButton.D):
		_break_grab()
		return

	# 窗口耗尽, 抓取成立: 按抓取段的伤害/击退结算
	if _grab_break_window <= 0:
		is_being_grabbed = false
		var atk: Fighter = _grab_attacker
		var seg: AttackData.Segment = _grab_segment
		_grab_attacker = null
		_grab_segment = null
		var dmg: int = seg.damage if seg else GlobalConfig.GRAB_DAMAGE
		var kbx: float = seg.knockback_x if seg else 150.0
		_on_grabbed_settle(dmg, kbx)
		if is_instance_valid(atk):
			atk._on_grab_landed()


# 拆投成功
func _break_grab() -> void:
	is_being_grabbed = false
	var atk: Fighter = _grab_attacker
	_grab_attacker = null
	_grab_segment = null
	_change_state(FighterState.State.IDLE)
	if is_instance_valid(atk):
		atk._on_grab_broken()


# 抓取成立(攻击方)
func _on_grab_landed() -> void:
	_change_state(FighterState.State.IDLE)


# 抓取被拆(攻击方)
func _on_grab_broken() -> void:
	_change_state(FighterState.State.IDLE)
	# 拆投成功的反击硬直/后撤
	velocity.x = (-1 if facing_right else 1) * 150.0


func _attempt_parry() -> void:
	# 招架：短暂窗口内格挡并反击
	# 简化实现: 切换到防御状态
	if _is_grounded():
		_change_state(FighterState.State.STAND_BLOCK)
		state_time = 0


# ============ 防御系统 ============

func _check_block(block_state: int) -> bool:
	if not opponent or not _is_grounded():
		return false
	
	# 检查是否在防御方向
	var opp_dir := _direction_toward_opponent()
	var hold_dir := InputHandler.get_horizontal(player_id)
	
	# 按住后退 = 防御
	if hold_dir != 0 and hold_dir != opp_dir:
		if InputHandler.is_pressed(player_id, InputHandler.InputButton.E):
			_change_state(block_state)
			return true
	
	return false


# ============ 受击系统 ============

func _on_hit(source_hitbox: Area2D, hurtbox = null) -> void:
	if not is_instance_valid(source_hitbox):
		return

	var seg: AttackData.Segment = source_hitbox.current_segment
	if not seg:
		return
	var attack_data_ref: AttackData = source_hitbox.attack_data
	var attacker: Fighter = source_hitbox.owner_fighter

	# 命中后取消自身 F 推进(避免受击后继续滑行)
	advance_velocity = Vector2.ZERO

	# 追地 (PURSUIT): 仅对倒地/起身中的对手成立; 未倒地则本次攻击不成立
	if seg.is_pursuit and current_state not in FighterState.DOWN_STATES:
		return

	# 甜点/酸点判定: 依据命中点落在判定框内哪个区域(需受击框提供命中点换算)
	var spot: int = Hitbox.Spot.NONE
	if hurtbox != null and source_hitbox.has_method("evaluate_spot"):
		spot = source_hitbox.evaluate_spot(hurtbox)

	# 追地命中: 强制对手软倒地 + 位置被推开(不影响虚血)
	if seg.is_pursuit:
		_apply_pursuit_hit(seg, attack_data_ref, attacker)
		return

	# 防御判定
	if _is_blocking_segment(seg, attacker):
		_take_block_damage(seg)
		# 防御硬直随攻击方等级提升(LV 越高防御硬直越长)
		block_stun_timer = int(round(seg.block_stun * GlobalConfig.attack_level_stun_mult(attacker.attack_level)))
		emit_signal("hit_landed", self, attacker, seg, true, Hitbox.Spot.NONE)
		return

	# 抓取属性: 命中后将本角色置入被抓取状态(抓取成立时按 seg 伤害/击退结算)
	if seg.has_attribute(AttackData.AttackAttribute.GRAB):
		_begin_grabbed(attacker, seg)
		return

	# 普通命中结算(按甜点/酸点修正伤害)
	var dmg := _spot_adjusted_damage(seg, spot)
	_take_damage(dmg, seg, attack_data_ref, attacker)

	# 受击硬直随攻击方等级提升(LV 越高对手硬直越长); 酸点额外削弱, 甜点额外强化
	var stun_mult := GlobalConfig.attack_level_stun_mult(attacker.attack_level)
	if spot == Hitbox.Spot.SOUR:
		stun_mult *= 0.7
	elif spot == Hitbox.Spot.SWEET:
		stun_mult *= 1.3
	_hit_stun_remaining = int(round(seg.hit_stun * stun_mult))
	hitbox.deactivate()
	current_attack = attack_data_ref
	_change_state(FighterState.State.HIT_STUN)

	# 击退
	var kb_dir: int = int(sign(global_position.x - attacker.global_position.x))
	if kb_dir == 0:
		kb_dir = 1 if attacker.facing_right else -1
	velocity.x = seg.knockback_x * kb_dir
	velocity.y = seg.knockback_y

	# 通知对战场景触发打击反馈(命中定格/火花/震动/音效/连击)
	emit_signal("hit_landed", self, attacker, seg, false, spot)


# 按甜点/酸点修正本次命中的伤害
#   甜点 SWEET: 伤害 x SWEET_DAMAGE_MULT; 酸点 SOUR: 伤害 x SOUR_DAMAGE_MULT
func _spot_adjusted_damage(seg: AttackData.Segment, spot: int) -> int:
	match spot:
		Hitbox.Spot.SWEET:
			return int(round(seg.damage * GlobalConfig.SWEET_DAMAGE_MULT))
		Hitbox.Spot.SOUR:
			return int(round(seg.damage * GlobalConfig.SOUR_DAMAGE_MULT))
	return seg.damage


# 追地命中结算: 强制本角色进入软倒地, 位置被推开
#   按设计: 追地攻击不产生虚血, 但仍正常扣血
func _apply_pursuit_hit(seg: AttackData.Segment, attack: AttackData, attacker: Fighter) -> void:
	_take_damage(seg.damage, seg, attack, attacker, false)

	# 位置被推开(沿远离对手的方向)
	var away_dir: int = int(sign(global_position.x - attacker.global_position.x))
	if away_dir == 0:
		away_dir = 1 if attacker.facing_right else -1
	global_position.x += away_dir * GlobalConfig.PURSUIT_POSITION_SHIFT

	# 强制软倒地(短时间后自行起身)
	hitbox.deactivate()
	velocity.x = 0
	_change_state(FighterState.State.SOFT_KNOCKDOWN)

	emit_signal("hit_landed", self, attacker, seg, false, Hitbox.Spot.NONE)


# 软倒地处理: 短暂躺地后自行起身(不进入 WAKEUP 的受身流程)
func _process_soft_knockdown() -> void:
	velocity.x = lerp(velocity.x, 0.0, 0.15)
	if state_time >= GlobalConfig.PURSUIT_SOFT_KNOCKDOWN_FRAMES:
		_change_state(FighterState.State.WAKEUP)


# 抓取成立: 应用抓取段的伤害/击退
func _on_grabbed_settle(damage: int, knockback_x: float) -> void:
	_take_damage_raw(damage)
	velocity.y = -300
	velocity.x = knockback_x * (-1 if facing_right else 1)
	_change_state(FighterState.State.KNOCKDOWN)


func _is_blocking_segment(seg: AttackData.Segment, attacker: Fighter) -> bool:
	if current_state not in [FighterState.State.STAND_BLOCK, FighterState.State.CROUCH_BLOCK]:
		return false

	# 方向: 必须面对攻击者
	var dir_to_attacker: int = int(sign(attacker.global_position.x - global_position.x))
	if (facing_right and dir_to_attacker < 0) or (not facing_right and dir_to_attacker > 0):
		return false

	# 按段的防御属性判定
	match seg.defense_property:
		AttackData.DefenseProperty.UNBLOCKABLE:
			return false
		AttackData.DefenseProperty.GRAB_BREAK_REQUIRED:
			# 需要被拆投: 不可防御(由抓取段承担命中效果)
			return false
		AttackData.DefenseProperty.FULL_BLOCK:
			# 全段防御: 站防、蹲防皆可
			return true
		AttackData.DefenseProperty.STANCE_BREAK:
			# 站姿破坏: 仅蹲防
			return current_state == FighterState.State.CROUCH_BLOCK
		AttackData.DefenseProperty.CROUCH_BREAK:
			# 蹲姿破坏: 仅站防
			return current_state == FighterState.State.STAND_BLOCK
		_:
			return true


func _take_damage(damage: int, seg: AttackData.Segment, attack: AttackData, attacker: Fighter, produce_gray := true) -> void:
	_take_damage_raw(damage)
	# 虚血(RECOVERABLE LIFE): 按伤害比例转化为灰色血量, 长时间未受击后恢复
	#   追地攻击不产生虚血(produce_gray = false)
	if produce_gray:
		_add_gray_life(int(round(damage * GlobalConfig.GRAY_LIFE_RATIO)))
	if attack:
		attacker._gain_meter(attack.meter_gain)
	# 受击方按所受伤害比例回气(防守反哺)
	_gain_meter(int(round(damage * GlobalConfig.METER_GAIN_ON_DAMAGE_RATIO)))
	attacker.combo_count += 1


func _take_block_damage(seg: AttackData.Segment) -> void:
	_take_damage_raw(seg.chip_damage)
	velocity.x = seg.knockback_x * 0.3 * (-1 if facing_right else 1)


func _take_damage_raw(damage: int) -> void:
	health -= damage
	emit_signal("health_changed", health, GlobalConfig.MAX_HEALTH)
	
	if health <= 0:
		health = 0
		_on_knockout()


# ===== 虚血 (RECOVERABLE LIFE) =====

# 累积灰色血量(不超过上限), 并重置"未受击"计时
func _add_gray_life(amount: int) -> void:
	if amount <= 0:
		return
	gray_life = mini(gray_life + amount, GlobalConfig.MAX_HEALTH)
	_gray_life_timer = 0
	emit_signal("gray_life_changed", gray_life, GlobalConfig.MAX_HEALTH)


# 虚血恢复: 长时间(3S)未受击后, 每逻辑帧把灰血转化为实际血量
func _tick_gray_life() -> void:
	if gray_life <= 0:
		_gray_life_timer = 0
		return
	# 未受击计时达到阈值后才开始恢复
	if _gray_life_timer < GlobalConfig.GRAY_LIFE_RECOVER_DELAY:
		_gray_life_timer += 1
		return
	var recover: int = mini(GlobalConfig.GRAY_LIFE_RECOVER_PER_FRAME, gray_life)
	if recover <= 0:
		return
	# 灰血不能把血量恢复超过上限
	var space := GlobalConfig.MAX_HEALTH - health
	recover = mini(recover, maxi(space, 0))
	if recover <= 0:
		# 血量已满, 清空灰血
		gray_life = 0
		emit_signal("gray_life_changed", gray_life, GlobalConfig.MAX_HEALTH)
		return
	gray_life -= recover
	health += recover
	emit_signal("gray_life_changed", gray_life, GlobalConfig.MAX_HEALTH)
	emit_signal("health_changed", health, GlobalConfig.MAX_HEALTH)


# 血量与虚血一起重置(回合开始/训练重置)
func reset_vitals() -> void:
	health = GlobalConfig.MAX_HEALTH
	gray_life = 0
	_gray_life_timer = 0
	emit_signal("health_changed", health, GlobalConfig.MAX_HEALTH)
	emit_signal("gray_life_changed", gray_life, GlobalConfig.MAX_HEALTH)


func _gain_meter(amount: int) -> void:
	meter = min(meter + amount, GlobalConfig.MAX_METER)
	emit_signal("meter_changed", meter, GlobalConfig.MAX_METER)


# 气槽被动回充: 仅在"自由/中立"状态且非训练无限气时回气
#   按逻辑帧(60 FPS)计量: 每帧恢复 METER_REGEN_PER_FRAME P(不满时)
#   推进(120f)/脱离(300f)后的回气锁定期间不回气
func _tick_meter(delta: float) -> void:
	var training_infinite := (MatchData.current_mode == MatchData.GameMode.TRAINING and MatchData.training_meter_infinite)
	if training_infinite:
		return
	# 回气锁定倒计时(推进/脱离后一段时间内禁止回气)
	if meter_regen_lockout > 0:
		meter_regen_lockout -= 1
		return
	if current_state in METER_REGEN_STATES:
		var gain := int(round(GlobalConfig.METER_REGEN_PER_FRAME * delta * 60.0))
		var before := meter
		meter = min(meter + gain, GlobalConfig.MAX_METER)
		if meter != before:
			emit_signal("meter_changed", meter, GlobalConfig.MAX_METER)


# 施加命中定格帧数(取较大值, 避免被更轻的连段打断冻结)
func apply_hitstop(frames: int) -> void:
	hitstop_frames = max(hitstop_frames, frames)


func _on_knockout() -> void:
	# 训练模式: 不判负, 立即回满血继续练习
	if MatchData.current_mode == MatchData.GameMode.TRAINING:
		health = GlobalConfig.MAX_HEALTH
		emit_signal("health_changed", health, GlobalConfig.MAX_HEALTH)
		return
	_change_state(FighterState.State.DEFEATED)
	emit_signal("round_lost", self)


# ============ 跳跃 ============

# 起跳: 同时计算横向与纵向速度
#   纵向固定为 JUMP_VELOCITY; 横向 = 保留的地面惯性 + 斜跳初速(方向键+跳 = 斜跳)
func _do_jump() -> void:
	if not _is_grounded():
		return
	
	var h := InputHandler.get_horizontal(player_id)
	var keep := velocity.x * GlobalConfig.JUMP_MOMENTUM_KEEP   # 保留部分当前移动惯性
	velocity.x = clampf(keep + h * GlobalConfig.JUMP_SPEED_X,
		-GlobalConfig.AIR_MAX_SPEED_X, GlobalConfig.AIR_MAX_SPEED_X)
	velocity.y = GlobalConfig.JUMP_VELOCITY
	
	if h == 0:
		_change_state(FighterState.State.JUMP_UP)
	elif h == _direction_toward_opponent():
		_change_state(FighterState.State.JUMP_FORWARD)
	else:
		_change_state(FighterState.State.JUMP_BACK)


func _check_dash_input() -> void:
	# 简化: 快速双击方向 = 冲刺
	var h := InputHandler.get_horizontal(player_id)
	if h != 0 and InputHandler.is_just_pressed(player_id, InputHandler.InputButton.RIGHT if h > 0 else InputHandler.InputButton.LEFT):
		# 检查是否在短时间内的第二次输入
		if buffer_timer > 0 and h == _direction_toward_opponent():
			_change_state(FighterState.State.DASH_FORWARD)
		elif buffer_timer > 0:
			_change_state(FighterState.State.DASH_BACK)
		buffer_timer = 15


# ============ 工具方法 ============

func _change_state(new_state: int) -> void:
	if current_state == new_state:
		return
	
	current_state = new_state
	state_time = 0
	emit_signal("state_changed", new_state)
	_update_debug_label()


func _is_grounded() -> bool:
	return is_on_floor()


func _direction_toward_opponent() -> int:
	if not opponent:
		return 1
	return 1 if opponent.global_position.x > global_position.x else -1


func _should_face_opponent() -> bool:
	if not opponent:
		return false
	return true


func _update_facing() -> void:
	if not opponent:
		return
	
	var dir: int = int(sign(opponent.global_position.x - global_position.x))
	if dir != 0:
		facing_right = dir > 0
	
	if sprite:
		sprite.flip_h = not facing_right
