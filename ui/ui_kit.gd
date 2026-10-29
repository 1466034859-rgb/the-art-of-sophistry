class_name UiKit
extends RefCounted
## 像素风 UI 工具箱：调色板、主题、常用控件工厂。
##
## 美术走「低饱和 + 直角 + 2px 描边」的像素感方案，不依赖任何外部图片资源。
## 中文字体通过 SystemFont 从系统字体里取，避免打包大字体文件。

const COL_BG := Color("#14161a")
const COL_PANEL := Color("#1e2228")
const COL_PANEL_LIGHT := Color("#262b33")
const COL_PANEL_DARK := Color("#171a1f")
const COL_BORDER := Color("#3a3f47")
const COL_BORDER_DIM := Color("#2a2e35")
const COL_INK := Color("#d8d3c8")
const COL_INK_DIM := Color("#8b877d")
const COL_ACCENT := Color("#c4b47f")
const COL_DANGER := Color("#c46f6f")
const COL_GOOD := Color("#9fb8a0")
const COL_BLUE := Color("#7fa7c4")


static func system_font() -> SystemFont:
	var font := SystemFont.new()
	font.font_names = PackedStringArray([
		"Microsoft YaHei UI",
		"Microsoft YaHei",
		"Noto Sans CJK SC",
		"Source Han Sans SC",
		"SimHei",
		"sans-serif",
	])
	font.font_weight = 500
	return font


static func build_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = system_font()
	theme.default_font_size = 16

	# 通用面板
	theme.set_stylebox("panel", "PanelContainer", box(COL_PANEL, COL_BORDER, 2))
	theme.set_stylebox("panel", "Panel", box(COL_PANEL, COL_BORDER, 2))
	theme.set_color("font_color", "Label", COL_INK)
	theme.set_color("default_color", "RichTextLabel", COL_INK)

	# 按钮：正常 / 悬停 / 按下 / 禁用
	theme.set_stylebox("normal", "Button", box(COL_PANEL_LIGHT, COL_BORDER, 2))
	theme.set_stylebox("hover", "Button", box(Color("#2f353d"), COL_ACCENT, 2))
	theme.set_stylebox("pressed", "Button", box(Color("#3a3f47"), COL_ACCENT, 2))
	theme.set_stylebox("disabled", "Button", box(COL_PANEL_DARK, COL_BORDER_DIM, 2))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_color("font_color", "Button", COL_INK)
	theme.set_color("font_hover_color", "Button", Color("#fff6dc"))
	theme.set_color("font_pressed_color", "Button", COL_ACCENT)
	theme.set_color("font_disabled_color", "Button", Color("#565b62"))

	# 进度条
	theme.set_stylebox("background", "ProgressBar", box(COL_PANEL_DARK, COL_BORDER_DIM, 1))
	theme.set_stylebox("fill", "ProgressBar", box(COL_ACCENT, COL_ACCENT, 0))

	# 滚动条等杂项保持暗色
	theme.set_color("font_color", "CheckBox", COL_INK)
	return theme


static func box(bg: Color, border: Color = COL_BORDER, border_width: int = 2) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(0)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


static func label(text: String, size: int = 16, color: Color = COL_INK) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	return node


static func title(text: String, size: int = 48, color: Color = COL_ACCENT) -> Label:
	var node := label(text, size, color)
	node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# 像素感标题：硬描边 + 右下投影，模拟 2px 像素轮廓
	node.add_theme_constant_override("outline_size", maxi(4, size / 8))
	node.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	node.add_theme_constant_override("shadow_offset_x", 3)
	node.add_theme_constant_override("shadow_offset_y", 3)
	node.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	return node


static func wrapped(text: String, size: int = 14, color: Color = COL_INK_DIM) -> Label:
	var node := label(text, size, color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.custom_minimum_size = Vector2(0, 0)
	return node


static func button(text: String, size: int = 16, min_height: float = 46.0) -> Button:
	var node := Button.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.custom_minimum_size = Vector2(0, min_height)
	return node


static func rich(text: String = "", size: int = 16, color: Color = COL_INK) -> RichTextLabel:
	var node := RichTextLabel.new()
	node.bbcode_enabled = true
	node.fit_content = true
	node.scroll_active = false
	node.add_theme_font_size_override("normal_font_size", size)
	node.add_theme_font_size_override("bold_font_size", size)
	node.add_theme_color_override("default_color", color)
	node.text = text
	return node


static func panel(accent: Color = COL_BORDER, bg: Color = COL_PANEL) -> PanelContainer:
	var node := PanelContainer.new()
	node.add_theme_stylebox_override("panel", box(bg, accent, 2))
	return node


static func spacer(height: float) -> Control:
	var node := Control.new()
	node.custom_minimum_size = Vector2(0, height)
	return node


static func grow_spacer() -> Control:
	var node := Control.new()
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return node


static func tag_chip(text: String, color: Color) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", box(Color(color.r * 0.18, color.g * 0.18, color.b * 0.18, 0.9), color, 1))
	var inner := label(text, 13, color)
	inner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.add_child(inner)
	return chip


## 把一组子节点塞进垂直容器。
static func vbox(children: Array, separation: int = 8, expand: bool = false) -> VBoxContainer:
	var box_node := VBoxContainer.new()
	box_node.add_theme_constant_override("separation", separation)
	if expand:
		box_node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for child in children:
		if child != null:
			box_node.add_child(child)
	return box_node


static func hbox(children: Array, separation: int = 8) -> HBoxContainer:
	var box_node := HBoxContainer.new()
	box_node.add_theme_constant_override("separation", separation)
	for child in children:
		if child != null:
			box_node.add_child(child)
	return box_node
