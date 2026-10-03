# Hurtbox.gd - 受击判定框
# 挂在角色身体上，被对方的Hitbox检测碰撞
class_name Hurtbox
extends Area2D

var owner_fighter: Node2D = null


func _ready() -> void:
	# 受击框: 层2, 侦测层4(攻击框)
	collision_layer = 2
	collision_mask = 4
	# 连接信号
	area_entered.connect(_on_area_entered)


func setup(fighter: Node2D) -> void:
	owner_fighter = fighter


func _on_area_entered(hitbox: Area2D) -> void:
	if not owner_fighter:
		return
	if hitbox.has_method("get_owner_fighter") and hitbox.get_owner_fighter() == owner_fighter:
		return
	if owner_fighter.has_method("_on_hit"):
		# 传入受击框自身: 攻击方据此换算命中点(甜点/酸点)并判断追地是否成立
		owner_fighter._on_hit(hitbox, self)
