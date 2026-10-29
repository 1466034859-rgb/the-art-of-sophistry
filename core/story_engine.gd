class_name StoryEngine
extends RefCounted
## 「故事模式」叙事引擎：场景卡 → 序幕 → 分歧 → 三回合交锋 → 结辩 → 评委投票 → 尾声 → 复盘。
##
## 设计要点：
##   * 每个选择都有明确出口：选对 / 选错→补救 / 补救失败→兜底，绝无“点了没反应”
##   * 数据驱动：完全读取 data/stories.json，脚本内容与代码分离
##   * 纯逻辑、无 UI 依赖，可 headless 遍历所有分支做死路检测

signal view_changed(view: Dictionary)
signal finished(result: Dictionary)

enum Phase {
	IDLE,
	SCENE_CARD,
	PROLOGUE,
	TRIGGER,
	ENDURE,
	TOPIC,
	STATEMENT,
	PICK_SENTENCE,
	PICK_FALLACY,
	REBUTTAL,
	ROUND_AUDIENCE,
	CLOSING,
	JUDGING,
	EPILOGUE,
	DEBRIEF,
	ENDED,
}

const AUDIENCE_KEYS := ["support", "neutral", "oppose"]

var story: Dictionary = {}
var phase: Phase = Phase.IDLE
var audience: Dictionary = {"support": 50, "neutral": 50, "oppose": 50}
var round_index: int = 0
var rounds_won: int = 0
var correct_first: int = 0
var remedies_used: int = 0
var selected_closing: String = ""
var current_view: Dictionary = {}
var result: Dictionary = {}
var history: Array[Dictionary] = []

var _dialogue_queue: Array = []
var _pending_after: String = ""
var _round: Dictionary = {}
var _statement_index: int = 0
var _sentence_attempts: int = 0
var _sentence_remedy: bool = false
var _fallacy_remedy: bool = false
var _removed_sentence: int = -1
var _removed_fallacy: String = ""
var _pending_hint: String = ""
var _audience_delta: Dictionary = {"support": 0, "neutral": 0, "oppose": 0}
var _won_this_round: bool = false
var _judge_votes: Array = []


# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------

func setup(story_data: Dictionary) -> void:
	story = story_data
	phase = Phase.SCENE_CARD
	audience = {"support": 50, "neutral": 50, "oppose": 50}
	var init_audience: Variant = (story.get("topic", {}) as Dictionary).get("audience_init", {})
	if init_audience is Dictionary:
		for key in AUDIENCE_KEYS:
			audience[key] = int((init_audience as Dictionary).get(key, 50))
	round_index = 0
	rounds_won = 0
	correct_first = 0
	remedies_used = 0
	selected_closing = ""
	result = {}
	history.clear()
	_dialogue_queue.clear()
	_pending_after = ""
	_round = {}
	_statement_index = 0
	_sentence_attempts = 0
	_sentence_remedy = false
	_fallacy_remedy = false
	_removed_sentence = -1
	_removed_fallacy = ""
	_pending_hint = ""
	_audience_delta = {"support": 0, "neutral": 0, "oppose": 0}
	_judge_votes.clear()
	_emit({
		"type": "scene_card",
		"title": str(story.get("title", "")),
		"subtitle": str(story.get("subtitle", "")),
		"card": story.get("scene_card", {}),
	})


# ---------------------------------------------------------------------------
# 推进
# ---------------------------------------------------------------------------

func advance() -> void:
	if phase == Phase.ENDED:
		return
	while true:
		if not _dialogue_queue.is_empty():
			var line: Dictionary = _dialogue_queue.pop_front()
			_emit_dialogue(line)
			return
		if _pending_after != "":
			var action := _pending_after
			_pending_after = ""
			_execute(action)
			return
		match phase:
			Phase.SCENE_CARD:
				phase = Phase.PROLOGUE
				_dialogue_queue = _as_lines(story.get("prologue", []))
				_pending_after = "_after_prologue"
			Phase.PROLOGUE:
				_pending_after = "_after_prologue"
			Phase.TOPIC:
				_start_round(0)
				return
			Phase.STATEMENT:
				_show_statement()
				return
			Phase.ROUND_AUDIENCE:
				_after_round_audience()
				return
			Phase.JUDGING:
				_after_judging()
				return
			Phase.DEBRIEF:
				_finish()
				return
			_:
				return


func choose(option_id: String) -> void:
	match phase:
		Phase.TRIGGER:
			_choose_trigger(option_id)
		Phase.PICK_SENTENCE:
			_choose_sentence(int(option_id))
		Phase.PICK_FALLACY:
			_choose_fallacy(int(option_id))
		Phase.REBUTTAL:
			_choose_rebuttal(int(option_id))
		Phase.CLOSING:
			_choose_closing(option_id)
		_:
			push_warning("StoryEngine: 当前阶段没有可选项（%d）" % phase)


# ---------------------------------------------------------------------------
# 流程实现
# ---------------------------------------------------------------------------

func _after_prologue() -> void:
	phase = Phase.TRIGGER
	var trigger: Dictionary = story.get("trigger", {})
	var options: Array = []
	for option in trigger.get("options", []):
		options.append({"id": str(option.get("id", "")), "text": str(option.get("text", ""))})
	_emit({
		"type": "choice",
		"kind": "trigger",
		"line": str(trigger.get("line", "")),
		"prompt": str(trigger.get("question", "你要怎么做？")),
		"options": options,
	})


func _choose_trigger(option_id: String) -> void:
	if option_id == "endure":
		var endure: Dictionary = story.get("endure", {})
		_apply_audience(endure.get("audience", {}))
		phase = Phase.ENDURE
		_dialogue_queue = _as_lines(endure.get("lines", []))
		_pending_after = "_after_endure"
		advance()
	else:
		phase = Phase.TOPIC
		_emit({
			"type": "topic",
			"title": str(story.get("title", "")),
			"topic": story.get("topic", {}),
		})


func _after_endure() -> void:
	_emit_debrief(false, true)


func _start_round(index: int) -> void:
	var rounds: Array = story.get("rounds", [])
	if index >= rounds.size():
		_start_closing()
		return
	round_index = index
	_round = rounds[index]
	phase = Phase.STATEMENT
	_statement_index = 0
	_won_this_round = false
	_sentence_attempts = 0
	_sentence_remedy = false
	_fallacy_remedy = false
	_removed_sentence = -1
	_removed_fallacy = ""
	_pending_hint = ""
	_audience_delta = {"support": 0, "neutral": 0, "oppose": 0}
	_show_statement()


func _show_statement() -> void:
	var statements: Array = _round.get("statements", [])
	if _statement_index >= statements.size():
		_emit_sentence_choice()
		return
	var line: Dictionary = statements[_statement_index]
	_emit({
		"type": "dialogue",
		"speaker": str(_round.get("speaker", "对方")),
		"text": str(line.get("text", "")),
		"meta": {
			"round": round_index + 1,
			"round_total": (story.get("rounds", []) as Array).size(),
			"statement": _statement_index + 1,
			"statement_total": statements.size(),
			"claim": str(_round.get("claim", "")),
			"structure": str(line.get("structure", "")),
		},
	})
	_statement_index += 1


func _flaw_index() -> int:
	var statements: Array = _round.get("statements", [])
	for i in range(statements.size()):
		if bool((statements[i] as Dictionary).get("flaw", false)):
			return i
	return -1


# ---- 第一步：选句子 ----

func _emit_sentence_choice(hint: String = "") -> void:
	var statements: Array = _round.get("statements", [])
	var options: Array = []
	for i in range(statements.size()):
		if i == _removed_sentence:
			continue
		options.append({"id": str(i), "text": str((statements[i] as Dictionary).get("text", ""))})
	_emit({
		"type": "choice",
		"kind": "sentence",
		"prompt": "这三句里，哪一句有问题？" if not _sentence_remedy else "再选一次：哪一句有问题？",
		"hint": hint,
		"statements": statements.duplicate(true),
		"options": options.duplicate(true),
	})
	phase = Phase.PICK_SENTENCE


func _choose_sentence(index: int) -> void:
	var flaw := _flaw_index()
	var statements: Array = _round.get("statements", [])
	if index >= 0 and index < statements.size():
		history.append({
			"round": round_index + 1,
			"type": "sentence",
			"text": str((statements[index] as Dictionary).get("text", "")),
			"ok": index == flaw,
		})
	if index == flaw:
		_emit_fallacy_choice()
		return
	if not _sentence_remedy:
		_sentence_remedy = true
		_sentence_attempts = 1
		_removed_sentence = index
		_apply_audience({"support": -3, "neutral": -2, "oppose": 2})
		phase = Phase.PICK_SENTENCE
		var wrong_speaker := str(_round.get("speaker", "对方"))
		_emit({"type": "result", "kind": "wrong", "text": "%s：「你看错了重点。我说的不是这句。」" % wrong_speaker})
		_pending_after = "_after_sentence_wrong"
		var hint := str((_round.get("remedy", {}) as Dictionary).get("hint", ""))
		_pending_hint = hint
	else:
		_fallback("老周：「连哪句有问题都看不出来，你还想跟我辩？」")


func _after_sentence_wrong() -> void:
	_emit_sentence_choice(_pending_hint)
	_pending_hint = ""


# ---- 第二步：选谬误类型 ----

func _emit_fallacy_choice() -> void:
	phase = Phase.PICK_FALLACY
	var question: Dictionary = _round.get("question", {})
	var raw_options: Array = question.get("options", [])
	var options: Array = []
	for i in range(raw_options.size()):
		var option: Dictionary = raw_options[i]
		if str(option.get("text", "")) == _removed_fallacy:
			continue
		options.append({"id": str(i), "text": str(option.get("text", ""))})
	_emit({
		"type": "choice",
		"kind": "flaw",
		"prompt": str(question.get("prompt", "这句话错在哪？")),
		"hint": _pending_hint if _fallacy_remedy else "",
		"options": options.duplicate(true),
	})


func _choose_fallacy(index: int) -> void:
	var question: Dictionary = _round.get("question", {})
	var raw_options: Array = question.get("options", [])
	if index < 0 or index >= raw_options.size():
		_fallback("")
		return
	var option: Dictionary = raw_options[index]
	var correct := bool(option.get("correct", false))
	history.append({
		"round": round_index + 1,
		"type": "fallacy",
		"text": str(option.get("text", "")),
		"ok": correct,
	})
	var correct_data: Dictionary = _round.get("correct", {})
	if correct:
		var half := _sentence_remedy or _fallacy_remedy
		if half:
			remedies_used += 1
			_apply_audience(_halve(correct_data.get("audience", {})))
			_emit({
				"type": "result",
				"kind": "remedy_ok",
				"text": "你补了一句：「……是我说岔了。」" + str(correct_data.get("reply", "")),
				"judge_note": str(correct_data.get("judge_note", "")),
				"cards": correct_data.get("cards", []),
			})
		else:
			rounds_won += 1
			correct_first += 1
			_won_this_round = true
			_apply_audience(correct_data.get("audience", {}))
			_emit({
				"type": "result",
				"kind": "correct",
				"text": str(correct_data.get("reply", "")),
				"judge_note": str(correct_data.get("judge_note", "")),
				"cards": correct_data.get("cards", []),
			})
		_pending_after = "_emit_rebuttal"
		return
	# 选错（第二次仍错 → 兜底）
	if _fallacy_remedy:
		_fallback(str(option.get("wrong_reply", "")))
		return
	_apply_audience(option.get("audience", {}))
	_removed_fallacy = str(option.get("text", ""))
	_fallacy_remedy = true
	_emit({"type": "result", "kind": "wrong", "text": str(option.get("wrong_reply", "%s：「你再想想。」" % str(_round.get("speaker", "对方"))))})
	_pending_hint = str((_round.get("remedy", {}) as Dictionary).get("hint", ""))
	_pending_after = "_after_fallacy_wrong"


func _after_fallacy_wrong() -> void:
	_emit_fallacy_choice()


# ---- 反驳出牌 ----

func _emit_rebuttal() -> void:
	phase = Phase.REBUTTAL
	var rebuttal: Dictionary = _round.get("rebuttal", {})
	var raw_options: Array = rebuttal.get("options", [])
	var options: Array = []
	for i in range(raw_options.size()):
		options.append({"id": str(i), "text": str((raw_options[i] as Dictionary).get("text", ""))})
	_emit({
		"type": "choice",
		"kind": "rebuttal",
		"prompt": str(rebuttal.get("prompt", "选一个最有力的回法")),
		"options": options.duplicate(true),
	})


func _choose_rebuttal(index: int) -> void:
	var rebuttal: Dictionary = _round.get("rebuttal", {})
	var raw_options: Array = rebuttal.get("options", [])
	if index < 0 or index >= raw_options.size():
		return
	var option: Dictionary = raw_options[index]
	history.append({
		"round": round_index + 1,
		"type": "rebuttal",
		"text": str(option.get("text", "")),
		"ok": bool(option.get("correct", false)),
	})
	_apply_audience(option.get("audience", {}))
	_emit({"type": "result", "kind": "rebuttal", "text": str(option.get("result", ""))})
	_pending_after = "_after_rebuttal"


func _after_rebuttal() -> void:
	_show_round_audience()


func _fallback(text: String) -> void:
	var fallback: Dictionary = _round.get("fallback", {})
	_apply_audience(fallback.get("audience", {}))
	phase = Phase.PICK_FALLACY
	_emit({
		"type": "result",
		"kind": "fallback",
		"text": text if text != "" else str(fallback.get("reply", "……")),
	})
	_pending_after = "_after_fallback"


func _after_fallback() -> void:
	_show_round_audience()


func _show_round_audience() -> void:
	phase = Phase.ROUND_AUDIENCE
	_emit({
		"type": "audience",
		"bars": _bar_data(),
		"notes": _round.get("audience_note", []),
		"won": _won_this_round,
		"round": round_index + 1,
		"round_total": (story.get("rounds", []) as Array).size(),
	})


func _after_round_audience() -> void:
	if round_index + 1 < (story.get("rounds", []) as Array).size():
		_start_round(round_index + 1)
	else:
		_start_closing()


func _start_closing() -> void:
	phase = Phase.CLOSING
	var closing: Dictionary = story.get("closing", {})
	var options: Array = []
	for option in closing.get("options", []):
		options.append({"id": str(option.get("id", "")), "text": str(option.get("text", ""))})
	_emit({
		"type": "choice",
		"kind": "closing",
		"prompt": str(closing.get("prompt", "结辩")),
		"options": options,
	})


func _choose_closing(option_id: String) -> void:
	var closing: Dictionary = story.get("closing", {})
	for option in closing.get("options", []):
		if str((option as Dictionary).get("id", "")) == option_id:
			selected_closing = option_id
			_apply_audience((option as Dictionary).get("audience", {}))
			_emit({"type": "result", "kind": "closing", "text": str((option as Dictionary).get("text", ""))})
			break
	_pending_after = "_after_closing"


func _after_closing() -> void:
	_judge_votes = _compute_judge_votes()
	var you_votes := 0
	for vote in _judge_votes:
		if bool((vote as Dictionary).get("you", false)):
			you_votes += 1
	var win := you_votes >= 2
	phase = Phase.JUDGING
	_emit({
		"type": "judging",
		"votes": _judge_votes,
		"you_votes": you_votes,
		"win": win,
		"closing": selected_closing,
	})
	result = {"win": win, "early": false, "you_votes": you_votes, "votes": _judge_votes}


func _after_judging() -> void:
	var epilogue_key := "epilogue_win" if bool(result.get("win", false)) else "epilogue_lose"
	phase = Phase.EPILOGUE
	_dialogue_queue = _as_lines(story.get(epilogue_key, []))
	_pending_after = "_after_epilogue"
	advance()


func _after_epilogue() -> void:
	_emit_debrief(bool(result.get("win", false)), false)


func _emit_debrief(win: bool, early: bool) -> void:
	phase = Phase.DEBRIEF
	var debrief: Dictionary = story.get("debrief", {})
	result = {
		"win": win,
		"early": early,
		"you_votes": int(result.get("you_votes", 0)),
		"votes": result.get("votes", _judge_votes),
		"rounds_won": rounds_won,
		"correct_first": correct_first,
		"remedies": remedies_used,
		"audience": audience.duplicate(),
	}
	var note := str(debrief.get("note", ""))
	if early:
		note = str((story.get("endure", {}) as Dictionary).get("debrief_note", note))
	_emit({
		"type": "debrief",
		"win": win,
		"early": early,
		"stats": {
			"rounds_won": rounds_won,
			"correct_first": correct_first,
			"remedies": remedies_used,
			"audience": audience.duplicate(),
		},
		"note": note,
		"fallacies": debrief.get("fallacies", []),
		"quiz": debrief.get("quiz", []),
		"history": history.duplicate(true),
	})


func _finish() -> void:
	phase = Phase.ENDED
	finished.emit(result)


# ---------------------------------------------------------------------------
# 工具
# ---------------------------------------------------------------------------

## 逃生阀：如果 UI 出现异常（例如选项为空）导致当前阶段无法继续，用它强制推进。
## 正常流程不会调用；只在 UI 检测到“空选项”时兜底，保证玩家永远卡不死。
func force_continue() -> void:
	match phase:
		Phase.TRIGGER:
			_choose_trigger("speak")
		Phase.PICK_SENTENCE:
			_choose_sentence(-1)
		Phase.PICK_FALLACY:
			_fallback("")
		Phase.REBUTTAL:
			_after_rebuttal()
		Phase.CLOSING:
			_choose_closing("A")
		Phase.DEBRIEF:
			_finish()
		_:
			advance()


func _execute(action: String) -> void:
	match action:
		"_after_prologue":
			_after_prologue()
		"_after_endure":
			_after_endure()
		"_after_sentence_wrong":
			_after_sentence_wrong()
		"_after_fallacy_wrong":
			_after_fallacy_wrong()
		"_emit_rebuttal":
			_emit_rebuttal()
		"_after_rebuttal":
			_after_rebuttal()
		"_after_fallback":
			_after_fallback()
		"_after_round_audience":
			_after_round_audience()
		"_after_closing":
			_after_closing()
		"_after_judging":
			_after_judging()
		"_after_epilogue":
			_after_epilogue()
		_:
			push_warning("StoryEngine: 未知流程动作 '%s'" % action)


func _emit(view: Dictionary) -> void:
	current_view = view
	view_changed.emit(view)


func _emit_dialogue(line: Dictionary) -> void:
	_emit({
		"type": "dialogue",
		"speaker": str(line.get("speaker", "")),
		"text": str(line.get("text", "")),
		"meta": line.get("meta", {}),
	})


func _as_lines(raw: Variant) -> Array:
	var lines: Array = []
	if raw is Array:
		for entry in (raw as Array):
			if entry is Dictionary:
				lines.append((entry as Dictionary).duplicate(true))
	return lines


func _apply_audience(delta: Variant) -> void:
	if not delta is Dictionary:
		return
	for key in AUDIENCE_KEYS:
		var change := int((delta as Dictionary).get(key, 0))
		if change == 0:
			continue
		audience[key] = clampi(int(audience[key]) + change, 0, 100)
		_audience_delta[key] = int(_audience_delta[key]) + change


func _halve(delta: Variant) -> Dictionary:
	var out := {"support": 0, "neutral": 0, "oppose": 0}
	if delta is Dictionary:
		for key in AUDIENCE_KEYS:
			out[key] = int(round(float((delta as Dictionary).get(key, 0)) * 0.5))
	return out


func _bar_data() -> Array:
	var labels: Dictionary = (story.get("topic", {}) as Dictionary).get("audience_labels", {})
	var bars: Array = []
	for key in AUDIENCE_KEYS:
		bars.append({
			"key": key,
			"label": str(labels.get(key, key)),
			"value": int(audience[key]),
			"delta": int(_audience_delta[key]),
		})
	return bars


func _compute_judge_votes() -> Array:
	var votes: Array = []
	for judge in story.get("judges", []):
		var judge_dict: Dictionary = judge
		var rule: Dictionary = judge_dict.get("rule", {})
		var ok := true
		if rule.has("min_correct_first") and correct_first < int(rule["min_correct_first"]):
			ok = false
		if rule.has("min_rounds_won") and rounds_won < int(rule["min_rounds_won"]):
			ok = false
		if rule.has("min_support") and int(audience["support"]) < int(rule["min_support"]):
			ok = false
		if rule.has("closing_in") and not (rule["closing_in"] as Array).has(selected_closing):
			ok = false
		votes.append({
			"name": str(judge_dict.get("name", "评委")),
			"bias": str(judge_dict.get("bias", "")),
			"you": ok,
		})
	return votes
