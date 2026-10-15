# BattleCamera.gd - 战斗摄像机
#   挂载于 versus_battle.tscn 的 Camera2D 节点, 由 versus_battle.gd 每帧驱动。
#
#   规则(按设计):
#     1. 正常状态下双方都显示在画面内
#     2. 双方都在画面边框继续拉开 -> 扩放到上限(CAM_MIN_ZOOM); 超过上限后
#        双方被画面边框限制, 无法继续拉开(帧边缘∩墙边界, 取更严者)
#     3. 双方贴身 -> 放大, 上限 CAM_MAX_ZOOM_IN
#     4. 纵向拟合: 只要未进入受击方优先模式(含"攻击方在地面/受击方在空中"
#        的受击情况), 一方跳高出画面上边界 -> 纵向扩放到足以显示双方
#        (同一 CAM_MIN_ZOOM 下限; 镜头允许高出舞台顶部, 底部不露出舞台底)
#     5. 双方均离地且一方受击 -> 受击方优先: 中心钉受击方, 缩放冻结;
#        攻击方移动出画面不触发任何扩放
class_name BattleCamera
extends Camera2D

enum Mode { NORMAL, VICTIM_PRIORITY }

var _a: Fighter = null
var _b: Fighter = null
var _mode: Mode = Mode.NORMAL
var _frozen_zoom := 1.0   # 进入受击方优先模式时冻结的缩放值

func setup(a: Fighter, b: Fighter) -> void:
	_a = a
	_b = b

func update_camera(delta: float) -> void:
	if not _a or not _b:
		return
	_update_mode()
	var target_zoom := _target_zoom()
	var target_pos := _target_position(target_zoom)

	# 平滑(沿用既有指数平滑公式)
	var zf := 1.0 - exp(-GlobalConfig.CAM_ZOOM_SMOOTH * delta)
	zoom.x = lerpf(zoom.x, target_zoom, zf)
	zoom.y = zoom.x
	var pf := 1.0 - exp(-GlobalConfig.CAM_FOLLOW_SMOOTH * delta)
	global_position = global_position.lerp(target_pos, pf)

	# 画面边框限制: 用目标帧判定, 不受平滑滞后影响(不会截断冲刺)
	_apply_frame_restriction(target_pos, target_zoom)

# ---------- 模式 ----------

# 受击方优先: 双方均离地 且 恰好一方处于受击反应状态
func _update_mode() -> void:
	var a_hit := _a.current_state in FighterState.HIT_REACTION_STATES
	var b_hit := _b.current_state in FighterState.HIT_REACTION_STATES
	if not _a.is_on_floor() and not _b.is_on_floor() and (a_hit != b_hit):
		if _mode != Mode.VICTIM_PRIORITY:
			_frozen_zoom = zoom.x
		_mode = Mode.VICTIM_PRIORITY
	else:
		_mode = Mode.NORMAL

func _victim() -> Fighter:
	return _a if _a.current_state in FighterState.HIT_REACTION_STATES else _b

# ---------- 目标缩放 ----------

func _target_zoom() -> float:
	# 受击方优先: 缩放冻结(攻击方出画不引起任何扩放)
	if _mode == Mode.VICTIM_PRIORITY:
		return clampf(_frozen_zoom, GlobalConfig.CAM_MIN_ZOOM, GlobalConfig.CAM_MAX_ZOOM_IN)

	var dist := absf(_a.global_position.x - _b.global_position.x)
	var z := 1.0
	if dist < GlobalConfig.CAM_MIN_DIST:
		# 贴身: 越近越放大, 上限 CAM_MAX_ZOOM_IN
		var t := clampf(dist / maxf(GlobalConfig.CAM_MIN_DIST, 1.0), 0.0, 1.0)
		z = lerpf(GlobalConfig.CAM_MAX_ZOOM_IN, 1.0, t)
	else:
		# 拉开: 越远越扩放, 下限 CAM_MIN_ZOOM
		var span := maxf(GlobalConfig.CAM_MAX_DIST - GlobalConfig.CAM_MIN_DIST, 1.0)
		var t := clampf((dist - GlobalConfig.CAM_MIN_DIST) / span, 0.0, 1.0)
		z = lerpf(1.0, GlobalConfig.CAM_MIN_ZOOM, t)

	# 纵向拟合: 除受击方优先模式外总是生效
	#   (含"攻击方在地面/受击方在空中"的受击情况: 扩放框住双方, 不冻结)
	#   只允许把镜头推远, 不允许推近
	z = minf(z, _vertical_fit_zoom())

	return clampf(z, GlobalConfig.CAM_MIN_ZOOM, GlobalConfig.CAM_MAX_ZOOM_IN)

# 纵向拟合缩放: 把双方视觉包围盒(+留白)框进画面所需的缩放; 无压力时返回放大上限(不影响横向)
func _vertical_fit_zoom() -> float:
	var need := _bbox().size.y + GlobalConfig.CAM_VERTICAL_MARGIN * 2.0
	if need <= GlobalConfig.GAME_HEIGHT:
		return GlobalConfig.CAM_MAX_ZOOM_IN
	return GlobalConfig.GAME_HEIGHT / need

# ---------- 目标位置 ----------

func _target_position(z: float) -> Vector2:
	var view := Vector2(GlobalConfig.GAME_WIDTH, GlobalConfig.GAME_HEIGHT) / z
	var focus: Vector2 = (_victim().global_position if _mode == Mode.VICTIM_PRIORITY \
		else (_a.global_position + _b.global_position) * 0.5)

	# x: 跟随焦点, 视宽不超出舞台
	var x := _clamp_axis(focus.x, view.x, GlobalConfig.STAGE_WIDTH)

	# y: 视觉包围盒能框住时用拟合中心; 框不住(纵向不扩放)时退回原点中点, 两端均摊
	var y := focus.y
	if _mode != Mode.VICTIM_PRIORITY:
		var bbox := _bbox()
		y = bbox.get_center().y if bbox.size.y + GlobalConfig.CAM_VERTICAL_MARGIN * 2.0 <= view.y \
			else (_a.global_position.y + _b.global_position.y) * 0.5
	# 只保留下界: 底部不露出舞台底; 不设上界: 允许高出舞台顶部
	y = minf(y, GlobalConfig.STAGE_HEIGHT - view.y * 0.5)
	return Vector2(x, y)

# 双方视觉包围盒(世界坐标): 顶 = 原点y - FIGHTER_VISUAL_TOP, 底 = 原点y + FIGHTER_VISUAL_BOTTOM
func _bbox() -> Rect2:
	var top := minf(_a.global_position.y - GlobalConfig.FIGHTER_VISUAL_TOP,
		_b.global_position.y - GlobalConfig.FIGHTER_VISUAL_TOP)
	var bottom := maxf(_a.global_position.y + GlobalConfig.FIGHTER_VISUAL_BOTTOM,
		_b.global_position.y + GlobalConfig.FIGHTER_VISUAL_BOTTOM)
	return Rect2(0.0, top, 0.0, bottom - top)

# ---------- 画面边框限制 ----------

# 已最大扩放(目标缩放触底)且双方间距超过帧宽时, 把双方钳制在 帧边缘∩墙边界 内。
#   仅钳位置不改速度: 受击滑行被边框别停时速度保留, 框松开后继续滑, 不产生抖动。
func _apply_frame_restriction(target_pos: Vector2, target_zoom: float) -> void:
	if _mode == Mode.VICTIM_PRIORITY:
		return   # 受击方优先: 攻击方允许出画, 不做边框限制
	if target_zoom > GlobalConfig.CAM_MIN_ZOOM + 0.001:
		return   # 还能继续扩放, 双方始终能被框住
	var half := (GlobalConfig.GAME_WIDTH / target_zoom) * 0.5
	var eff_l := maxf(target_pos.x - half, GlobalConfig.FIGHTER_BOUND_MARGIN)
	var eff_r := minf(target_pos.x + half,
		GlobalConfig.STAGE_WIDTH - GlobalConfig.FIGHTER_BOUND_MARGIN)
	if eff_l >= eff_r:
		return
	for f in [_a, _b]:
		if f.global_position.x < eff_l:
			f.global_position.x = eff_l
		elif f.global_position.x > eff_r:
			f.global_position.x = eff_r

# ---------- 工具 ----------

# 把镜头中心限制在舞台内: 可视范围小于舞台时按可视半宽夹取, 否则居中
func _clamp_axis(v: float, view_size: float, stage_size: float) -> float:
	if view_size >= stage_size:
		return stage_size * 0.5
	return clampf(v, view_size * 0.5, stage_size - view_size * 0.5)
