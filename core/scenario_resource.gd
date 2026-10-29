class_name ScenarioResource
extends Resource
## 情景（场景）：把战斗放回箱庭世界，本身是一个“环境修正因子”。

@export var id: String = ""
@export var scenario_name: String = ""
@export var description: String = ""
@export var ambient_tag: LogicCard.LogicTag = LogicCard.LogicTag.LOGIC
@export var accent_color: Color = Color("#7fa7c4")
## 环境修正因子，键名由 BattleEngine 解释：
##   damage_by_tag: {TAG: 倍率}
##   pivot_self_damage_mult: 诡辩卡自损倍率
##   counter_heal_by_tag: {TAG: 回复心气}
##   response_time_delta: 全局响应窗口变化（秒）
##   spirit_start: 初始心气
@export var mods: Dictionary = {}


static func from_dict(data: Dictionary) -> ScenarioResource:
	var sc := ScenarioResource.new()
	sc.id = str(data.get("id", ""))
	sc.scenario_name = str(data.get("name", "无名场景"))
	sc.description = str(data.get("desc", ""))
	sc.ambient_tag = LogicCard.tag_from_string(str(data.get("ambient", "LOGIC")))
	sc.accent_color = Color.from_string(str(data.get("accent", "#7fa7c4")), Color("#7fa7c4"))
	var m: Variant = data.get("mods", {})
	if m is Dictionary:
		sc.mods = (m as Dictionary).duplicate(true)
	return sc


func ambient_label() -> String:
	return LogicCard.tag_label_of(ambient_tag)


func damage_mult_for(tag: int) -> float:
	var table: Variant = mods.get("damage_by_tag", {})
	if table is Dictionary:
		# 数据里用字符串键（FACT/EMOTION/...），这里做一次映射。
		for tag_name in (table as Dictionary).keys():
			if LogicCard.tag_from_string(str(tag_name)) == tag:
				return float((table as Dictionary)[tag_name])
	return 1.0
