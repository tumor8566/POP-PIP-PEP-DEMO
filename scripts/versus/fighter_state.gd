# FighterState.gd - 角色状态机
# 管理角色的所有状态(待机、行走、攻击、受击等)
class_name FighterState
extends Node

enum State {
	IDLE,           # 待机
	WALK_FORWARD,   # 前进
	WALK_BACK,      # 后退
	DASH_FORWARD,   # 前冲
	DASH_BACK,      # 后撤
	CROUCH,         # 下蹲
	CROUCH_BLOCK,   # 蹲防
	STAND_BLOCK,    # 站防
	JUMP_UP,        # 垂直跳
	JUMP_FORWARD,   # 前跳
	JUMP_BACK,      # 后跳
	ATTACK_LIGHT,   # 轻攻击(通常技)
	ATTACK_MEDIUM,  # 中攻击(通常技)
	ATTACK_HEAVY,   # 重攻击(通常技)
	ATTACK_SPECIAL, # 必杀技(气拳)
	GRAB,           # 抓取(D 键)
	ESCAPE,         # 脱离(防御硬直中 方向+F 强制挣脱)
	HIT_STUN,       # 受击硬直
	GRABBED,        # 被抓取(可拆投)
	KNOCKDOWN,      # 倒地
	SOFT_KNOCKDOWN, # 软倒地(被追地命中, 短时间后自行起身)
	WAKEUP,         # 起身
	CRASHED,        # 相杀(双方攻击判定相撞后的短暂硬直)
	VICTORY,        # 胜利
	DEFEATED,       # 败北
	INTRO,          # 入场
}

# 状态是否允许移动
const MOBILE_STATES := [
	State.IDLE, State.WALK_FORWARD, State.WALK_BACK,
]

# 状态是否在地面
const GROUND_STATES := [
	State.IDLE, State.WALK_FORWARD, State.WALK_BACK,
	State.DASH_FORWARD, State.DASH_BACK, State.CROUCH,
	State.CROUCH_BLOCK, State.STAND_BLOCK,
	State.ATTACK_LIGHT, State.ATTACK_MEDIUM, State.ATTACK_HEAVY,
	State.ATTACK_SPECIAL,
	State.GRAB, State.ESCAPE, State.HIT_STUN, State.GRABBED, State.WAKEUP,
	State.SOFT_KNOCKDOWN, State.CRASHED,
]

# 属于"倒地类"的状态(可被追地攻击命中)
const DOWN_STATES := [
	State.KNOCKDOWN, State.SOFT_KNOCKDOWN, State.WAKEUP,
]

# 状态是否可取消(用于连招系统)
# 取消链: 通常技(轻/中/重) -> 必杀技(气拳, 链尾)
const CANCELLABLE_STATES := [
	State.ATTACK_LIGHT, State.ATTACK_MEDIUM, State.ATTACK_HEAVY, State.ATTACK_SPECIAL,
]
