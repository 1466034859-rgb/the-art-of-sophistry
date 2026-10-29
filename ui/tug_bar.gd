class_name TugBar
extends Control
## 观众倾向条：中间一分为二，左半边越长越倾向「你」，右半边越长越倾向「对方」。
## 数值 value = 倾向你的程度（0~100）；对手倾向 = 100 - value。

const BAR_HEIGHT := 12.0

var value: float = 50.0
var display_value: float = 50.0
var you_color: Color = Color("#9fb8a0")
var opponent_color: Color = Color("#c46f6f")


func _ready() -> void:
	custom_minimum_size = Vector2(0, BAR_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func setup(you_tint: Color, opponent_tint: Color) -> void:
	you_color = you_tint
	opponent_color = opponent_tint
	queue_redraw()


func set_value(new_value: float, animate: bool = true) -> void:
	value = clampf(new_value, 0.0, 100.0)
	if animate and is_inside_tree():
		var tween := create_tween()
		tween.tween_method(_step, display_value, value, 0.35).set_trans(Tween.TRANS_SINE)
	else:
		display_value = value
		queue_redraw()


func _step(v: float) -> void:
	display_value = v
	queue_redraw()


func _draw() -> void:
	var width := size.x
	var height := BAR_HEIGHT
	var center_x := width * 0.5
	var track := Rect2(Vector2.ZERO, Vector2(width, height))
	draw_rect(track, Color("#121418"), true)

	var left_width := center_x * display_value / 100.0
	var right_width := center_x * (100.0 - display_value) / 100.0
	if left_width > 0.5:
		draw_rect(Rect2(Vector2(center_x - left_width, 0.0), Vector2(left_width, height)), you_color, true)
		draw_rect(Rect2(Vector2(center_x - left_width, 0.0), Vector2(left_width, 3.0)), Color(1, 1, 1, 0.18), true)
	if right_width > 0.5:
		draw_rect(Rect2(Vector2(center_x, 0.0), Vector2(right_width, height)), opponent_color, true)
		draw_rect(Rect2(Vector2(center_x, 0.0), Vector2(right_width, 3.0)), Color(1, 1, 1, 0.12), true)
	# 中线
	draw_rect(Rect2(Vector2(center_x - 1.0, -1.0), Vector2(2.0, height + 2.0)), Color("#d8d3c8"), true)
	# 边框
	draw_rect(track, Color("#2f343b"), false, 2.0)
