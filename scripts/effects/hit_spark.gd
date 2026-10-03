# HitSpark.gd - 程序化打击火花特效
# 命中瞬间在命中点生成一个放射状扩张火花, 自身缩放放大并淡出后自动释放。
extends Node2D
class_name HitSpark

var _color := Color.WHITE
var _scale := 1.0
var _lifetime := 0.22
var _t := 0.0


# 由调用方在 instantiate 之后传入颜色与缩放
func setup(color: Color, scl: float) -> void:
	_color = color
	_scale = scl


func _ready() -> void:
	z_index = 50
	top_level = true          # 不受父节点 transform 影响, 直接以世界坐标绘制
	var tween := create_tween()
	tween.tween_method(_advance, 0.0, 1.0, _lifetime)
	tween.finished.connect(queue_free)


func _advance(p: float) -> void:
	_t = p
	queue_redraw()


func _draw() -> void:
	var a := 1.0 - _t
	if a <= 0.0:
		return
	var base_r := 26.0 * _scale
	var cr := Color(_color.r, _color.g, _color.b, a)

	# 核心圆(命中瞬间最亮, 快速收缩)
	draw_circle(Vector2.ZERO, base_r * (1.0 - 0.6 * _t), cr)

	# 放射状火花线(随生命周期向外伸展)
	var spikes := 7
	for i in range(spikes):
		var ang := float(i) / float(spikes) * TAU + _t * 0.6
		var inner := base_r * 0.4
		var outer := base_r * (1.4 + 0.8 * _t)
		var p1 := Vector2(cos(ang), sin(ang)) * inner
		var p2 := Vector2(cos(ang), sin(ang)) * outer
		draw_line(p1, p2, cr, 4.0 * _scale, true)

	# 外环(扩张淡出, 强化冲击范围)
	draw_arc(Vector2.ZERO, base_r * (1.0 + 1.2 * _t), 0.0, TAU, 24,
		Color(_color.r, _color.g, _color.b, a * 0.6), 3.0 * _scale, true)
