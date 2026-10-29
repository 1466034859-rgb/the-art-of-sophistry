class_name CardWidget
extends PanelContainer
## 手牌控件：像素风卡片，可点击出牌 / 回应。

signal clicked(index: int)

const CARD_SIZE := Vector2(172, 168)

var card: LogicCard = null
var hand_index: int = 0
var playable: bool = true

var _built: bool = false
var _accent: Color = Color.WHITE
var _type_label: Label
var _cost_label: Label
var _name_label: Label
var _tag_panel: PanelContainer
var _tag_label: Label
var _damage_label: Label
var _dialogue_label: Label


func setup(new_card: LogicCard, index: int, can_play: bool) -> void:
	card = new_card
	hand_index = index
	playable = can_play
	if not _built:
		_build()
	_refresh()


func _build() -> void:
	_built = true
	custom_minimum_size = CARD_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	resized.connect(_on_resized)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)
	_type_label = UiKit.label("构建", 12, UiKit.COL_INK_DIM)
	header.add_child(_type_label)
	header.add_child(UiKit.grow_spacer())
	_cost_label = UiKit.label("1AP", 12, UiKit.COL_INK_DIM)
	header.add_child(_cost_label)

	_name_label = UiKit.label("卡名", 19, UiKit.COL_INK)
	_name_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	column.add_child(_name_label)

	var chip_row := HBoxContainer.new()
	column.add_child(chip_row)
	_tag_panel = PanelContainer.new()
	_tag_panel.add_theme_stylebox_override("panel", UiKit.box(Color("#22262c"), UiKit.COL_BORDER, 1))
	chip_row.add_child(_tag_panel)
	_tag_label = UiKit.label("价值", 13, UiKit.COL_ACCENT)
	_tag_panel.add_child(_tag_label)
	chip_row.add_child(UiKit.grow_spacer())

	_damage_label = UiKit.label("", 12, UiKit.COL_DANGER)
	column.add_child(_damage_label)

	_dialogue_label = UiKit.label("", 12, UiKit.COL_INK_DIM)
	_dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialogue_label.custom_minimum_size = Vector2(0, 32)
	_dialogue_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dialogue_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	column.add_child(_dialogue_label)


func _refresh() -> void:
	if card == null:
		return
	_accent = card.tag_color()
	var border := _accent if playable else UiKit.COL_BORDER_DIM
	var background := UiKit.COL_PANEL_LIGHT if playable else UiKit.COL_PANEL_DARK
	add_theme_stylebox_override("panel", UiKit.box(background, border, 2))

	_type_label.text = card.type_label()
	_type_label.add_theme_color_override("font_color", _accent)
	_cost_label.text = "%d AP" % card.cost
	_name_label.text = card.card_name
	_name_label.add_theme_color_override("font_color", UiKit.COL_INK if playable else UiKit.COL_INK_DIM)
	_tag_label.text = card.tag_label()
	_tag_label.add_theme_color_override("font_color", _accent)
	_tag_panel.add_theme_stylebox_override(
		"panel",
		UiKit.box(Color(_accent.r * 0.16, _accent.g * 0.16, _accent.b * 0.16, 0.95), _accent, 1)
	)

	var bits: Array[String] = []
	if card.base_damage > 0:
		bits.append("伤害 %d" % card.base_damage)
	if card.silence_penalty > 0:
		bits.append("沉默 +%d" % card.silence_penalty)
	if card.self_damage > 0:
		bits.append("自损 %d" % card.self_damage)
	_damage_label.text = " · ".join(bits)
	_dialogue_label.text = "「%s」" % card.dialogue

	modulate = Color.WHITE if playable else Color(1, 1, 1, 0.55)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if playable else Control.CURSOR_ARROW
	tooltip_text = card.tooltip_text()


func _on_resized() -> void:
	pivot_offset = size * 0.5


func _on_mouse_entered() -> void:
	if not playable:
		return
	z_index = 10
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2(1.05, 1.05), 0.12)


func _on_mouse_exited() -> void:
	z_index = 0
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2.ONE, 0.12)


func _gui_input(event: InputEvent) -> void:
	if not playable or card == null:
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			clicked.emit(hand_index)
			accept_event()
