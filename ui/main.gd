extends Control
## 主控：主菜单 → 角色 / 对手 / 场景选择 → 战斗 → 结算。

var _screen: Control = null
var _library: GameLibrary
var _option_buttons: Dictionary = {}

var _player_choice: String = "polite_assassin"
var _enemy_choice: String = "fact_checker"
var _scenario_choice: String = "office_pantry"


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_library = GameLibrary.shared()
	theme = UiKit.build_theme()
	_show_menu()


func _switch_to(screen: Control) -> void:
	if _screen != null:
		_screen.queue_free()
	_screen = screen
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(screen)
	screen.modulate.a = 0.0
	var tween := screen.create_tween()
	tween.tween_property(screen, "modulate:a", 1.0, 0.28)


func _background() -> ColorRect:
	var background := ColorRect.new()
	background.color = UiKit.COL_BG
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return background


# ---------------------------------------------------------------------------
# 主菜单
# ---------------------------------------------------------------------------

func _show_menu() -> void:
	var root := Control.new()
	root.add_child(_background())

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(column)

	var title := UiKit.title("诡辩之术", 76, UiKit.COL_ACCENT)
	column.add_child(title)
	var subtitle := UiKit.label("T H E   A R T   O F   S O P H I S T R Y", 15, UiKit.COL_INK_DIM)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(subtitle)
	column.add_child(UiKit.spacer(10))

	var roster := HBoxContainer.new()
	roster.alignment = BoxContainer.ALIGNMENT_CENTER
	roster.add_theme_constant_override("separation", 18)
	column.add_child(roster)
	for character_id in _library.characters.keys():
		var character: CharacterResource = _library.characters[character_id]
		var chip := UiKit.label(character.char_name, 14, character.accent_color)
		chip.tooltip_text = character.tagline
		roster.add_child(chip)

	column.add_child(UiKit.spacer(20))
	var story := UiKit.button("故事模式 · 四场辩论", 22, 58)
	story.custom_minimum_size = Vector2(340, 58)
	story.pressed.connect(_show_story_select)
	column.add_child(story)
	var start := UiKit.button("快速对战（卡牌）", 16, 44)
	start.custom_minimum_size = Vector2(340, 44)
	start.pressed.connect(_show_select)
	column.add_child(start)
	var feedback_button := UiKit.button("反馈 / 诊断包", 15, 40)
	feedback_button.custom_minimum_size = Vector2(340, 40)
	feedback_button.pressed.connect(_open_feedback)
	column.add_child(feedback_button)
	var quit_button := UiKit.button("退出游戏", 16, 44)
	quit_button.custom_minimum_size = Vector2(340, 44)
	quit_button.pressed.connect(func() -> void: get_tree().quit())
	column.add_child(quit_button)
	column.add_child(UiKit.spacer(6))
	var footer := UiKit.label("v0.6 试玩版 · 四场故事 · F3 调试 · 反馈会带上日志与截图", 12, Color("#5f646b"))
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(footer)

	_switch_to(root)


func _show_story_select() -> void:
	var root := Control.new()
	root.add_child(_background())

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 30)
	root.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var title := UiKit.title("选择一场辩论", 40)
	column.add_child(title)
	var subtitle := UiKit.label("四个场景，四个议题。每一场都有人要说服，也有人要被说服。", 14, UiKit.COL_INK_DIM)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(subtitle)
	column.add_child(UiKit.spacer(8))

	for story_id in _library.stories.keys():
		var story: Dictionary = _library.stories[story_id]
		var button := UiKit.button("%s\n%s" % [str(story.get("title", story_id)), str(story.get("subtitle", ""))], 16, 66)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 66)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.tooltip_text = str((story.get("scene_card", {}) as Dictionary).get("stake", ""))
		var captured_id := str(story_id)
		button.pressed.connect(func() -> void: _show_story(captured_id))
		column.add_child(button)

	column.add_child(UiKit.spacer(8))
	var back := UiKit.button("返回主菜单", 16, 46)
	back.custom_minimum_size = Vector2(220, 46)
	back.pressed.connect(_show_menu)
	var back_row := HBoxContainer.new()
	back_row.alignment = BoxContainer.ALIGNMENT_CENTER
	back_row.add_child(back)
	column.add_child(back_row)

	_switch_to(root)


func _show_story(story_id: String) -> void:
	var screen := StoryScreen.new()
	screen.setup(story_id)
	screen.exit_requested.connect(_show_story_select)
	screen.restart_requested.connect(func() -> void: _show_story(story_id))
	_switch_to(screen)


func _open_feedback() -> void:
	var panel := FeedbackPanel.new()
	add_child(panel)
	panel.closed.connect(panel.queue_free)


# ---------------------------------------------------------------------------
# 选择界面
# ---------------------------------------------------------------------------

func _show_select() -> void:
	var root := Control.new()
	root.add_child(_background())

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 24)
	root.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)

	var header := UiKit.title("选择你的立场", 40)
	column.add_child(header)
	var subtitle := UiKit.label("同一套逻辑，不同的活法。先选自己，再选对手和场地。", 14, UiKit.COL_INK_DIM)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(subtitle)

	var groups := HBoxContainer.new()
	groups.add_theme_constant_override("separation", 22)
	groups.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(groups)
	groups.add_child(_build_group("你的角色", _library.characters.keys(), _player_choice, true, _on_pick_player))
	groups.add_child(_build_group("对手", _library.characters.keys(), _enemy_choice, true, _on_pick_enemy))
	groups.add_child(_build_group("场景", _library.scenarios.keys(), _scenario_choice, false, _on_pick_scenario))

	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 18)
	column.add_child(bottom)
	var back := UiKit.button("返回", 16, 50)
	back.custom_minimum_size = Vector2(180, 50)
	back.pressed.connect(_show_menu)
	bottom.add_child(back)
	var fight := UiKit.button("开始对峙", 20, 50)
	fight.custom_minimum_size = Vector2(320, 50)
	fight.pressed.connect(_start_battle)
	bottom.add_child(fight)

	_switch_to(root)


func _build_group(header: String, ids: Array, current: String, is_character: bool, pick: Callable) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(UiKit.label(header, 15, UiKit.COL_INK_DIM))

	var buttons: Array = []
	for i in range(ids.size()):
		var option_id := str(ids[i])
		var accent := UiKit.COL_BORDER
		var title := option_id
		var subtitle := ""
		var detail := ""
		if is_character and _library.characters.has(option_id):
			var character: CharacterResource = _library.characters[option_id]
			accent = character.accent_color
			title = character.char_name
			subtitle = "%s · %s" % [character.affinity_label(), character.passive_name]
			detail = "%s\n被动【%s】：%s" % [character.tagline, character.passive_name, character.passive_desc]
		elif _library.scenarios.has(option_id):
			var scenario: ScenarioResource = _library.scenarios[option_id]
			accent = scenario.accent_color
			title = scenario.scenario_name
			subtitle = "环境倾向 · " + scenario.ambient_label()
			detail = scenario.description
			var topic: DebateTopic = _library.topic_for_scene(option_id)
			if topic != null:
				subtitle += "｜辩题：%s" % topic.title
				detail += "\n\n辩题：%s\n%s" % [topic.proposition, topic.stake]
		var button := UiKit.button("%s\n%s" % [title, subtitle], 15, 64)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 64)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.tooltip_text = detail
		button.set_meta("option_id", option_id)
		button.set_meta("accent", accent)
		button.pressed.connect(func() -> void: pick.call(option_id))
		column.add_child(button)
		buttons.append(button)
	_option_buttons[header] = buttons
	_restyle_options(header, current)
	return column


func _restyle_options(header: String, selected_id: String) -> void:
	var buttons: Array = _option_buttons.get(header, [])
	for button in buttons:
		var is_selected := str(button.get_meta("option_id")) == selected_id
		var accent: Color = button.get_meta("accent")
		var background := Color("#2a2f37") if is_selected else UiKit.COL_PANEL_LIGHT
		var border := accent if is_selected else UiKit.COL_BORDER
		button.add_theme_stylebox_override("normal", UiKit.box(background, border, 2))
		button.add_theme_color_override("font_color", Color("#fff6dc") if is_selected else UiKit.COL_INK)


func _on_pick_player(character_id: String) -> void:
	_player_choice = character_id
	_restyle_options("你的角色", character_id)


func _on_pick_enemy(character_id: String) -> void:
	_enemy_choice = character_id
	_restyle_options("对手", character_id)


func _on_pick_scenario(scenario_id: String) -> void:
	_scenario_choice = scenario_id
	_restyle_options("场景", scenario_id)


func _start_battle() -> void:
	var battle := BattleScreen.new()
	battle.setup(_player_choice, _enemy_choice, _scenario_choice)
	battle.exit_requested.connect(_show_menu)
	battle.rematch_requested.connect(_start_battle)
	_switch_to(battle)
