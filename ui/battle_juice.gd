class_name BattleJuice
extends RefCounted
## 视觉反馈小工具：打字机对白、屏幕震动、浮动伤害数字。


static func typewriter(label: RichTextLabel, text: String, chars_per_second: float = 40.0) -> Tween:
	if label == null:
		return null
	label.text = text
	label.visible_ratio = 0.0
	var duration := maxf(0.12, float(text.length()) / maxf(1.0, chars_per_second))
	var tween := label.create_tween()
	tween.tween_property(label, "visible_ratio", 1.0, duration)
	return tween


static func shake(node: Control, intensity: float = 8.0, duration: float = 0.3) -> void:
	if node == null or not node.is_inside_tree():
		return
	var origin := node.position
	var steps := 6
	var tween := node.create_tween()
	for i in range(steps):
		var offset := Vector2(
			randf_range(-intensity, intensity),
			randf_range(-intensity * 0.6, intensity * 0.6)
		)
		tween.tween_property(node, "position", origin + offset, duration / float(steps))
	tween.tween_property(node, "position", origin, duration / float(steps))


static func float_text(parent: Control, text: String, at: Vector2, color: Color, size: int = 22) -> void:
	if parent == null:
		return
	var node := UiKit.label(text, size, color)
	node.z_index = 30
	node.position = at
	parent.add_child(node)
	var tween := node.create_tween()
	tween.set_parallel(true)
	tween.tween_property(node, "position:y", at.y - 52.0, 0.8).set_trans(Tween.TRANS_SINE)
	tween.tween_property(node, "modulate:a", 0.0, 0.8)
	tween.chain().tween_callback(node.queue_free)


static func fade_in(node: CanvasItem, duration: float = 0.25) -> void:
	if node == null:
		return
	node.modulate.a = 0.0
	var tween := node.create_tween()
	tween.tween_property(node, "modulate:a", 1.0, duration)


static func banner(label: Label, text: String, color: Color) -> void:
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.modulate.a = 1.0
	var tween := label.create_tween()
	tween.tween_interval(0.9)
	tween.tween_property(label, "modulate:a", 0.35, 0.4)
