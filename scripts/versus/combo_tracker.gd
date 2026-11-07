# ComboTracker.gd - 连击"记录"计数器(纯逻辑, 每个攻击者一个实例)
# 只负责一件事: 统计对方处于受击硬直(FighterState.RESTRICTED_STATES)期间的有效命中数。
#
#   *** 1 秒显示滞留与记录判定完全无关 ***
#   连击结束后 HUD 保留最后数字 1 秒(GlobalConfig.COMBO_LINGER_SECONDS), 那只是
#   "显示持续时间", 不是记录窗口, 也没有任何容差/续连语义:
#     - register_hit() 从不读取显示计时, 任何时刻的命中都只按"记录状态"判定;
#     - 记录已结束(含数字滞留显示期间) => 一律开启新连击, 从 1 开始, 并作废旧显示计时;
#     - 记录进行中 => 累加到同一连击。
#   _show_timer 只决定"何时把标签隐藏", 不参与任何计数/判定/记录范围。
extends RefCounted
class_name ComboTracker

var count: int = 0          # 当前连击记录(连击结束立即归零)
var last_count: int = 0     # 连击结束时留存给 HUD 的最后数字(纯显示数据, 不参与判定)
var defender: Fighter = null

var _recording := false     # 记录进行中(对方仍在受击硬直范围内)
var _showing := false       # 记录已结束, 最后数字正在滞留显示
var _show_timer := 0.0      # 纯显示倒计时(与记录判定无关)


# 登记一次有效命中, 返回本次命中后应显示的连击数
func register_hit(target: Fighter) -> int:
	# 判定只看"记录是否仍在进行 + 是否同一个受击方", 完全不看显示计时
	if _recording and is_instance_valid(defender) and defender == target:
		count += 1
	else:
		# 记录已结束(含数字滞留显示期间)或首次命中: 开启新连击
		count = 1
	defender = target
	_recording = true
	last_count = count
	# 新命中立即刷新显示, 旧的滞留数字与计时一并作废
	_showing = false
	_show_timer = 0.0
	return count


# 每帧驱动(暂停/回合结束时调用方应跳过)
#   返回 true = 1 秒显示滞留结束, 调用方隐藏计数器标签
func update(delta: float) -> bool:
	if _recording:
		# 仍在受击硬直范围内: 记录继续有效
		if is_instance_valid(defender) \
				and defender.current_state in FighterState.RESTRICTED_STATES:
			return false
		# 恢复自由活动: 连击结束, 记录立即重置; 最后数字只作显示滞留
		_recording = false
		last_count = count
		count = 0
		_showing = true
		_show_timer = 0.0
		return false
	if _showing:
		# 纯显示计时: 满 1 秒隐藏标签。期间发生的命中不读这里, 一律开新连击
		_show_timer += delta
		if _show_timer >= GlobalConfig.COMBO_LINGER_SECONDS:
			_showing = false
			last_count = 0
			return true
	return false


func reset() -> void:
	count = 0
	last_count = 0
	defender = null
	_recording = false
	_showing = false
	_show_timer = 0.0
