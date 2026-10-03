# GlobalConfig.gd - 全局配置单例 (Godot 4 适配)
# 管理游戏全局设置、音量、键位等
extends Node

# 设置持久化路径(与设置界面 settings.gd 共用)
const SETTINGS_PATH := "user://settings.cfg"

# 游戏分辨率
const GAME_WIDTH := 1280
const GAME_HEIGHT := 720

# 格斗参数
const ROUND_TIME := 99           # 每回合时间(秒)
const MAX_ROUNDS := 3            # 最大回合数(三局两胜)
const MAX_HEALTH := 100          # 最大血量 (100 H)
const MAX_METER := 100           # 最大气槽 (100 P)

# 角色通用属性
const WALK_SPEED := 400.0
const DASH_SPEED := 1000.0
const DASH_DURATION := 0.15
const JUMP_VELOCITY := -500.0
const GRAVITY := 1200.0
const MAX_FALL_SPEED := 800.0

# 跳跃(起跳惯性 + 斜跳)
const JUMP_SPEED_X := 380.0        # 斜跳横向初速
const JUMP_MOMENTUM_KEEP := 0.5    # 起跳保留的地面横向惯性比例
const AIR_MAX_SPEED_X := 650.0     # 起跳横向速度上限

# 竞技场/舞台(比视口更宽, 摄像机才有平移空间)
const STAGE_WIDTH := 1920.0
const STAGE_HEIGHT := 900.0
const GROUND_Y := 562.0            # 地面碰撞体上表面
const FIGHTER_BOUND_MARGIN := 40.0 # 角色活动边界留白(半宽)

# 摄像机(固定基准大小 + 轻微缩放)
const CAM_MIN_DIST := 320.0        # 低于此距离不缩放, 保持固定大小
const CAM_MAX_DIST := 900.0        # 超过此距离不再继续缩放
const CAM_MIN_ZOOM := 0.9          # 最小缩放, 仅略微拉远以框住双方
const CAM_FOLLOW_SMOOTH := 6.0     # 跟随平滑
const CAM_ZOOM_SMOOTH := 4.0       # 缩放平滑

# 攻击属性
const LIGHT_DAMAGE := 50
const MEDIUM_DAMAGE := 80
const HEAVY_DAMAGE := 120
const GRAB_DAMAGE := 140
const GRAB_RANGE := 55.0         # 抓取成立距离(贴身框架默认值; 具体角色/招式可覆盖 Fighter.grab_range)
const GRAB_BREAK_WINDOW := 12    # 拆投窗口(GRAB BREAK, 帧)：被抓取后在此期间按抓取键(D)可化解

# 攻击等级 (F 推进技): LV1 ~ LV5
const ATTACK_LEVEL_MIN := 1
const ATTACK_LEVEL_MAX := 5
# 攻击等级 -> 受击硬直 / 防御硬直倍率 (index 0 占位, 1..5 即 LV1..LV5)
const ATTACK_LEVEL_STUN_MULT := [1.0, 1.0, 1.25, 1.5, 1.75, 2.0]

# 方向+F 系统(统一入口):
#   动作发生中   -> 推进(POP IMPETUS): 保留运动状态附加额外动量, 攻击等级+1
#   防御硬直中   -> 脱离(ESCAPE): 强制挣脱, 附加额外动量
const F_ADVANCE_SPEED := 420.0        # 推进/脱离注入的额外动量速度(冲量)
const F_ADVANCE_DECAY := 0.85         # 每帧衰减系数
const F_ADVANCE_METER_COST := 30      # 推进(POP IMPETUS)短按消耗 30P(训练无限气时免消耗)
const F_ADVANCE_REGEN_LOCK := 120     # 推进后 120f 内无法自动回气

# 脱离(ESCAPE): 防御硬直中 方向+F 的强制挣脱
const ESCAPE_METER_COST := 50         # 脱离消耗 50P
const ESCAPE_STUN_FRAMES := 30        # 脱离动作硬直 30f(结束后可自由行动)
const ESCAPE_REGEN_LOCK := 300        # 脱离后 300f 内无法自动回气

# 能量条(气槽)系统 (满值 100 P, 每局开始默认 100 P)
#   逻辑帧为 1 秒 60 帧, 故"每帧"即按 60 FPS 计量
const METER_REGEN_PER_FRAME := 6            # 中立/自由状态每逻辑帧自动回气(不满时)
const METER_GAIN_ON_DAMAGE_RATIO := 0.5     # 受击方按所受伤害比例回气(防守反哺)

# ===== 虚血 (RECOVERABLE LIFE) =====
#   受击时按伤害的一定比例额外累积"灰色血量"(显示为血条上的灰段),
#   长时间(3S = 180 逻辑帧)未受击时开始逐步恢复为实际血量。
#   灰色血量不参与 KO 判定, 仅作为"可恢复的缓冲"。
const GRAY_LIFE_RATIO := 0.35               # 受击时转化为虚血的比例(其余为实际扣血)
const GRAY_LIFE_RECOVER_DELAY := 180        # 多久(帧)未受击后开始恢复(3S = 180f)
const GRAY_LIFE_RECOVER_PER_FRAME := 1      # 恢复开始后, 每逻辑帧恢复的虚血量

# ===== 甜点 (SWEET) / 酸点 (SOUR) =====
#   部分招式存在"最优/最劣判定区域"(以攻击判定框内的相对矩形区域定义)。
#   命中甜点: 伤害提高 SWEET_DAMAGE_MULT 倍并产生额外演出(闪白+震动更强)。
#   命中酸点: 伤害降低 SOUR_DAMAGE_MULT 倍并削弱演出。
const SWEET_DAMAGE_MULT := 1.5              # 甜点伤害倍率
const SOUR_DAMAGE_MULT := 0.6               # 酸点伤害倍率
const SWEET_SHAKE_BONUS := 12.0             # 甜点额外震屏强度
const SOUR_SHAKE_MULT := 0.5                # 酸点震屏折扣

# ===== 追地 (PURSUIT) =====
#   仅当对手处于倒地(KNOCKDOWN)/起身(WAKEUP)状态时才成立的追地攻击。
#   命中后强制对手进入"软倒地"(SOFT_KNOCKDOWN, 短时间后自行起身),
#   追地攻击不产生虚血(灰色血量)。
const PURSUIT_SOFT_KNOCKDOWN_FRAMES := 90   # 追地命中后对手软倒地持续帧(90f = 1.5S)
const PURSUIT_POSITION_SHIFT := 26.0        # 追地命中时把对手位置推开/拉近的距离

# ===== 相杀 (CRASH) =====
#   双方攻击判定框重叠时(且双方均未受击), 双方产生 10% 的停帧,
#   并根据自身攻击等级互相推开一定距离(等级高者推得更少, 占据优势)。
const CRASH_HITSTOP_FRAMES := 6             # 相杀停帧(帧)
const CRASH_PUSH_PER_LEVEL := 45.0          # 每级攻击等级的推开距离系数
const CRASH_PUSH_BASE := 60.0               # 基础推开距离

# 按攻击等级取硬直倍率
static func attack_level_stun_mult(level: int) -> float:
	var l := clampi(level, ATTACK_LEVEL_MIN, ATTACK_LEVEL_MAX)
	return ATTACK_LEVEL_STUN_MULT[l]

# 音量
var master_volume := 1.0:
	set(value):
		master_volume = clampf(value, 0.0, 1.0)
		var idx := AudioServer.get_bus_index("Master")
		if idx >= 0:
			AudioServer.set_bus_volume_db(idx, linear_to_db(master_volume))

var bgm_volume := 0.8:
	set(value):
		bgm_volume = clampf(value, 0.0, 1.0)
		var idx := AudioServer.get_bus_index("BGM")
		if idx >= 0:
			AudioServer.set_bus_volume_db(idx, linear_to_db(bgm_volume))

var sfx_volume := 1.0:
	set(value):
		sfx_volume = clampf(value, 0.0, 1.0)
		var idx := AudioServer.get_bus_index("SFX")
		if idx >= 0:
			AudioServer.set_bus_volume_db(idx, linear_to_db(sfx_volume))

# 设置
var fullscreen := false:
	set(value):
		fullscreen = value
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if value else DisplayServer.WINDOW_MODE_WINDOWED
		)

var show_hitboxes := false    # 调试用

# 回合时间: 默认无限时间
var round_time_infinite := true
var round_time_seconds := 99    # 非无限时每回合秒数

# 显示设置(由设置界面写入 user://settings.cfg, 启动时读取应用)
var window_width := 1280
var window_height := 720


func _ready() -> void:
	_load_display()


# 启动时应用上次保存的分辨率 / 全屏设置
func _load_display() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	window_width = int(cfg.get_value("display", "width", 1280))
	window_height = int(cfg.get_value("display", "height", 720))
	var fs := bool(cfg.get_value("display", "fullscreen", false))
	_apply_display(fs)


func _apply_display(fs: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if fs:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(window_width, window_height))
	fullscreen = fs
