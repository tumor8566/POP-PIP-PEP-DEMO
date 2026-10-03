# AttackData.gd - 攻击数据资源
# 一个攻击动作(AttackData)由若干"段"(Segment)组成。
# 每段拥有独立的防御属性(单选)、攻击属性(可叠加位标志)、几何与命中结算数据。
class_name AttackData
extends Resource

enum AttackType {
	LIGHT,      # 轻攻击
	MEDIUM,     # 中攻击
	HEAVY,      # 重攻击
	THROW,      # 投技
	SPECIAL,    # 必杀技
}

# 防御属性: 每段攻击在防御侧的表现(单选，仅能同时存在一个)
enum DefenseProperty {
	FULL_BLOCK,            # 全段防御 (高/上段) — 站防、蹲防皆可
	STANCE_BREAK,          # 站姿破坏 (下段)   — 仅蹲防可防，站防无效
	CROUCH_BREAK,          # 蹲姿破坏 (中段·越头) — 仅站防可防，蹲防无效
	UNBLOCKABLE,           # 不可防御          — 任何防御均无效
	THROW_BREAK_REQUIRED,  # 需要被拆投        — 不可防御，需在窗口内按下投技键化解
}

# 攻击属性: 每段攻击命中后的效果标签(位标志，可叠加)
enum AttackAttribute {
	HEAD = 1,        # 对头   — 打击/受创针对头部
	CHEST = 2,       # 对胸   — 打击/受创针对胸部
	STOMACH = 4,     # 对腹   — 打击/受创针对腹部
	ARM = 8,         # 对臂   — 打击/受创针对手臂
	FOOT = 16,       # 对足   — 打击/受创针对足部
	GRAB = 32,       # 抓取属性 — 命中后将对手置入"被抓取"受创状态
	PROJECTILE = 64, # 飞行道具属性 — 同级飞行道具相碰互相抵消，亦可被其他属性抵消
	PUPPET = 128,    # 傀儡属性 — 仅供携带傀儡单位的角色使用
	WEAPON = 256,    # 武器属性 — 仅供携带武器的角色使用
	QI = 512,        # 气攻属性 — 特殊攻击属性
}

# ===== 攻击动作级(整体)属性 =====
@export var attack_name: String = "未命名"
@export var attack_type: AttackType = AttackType.LIGHT
# 招式固有攻击等级 (LV1 ~ LV5): 由招式动作本身决定, 不再统一从 LV1 起算
#   轻攻击=LV1 / 中攻击=LV2 / 重攻击=LV3 / 必杀技(气拳)=LV4
#   F 推进技会在该基础等级上再 +1 (上限 LV5)
@export var attack_level: int = 1
@export var meter_gain: int = 80
@export var meter_cost: int = 0
@export var cancel_to_light: bool = false
@export var cancel_to_medium: bool = false
@export var cancel_to_heavy: bool = false
@export var cancel_to_special: bool = false

# 段列表(按顺序，每段对应一次独立的命中判定窗口)
var segments: Array = []  # Array[AttackData.Segment]


# 总帧数 = 全部段中 (trigger_frame + active_duration) 的最大值
func total_frames() -> int:
	var m := 0
	for seg in segments:
		if seg is Segment:
			var end_frame: int = seg.trigger_frame + seg.active_duration
			if end_frame > m:
				m = end_frame
	return m


# 获取当前帧对应的激活段(若多个重叠，取最先加入者)
func get_active_segment(frame: int):
	for seg in segments:
		if seg is Segment \
				and frame >= seg.trigger_frame \
				and frame < seg.trigger_frame + seg.active_duration:
			return seg
	return null


# ===== 段(Segment)：每段独立的几何 / 防御 / 攻击 / 命中数据 =====
class Segment extends RefCounted:
	var defense_property: int = AttackData.DefenseProperty.FULL_BLOCK
	var attack_attributes: int = AttackData.AttackAttribute.CHEST  # 位标志，可叠加

	var damage: int = 50
	var hit_stun: int = 15
	var block_stun: int = 10
	var chip_damage: int = 0
	var knockback_x: float = 200.0
	var knockback_y: float = 0.0
	var juggle: bool = false

	var hitbox_offset: Vector2 = Vector2(40, 0)
	var hitbox_size: Vector2 = Vector2(60, 40)

	var trigger_frame: int = 0
	var active_duration: int = 4


	func has_attribute(attr: int) -> bool:
		return (attack_attributes & attr) != 0
