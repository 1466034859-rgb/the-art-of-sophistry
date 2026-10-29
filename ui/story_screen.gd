class_name StoryScreen
extends Control
## 故事模式界面：场景卡 → 序幕对白 → 分歧选择 → 找漏洞 → 反驳 → 观众跑票 → 结辩 → 评委投票 → 尾声 → 复盘。
##
## 完全由 StoryEngine 的 view_changed 信号驱动；任何可点击选项都绑定到引擎，
## 点下去一定会推进流程（不会出现“点了没反应”）。

signal exit_requested()
signal restart_requested()

var story_id: String = ""
var engine: StoryEngine = null

var _title_label: Label
var _subtitle_label: Label
var _content: VBoxContainer
var _hint_label: Label
var _audience_bars: Dictionary = {}
var _audience_delta_labels: Dictionary = {}
var _total_bar: TugBar
var _total_label: Label
var _judge_labels: Array[Label] = []
var _judge_rows: Array[HBoxContainer] = []
var _busy: bool = false
var _current_view: Dictionary = {}
var _choice_buttons: Array[Button] = []
var _choice_options: Array = []
var _choice_statements: Array = []
var _choice_kind: String = ""
var _show_structure: bool = false
var _judge_result_label: Label
var _typing_label: RichTextLabel
var _typing_tween: Tween
var _transcript: Array[String] = []
var _transcript_panel: PanelContainer
var _transcript_label: RichTextLabel
var _paused: bool = false
var _pause_overlay: ColorRect


func setup(new_story_id: String) -> void:
	story_id = new_story_id


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiKit.build_theme()
	_build_layout()
	engine = StoryEngine.new()
	engine.view_changed.connect(_on_view_changed)
	engine.finished.connect(_on_finished)
	engine.setup(GameLibrary.shared().story_for_id(story_id))
	_refresh_audience()
	_refresh_judges(null)


# ---------------------------------------------------------------------------
# 布局
# ---------------------------------------------------------------------------

func _build_layout() -> void:
	var background := ColorRect.new()
	background.color = UiKit.COL_BG
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	# 顶栏
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	root.add_child(top)
	_title_label = UiKit.label("故事模式", 24, UiKit.COL_ACCENT)
	top.add_child(_title_label)
	_subtitle_label = UiKit.label("", 13, UiKit.COL_INK_DIM)
	top.add_child(_subtitle_label)
	top.add_child(UiKit.grow_spacer())
	var feedback_button := UiKit.button("反馈", 13, 32)
	feedback_button.custom_minimum_size = Vector2(80, 32)
	feedback_button.pressed.connect(_open_feedback)
	top.add_child(feedback_button)
	var sfx_button := UiKit.button("音效：开", 13, 32)
	sfx_button.custom_minimum_size = Vector2(100, 32)
	sfx_button.pressed.connect(func() -> void:
		var node := get_node_or_null("/root/Sfx")
		if node == null:
			return
		var on: bool = node.toggle()
		sfx_button.text = "音效：开" if on else "音效：关"
	)
	top.add_child(sfx_button)
	var transcript_button := UiKit.button("对白记录", 13, 32)
	transcript_button.custom_minimum_size = Vector2(110, 32)
	transcript_button.pressed.connect(_toggle_transcript)
	top.add_child(transcript_button)
	var exit_button := UiKit.button("离开", 13, 32)
	exit_button.custom_minimum_size = Vector2(90, 32)
	exit_button.pressed.connect(func() -> void: exit_requested.emit())
	top.add_child(exit_button)

	# 中部：内容 + 右侧观众/评委
	var middle := HBoxContainer.new()
	middle.add_theme_constant_override("separation", 14)
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(middle)

	var content_panel := UiKit.panel(UiKit.COL_BORDER, UiKit.COL_PANEL_DARK)
	content_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_child(content_panel)
	var content_margin := MarginContainer.new()
	content_margin.add_theme_constant_override("margin_left", 14)
	content_margin.add_theme_constant_override("margin_right", 14)
	content_margin.add_theme_constant_override("margin_top", 12)
	content_margin.add_theme_constant_override("margin_bottom", 12)
	content_panel.add_child(content_margin)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 10)
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_margin.add_child(_content)

	var side := UiKit.panel(UiKit.COL_BORDER_DIM, UiKit.COL_PANEL_DARK)
	side.custom_minimum_size = Vector2(250, 0)
	middle.add_child(side)
	var side_column := VBoxContainer.new()
	side_column.add_theme_constant_override("separation", 6)
	side.add_child(side_column)
	side_column.add_child(UiKit.label("观众倾向", 14, UiKit.COL_INK_DIM))
	# 总倾向：中分双半，左倾你 / 右倾对方
	var total_row := HBoxContainer.new()
	side_column.add_child(total_row)
	total_row.add_child(UiKit.label("总倾向", 12, UiKit.COL_INK_DIM))
	total_row.add_child(UiKit.grow_spacer())
	_total_label = UiKit.label("50 : 50", 12, UiKit.COL_INK_DIM)
	total_row.add_child(_total_label)
	_total_bar = TugBar.new()
	_total_bar.setup(UiKit.COL_GOOD, UiKit.COL_DANGER)
	side_column.add_child(_total_bar)
	side_column.add_child(UiKit.spacer(6))
	for key in ["support", "neutral", "oppose"]:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		side_column.add_child(row)
		var label_row := HBoxContainer.new()
		row.add_child(label_row)
		var name_label := UiKit.label(key, 12, UiKit.COL_INK_DIM)
		label_row.add_child(name_label)
		label_row.add_child(UiKit.grow_spacer())
		var delta_label := UiKit.label("50 : 50", 12, UiKit.COL_INK_DIM)
		label_row.add_child(delta_label)
		var bar := TugBar.new()
		bar.setup(UiKit.COL_GOOD, UiKit.COL_DANGER)
		row.add_child(bar)
		_audience_bars[key] = bar
		_audience_delta_labels[key] = delta_label
		_audience_bars[key].set_meta("name_label", name_label)
	side_column.add_child(UiKit.spacer(10))
	side_column.add_child(UiKit.label("评委", 14, UiKit.COL_INK_DIM))
	for i in range(3):
		var row := HBoxContainer.new()
		side_column.add_child(row)
		var label := UiKit.label("？", 12, UiKit.COL_INK_DIM)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var vote := UiKit.label("", 12, UiKit.COL_INK_DIM)
		row.add_child(vote)
		_judge_labels.append(vote)
		_judge_rows.append(row)

	# 底部提示
	_hint_label = UiKit.wrapped("", 13, UiKit.COL_INK_DIM)
	root.add_child(_hint_label)

	# 对白记录浮层（随时可回看已经说过的话）
	_transcript_panel = UiKit.panel(UiKit.COL_ACCENT, Color("#1b1f25"))
	_transcript_panel.visible = false
	_transcript_panel.set_anchors_preset(Control.PRESET_CENTER)
	_transcript_panel.offset_left = -380
	_transcript_panel.offset_right = 380
	_transcript_panel.offset_top = -230
	_transcript_panel.offset_bottom = 250
	add_child(_transcript_panel)
	var transcript_column := VBoxContainer.new()
	transcript_column.add_theme_constant_override("separation", 8)
	_transcript_panel.add_child(transcript_column)
	transcript_column.add_child(UiKit.label("对白记录", 16, UiKit.COL_ACCENT))
	_transcript_label = UiKit.rich("", 13, UiKit.COL_INK)
	_transcript_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_transcript_label.scroll_active = true
	_transcript_label.scroll_following = true
	transcript_column.add_child(_transcript_label)
	var close_button := UiKit.button("关闭", 13, 34)
	close_button.custom_minimum_size = Vector2(120, 34)
	close_button.pressed.connect(func() -> void: _transcript_panel.visible = false)
	var close_row := HBoxContainer.new()
	close_row.alignment = BoxContainer.ALIGNMENT_CENTER
	close_row.add_child(close_button)
	transcript_column.add_child(close_row)

	# 暂停浮层（Esc）：全屏遮罩 + 继续 / 重开 / 离开
	_pause_overlay = ColorRect.new()
	_pause_overlay.color = Color(0.02, 0.02, 0.03, 0.7)
	_pause_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_overlay.visible = false
	add_child(_pause_overlay)
	var pause_center := CenterContainer.new()
	pause_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.add_child(pause_center)
	var pause_box := UiKit.panel(UiKit.COL_ACCENT, UiKit.COL_PANEL_DARK)
	pause_box.custom_minimum_size = Vector2(360, 0)
	pause_center.add_child(pause_box)
	var pause_column := VBoxContainer.new()
	pause_column.add_theme_constant_override("separation", 12)
	pause_box.add_child(pause_column)
	var pause_title := UiKit.title("已暂停", 30)
	pause_column.add_child(pause_title)
	var pause_hint := UiKit.label("Esc 继续 · 对白记录可随时回看", 12, UiKit.COL_INK_DIM)
	pause_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_column.add_child(pause_hint)
	var resume_button := UiKit.button("继续", 16, 42)
	resume_button.custom_minimum_size = Vector2(240, 42)
	resume_button.pressed.connect(_toggle_pause)
	pause_column.add_child(resume_button)
	var restart_button := UiKit.button("重新开始本场", 15, 40)
	restart_button.custom_minimum_size = Vector2(240, 40)
	restart_button.pressed.connect(func() -> void: restart_requested.emit())
	pause_column.add_child(restart_button)
	var leave_button := UiKit.button("离开到选场", 15, 40)
	leave_button.custom_minimum_size = Vector2(240, 40)
	leave_button.pressed.connect(func() -> void: exit_requested.emit())
	pause_column.add_child(leave_button)


func _clear_content() -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()


func _add_continue(text: String = "点击继续") -> void:
	var row := HBoxContainer.new()
	row.add_child(UiKit.grow_spacer())
	var button := UiKit.button(text, 16, 42)
	button.custom_minimum_size = Vector2(200, 42)
	button.pressed.connect(_on_continue_pressed)
	row.add_child(button)
	_content.add_child(row)


func _add_choice_options(options: Array, statements: Array = [], kind: String = "") -> void:
	# 必须拷贝：options / statements 是引擎里活的数据，UI 绝不能持有同一份引用去 clear，
	# 否则会把引擎当回合的陈词数组清空，导致「选错后再选一次」时选项为空（点不动）。
	_choice_options = options.duplicate(true)
	_choice_statements = statements.duplicate(true)
	_choice_kind = kind
	_choice_buttons.clear()
	for option in options:
		var option_dict: Dictionary = option
		var button := UiKit.button("", 15, 52)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size = Vector2(0, 52)
		button.tooltip_text = str(option_dict.get("text", ""))
		var option_id := str(option_dict.get("id", ""))
		button.pressed.connect(func() -> void: _on_option_pressed(option_id))
		_content.add_child(button)
		_choice_buttons.append(button)
	_refresh_choice_button_texts()


func _refresh_choice_button_texts() -> void:
	for i in range(_choice_buttons.size()):
		if i >= _choice_options.size():
			continue
		var option: Dictionary = _choice_options[i]
		var text := "%d. %s" % [i + 1, str(option.get("text", ""))]
		if _show_structure and _choice_kind == "sentence":
			var statement_index := int(option.get("id", i))
			if statement_index >= 0 and statement_index < _choice_statements.size():
				var statement: Dictionary = _choice_statements[statement_index]
				text += "   〔%s〕" % safe_structure(str(statement.get("structure", "")))
		_choice_buttons[i].text = text


func safe_structure(structure: String) -> String:
	if structure == "漏洞句":
		return "结论"
	if structure.begins_with("依据"):
		return "依据"
	return structure


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.keycode == KEY_ESCAPE:
		_toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if _paused or _busy:
		return
	var view_type := str(_current_view.get("type", ""))
	if key.keycode == KEY_SPACE or key.keycode == KEY_ENTER:
		if view_type != "choice" and view_type != "debrief":
			_on_continue_pressed()
			get_viewport().set_input_as_handled()
		return
	if key.keycode >= KEY_1 and key.keycode <= KEY_9:
		if view_type == "choice":
			var index := int(key.keycode - KEY_1)
			if index < _choice_options.size():
				_on_option_pressed(str((_choice_options[index] as Dictionary).get("id", "")))
				get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# 视图渲染
# ---------------------------------------------------------------------------

func _on_view_changed(view: Dictionary) -> void:
	_busy = false
	_clear_content()
	_current_view = view
	_choice_buttons.clear()
	_choice_options = []
	_choice_statements = []
	_choice_kind = ""
	var feedback := _feedback()
	if feedback != null and str(view.get("type", "")) in ["choice", "result", "audience", "judging", "debrief"]:
		feedback.log_event("view", {
			"story": story_id,
			"type": str(view.get("type", "")),
			"kind": str(view.get("kind", "")),
			"round": engine.round_index + 1 if engine != null else 0,
			"phase": engine.phase if engine != null else -1,
		})
	_refresh_audience()
	if str(view.get("type", "")) == "audience":
		_float_audience_deltas(view.get("bars", []))
	_title_label.text = str(engine.story.get("title", "故事模式"))
	_subtitle_label.text = str(engine.story.get("subtitle", ""))
	_hint_label.text = "空格 / 回车继续 · 数字键 1-9 选择"
	match str(view.get("type", "")):
		"scene_card":
			_render_scene_card(view)
		"dialogue":
			_render_dialogue(view)
		"choice":
			_render_choice(view)
		"result":
			_render_result(view)
		"topic":
			_render_topic(view)
		"audience":
			_render_audience(view)
		"judging":
			_render_judging(view)
		"debrief":
			_render_debrief(view)
		_:
			_add_continue()


func _render_scene_card(view: Dictionary) -> void:
	var card: Dictionary = view.get("card", {})
	_content.add_child(UiKit.label("【场景】" + str(view.get("title", "")), 22, UiKit.COL_ACCENT))
	_content.add_child(UiKit.wrapped("时间：" + str(card.get("time", "")), 15, UiKit.COL_INK))
	_content.add_child(UiKit.wrapped("地点：" + str(card.get("place", "")), 15, UiKit.COL_INK))
	_content.add_child(UiKit.wrapped("在场：" + str(card.get("present", "")), 15, UiKit.COL_INK_DIM))
	_content.add_child(UiKit.wrapped("为什么：" + str(card.get("reason", "")), 15, UiKit.COL_INK_DIM))
	_content.add_child(UiKit.wrapped("赌注：" + str(card.get("stake", "")), 15, UiKit.COL_DANGER))
	_add_continue("开始")


func _render_dialogue(view: Dictionary) -> void:
	var meta: Dictionary = view.get("meta", {})
	var speaker := str(view.get("speaker", ""))
	if speaker != "":
		_content.add_child(UiKit.label(speaker, 18, UiKit.COL_ACCENT))
	var rich := UiKit.rich("", 20, UiKit.COL_INK)
	rich.custom_minimum_size = Vector2(0, 120)
	_content.add_child(rich)
	_start_typewriter(rich, str(view.get("text", "")), 34.0)
	_transcript.append("%s：%s" % [speaker if speaker != "" else "旁白", str(view.get("text", ""))])
	while _transcript.size() > 80:
		_transcript.pop_front()
	var tag := ""
	if meta.has("round"):
		tag = "第 %d/%d 回合 · 第 %d/%d 句" % [
			int(meta.get("round", 1)), int(meta.get("round_total", 1)),
			int(meta.get("statement", 1)), int(meta.get("statement_total", 1)),
		]
		if str(meta.get("claim", "")) != "":
			tag += " · " + str(meta.get("claim", ""))
	_content.add_child(UiKit.label(tag, 12, UiKit.COL_INK_DIM))
	var structure := str(meta.get("structure", ""))
	if structure != "":
		_content.add_child(UiKit.label("结构：" + safe_structure(structure), 12, UiKit.COL_INK_DIM))
	_add_continue()


func _render_choice(view: Dictionary) -> void:
	var line := str(view.get("line", ""))
	if line != "":
		var rich := UiKit.rich("", 17, UiKit.COL_INK_DIM)
		rich.custom_minimum_size = Vector2(0, 60)
		_content.add_child(rich)
		BattleJuice.typewriter(rich, line, 40)
	var prompt := str(view.get("prompt", ""))
	_content.add_child(UiKit.label(prompt, 18, UiKit.COL_ACCENT))
	var hint := str(view.get("hint", ""))
	if hint != "":
		_content.add_child(UiKit.wrapped("提示：" + hint, 14, UiKit.COL_GOOD))
	var kind := str(view.get("kind", ""))
	var statements: Array = view.get("statements", [])
	if (view.get("options", []) as Array).is_empty():
		# 兜底：任何异常导致选项为空时，记录日志并给一个“跳过”出口，保证玩家卡不死。
		var feedback := _feedback()
		if feedback != null:
			feedback.log_error("empty choice options", {
				"story": story_id,
				"kind": kind,
				"phase": engine.phase if engine != null else -1,
			})
		_content.add_child(UiKit.label("这一页没有选项（已记录日志）。点下面继续，不会卡住。", 14, UiKit.COL_DANGER))
		var skip_button := UiKit.button("继续（跳过异常步骤）", 15, 42)
		skip_button.pressed.connect(func() -> void:
			if _busy:
				return
			_busy = true
			engine.force_continue()
		)
		_content.add_child(skip_button)
		_hint_label.text = "已记录错误日志：按 F3 查看，或在「反馈」里打包日志发给开发者"
		return
	if kind == "sentence":
		var toggle := UiKit.button("结构视图：" + ("开" if _show_structure else "关"), 13, 34)
		toggle.custom_minimum_size = Vector2(160, 34)
		toggle.pressed.connect(func() -> void:
			_show_structure = not _show_structure
			_refresh_choice_button_texts()
		)
		_content.add_child(toggle)
	_add_choice_options(view.get("options", []), statements, kind)
	_hint_label.text = "数字键 1-9 选择 · 选择后立刻结算，不会卡住"


func _render_result(view: Dictionary) -> void:
	var kind := str(view.get("kind", ""))
	var color := UiKit.COL_INK
	if kind == "correct" or kind == "remedy_ok":
		color = UiKit.COL_GOOD
	elif kind == "wrong" or kind == "fallback":
		color = UiKit.COL_DANGER
	var rich := UiKit.rich("", 19, color)
	rich.custom_minimum_size = Vector2(0, 120)
	_content.add_child(rich)
	_start_typewriter(rich, str(view.get("text", "")), 36.0)
	if kind == "wrong" or kind == "fallback":
		_sfx_call("wrong")
		BattleJuice.shake(self, 6.0)
	elif kind == "correct" or kind == "remedy_ok":
		_sfx_call("correct")
	var note := str(view.get("judge_note", ""))
	if note != "":
		_content.add_child(UiKit.label("识别出的谬误：" + note, 14, UiKit.COL_ACCENT))
	var cards: Array = view.get("cards", [])
	if not cards.is_empty():
		var parts: Array[String] = []
		for card in cards:
			parts.append(str(card))
		_content.add_child(UiKit.label("推荐出牌：" + "、".join(parts), 13, UiKit.COL_INK_DIM))
	_add_continue()


func _render_topic(view: Dictionary) -> void:
	var topic: Dictionary = view.get("topic", {})
	_content.add_child(UiKit.label("【辩题】" + str(topic.get("proposition", "")), 22, UiKit.COL_ACCENT))
	_content.add_child(UiKit.wrapped("你：" + str(topic.get("your_side", "")), 15, UiKit.COL_GOOD))
	_content.add_child(UiKit.wrapped("对方：" + str(topic.get("npc_side", "")), 15, UiKit.COL_DANGER))
	_content.add_child(UiKit.wrapped("赌注：" + str(topic.get("stake", "")), 15, UiKit.COL_INK_DIM))
	var labels: Dictionary = topic.get("audience_labels", {})
	var audience_text := "观众："
	var parts: Array[String] = []
	for key in ["support", "neutral", "oppose"]:
		parts.append(str(labels.get(key, key)))
	audience_text += "、".join(parts)
	_content.add_child(UiKit.wrapped(audience_text, 14, UiKit.COL_INK_DIM))
	_add_continue("开始辩论")


func _render_audience(view: Dictionary) -> void:
	var won := bool(view.get("won", false))
	_content.add_child(UiKit.label("第 %d/%d 回合结算" % [int(view.get("round", 1)), int(view.get("round_total", 1))], 18, UiKit.COL_ACCENT))
	_content.add_child(UiKit.label("这一回合：" + ("你赢下了" if won else "对方扳回一城"), 16, UiKit.COL_GOOD if won else UiKit.COL_DANGER))
	for note in view.get("notes", []):
		var note_dict: Dictionary = note
		_content.add_child(UiKit.wrapped("%s：%s" % [str(note_dict.get("speaker", "")), str(note_dict.get("text", ""))], 14, UiKit.COL_INK_DIM))
	_add_continue()


func _render_judging(view: Dictionary) -> void:
	_content.add_child(UiKit.label("评委投票", 20, UiKit.COL_ACCENT))
	_judge_result_label = UiKit.label("三位评委正在写票……", 15, UiKit.COL_INK_DIM)
	_content.add_child(_judge_result_label)
	_reveal_votes(view.get("votes", []), int(view.get("you_votes", 0)), bool(view.get("win", false)))
	_add_continue("查看结果")
	_hint_label.text = "评委正在投票……"


func _render_debrief(view: Dictionary) -> void:
	var win := bool(view.get("win", false))
	var early := bool(view.get("early", false))
	var feedback := _feedback()
	if feedback != null:
		feedback.log_event("story_finished", {
			"story": story_id,
			"win": win,
			"early": early,
			"stats": view.get("stats", {}),
		})
	_sfx_call("win" if win else "lose")
	var stats: Dictionary = view.get("stats", {})
	var title := "你赢下了这场辩论" if win else ("你选择了沉默" if early else "你被说服了")
	_content.add_child(UiKit.label(title, 24, UiKit.COL_ACCENT if win else UiKit.COL_DANGER))
	_content.add_child(UiKit.wrapped("回合胜场 %d / 3 · 一次选对 %d 次 · 补救 %d 次" % [
		int(stats.get("rounds_won", 0)), int(stats.get("correct_first", 0)), int(stats.get("remedies", 0))
	], 14, UiKit.COL_INK_DIM))
	var note := str(view.get("note", ""))
	if note != "":
		_content.add_child(UiKit.wrapped("一句话笔记：" + note, 15, UiKit.COL_INK))
	var fallacies: Array = view.get("fallacies", [])
	if not fallacies.is_empty():
		var parts: Array[String] = []
		for item in fallacies:
			parts.append(str(item))
		_content.add_child(UiKit.wrapped("本场谬误图鉴：" + "、".join(parts), 14, UiKit.COL_ACCENT))
	var history: Array = view.get("history", [])
	if not history.is_empty():
		_content.add_child(UiKit.label("本场时间线", 14, UiKit.COL_INK_DIM))
		for entry in history:
			var record: Dictionary = entry
			var type_key := str(record.get("type", ""))
			var kind_label := "选句"
			if type_key == "fallacy":
				kind_label = "谬误"
			elif type_key == "rebuttal":
				kind_label = "反驳"
			var mark := "✓" if bool(record.get("ok", false)) else "×"
			_content.add_child(UiKit.wrapped("第 %d 轮 · %s：%s  %s" % [
				int(record.get("round", 0)), kind_label, str(record.get("text", "")), mark
			], 12, UiKit.COL_INK_DIM))
	var quiz: Array = view.get("quiz", [])
	if not quiz.is_empty():
		_content.add_child(UiKit.label("课后小测（答案已折叠在复盘里）", 14, UiKit.COL_INK_DIM))
		for item in quiz:
			var quiz_dict: Dictionary = item
			_content.add_child(UiKit.wrapped("· %s → %s" % [str(quiz_dict.get("q", "")), str(quiz_dict.get("a", ""))], 13, UiKit.COL_INK_DIM))
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	var restart := UiKit.button("再来一局", 17, 46)
	restart.custom_minimum_size = Vector2(200, 46)
	restart.pressed.connect(func() -> void: restart_requested.emit())
	buttons.add_child(restart)
	var menu := UiKit.button("回到主菜单", 17, 46)
	menu.custom_minimum_size = Vector2(200, 46)
	menu.pressed.connect(func() -> void: exit_requested.emit())
	buttons.add_child(menu)
	_content.add_child(buttons)


# ---------------------------------------------------------------------------
# 交互
# ---------------------------------------------------------------------------

func _on_continue_pressed() -> void:
	if _busy:
		return
	if _try_finish_typing():
		_sfx_call("click")
		return
	_sfx_call("click")
	_busy = true
	engine.advance()


func _start_typewriter(label: RichTextLabel, text: String, chars_per_second: float = 34.0) -> void:
	_typing_label = label
	if _typing_tween != null and _typing_tween.is_valid():
		_typing_tween.kill()
	_typing_tween = BattleJuice.typewriter(label, text, chars_per_second)


## 若正在打字，点击/空格先瞬间补全，而不是直接跳到下一句（避免漏读）。
func _try_finish_typing() -> bool:
	if _typing_tween == null or not _typing_tween.is_valid() or not _typing_tween.is_running():
		_typing_tween = null
		return false
	_typing_tween.kill()
	if _typing_label != null:
		_typing_label.visible_ratio = 1.0
	_typing_tween = null
	return true


func _toggle_transcript() -> void:
	_transcript_panel.visible = not _transcript_panel.visible
	if not _transcript_panel.visible:
		return
	var lines: Array[String] = []
	for line in _transcript:
		lines.append(line)
	_transcript_label.text = "\n".join(lines)
	_transcript_label.scroll_to_line(maxi(0, lines.size() - 1))


func _float_audience_deltas(bars: Array) -> void:
	for bar_data in bars:
		var record: Dictionary = bar_data
		var delta := int(record.get("delta", 0))
		if delta == 0:
			continue
		var bar: TugBar = _audience_bars.get(str(record.get("key", "")))
		if bar == null:
			continue
		var at := bar.global_position + Vector2(70.0, -14.0)
		BattleJuice.float_text(self, "%+d" % delta, at, UiKit.COL_GOOD if delta > 0 else UiKit.COL_DANGER, 18)


func _on_option_pressed(option_id: String) -> void:
	if _busy:
		return
	_sfx_call("click")
	var chosen_text := ""
	for option in _choice_options:
		if str((option as Dictionary).get("id", "")) == option_id:
			chosen_text = str((option as Dictionary).get("text", ""))
			break
	var feedback := _feedback()
	if feedback != null:
		feedback.log_event("choice", {
			"story": story_id,
			"kind": _choice_kind,
			"id": option_id,
			"text": chosen_text,
			"round": engine.round_index + 1,
		})
	_busy = true
	engine.choose(option_id)


func _refresh_audience() -> void:
	if engine == null:
		return
	var labels: Dictionary = (engine.story.get("topic", {}) as Dictionary).get("audience_labels", {})
	var total := 0.0
	for key in ["support", "neutral", "oppose"]:
		var bar: TugBar = _audience_bars.get(key)
		if bar == null:
			continue
		var value := float(int(engine.audience[key]))
		bar.set_value(value)
		total += value
		var name_label: Label = bar.get_meta("name_label")
		if name_label != null:
			name_label.text = str(labels.get(key, key))
		var delta_label: Label = _audience_delta_labels.get(key)
		if delta_label != null:
			delta_label.text = "%d : %d" % [int(value), 100 - int(value)]
	if _total_bar != null:
		var average := total / 3.0
		_total_bar.set_value(average)
	if _total_label != null:
		var avg := int(round(total / 3.0))
		_total_label.text = "%d : %d" % [avg, 100 - avg]


func _refresh_judges(votes: Variant) -> void:
	if votes == null or not votes is Array:
		return
	var items: Array = votes
	for i in range(_judge_rows.size()):
		if i >= items.size():
			continue
		_set_judge_vote(i, items[i])


func _set_judge_vote(index: int, vote: Dictionary) -> void:
	if index < 0 or index >= _judge_rows.size():
		return
	var name_label: Label = _judge_rows[index].get_child(0)
	name_label.text = str(vote.get("name", "评委"))
	var vote_label: Label = _judge_labels[index]
	var you := bool(vote.get("you", false))
	vote_label.text = "你" if you else "对方"
	vote_label.add_theme_color_override("font_color", UiKit.COL_GOOD if you else UiKit.COL_DANGER)


## 逐票揭晓：三位评委依次亮票，比一次性显示更有仪式感。
func _reveal_votes(votes: Array, you_votes: int, win: bool) -> void:
	for i in range(votes.size()):
		await get_tree().create_timer(0.35).timeout
		if not is_inside_tree():
			return
		_set_judge_vote(i, votes[i] as Dictionary)
		_sfx_call("vote", bool((votes[i] as Dictionary).get("you", false)))
	if _judge_result_label != null and is_inside_tree():
		_judge_result_label.text = "你获得 %d 票" % you_votes
		_judge_result_label.add_theme_color_override("font_color", UiKit.COL_GOOD if win else UiKit.COL_DANGER)
		_hint_label.text = "空格继续 · 查看结果"


func _on_finished(_result: Dictionary) -> void:
	_hint_label.text = "本场结束。戳「再来一局」可以换一条路重打。"


func _sfx_call(method: String, arg: Variant = null) -> void:
	var node := get_node_or_null("/root/Sfx")
	if node == null:
		return
	if arg == null:
		node.call(method)
	else:
		node.call(method, arg)


func _feedback() -> Node:
	return get_node_or_null("/root/Feedback")


func _open_feedback() -> void:
	var panel := FeedbackPanel.new()
	add_child(panel)
	panel.closed.connect(panel.queue_free)


func _toggle_pause() -> void:
	_paused = not _paused
	if _pause_overlay != null:
		_pause_overlay.visible = _paused
	if _typing_tween != null and _typing_tween.is_valid():
		if _paused:
			_typing_tween.pause()
		else:
			_typing_tween.play()
	_sfx_call("click")
