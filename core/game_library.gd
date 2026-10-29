class_name GameLibrary
extends RefCounted
## 静态数据库：从 res://data/*.json 读取卡牌 / 角色 / 场景 / 状态，并构建克制矩阵。
##
## 单例通过 GameLibrary.shared() 获取；不依赖 Autoload，因此可以在
## headless 测试脚本里独立实例化。

const CARDS_PATH := "res://data/cards.json"
const CHARACTERS_PATH := "res://data/characters.json"
const SCENARIOS_PATH := "res://data/scenarios.json"
const STATUSES_PATH := "res://data/statuses.json"
const TOPICS_PATH := "res://data/topics.json"
const STORIES_PATH := "res://data/stories.json"

const FIT_BONUS := 2.0

static var _shared: GameLibrary = null

var cards: Dictionary = {}       # card_id -> LogicCard
var characters: Dictionary = {}  # char_id -> CharacterResource
var scenarios: Dictionary = {}   # scenario_id -> ScenarioResource
var statuses: Dictionary = {}    # status_id -> StatusDef
var topics: Dictionary = {}      # topic_id -> DebateTopic
var stories: Dictionary = {}     # story_id -> Dictionary（故事模式脚本）
var fit_matrix: Dictionary = {}  # 攻击标签(int) -> {被克制标签(int): 倍率}
var load_errors: Array[String] = []


static func shared() -> GameLibrary:
	if _shared == null:
		_shared = GameLibrary.new()
		_shared.load_all()
	return _shared


static func reset_shared() -> void:
	_shared = null


func load_all() -> void:
	load_errors.clear()
	cards.clear()
	characters.clear()
	scenarios.clear()
	statuses.clear()
	topics.clear()
	stories.clear()
	fit_matrix.clear()
	_load_statuses()
	_load_cards()
	_load_characters()
	_load_scenarios()
	_load_topics()
	_load_stories()
	_build_fit_matrix()
	for error_text in load_errors:
		push_error("[GameLibrary] " + error_text)


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		load_errors.append("缺少数据文件：%s" % path)
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		load_errors.append("无法打开数据文件：%s" % path)
		return null
	var text := file.get_as_text()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		load_errors.append("JSON 解析失败：%s" % path)
		return null
	return parsed


func _load_statuses() -> void:
	var raw: Variant = _read_json(STATUSES_PATH)
	if not raw is Dictionary:
		if raw != null:
			load_errors.append("statuses.json 顶层必须是对象")
		return
	for key in (raw as Dictionary).keys():
		var entry: Variant = (raw as Dictionary)[key]
		if entry is Dictionary:
			statuses[str(key)] = StatusDef.from_dict(str(key), entry)
		else:
			load_errors.append("状态 '%s' 定义格式错误" % str(key))


func _load_cards() -> void:
	var raw: Variant = _read_json(CARDS_PATH)
	if not raw is Array:
		if raw != null:
			load_errors.append("cards.json 顶层必须是数组")
		return
	for entry in (raw as Array):
		if not entry is Dictionary:
			load_errors.append("卡牌条目格式错误（不是对象）")
			continue
		var card := LogicCard.from_dict(entry)
		if card.id == "":
			load_errors.append("存在没有 id 的卡牌：%s" % card.card_name)
			continue
		if cards.has(card.id):
			load_errors.append("卡牌 id 重复：%s" % card.id)
			continue
		if card.owner_id == "":
			load_errors.append("卡牌 '%s' 缺少 owner" % card.id)
		cards[card.id] = card


func _load_characters() -> void:
	var raw: Variant = _read_json(CHARACTERS_PATH)
	if not raw is Array:
		if raw != null:
			load_errors.append("characters.json 顶层必须是数组")
		return
	for entry in (raw as Array):
		if not entry is Dictionary:
			load_errors.append("角色条目格式错误（不是对象）")
			continue
		var character := CharacterResource.from_dict(entry)
		if character.id == "":
			load_errors.append("存在没有 id 的角色：%s" % character.char_name)
			continue
		characters[character.id] = character
	# 把卡牌按 owner 归入角色卡组
	for card_id in cards.keys():
		var card: LogicCard = cards[card_id]
		if characters.has(card.owner_id):
			characters[card.owner_id].deck.append(card)
		else:
			load_errors.append("卡牌 '%s' 的 owner '%s' 不存在" % [card.id, card.owner_id])
	for character_id in characters.keys():
		var character: CharacterResource = characters[character_id]
		if character.deck.size() < 10:
			load_errors.append("角色 '%s' 卡组只有 %d 张（至少 10 张）" % [character.char_name, character.deck.size()])


func _load_scenarios() -> void:
	var raw: Variant = _read_json(SCENARIOS_PATH)
	if not raw is Array:
		if raw != null:
			load_errors.append("scenarios.json 顶层必须是数组")
		return
	for entry in (raw as Array):
		if not entry is Dictionary:
			load_errors.append("场景条目格式错误（不是对象）")
			continue
		var scenario := ScenarioResource.from_dict(entry)
		if scenario.id == "":
			load_errors.append("存在没有 id 的场景")
			continue
		scenarios[scenario.id] = scenario


func _load_topics() -> void:
	var raw: Variant = _read_json(TOPICS_PATH)
	if not raw is Array:
		if raw != null:
			load_errors.append("topics.json 顶层必须是数组")
		return
	for entry in (raw as Array):
		if not entry is Dictionary:
			load_errors.append("辩题条目格式错误（不是对象）")
			continue
		var topic := DebateTopic.from_dict(entry)
		if topic.id == "":
			load_errors.append("存在没有 id 的辩题")
			continue
		if topic.scene != "" and not scenarios.has(topic.scene):
			load_errors.append("辩题 '%s' 绑定的场景 '%s' 不存在" % [topic.id, topic.scene])
		if topic.claims.is_empty():
			load_errors.append("辩题 '%s' 没有争点" % topic.id)
		for index in range(topic.claims.size()):
			var claim: Variant = topic.claims[index]
			if not claim is Dictionary:
				load_errors.append("辩题 '%s' 的第 %d 个争点格式错误" % [topic.id, index + 1])
				continue
			if topic.claim_text(index) == "":
				load_errors.append("辩题 '%s' 的第 %d 个争点没有文本" % [topic.id, index + 1])
			if topic.claim_materials(index).is_empty():
				load_errors.append("辩题 '%s' 的第 %d 个争点没有素材（模板里的 {material} 会为空）" % [topic.id, index + 1])
		topics[topic.id] = topic


## 按场景找辩题；没有绑定辩题的场景返回 null（退化为纯卡牌对战）。
func topic_for_scene(scene_id: String) -> DebateTopic:
	for topic_id in topics.keys():
		var topic: DebateTopic = topics[topic_id]
		if topic.scene == scene_id:
			return topic
	return null


func topic_for_id(topic_id: String) -> DebateTopic:
	return topics.get(topic_id)


func _build_fit_matrix() -> void:
	var t := LogicCard.LogicTag
	var beats := {
		t.FACT: t.EMOTION,
		t.EMOTION: t.VALUE,
		t.VALUE: t.LOGIC,
		t.LOGIC: t.FACT,
	}
	for attacker_tag in beats.keys():
		fit_matrix[attacker_tag] = {beats[attacker_tag]: FIT_BONUS}


## 返回攻击标签对防守标签的契合倍率（1.0 或 2.0）。
func fit_multiplier(attacker_tag: int, defender_tag: int) -> float:
	var row: Variant = fit_matrix.get(attacker_tag, {})
	if row is Dictionary:
		return float((row as Dictionary).get(defender_tag, 1.0))
	return 1.0


func fits(attacker_tag: int, defender_tag: int) -> bool:
	return fit_multiplier(attacker_tag, defender_tag) > 1.0


func cards_of(character_id: String) -> Array[LogicCard]:
	var character: CharacterResource = characters.get(character_id)
	if character == null:
		return []
	return character.deck


## 返回缺失的 status id 列表（给数据自检用）。
func missing_status_references() -> Array[String]:
	var missing: Array[String] = []
	for card_id in cards.keys():
		var card: LogicCard = cards[card_id]
		for op_list in [card.effects, card.counter_effects]:
			_collect_status_refs(op_list, missing)
	return missing


func _collect_status_refs(ops: Variant, missing: Array[String]) -> void:
	if not ops is Array:
		return
	for op in (ops as Array):
		if not op is Dictionary:
			continue
		var dict := op as Dictionary
		if str(dict.get("op", "")) == "status":
			var status_id := str(dict.get("id", ""))
			if status_id != "" and not statuses.has(status_id) and not missing.has(status_id):
				missing.append(status_id)
		for nested_key in ["then", "else"]:
			if dict.has(nested_key):
				_collect_status_refs(dict[nested_key], missing)
		if dict.has("options"):
			for option in (dict["options"] as Array):
				_collect_status_refs(option, missing)


# ---------------------------------------------------------------------------
# 故事模式
# ---------------------------------------------------------------------------

func _load_stories() -> void:
	var raw: Variant = _read_json(STORIES_PATH)
	if not raw is Array:
		if raw != null:
			load_errors.append("stories.json 顶层必须是数组")
		return
	for entry in (raw as Array):
		if not entry is Dictionary:
			load_errors.append("故事条目格式错误（不是对象）")
			continue
		var story := (entry as Dictionary).duplicate(true)
		var story_id := str(story.get("id", ""))
		if story_id == "":
			load_errors.append("存在没有 id 的故事")
			continue
		if stories.has(story_id):
			load_errors.append("故事 id 重复：%s" % story_id)
			continue
		_validate_story(story, story_id)
		stories[story_id] = story


func story_for_scene(scene_id: String) -> Dictionary:
	for story_id in stories.keys():
		var story: Dictionary = stories[story_id]
		if str(story.get("scene_id", "")) == scene_id:
			return story
	return {}


func story_for_id(story_id: String) -> Dictionary:
	return stories.get(story_id, {})


## 数据自检：任何“点了没反应”的隐患都必须在加载期报错。
func _validate_story(story: Dictionary, story_id: String) -> void:
	for key in ["title", "scene_card", "prologue", "trigger", "topic", "rounds", "closing", "judges", "debrief"]:
		if not story.has(key):
			load_errors.append("故事 '%s' 缺少字段 %s" % [story_id, key])
	var rounds: Variant = story.get("rounds", [])
	if not rounds is Array or (rounds as Array).is_empty():
		load_errors.append("故事 '%s' 没有回合" % story_id)
		return
	for index in range((rounds as Array).size()):
		_validate_round(story_id, index, (rounds as Array)[index])
	var trigger: Variant = story.get("trigger", {})
	if trigger is Dictionary:
		var options: Array = (trigger as Dictionary).get("options", [])
		if options.size() < 2:
			load_errors.append("故事 '%s' 的分歧选择至少要有 2 个选项" % story_id)
	var judges: Variant = story.get("judges", [])
	if not judges is Array or (judges as Array).size() != 3:
		load_errors.append("故事 '%s' 需要 3 位评委" % story_id)
	var closing: Variant = story.get("closing", {})
	if closing is Dictionary:
		var items: Array = (closing as Dictionary).get("options", [])
		if items.is_empty():
			load_errors.append("故事 '%s' 缺少结辩选项" % story_id)


func _validate_round(story_id: String, index: int, raw_round: Variant) -> void:
	if not raw_round is Dictionary:
		load_errors.append("故事 '%s' 第 %d 回合格式错误" % [story_id, index + 1])
		return
	var round_data: Dictionary = raw_round
	var statements: Array = round_data.get("statements", [])
	if statements.size() < 2:
		load_errors.append("故事 '%s' 第 %d 回合陈词少于 2 句" % [story_id, index + 1])
	var flaw_count := 0
	for statement in statements:
		if bool((statement as Dictionary).get("flaw", false)):
			flaw_count += 1
	if flaw_count != 1:
		load_errors.append("故事 '%s' 第 %d 回合必须恰好有 1 个漏洞句（当前 %d）" % [story_id, index + 1, flaw_count])
	var question: Variant = round_data.get("question", {})
	if question is Dictionary:
		var options: Array = (question as Dictionary).get("options", [])
		var correct := 0
		for option in options:
			var option_dict: Dictionary = option
			if bool(option_dict.get("correct", false)):
				correct += 1
			elif str(option_dict.get("wrong_reply", "")) == "":
				load_errors.append("故事 '%s' 第 %d 回合的错误选项 '%s' 缺少 wrong_reply（会导致点了没反应）" % [story_id, index + 1, str(option_dict.get("text", ""))])
		if correct != 1:
			load_errors.append("故事 '%s' 第 %d 回合必须恰好有 1 个正确谬误选项" % [story_id, index + 1])
		if options.size() < 3 or options.size() > 4:
			load_errors.append("故事 '%s' 第 %d 回合的谬误选项应为 3~4 个" % [story_id, index + 1])
	if str((round_data.get("correct", {}) as Dictionary).get("reply", "")) == "":
		load_errors.append("故事 '%s' 第 %d 回合缺少正确的反驳台词" % [story_id, index + 1])
	var rebuttal: Variant = round_data.get("rebuttal", {})
	if rebuttal is Dictionary:
		var rebuttal_options: Array = (rebuttal as Dictionary).get("options", [])
		var rebuttal_correct := 0
		for option in rebuttal_options:
			var option_dict: Dictionary = option
			if bool(option_dict.get("correct", false)):
				rebuttal_correct += 1
			if str(option_dict.get("result", "")) == "":
				load_errors.append("故事 '%s' 第 %d 回合的反驳选项缺少 result 文案" % [story_id, index + 1])
		if rebuttal_options.size() < 2:
			load_errors.append("故事 '%s' 第 %d 回合至少要有 2 个反驳选项" % [story_id, index + 1])
		if rebuttal_correct != 1:
			load_errors.append("故事 '%s' 第 %d 回合必须恰好有 1 个最优反驳选项" % [story_id, index + 1])
	var remedy: Variant = round_data.get("remedy", {})
	if not remedy is Dictionary or str((remedy as Dictionary).get("hint", "")) == "":
		load_errors.append("故事 '%s' 第 %d 回合缺少补救提示" % [story_id, index + 1])
	if not round_data.has("fallback"):
		load_errors.append("故事 '%s' 第 %d 回合缺少兜底分支" % [story_id, index + 1])
