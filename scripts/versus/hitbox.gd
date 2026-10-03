# Hitbox.gd - 攻击判定框
# 挂在攻击动画的关键帧上，检测是否命中对方Hurtbox或其他Hitbox。
# 每次"段"激活时由 Fighter 调用 activate(segment) 配置本帧的几何与属性。
class_name Hitbox
extends Area2D

var owner_fighter: Node2D = null
var attack_data: AttackData = null          # 父级 AttackData(整段攻击)
var current_segment: AttackData.Segment = null  # 当前激活的子段(决定防御/攻击属性与几何)
var hit_targets := []   # 本次激活窗口内已命中的目标(防止单次攻击多次判定同一目标)
var crashed_with := []  # 本次激活窗口内已发生过相杀的对象(防止双方重复触发; deactivate 不清空,用于相杀后追溯)
var _crash_locked := false  # 本次激活窗口是否已发生过相杀(deactivate 会清空)

# 本次命中结算的判定区结果(由 evaluate_spot 计算, 供 Fighter._on_hit 读取)
enum Spot { NONE, SWEET, SOUR }
var last_spot: int = Spot.NONE


func _ready() -> void:
	# 攻击框: 层4, 侦测层2(受击框) + 层4(其它攻击框, 用于飞行道具抵消与相杀)
	collision_layer = 4
	collision_mask = 2 | 4
	area_entered.connect(_on_area_entered)


func setup(fighter: Node2D, data: AttackData) -> void:
	owner_fighter = fighter
	attack_data = data


# 激活指定段: 清除命中记录、配置几何与掩码
func activate(seg: AttackData.Segment) -> void:
	if not seg:
		deactivate()
		return
	hit_targets.clear()
	crashed_with.clear()
	_crash_locked = false
	current_segment = seg
	last_spot = Spot.NONE
	_apply_segment(seg)
	monitoring = true


# 主动检测一次当前重叠的判定框, 补上可能缺失的相杀/命中判定
#   原因: Area2D 的 area_entered / get_overlapping_areas 依赖物理帧同步,
#   判定框激活当帧双方重叠时可能检测不到, 导致"相杀"被漏掉。
#   攻击判定相撞必须在重叠当帧生效, 故这里用矩形直接判定。
func _probe_overlaps() -> void:
	if not monitoring or not current_segment:
		return
	var my_rect := _world_rect()
	if my_rect.size.x <= 0.0 or my_rect.size.y <= 0.0:
		return

	# 相杀: 与对方攻击判定框的矩形重叠检测
	var tree := get_tree()
	if not tree:
		return
	for node in tree.get_nodes_in_group("fighters"):
		var other_f := node as Fighter
		if not other_f or other_f == owner_fighter:
			continue
		var other_hb := other_f.hitbox as Hitbox
		if not other_hb or not other_hb.monitoring or not other_hb.current_segment:
			continue
		if other_hb in crashed_with:
			continue
		if not my_rect.intersects(other_hb._world_rect()):
			continue
		if _on_projectile_collision(other_hb):
			continue
		_try_crash(other_hb)


func deactivate() -> void:
	monitoring = false
	current_segment = null
	hit_targets.clear()
	last_spot = Spot.NONE


# 按当前段的属性配置判定框位置/大小与碰撞掩码
func _apply_segment(seg: AttackData.Segment) -> void:
	var shape_node := get_node_or_null("HitboxCollision")
	if not shape_node or not shape_node.shape is RectangleShape2D:
		return

	var dir := 1 if (owner_fighter and owner_fighter.facing_right) else -1
	shape_node.position = Vector2(seg.hitbox_offset.x * dir, seg.hitbox_offset.y)
	shape_node.shape.extents = seg.hitbox_size / 2.0


# 本攻击框当前的世界矩形(用于把命中点换算成 0~1 归一化坐标)
func _world_rect() -> Rect2:
	var cs := get_node_or_null("HitboxCollision") as CollisionShape2D
	if not cs or not cs.shape is RectangleShape2D:
		return Rect2(global_position, Vector2.ZERO)
	var ext: Vector2 = (cs.shape as RectangleShape2D).extents
	return Rect2(cs.global_position - ext, ext * 2.0)


func _hurtbox_world_rect(hurtbox: Hurtbox) -> Rect2:
	var cs := hurtbox.get_node_or_null("HurtboxCollision") as CollisionShape2D
	if not cs or not cs.shape is RectangleShape2D:
		return Rect2(hurtbox.global_position, Vector2.ZERO)
	var ext: Vector2 = (cs.shape as RectangleShape2D).extents
	return Rect2(cs.global_position - ext, ext * 2.0)


# 依据命中点落在判定框内哪个甜点/酸点区域, 计算本次命中的判定区结果
func evaluate_spot(hurtbox: Hurtbox) -> int:
	last_spot = Spot.NONE
	if not current_segment or not hurtbox:
		return last_spot

	var hb := _world_rect()
	if hb.size.x <= 0.0 or hb.size.y <= 0.0:
		return last_spot

	# 取两个矩形的重叠区中心作为命中点(比用受击框中心更贴近真实接触位置)
	var overlap := hb.intersection(_hurtbox_world_rect(hurtbox))
	var point: Vector2 = overlap.get_center() if overlap.size.length() > 0.0 \
			else _hurtbox_world_rect(hurtbox).get_center()
	var rel := (point - hb.position) / hb.size

	if current_segment.is_sweet_point(rel):
		last_spot = Spot.SWEET
	elif current_segment.is_sour_point(rel):
		last_spot = Spot.SOUR
	return last_spot


func _on_area_entered(area: Area2D) -> void:
	if not owner_fighter or not current_segment:
		return

	# 攻击框 vs 攻击框: 飞行道具互撞/相杀
	if area is Hitbox:
		var other := area as Hitbox
		if _on_projectile_collision(other):
			return
		_try_crash(other)
		return

	# 普通命中: 仅处理受击框(Hurtbox)
	if not (area is Hurtbox):
		return
	var hurtbox := area as Hurtbox

	# 防止自伤
	if hurtbox.owner_fighter == owner_fighter:
		return

	# 防止单次攻击多次判定同一目标
	if hurtbox.owner_fighter in hit_targets:
		return

	hit_targets.append(hurtbox.owner_fighter)


# 飞行道具碰撞: 同级飞行道具相碰互相抵消；其它攻击属性也可抵消飞行道具
#   返回 true 表示本次碰撞已按"飞行道具抵消"处理完毕
func _on_projectile_collision(other: Hitbox) -> bool:
	if not other.current_segment or other.owner_fighter == owner_fighter:
		return false

	var self_proj := current_segment.has_attribute(AttackData.AttackAttribute.PROJECTILE)
	var other_proj := other.current_segment.has_attribute(AttackData.AttackAttribute.PROJECTILE)

	# 飞行道具 vs 飞行道具: 互相抵消
	if self_proj and other_proj:
		deactivate()
		other.deactivate()
		return true

	# 飞行道具被其它攻击命中: 抵消飞行道具
	if self_proj:
		deactivate()
		return true
	if other_proj:
		other.deactivate()
		return true
	return false


# 相杀 (CRASH): 双方攻击判定重叠时(且双方均未受击), 双方产生停帧并按攻击等级互相推开
func _try_crash(other: Hitbox) -> void:
	# 双方必须都是有效攻击中的角色, 且都不是飞行道具(飞行道具走抵消逻辑)
	if other in crashed_with:
		return
	if current_segment.has_attribute(AttackData.AttackAttribute.PROJECTILE):
		return
	if other.current_segment.has_attribute(AttackData.AttackAttribute.PROJECTILE):
		return
	if not is_instance_valid(other.owner_fighter) or other.owner_fighter == owner_fighter:
		return
	if not owner_fighter.can_crash() or not other.owner_fighter.can_crash():
		return

	crashed_with.append(other)
	other.crashed_with.append(self)

	# 记录先触发的一方为"碰撞主导", 避免双方重复结算
	if get_instance_id() < other.get_instance_id():
		owner_fighter.resolve_crash(other.owner_fighter)
		other.owner_fighter.resolve_crash(owner_fighter)


func get_owner_fighter() -> Node2D:
	return owner_fighter
