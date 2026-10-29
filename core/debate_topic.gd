class_name DebateTopic
extends Resource
## 辩题：把一场抽象卡牌对战锚定成"有命题、有立场、有代价"的吵架。
##
## 结构：
##   辩题（proposition / your_side / npc_side / stake）
##   └─ 3 个争点（claims），一个接一个被争夺
##        └─ 每个争点有标签（tag = 对方话术的性质）与素材库（material = 可引用的事实/细节）
##
## 「有效手法」由克制矩阵自动推出：能克制 claim.tag 的标签，就是能赢下这个争点的手法。

@export var id: String = ""
@export var scene: String = ""
@export var title: String = ""
@export var proposition: String = ""
@export var your_side: String = ""
@export var npc_side: String = ""
@export var stake: String = ""
@export var flavor: String = ""
@export var claims: Array = []
@export var opening: Dictionary = {}
@export var debrief: Dictionary = {}


static func from_dict(data: Dictionary) -> DebateTopic:
	var topic := DebateTopic.new()
	topic.id = str(data.get("id", ""))
	topic.scene = str(data.get("scene", ""))
	topic.title = str(data.get("title", ""))
	topic.proposition = str(data.get("proposition", ""))
	topic.your_side = str(data.get("your_side", ""))
	topic.npc_side = str(data.get("npc_side", ""))
	topic.stake = str(data.get("stake", ""))
	topic.flavor = str(data.get("flavor", ""))
	var raw_claims: Variant = data.get("claims", [])
	if raw_claims is Array:
		topic.claims = (raw_claims as Array).duplicate(true)
	var raw_open: Variant = data.get("opening", {})
	if raw_open is Dictionary:
		topic.opening = (raw_open as Dictionary).duplicate(true)
	var raw_debrief: Variant = data.get("debrief", {})
	if raw_debrief is Dictionary:
		topic.debrief = (raw_debrief as Dictionary).duplicate(true)
	return topic


func claim_count() -> int:
	return claims.size()


func claim_text(index: int) -> String:
	if index < 0 or index >= claims.size():
		return ""
	return str((claims[index] as Dictionary).get("text", ""))


func claim_tag(index: int) -> LogicCard.LogicTag:
	if index < 0 or index >= claims.size():
		return LogicCard.LogicTag.LOGIC
	return LogicCard.tag_from_string(str((claims[index] as Dictionary).get("tag", "LOGIC")))


func claim_npc_lines(index: int) -> Array:
	if index < 0 or index >= claims.size():
		return []
	var lines: Variant = (claims[index] as Dictionary).get("npc_lines", [])
	if lines is Array:
		return lines
	return []


func claim_materials(index: int) -> Array:
	if index < 0 or index >= claims.size():
		return []
	var materials: Variant = (claims[index] as Dictionary).get("material", [])
	if materials is Array:
		return materials
	return []


func claim_lesson(index: int) -> String:
	if index < 0 or index >= claims.size():
		return ""
	return str((claims[index] as Dictionary).get("lesson", ""))


func opening_line(who: String) -> String:
	return str(opening.get(who, ""))


func debrief_line(result_key: String) -> String:
	return str(debrief.get(result_key, ""))
