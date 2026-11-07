# ComboTracker.gd - 连击计数器(纯逻辑, 每个攻击者一个实例)
# 由 VersusBattle 持有并驱动, 判定依据为 hit_landed 信号 + 受击方状态:
#   - 每次有效命中(非格挡) +1, 调用方立即刷新 HUD
#   - 对手处于"不能自由活动"状态(FighterState.RESTRICTED_STATES): 连击持续
#   - 对手恢复自由活动: 进入 1 秒滞留窗口, 数字保持显示;
#       窗口内再被命中 -> 连击继续(+1), 窗口归零;
#       窗口内没有下一次命中 -> 连击中断, 计数清零(调用方隐藏计数器)
#   - 计数 >= 1 即显示; 归零后下一次命中从 1 重新计数
extends RefCounted
class_name ComboTracker

var count: int = 0
var defender: Fighter = null

var _linger: float = 0.0


# 登记一次有效命中; target 为本次被命中的对手
func register_hit(target: Fighter) -> void:
	defender = target
	count += 1
	_linger = 0.0


# 每帧驱动(暂停时调用方应跳过); 返回 true 表示本帧连击结束, 需要隐藏计数器
func update(delta: float) -> bool:
	if count <= 0:
		return false
	# 对手仍不能自由活动: 连击持续, 滞留计时不成立
	if is_instance_valid(defender) \
			and defender.current_state in FighterState.RESTRICTED_STATES:
		_linger = 0.0
		return false
	# 对手已可自由活动: 滞留(观察)窗口开始累计
	_linger += delta
	if _linger >= GlobalConfig.COMBO_LINGER_SECONDS:
		reset()
		return true
	return false


func reset() -> void:
	count = 0
	defender = null
	_linger = 0.0
