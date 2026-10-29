class_name CharacterResource
extends Resource
## 角色原型：专属逻辑标签倾向、被动、AI 性格权重、专属卡组。

@export var id: String = ""
@export var char_name: String = ""
@export var title: String = ""
@export var tagline: String = ""
@export var affinity_tag: LogicCard.LogicTag = LogicCard.LogicTag.LOGIC
@export var passive_id: String = ""
@export var passive_name: String = ""
@export var passive_desc: String = ""
@export var accent_color: Color = Color("#c4b47f")
## AI 性格参数：counter_rate（响应率）与 weights（按卡牌类型的出牌偏好）。
@export var ai_profile: Dictionary = {}
## 由 GameLibrary 填充。
var deck: Array[LogicCard] = []


static func from_dict(data: Dictionary) -> CharacterResource:
	var ch := CharacterResource.new()
	ch.id = str(data.get("id", ""))
	ch.char_name = str(data.get("name", "无名角色"))
	ch.title = str(data.get("title", ""))
	ch.tagline = str(data.get("tagline", ""))
	ch.affinity_tag = LogicCard.tag_from_string(str(data.get("affinity", "LOGIC")))
	ch.passive_id = str(data.get("passive", ""))
	ch.passive_name = str(data.get("passive_name", ""))
	ch.passive_desc = str(data.get("passive_desc", ""))
	var accent := str(data.get("accent", "#c4b47f"))
	ch.accent_color = Color.from_string(accent, Color("#c4b47f"))
	var ai: Variant = data.get("ai", {})
	if ai is Dictionary:
		ch.ai_profile = (ai as Dictionary).duplicate(true)
	return ch


func affinity_label() -> String:
	return LogicCard.tag_label_of(affinity_tag)


func affinity_color() -> Color:
	return LogicCard.tag_color_of(affinity_tag)
