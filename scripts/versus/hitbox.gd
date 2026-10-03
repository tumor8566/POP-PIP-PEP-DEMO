# Hitbox.gd - 攻击判定框
# 挂在攻击动画的关键帧上，检测是否命中对方Hurtbox或其他飞行道具。
# 每次"段"激活时由 Fighter 调用 activate(segment) 配置本帧的几何与属性。
class_name Hitbox
extends Area2D

var owner_fighter: Node2D = null
var attack_data: AttackData = null          # 父级 AttackData(整段攻击)
var current_segment: AttackData.Segment = null  # 当前激活的子段(决定防御/攻击属性与几何)
var hit_targets := []   # 本次激活窗口内已命中的目标(防止单次攻击多次判定同一目标)


func _ready() -> void:
	# 攻击框: 层4, 默认侦测层2(受击框)
	collision_layer = 4
	collision_mask = 2
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
	current_segment = seg
	_apply_segment(seg)
	monitoring = true


func deactivate() -> void:
	monitoring = false
	current_segment = null
	hit_targets.clear()


# 按当前段的属性配置判定框位置/大小与碰撞掩码
func _apply_segment(seg: AttackData.Segment) -> void:
	# 飞行道具段: 让命中框也能侦测其它飞行道具(用于互相抵消)
	if seg.has_attribute(AttackData.AttackAttribute.PROJECTILE):
		collision_mask |= 4

	var shape_node := get_node_or_null("HitboxCollision")
	if not shape_node or not shape_node.shape is RectangleShape2D:
		return

	var dir := 1 if (owner_fighter and owner_fighter.facing_right) else -1
	shape_node.position = Vector2(seg.hitbox_offset.x * dir, seg.hitbox_offset.y)
	shape_node.shape.extents = seg.hitbox_size / 2.0


func _on_area_entered(area: Area2D) -> void:
	if not owner_fighter or not current_segment:
		return

	# 飞行道具互撞 / 被其它攻击属性抵消
	if area is Hitbox:
		_on_projectile_collision(area as Hitbox)
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
func _on_projectile_collision(other: Hitbox) -> void:
	if not other.current_segment or other.owner_fighter == owner_fighter:
		return

	var self_proj := current_segment.has_attribute(AttackData.AttackAttribute.PROJECTILE)
	var other_proj := other.current_segment.has_attribute(AttackData.AttackAttribute.PROJECTILE)

	# 飞行道具 vs 飞行道具: 互相抵消
	if self_proj and other_proj:
		deactivate()
		other.deactivate()
		return

	# 飞行道具被其它攻击命中: 抵消飞行道具
	if self_proj:
		deactivate()
	elif other_proj:
		other.deactivate()


func get_owner_fighter() -> Node2D:
	return owner_fighter
