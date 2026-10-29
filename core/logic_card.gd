class_name LogicCard
extends Resource
## 一张逻辑卡。完全由 res://data/cards.json 驱动（数据与逻辑分离）。

enum CardType { CONSTRUCTION, DECONSTRUCTION, PIVOT }
enum LogicTag { FACT, EMOTION, VALUE, LOGIC }

const TYPE_LABELS := {
	CardType.CONSTRUCTION: "构建",
	CardType.DECONSTRUCTION: "拆解",
	CardType.PIVOT: "诡辩",
}

const TAG_LABELS := {
	LogicTag.FACT: "事实",
	LogicTag.EMOTION: "情绪",
	LogicTag.VALUE: "价值",
	LogicTag.LOGIC: "逻辑",
}

@export var id: String = ""
@export var owner_id: String = ""
@export var card_name: String = ""
@export var dialogue: String = ""
@export var card_type: CardType = CardType.CONSTRUCTION
@export var tag: LogicTag = LogicTag.VALUE
@export var cost: int = 1
@export var base_damage: int = 0
## 对方“哑口无言”时额外造成的固定伤害（破防惩罚的基础值，0 = 无额外惩罚）。
@export var silence_penalty: int = 0
## 打出该卡时自身承受的心气损失（诡辩卡的代价）。
@export var self_damage: int = 0
## 作为主动牌打出时执行的效果操作列表。
@export var effects: Array = []
## 在响应窗口内成功拆解 / 反打时执行的效果操作列表。
@export var counter_effects: Array = []
## 台词层：这张牌在辩论里属于什么「手法」（言语行为）。
@export var move_name: String = "陈述"
## 这张牌可能踩到的逻辑谬误（空字符串 = 不是谬误）。
@export var move_fallacy: String = ""
## 复盘时对这条谬误的一句人话解释。
@export var move_lesson: String = ""
## 主动打出时的台词模板，支持 {claim} {material} {topic} {last_move} 等变量。
@export var target_template: String = ""
## 作为回应打出时的台词模板（拆解 / 诡辩卡使用）。
@export var reply_template: String = ""


static func type_from_string(raw: String) -> CardType:
	match raw.strip_edges().to_upper():
		"CONSTRUCTION", "B", "BUILD", "CONSTRUCT":
			return CardType.CONSTRUCTION
		"DECONSTRUCTION", "D", "COUNTER":
			return CardType.DECONSTRUCTION
		"PIVOT", "P":
			return CardType.PIVOT
	push_warning("LogicCard: 未知卡牌类型 '%s'，回退为 CONSTRUCTION" % raw)
	return CardType.CONSTRUCTION


static func tag_from_string(raw: String) -> LogicTag:
	match raw.strip_edges().to_upper():
		"FACT":
			return LogicTag.FACT
		"EMOTION":
			return LogicTag.EMOTION
		"VALUE":
			return LogicTag.VALUE
		"LOGIC":
			return LogicTag.LOGIC
	push_warning("LogicCard: 未知逻辑标签 '%s'，回退为 LOGIC" % raw)
	return LogicTag.LOGIC


static func type_label_of(value: int) -> String:
	return TYPE_LABELS.get(value, "未知")


static func tag_label_of(value: int) -> String:
	return TAG_LABELS.get(value, "未知")


static func tag_color_of(value: int) -> Color:
	match value:
		LogicTag.FACT:
			return Color("#7fa7c4")
		LogicTag.EMOTION:
			return Color("#c48f8f")
		LogicTag.VALUE:
			return Color("#c4b47f")
		LogicTag.LOGIC:
			return Color("#9fb8a0")
	return Color("#b9b3a6")


static func from_dict(data: Dictionary) -> LogicCard:
	var card := LogicCard.new()
	card.id = str(data.get("id", ""))
	card.owner_id = str(data.get("owner", ""))
	card.card_name = str(data.get("name", "无名卡"))
	card.dialogue = str(data.get("dialogue", ""))
	card.card_type = type_from_string(str(data.get("type", "CONSTRUCTION")))
	card.tag = tag_from_string(str(data.get("tag", "VALUE")))
	card.cost = int(data.get("cost", 1))
	card.base_damage = int(data.get("damage", 0))
	card.silence_penalty = int(data.get("silence_penalty", 0))
	card.self_damage = int(data.get("self_damage", 0))
	var fx: Variant = data.get("effects", [])
	if fx is Array:
		card.effects = (fx as Array).duplicate(true)
	var cfx: Variant = data.get("counter_effects", [])
	if cfx is Array:
		card.counter_effects = (cfx as Array).duplicate(true)
	var move: Variant = data.get("move", {})
	if move is Dictionary:
		card.move_name = str((move as Dictionary).get("name", "陈述"))
		card.move_fallacy = str((move as Dictionary).get("fallacy", ""))
		card.move_lesson = str((move as Dictionary).get("lesson", ""))
	card.target_template = str(data.get("target", ""))
	card.reply_template = str(data.get("reply", ""))
	return card


func type_key() -> String:
	match card_type:
		CardType.CONSTRUCTION:
			return "CONSTRUCTION"
		CardType.DECONSTRUCTION:
			return "DECONSTRUCTION"
		CardType.PIVOT:
			return "PIVOT"
	return "CONSTRUCTION"


func tag_key() -> String:
	match tag:
		LogicTag.FACT:
			return "FACT"
		LogicTag.EMOTION:
			return "EMOTION"
		LogicTag.VALUE:
			return "VALUE"
		LogicTag.LOGIC:
			return "LOGIC"
	return "LOGIC"


func type_label() -> String:
	return type_label_of(card_type)


func tag_label() -> String:
	return tag_label_of(tag)


func tag_color() -> Color:
	return tag_color_of(tag)


func is_attack() -> bool:
	return base_damage > 0


## 辩论里的「手法」标签，用于对白与复盘。
func move_label() -> String:
	if move_name == "":
		return "陈述"
	if move_fallacy != "":
		return "%s（%s）" % [move_name, move_fallacy]
	return move_name


func has_fallacy() -> bool:
	return move_fallacy != ""


func has_target_template() -> bool:
	return target_template != ""


func has_reply_template() -> bool:
	return reply_template != ""


func header_text() -> String:
	return "%s · %s" % [type_label(), tag_label()]


## UI 悬浮提示用的完整说明（不含效果细节，效果由 statuses / 引擎解释）。
func tooltip_text() -> String:
	var lines: Array[String] = []
	lines.append("%s〔%s · %s｜消耗 %d AP〕" % [card_name, type_label(), tag_label(), cost])
	if dialogue != "":
		lines.append("「%s」" % dialogue)
	if base_damage > 0:
		lines.append("基础伤害：%d" % base_damage)
	if silence_penalty > 0:
		lines.append("对方哑口无言：额外 +%d 心气伤害" % silence_penalty)
	if self_damage > 0:
		lines.append("代价：自身 -%d 心气" % self_damage)
	return "\n".join(lines)
