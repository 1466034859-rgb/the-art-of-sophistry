class_name SpiritBar
extends Control
## 心气条：分段像素块，心气变化时用 Tween 平滑过渡。

const SEGMENT_HEIGHT := 20.0
const SEGMENT_GAP := 6.0

var max_value: int = 5
var value: int = 5
var display_value: float = 5.0
var accent: Color = Color("#c46f6f")


func _ready() -> void:
	custom_minimum_size = Vector2(260, SEGMENT_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(maximum: int, accent_color: Color) -> void:
	max_value = maxi(1, maximum)
	value = max_value
	display_value = float(max_value)
	accent = accent_color
	queue_redraw()


func set_value(new_value: int, animate: bool = true) -> void:
	var target := clampi(new_value, 0, max_value)
	if target == value and is_equal_approx(display_value, float(target)):
		return
	value = target
	if animate and is_inside_tree():
		var tween := create_tween()
		tween.tween_method(_on_display_step, display_value, float(target), 0.4).set_trans(Tween.TRANS_SINE)
	else:
		display_value = float(target)
		queue_redraw()


func flash(color: Color) -> void:
	if not is_inside_tree():
		return
	modulate = color
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, 0.35)


func _on_display_step(v: float) -> void:
	display_value = v
	queue_redraw()


func _draw() -> void:
	var total_width := size.x
	var segment_width := (total_width - SEGMENT_GAP * float(max_value - 1)) / float(max_value)
	for i in range(max_value):
		var rect := Rect2(
			Vector2(float(i) * (segment_width + SEGMENT_GAP), 0.0),
			Vector2(segment_width, SEGMENT_HEIGHT)
		)
		draw_rect(rect, Color("#121418"), true)
		var partial := clampf(display_value - float(i), 0.0, 1.0)
		if partial > 0.0:
			var fill := Rect2(rect.position, Vector2(rect.size.x * partial, rect.size.y))
			draw_rect(fill, accent, true)
			var highlight := Rect2(fill.position, Vector2(fill.size.x, 3.0))
			draw_rect(highlight, Color(1, 1, 1, 0.16), true)
		draw_rect(rect, Color("#2f343b"), false, 2.0)
