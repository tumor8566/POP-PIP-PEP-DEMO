# ComboTracker.gd - 连击计数器(纯逻辑, 每个攻击者一个实例)
# 由 VersusBattle 持有并驱动, 判定依据为命中信号 + 受击方状态:
#   - 记录范围仅限"对方处于受击硬直"(FighterState.RESTRICTED_STATES)的时间:
#       该范围内每次有效命中(非格挡)累加到同一连击, 命中当帧实时刷新 HUD
#   - 对手一旦恢复自由活动 => 连击结束, 记录立即重置(count=0);
#       HUD 保留最后数字滞留 1 秒(GlobalConfig.COMBO_LINGER_SECONDS)后隐藏
#   - 记录结束后(含滞留期间)的命中 => 开启新连击(从 1 开始), 不沿用旧记录
#   - 回合结束由调用方停止记录, 本类提供 reset()
extends RefCounted
class_name ComboTracker

var count: int = 0        # 当前连击记录(连击结束即归零)
var defender: Fighter = null

var _active := false      # 记录进行中(对手仍在受击硬直范围内)
var _lingering := false   # 记录已结束, 最后数字滞留显示中
var _linger := 0.0


# 登记一次有效命中, 返回本次命中后应显示的连击数
func register_hit(target: Fighter) -> int:
	if _active and is_instance_valid(defender) and defender == target:
		count += 1
	else:
		# 上一段连击已结束(记录已重置)或首次命中: 开启新连击
		count = 1
	defender = target
	_active = true
	_lingering = false
	_linger = 0.0
	return count


# 每帧驱动(暂停/回合结束时调用方应跳过); 返回 true 表示滞留结束, 调用方隐藏计数器
func update(delta: float) -> bool:
	if _active:
		# 仍在受击硬直范围内: 记录继续有效
		if is_instance_valid(defender) \
				and defender.current_state in FighterState.RESTRICTED_STATES:
			return false
		# 恢复自由活动: 连击结束, 记录立即重置; 最后数字交给 HUD 滞留显示
		_active = false
		count = 0
		_lingering = true
		_linger = 0.0
		return false
	if _lingering:
		_linger += delta
		if _linger >= GlobalConfig.COMBO_LINGER_SECONDS:
			_lingering = false
			return true
	return false


func reset() -> void:
	count = 0
	defender = null
	_active = false
	_lingering = false
	_linger = 0.0
