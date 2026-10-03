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
const THROW_DAMAGE := 140
const THROW_RANGE := 55.0        # 投技成立距离(贴身框架默认值; 具体角色/招式可覆盖 Fighter.throw_range)
const GRAB_TECH_WINDOW := 12     # 拆投窗口(帧)，被抓取后在此期间按投技键可化解

# 攻击等级 (F 推进技): LV1 ~ LV5
const ATTACK_LEVEL_MIN := 1
const ATTACK_LEVEL_MAX := 5
# 攻击等级 -> 受击硬直 / 防御硬直倍率 (index 0 占位, 1..5 即 LV1..LV5)
const ATTACK_LEVEL_STUN_MULT := [1.0, 1.0, 1.25, 1.5, 1.75, 2.0]

# F 推进技: 角色执行动作时 方向键+F 注入的额外动量
const F_ADVANCE_SPEED := 420.0     # 推进冲量速度
const F_ADVANCE_DECAY := 0.85      # 每帧衰减系数
const F_ADVANCE_METER_COST := 25   # F 推进技消耗的气量(训练无限气时免消耗)

# 能量条(气槽)系统 (满值 100 P, 每局开始默认 100 P)
#   逻辑帧为 1 秒 60 帧, 故"每帧"即按 60 FPS 计量
const METER_REGEN_PER_FRAME := 6            # 中立/自由状态每逻辑帧自动回气(不满时)
const METER_GAIN_ON_DAMAGE_RATIO := 0.5     # 受击方按所受伤害比例回气(防守反哺)

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
