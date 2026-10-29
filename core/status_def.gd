class_name StatusDef
extends Resource
## 状态定义（Buff / Debuff）。数值修正通过 mods 字典表达，由 BattleEngine 聚合。
##
## 支持的 mods 键：
##   outgoing_damage_flat          造成伤害 +N
##   outgoing_damage_mult          造成伤害 ×(1+N)
##   incoming_damage_mult          受到伤害 ×(1+N)
##   counter_damage_flat           作为拆解反击时伤害 +N
##   dot                           自己回合开始时损失 N 心气
##   heal_per_turn                 自己回合开始时回复 N 心气
##   ap_delta                      下回合 AP 变化
##   ap_cost_delta                 出牌 AP 消耗 +N
##   response_time_delta           自身防守响应窗口 ±N 秒
##   silence_penalty_mult          “哑口无言”惩罚倍率
##   enemy_response_chance_delta   降低对手反击概率
##   on_attack_self_damage_chance  被攻击时反噬概率
##   on_attack_self_damage         反噬伤害
##   ban_type                      禁止使用某类卡（字符串）
##   ban_response                  是否无法进入响应（1 = 无法响应）

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var kind: String = "debuff"  # buff / debuff / neutral
@export var default_duration: int = 1
@export var mods: Dictionary = {}


static func from_dict(status_id: String, data: Dictionary) -> StatusDef:
	var st := StatusDef.new()
	st.id = status_id
	st.display_name = str(data.get("name", status_id))
	st.description = str(data.get("desc", ""))
	st.kind = str(data.get("kind", "debuff"))
	st.default_duration = int(data.get("duration", 1))
	var m: Variant = data.get("mods", {})
	if m is Dictionary:
		st.mods = (m as Dictionary).duplicate(true)
	return st


func is_buff() -> bool:
	return kind == "buff"


func is_debuff() -> bool:
	return kind == "debuff"


## 生成运行时状态实例（带剩余回合数）。
func make_runtime(duration: int = -1) -> Dictionary:
	return {
		"id": id,
		"name": display_name,
		"kind": kind,
		"desc": description,
		"duration": duration if duration > 0 else default_duration,
		"mods": mods.duplicate(true),
	}
