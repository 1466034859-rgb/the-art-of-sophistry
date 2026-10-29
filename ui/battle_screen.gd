class_name BattleScreen
extends Control
## 战斗界面：出牌 → 响应窗口 → 结算 → 回合切换，全部由 BattleEngine 的 signal 驱动。

signal exit_requested()
signal rematch_requested()

const PLAYER := 0
const ENEMY := 1

var engine: BattleEngine = null
var player_id: String = ""
var enemy_id: String = ""
var scenario_id: String = ""

var _shake_root: Control
var _enemy_name: Label
var _enemy_meta: Label
var _enemy_ap: Label
var _enemy_spirit: SpiritBar
var _enemy_status: Label
var _player_name: Label
var _player_meta: Label
var _player_ap: Label
var _player_spirit: SpiritBar
var _player_status: Label
var _hand_row: HBoxContainer
var _dialogue: RichTextLabel
var _hint: Label
var _log_view: RichTextLabel
var _turn_label: Label
var _scenario_label: Label
var _response_panel: PanelContainer
var _response_label: Label
var _response_bar: ProgressBar
var _silence_button: Button
var _result_layer: Control
var _result_title: Label
var _result_desc: Label
var _result_debrief: RichTextLabel
var _debate_panel: PanelContainer
var _debate_label: RichTextLabel

var _log_lines: Array[String] = []
var _pending_response := false
var _response_total := 3.0
var _response_deadline := 0.0
var _enemy_busy := false
var _ended := false


func setup(new_player_id: String, new_enemy_id: String, new_scenario_id: String) -> void:
	player_id = new_player_id
	enemy_id = new_enemy_id
	scenario_id = new_scenario_id


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiKit.build_theme()
	_build_layout()
	_start_battle()


func _process(_delta: float) -> void:
	if not _pending_response:
		return
	if engine == null or engine.state != BattleEngine.State.WAITING_FOR_RESPONSE:
		_pending_response = false
		_response_panel.visible = false
		return
	var remaining := maxf(0.0, _response_deadline - _now())
	_response_bar.value = clampf(remaining / maxf(0.01, _response_total), 0.0, 1.0) * 100.0
	_response_label.text = "回应窗口 %.1fs" % remaining
	if remaining <= 0.0:
		_pending_response = false
		_response_panel.visible = false
		engine.submit_response(PLAYER, -1)


# ---------------------------------------------------------------------------
# 布局
# ---------------------------------------------------------------------------

func _build_layout() -> void:
	var background := ColorRect.new()
	background.color = UiKit.COL_BG
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var floor_band := ColorRect.new()
	floor_band.color = Color("#101216")
	floor_band.anchor_top = 0.7
	floor_band.anchor_right = 1.0
	floor_band.anchor_bottom = 1.0
	floor_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(floor_band)

	_shake_root = Control.new()
	_shake_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shake_root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_shake_root)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	_shake_root.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 12)
	top_row.custom_minimum_size = Vector2(0, 148)
	column.add_child(top_row)
	top_row.add_child(_build_side_panel(ENEMY, true))
	top_row.add_child(_build_info_panel())

	var dialogue_panel := UiKit.panel(UiKit.COL_BORDER, UiKit.COL_PANEL_DARK)
	dialogue_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(dialogue_panel)
	var dialogue_column := VBoxContainer.new()
	dialogue_column.add_theme_constant_override("separation", 6)
	dialogue_panel.add_child(dialogue_column)
	dialogue_column.add_child(_build_debate_panel())
	_dialogue = UiKit.rich("", 20, UiKit.COL_INK)
	_dialogue.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dialogue.custom_minimum_size = Vector2(0, 46)
	dialogue_column.add_child(_dialogue)
	dialogue_column.add_child(_build_response_panel())
	var hint_row := HBoxContainer.new()
	hint_row.add_theme_constant_override("separation", 10)
	dialogue_column.add_child(hint_row)
	_hint = UiKit.wrapped("", 14, UiKit.COL_INK_DIM)
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint_row.add_child(_hint)
	_silence_button = UiKit.button("沉默", 15, 38)
	_silence_button.custom_minimum_size = Vector2(140, 38)
	_silence_button.pressed.connect(_on_silence_pressed)
	_silence_button.visible = false
	hint_row.add_child(_silence_button)

	column.add_child(_build_side_panel(PLAYER, false))

	var hand_wrap := HBoxContainer.new()
	hand_wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(hand_wrap)
	_hand_row = HBoxContainer.new()
	_hand_row.add_theme_constant_override("separation", 8)
	hand_wrap.add_child(_hand_row)

	_build_result_layer()


func _build_side_panel(side: int, is_enemy: bool) -> PanelContainer:
	var accent := UiKit.COL_BLUE
	var player: CharacterResource = GameLibrary.shared().characters.get(player_id)
	var enemy: CharacterResource = GameLibrary.shared().characters.get(enemy_id)
	var character: CharacterResource = enemy if is_enemy else player
	if character != null:
		accent = character.accent_color
	var panel := UiKit.panel(accent, UiKit.COL_PANEL)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	column.add_child(head)
	var name_label := UiKit.label("对手" if is_enemy else "你", 21, accent)
	head.add_child(name_label)
	var meta := UiKit.label("", 12, UiKit.COL_INK_DIM)
	head.add_child(meta)
	head.add_child(UiKit.grow_spacer())
	var ap_label := UiKit.label("", 13, UiKit.COL_ACCENT)
	head.add_child(ap_label)

	var bar := SpiritBar.new()
	bar.setup(5, accent)
	column.add_child(bar)
	var status_label := UiKit.wrapped("", 12, UiKit.COL_INK_DIM)
	column.add_child(status_label)

	if is_enemy:
		_enemy_name = name_label
		_enemy_meta = meta
		_enemy_ap = ap_label
		_enemy_spirit = bar
		_enemy_status = status_label
	else:
		_player_name = name_label
		_player_meta = meta
		_player_ap = ap_label
		_player_spirit = bar
		_player_status = status_label
	return panel


func _build_info_panel() -> PanelContainer:
	var panel := UiKit.panel(UiKit.COL_BORDER_DIM, UiKit.COL_PANEL_DARK)
	panel.custom_minimum_size = Vector2(330, 0)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	panel.add_child(column)

	_turn_label = UiKit.label("回合 01", 15, UiKit.COL_ACCENT)
	column.add_child(_turn_label)
	_scenario_label = UiKit.wrapped("", 12, UiKit.COL_INK_DIM)
	column.add_child(_scenario_label)
	_log_view = UiKit.rich("", 11, UiKit.COL_INK_DIM)
	_log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_view.custom_minimum_size = Vector2(0, 46)
	_log_view.fit_content = false
	_log_view.scroll_active = false
	column.add_child(_log_view)
	var leave := UiKit.button("离开对局", 12, 26)
	leave.pressed.connect(_on_leave_pressed)
	column.add_child(leave)
	return panel


## 辩题条：标题 / 争点进度 / 有效手法 / 论点分。
func _build_debate_panel() -> PanelContainer:
	_debate_panel = UiKit.panel(UiKit.COL_ACCENT, Color("#1b1f25"))
	_debate_panel.visible = false
	_debate_label = UiKit.rich("", 13, UiKit.COL_INK)
	_debate_panel.add_child(_debate_label)
	return _debate_panel


func _refresh_debate_panel() -> void:
	if _debate_label == null or engine == null:
		return
	if not engine.has_topic():
		_debate_panel.visible = false
		return
	_debate_panel.visible = true
	var progress := engine.claim_progress()
	var effective := LogicCard.tag_label_of(engine.effective_tag_for_claim())
	_debate_label.text = (
		"[color=#c4b47f]【辩题】%s[/color]   [color=#9fb8a0]论点 %d : %d[/color]\n"
		+ "[color=#d8d3c8]争点 %d/%d：%s[/color]   [color=#8b877d]对题手法：%s（+%d 压力）[/color]"
	) % [
		engine.topic.title,
		engine.points_of(PLAYER),
		engine.points_of(ENEMY),
		progress.x,
		progress.y,
		engine.current_claim_text(),
		effective,
		BattleEngine.CLAIM_FIT_BONUS,
	]


## 响应窗口计数条：嵌在对白面板内部，出现时自动挤开对白，不会遮挡任何内容。
func _build_response_panel() -> PanelContainer:
	var wrapper := UiKit.panel(UiKit.COL_ACCENT, Color("#1b1f25"))
	wrapper.visible = false
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	wrapper.add_child(row)
	_response_label = UiKit.label("回应窗口", 15, UiKit.COL_ACCENT)
	_response_label.custom_minimum_size = Vector2(230, 0)
	row.add_child(_response_label)
	_response_bar = ProgressBar.new()
	_response_bar.max_value = 100.0
	_response_bar.value = 100.0
	_response_bar.custom_minimum_size = Vector2(0, 10)
	_response_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_response_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_response_bar.show_percentage = false
	row.add_child(_response_bar)
	_response_panel = wrapper
	return wrapper


func _build_result_layer() -> void:
	_result_layer = Control.new()
	_result_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result_layer.visible = false
	_result_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_result_layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result_layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result_layer.add_child(center)

	var panel := UiKit.panel(UiKit.COL_ACCENT, UiKit.COL_PANEL)
	panel.custom_minimum_size = Vector2(600, 0)
	center.add_child(panel)
	var column := UiKit.vbox([], 14)
	panel.add_child(column)

	_result_title = UiKit.title("", 44)
	column.add_child(_result_title)
	_result_desc = UiKit.wrapped("", 16, UiKit.COL_INK)
	_result_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_result_desc)
	_result_debrief = UiKit.rich("", 13, UiKit.COL_INK)
	_result_debrief.custom_minimum_size = Vector2(0, 120)
	column.add_child(_result_debrief)
	column.add_child(UiKit.spacer(6))

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	column.add_child(buttons)
	var rematch := UiKit.button("再来一局", 18, 48)
	rematch.custom_minimum_size = Vector2(200, 48)
	rematch.pressed.connect(func() -> void: rematch_requested.emit())
	buttons.add_child(rematch)
	var menu := UiKit.button("回到主菜单", 18, 48)
	menu.custom_minimum_size = Vector2(200, 48)
	menu.pressed.connect(func() -> void: exit_requested.emit())
	buttons.add_child(menu)


# ---------------------------------------------------------------------------
# 战斗启动与信号
# ---------------------------------------------------------------------------

func _start_battle() -> void:
	engine = BattleEngine.new()
	engine.battle_started.connect(_on_battle_started)
	engine.turn_started.connect(_on_turn_started)
	engine.action_needed.connect(_on_action_needed)
	engine.card_played.connect(_on_card_played)
	engine.response_requested.connect(_on_response_requested)
	engine.response_committed.connect(_on_response_committed)
	engine.resolution_finished.connect(_on_resolution_finished)
	engine.spirit_changed.connect(_on_spirit_changed)
	engine.status_changed.connect(_on_status_changed)
	engine.log_line.connect(_on_log_line)
	engine.battle_ended.connect(_on_battle_ended)
	engine.claim_announced.connect(_on_claim_announced)
	engine.claim_resolved.connect(_on_claim_resolved)
	engine.setup_battle(player_id, enemy_id, scenario_id)
	_refresh_labels()


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _on_battle_started(_scenario_key: String) -> void:
	var player := engine.character_of(PLAYER)
	var enemy := engine.character_of(ENEMY)
	_player_name.text = player.char_name
	_player_name.add_theme_color_override("font_color", player.accent_color)
	_player_meta.text = "%s · %s" % [player.affinity_label(), player.passive_name]
	_enemy_name.text = enemy.char_name
	_enemy_name.add_theme_color_override("font_color", enemy.accent_color)
	_enemy_meta.text = "%s · %s" % [enemy.affinity_label(), enemy.passive_name]
	_player_spirit.setup(engine.max_spirit_of(PLAYER), player.accent_color)
	_enemy_spirit.setup(engine.max_spirit_of(ENEMY), enemy.accent_color)
	_player_spirit.set_value(engine.spirit_of(PLAYER), false)
	_enemy_spirit.set_value(engine.spirit_of(ENEMY), false)
	if engine.scenario != null:
		_scenario_label.text = "【%s】环境倾向 · %s" % [
			engine.scenario.scenario_name,
			engine.scenario.ambient_label(),
		]
	else:
		_scenario_label.text = ""
	_refresh_debate_panel()
	var opening := ""
	if engine.has_topic():
		opening = engine.topic.opening_line("player")
	if opening == "":
		opening = _opening_line()
	_dialogue.text = "[color=#8b877d]%s[/color]" % opening
	_refresh_labels()
	_refresh_hand()


func _opening_line() -> String:
	var lines := [
		"空气安静了下来。谁先开口，谁就先暴露立场。",
		"对面的人笑了一下，那是一种「你继续说」的笑。",
		"这不是吵架，这是一场有分寸的处刑。",
		"所有人都在等，等一个足够体面的破绽。",
	]
	return lines[engine.rng.randi_range(0, lines.size() - 1)]


func _on_turn_started(side: int, turn_number: int) -> void:
	_turn_label.text = "第 %02d 回合 · %s" % [turn_number, "你的回合" if side == PLAYER else "对方回合"]
	_refresh_labels()


func _on_action_needed(side: int) -> void:
	if _ended:
		return
	_refresh_labels()
	_refresh_hand()
	if side == PLAYER:
		_show_hint("轮到你了：点击一张手牌出牌，或点「沉默」把话头让出去。")
		_silence_button.visible = true
		_silence_button.text = "沉默"
	else:
		_show_hint("对方正在组织语言……")
		_silence_button.visible = false
		_enemy_act_later()


func _on_card_played(side: int, card: LogicCard) -> void:
	_refresh_labels()
	_refresh_hand()
	var who: String = engine.character_of(side).char_name
	BattleJuice.typewriter(_dialogue, "%s\n[color=#8b877d]—— %s · 【%s】[/color]" % [engine.last_line, who, card.move_name], 34)
	if side == PLAYER:
		if engine.has_topic() and engine.library.fits(card.tag, engine.current_claim_tag()):
			_show_hint("这一手正打在争点上：「%s」，等对方接话……" % engine.current_claim_text())
		else:
			_show_hint("你打出了「%s」，等对方接话……" % card.card_name)
	else:
		_show_hint("对方打出了「%s」。" % card.card_name)
	_pulse_panel(side)


func _on_response_requested(defender_side: int, attack_card: LogicCard, window_seconds: float) -> void:
	_refresh_labels()
	_refresh_hand()
	if defender_side == PLAYER:
		_pending_response = true
		_response_total = window_seconds
		_response_deadline = _now() + window_seconds
		_response_panel.visible = true
		_response_bar.value = 100.0
		_response_label.text = "回应窗口 %.1fs" % window_seconds
		_silence_button.visible = true
		_silence_button.text = "哑口无言"
		if engine.can_respond_at_all(PLAYER):
			_show_hint("对方打出「%s」——用克制其标签的【拆解卡】回应可完美抵消，或用【诡辩卡】对拼。" % attack_card.card_name)
		else:
			_show_hint("你没有可用的回应（AP 不足或手上没有拆解/诡辩卡）——这一击只能硬接。")
	else:
		_response_panel.visible = true
		_response_bar.value = 100.0
		_response_label.text = "对方正在寻找你的破绽……"
		_silence_button.visible = false
		_show_hint("对方正在权衡要不要接这一击……")
		_enemy_respond_later(attack_card, window_seconds)


func _on_response_committed(defender_side: int, card: LogicCard) -> void:
	_pending_response = false
	_response_panel.visible = false
	if card != null:
		var who: String = engine.character_of(defender_side).char_name
		BattleJuice.typewriter(_dialogue, "%s\n[color=#8b877d]—— %s · 【%s】（回应）[/color]" % [engine.last_line, who, card.move_name], 34)
	else:
		BattleJuice.typewriter(_dialogue, "[color=#8b877d]……（沉默）[/color]", 20)
	_refresh_hand()


func _on_resolution_finished(info: Dictionary) -> void:
	_refresh_labels()
	_refresh_hand()
	_silence_button.visible = false
	var outcome: int = info.get("outcome", BattleEngine.Outcome.SILENCE)
	var text := ""
	match outcome:
		BattleEngine.Outcome.SILENCE:
			text = "[color=#c46f6f]哑口无言！[/color] 这一击结结实实。"
		BattleEngine.Outcome.PERFECT:
			text = "[color=#9fb8a0]完美拆解！[/color] 反手一击。"
		BattleEngine.Outcome.PARTIAL:
			text = "[color=#c4b47f]勉强挡下一半[/color]，但没能完全拆掉。"
		BattleEngine.Outcome.TRADE:
			text = "[color=#c48f8f]诡辩对拼[/color]，双方都不体面。"
	_append_log(text)
	var total_damage: int = int(info.get("damage_to_defender", 0)) + int(info.get("damage_to_attacker", 0))
	if total_damage >= 2:
		BattleJuice.shake(_shake_root, 9.0)


func _on_spirit_changed(side: int, old_value: int, new_value: int) -> void:
	var bar: SpiritBar = _player_spirit if side == PLAYER else _enemy_spirit
	if bar == null:
		return
	bar.set_value(new_value)
	var delta := new_value - old_value
	var at := bar.global_position + Vector2(20.0, -18.0)
	if delta < 0:
		bar.flash(Color(1.0, 0.55, 0.55))
		BattleJuice.float_text(self, "%d" % delta, at, UiKit.COL_DANGER)
	else:
		bar.flash(Color(0.7, 1.0, 0.78))
		BattleJuice.float_text(self, "+%d" % delta, at, UiKit.COL_GOOD)


func _on_status_changed(_side: int, _status: Dictionary, _added: bool) -> void:
	_refresh_labels()


func _on_log_line(text: String, kind: String) -> void:
	if _log_view == null:
		return
	var escaped := text.replace("[", "[lb]")
	if kind == "damage":
		escaped = "[color=#c46f6f]%s[/color]" % escaped
	elif kind == "heal":
		escaped = "[color=#9fb8a0]%s[/color]" % escaped
	_log_lines.append(escaped)
	while _log_lines.size() > 3:
		_log_lines.pop_front()
	_log_view.text = "\n".join(_log_lines)


func _on_battle_ended(winner: int, reason: String) -> void:
	_ended = true
	_pending_response = false
	_ended_banner(winner, reason)


func _ended_banner(winner: int, reason: String) -> void:
	await get_tree().create_timer(0.65).timeout
	if _result_layer == null:
		return
	_result_layer.visible = true
	BattleJuice.fade_in(_result_layer)
	if winner == PLAYER:
		_result_title.text = "你赢了"
		_result_title.add_theme_color_override("font_color", UiKit.COL_ACCENT)
	elif winner == ENEMY:
		_result_title.text = "你破防了"
		_result_title.add_theme_color_override("font_color", UiKit.COL_DANGER)
	else:
		_result_title.text = "平局"
		_result_title.add_theme_color_override("font_color", UiKit.COL_INK_DIM)
	var description := reason
	if engine != null and engine.has_topic():
		var key := "draw"
		if winner == PLAYER:
			key = "win"
		elif winner == ENEMY:
			key = "lose"
		var flavor := engine.topic.debrief_line(key)
		if flavor != "":
			description = "%s\n%s" % [reason, flavor]
	_result_desc.text = "%s\n回合数 %d · 共打出 %d 张卡" % [description, engine.turn_number, engine.played_cards.size()]
	_result_debrief.text = _debrief_text()


# ---------------------------------------------------------------------------
# 辩题事件
# ---------------------------------------------------------------------------

func _on_claim_announced(index: int, total: int, claim_text: String, effective_tag: String, npc_line: String) -> void:
	_refresh_debate_panel()
	var headline := "【争点 %d/%d】%s" % [index + 1, total, claim_text]
	var sub := "对题手法：%s（额外 +%d 压力）" % [effective_tag, BattleEngine.CLAIM_FIT_BONUS]
	if npc_line != "":
		sub = "对方：%s\n[color=#c4b47f]对题手法：%s（+%d 压力）[/color]" % [npc_line, effective_tag, BattleEngine.CLAIM_FIT_BONUS]
	BattleJuice.typewriter(_dialogue, "[color=#c4b47f]%s[/color]\n[color=#8b877d]%s[/color]" % [headline, sub], 40)
	_show_hint("当前争点「%s」——用【%s】类牌施压更容易拿下它。" % [claim_text, effective_tag])


func _on_claim_resolved(_index: int, winner: int, _points: Array) -> void:
	_refresh_debate_panel()
	if winner == PLAYER:
		_append_log("[color=#9fb8a0]你赢下了这个争点。[/color]")
	elif winner == ENEMY:
		_append_log("[color=#c46f6f]对方赢下了这个争点。[/color]")
	else:
		_append_log("[color=#8b877d]这个争点僵持不下。[/color]")


func _join_names(values: Array) -> String:
	var packed := PackedStringArray()
	for value in values:
		packed.append(str(value))
	return "、".join(packed)


## 战后复盘：手法统计 / 谬误提醒 / 争点得失。
func _debrief_text() -> String:
	if engine == null or not engine.has_topic():
		return ""
	var data := engine.debrief_for(PLAYER)
	var lines: Array[String] = []
	lines.append("[color=#c4b47f]【辩论复盘】论点 %d : %d[/color]" % [int(data["points"]), int(data["opp_points"])])
	var moves: Dictionary = data["moves"]
	if not moves.is_empty():
		var parts: Array[String] = []
		for name in moves.keys():
			parts.append("%s×%d" % [str(name), int(moves[name])])
		lines.append("[color=#d8d3c8]用过的招法：%s[/color]" % "、".join(parts))
	var claims_won: Array = data["claims_won"]
	if not claims_won.is_empty():
		lines.append("[color=#9fb8a0]赢下争点：%s[/color]" % _join_names(claims_won))
	var fallacies: Dictionary = data["fallacies"]
	if not fallacies.is_empty():
		var fallacy_parts: Array[String] = []
		for name in fallacies.keys():
			fallacy_parts.append("%s×%d" % [str(name), int(fallacies[name])])
		lines.append("[color=#c46f6f]踩到的谬误：%s[/color]" % "、".join(fallacy_parts))
		var lessons_map: Dictionary = data["fallacy_lessons"]
		for name in lessons_map.keys():
			lines.append("[color=#8b877d]· %s[/color]" % str(lessons_map[name]))
	var lessons: Array = data["lessons"]
	for lesson in lessons:
		lines.append("[color=#8b877d]· %s[/color]" % str(lesson))
	return "\n".join(lines)


# ---------------------------------------------------------------------------
# 流程控制
# ---------------------------------------------------------------------------

func _on_silence_pressed() -> void:
	if engine == null or _ended:
		return
	if engine.state == BattleEngine.State.WAITING_FOR_RESPONSE and engine.defender_side == PLAYER:
		_pending_response = false
		_response_panel.visible = false
		engine.submit_response(PLAYER, -1)
	elif engine.state == BattleEngine.State.AWAITING_ACTION and engine.turn_side == PLAYER:
		_silence_button.visible = false
		engine.pass_turn(PLAYER)


func _on_leave_pressed() -> void:
	exit_requested.emit()


func _on_card_clicked(index: int) -> void:
	if engine == null or _ended:
		return
	if engine.state == BattleEngine.State.AWAITING_ACTION and engine.turn_side == PLAYER:
		if engine.play_card(PLAYER, index):
			_silence_button.visible = false
			_refresh_hand()
	elif engine.state == BattleEngine.State.WAITING_FOR_RESPONSE and engine.defender_side == PLAYER:
		if engine.can_respond(PLAYER, index):
			_pending_response = false
			_response_panel.visible = false
			engine.submit_response(PLAYER, index)
		else:
			_show_hint("这张牌不能用来回应：回应只能打【拆解卡】（标签克制则完美抵消）或【诡辩卡】（对拼）。")


func _enemy_act_later() -> void:
	if _enemy_busy:
		return
	_enemy_busy = true
	await get_tree().create_timer(0.85).timeout
	_enemy_busy = false
	if engine == null or _ended:
		return
	if engine.state != BattleEngine.State.AWAITING_ACTION or engine.turn_side != ENEMY:
		return
	var index := AIController.choose_action(engine, ENEMY)
	if index < 0 or not engine.play_card(ENEMY, index):
		engine.pass_turn(ENEMY)


func _enemy_respond_later(attack_card: LogicCard, window_seconds: float) -> void:
	var delay := randf_range(0.6, minf(1.8, maxf(0.85, window_seconds * 0.55)))
	await get_tree().create_timer(delay).timeout
	_response_panel.visible = false
	if engine == null or _ended:
		return
	if engine.state != BattleEngine.State.WAITING_FOR_RESPONSE or engine.defender_side != ENEMY:
		return
	var index := AIController.choose_response(engine, ENEMY, attack_card)
	engine.submit_response(ENEMY, index)


# ---------------------------------------------------------------------------
# 刷新
# ---------------------------------------------------------------------------

func _refresh_labels() -> void:
	if engine == null:
		return
	_player_ap.text = "%d AP" % engine.ap_of(PLAYER)
	_enemy_ap.text = "%d AP" % engine.ap_of(ENEMY)
	_player_status.text = _status_text(PLAYER)
	_enemy_status.text = _status_text(ENEMY)


func _status_text(side: int) -> String:
	var parts: Array[String] = []
	for status in engine.statuses_of(side):
		parts.append("%s(%d)" % [str(status.get("name", "")), int(status.get("duration", 1))])
	if parts.is_empty():
		return "无状态"
	return "状态：" + "  ".join(parts)


func _refresh_hand() -> void:
	if _hand_row == null:
		return
	for child in _hand_row.get_children():
		_hand_row.remove_child(child)
		child.queue_free()
	if engine == null:
		return
	var hand: Array = engine.hand_of(PLAYER)
	for i in range(hand.size()):
		var card: LogicCard = hand[i]
		var playable := false
		if not _ended:
			if engine.state == BattleEngine.State.AWAITING_ACTION and engine.turn_side == PLAYER:
				playable = engine.can_play(PLAYER, i)
			elif engine.state == BattleEngine.State.WAITING_FOR_RESPONSE and engine.defender_side == PLAYER:
				playable = engine.can_respond(PLAYER, i)
		var widget := CardWidget.new()
		widget.setup(card, i, playable)
		widget.clicked.connect(_on_card_clicked)
		_hand_row.add_child(widget)


func _show_hint(text: String) -> void:
	if _hint != null:
		_hint.text = text


func _append_log(text: String) -> void:
	if _log_view == null:
		return
	_log_lines.append(text)
	while _log_lines.size() > 3:
		_log_lines.pop_front()
	_log_view.text = "\n".join(_log_lines)


func _pulse_panel(side: int) -> void:
	var bar: SpiritBar = _player_spirit if side == PLAYER else _enemy_spirit
	if bar == null:
		return
	var tween := create_tween()
	tween.tween_property(bar, "modulate", Color(1.4, 1.4, 1.4), 0.08)
	tween.tween_property(bar, "modulate", Color.WHITE, 0.2)
