class_name AIController
extends RefCounted
## AI 的“嘴炮大脑”：响应决策 + 性格权重出牌 + 压力感知。
##
## 设计对应文档里的优先级决策树：
##   1. 生存：心气 ≤ 2 时优先诡辩卡（拼命一搏）
##   2. 拦截：响应窗口里优先用能克制对方的拆解卡
##   3. 节奏：按角色性格权重选择立论 / 拆解 / 诡辩
##   4. 兜底：加权随机，避免每局完全一样


## 主动回合选牌。返回手牌下标，-1 表示放弃（沉默）。
static func choose_action(engine: BattleEngine, side: int) -> int:
	var hand: Array = engine.hand_of(side)
	if hand.is_empty():
		return -1
	var character: CharacterResource = engine.character_of(side)
	var weights: Dictionary = character.ai_profile.get("weights", {})
	var own_spirit := engine.spirit_of(side)
	var enemy_spirit := engine.spirit_of(engine.other_side(side))
	var best_index := -1
	var best_score := -1e20
	for i in range(hand.size()):
		if not engine.can_play(side, i):
			continue
		var card: LogicCard = hand[i]
		var score := float(weights.get(card.type_key(), 1.0))
		score += float(card.base_damage) * 0.45
		if card.tag == character.affinity_tag:
			score += 0.35
		# 辩题层：能拿下当前争点的牌更值得打
		if engine.has_topic() and engine.library.fits(card.tag, engine.current_claim_tag()):
			score += 0.9
		if own_spirit <= 2 and card.card_type == LogicCard.CardType.PIVOT:
			score += 2.2
		if enemy_spirit <= 2 and card.base_damage >= 2:
			score += 1.0
		if card.card_type == LogicCard.CardType.PIVOT:
			score -= float(card.self_damage) * 0.5
			if own_spirit <= 2:
				score -= float(card.self_damage) * 0.6
		if _is_dead_card(engine, side, card):
			score -= 5.0
		# 加权随机：性格越接近的两张牌，出手越随机，避免可预测
		score += engine.rng.randf() * 0.55
		if score > best_score:
			best_score = score
			best_index = i
	return best_index


## 响应窗口选牌。返回手牌下标，-1 表示哑口无言。
static func choose_response(engine: BattleEngine, side: int, attack_card: LogicCard) -> int:
	if attack_card == null or not engine.can_respond_at_all(side):
		return -1
	# 完全无威胁的攻击，不值得浪费 AP
	if attack_card.base_damage <= 0 and engine.rng.randf() < 0.5:
		return -1
	var character: CharacterResource = engine.character_of(side)
	var rate := float(character.ai_profile.get("counter_rate", 0.6))
	rate += float(engine.mods_of(side).get("enemy_response_chance_delta", 0.0))
	rate = clampf(rate, 0.05, 0.98)
	var hand: Array = engine.hand_of(side)
	var best_index := -1
	var best_score := -1e20
	for i in range(hand.size()):
		if not engine.can_respond(side, i):
			continue
		var card: LogicCard = hand[i]
		var score := 0.0
		if card.card_type == LogicCard.CardType.DECONSTRUCTION:
			score = 2.0 if engine.fits(card.tag, attack_card.tag) else 1.0
			score += float(card.base_damage) * 0.2
			if card.tag == character.affinity_tag:
				score += 0.25
			if engine.spirit_of(side) <= 2:
				score += 0.5
			if engine.spirit_of(engine.other_side(side)) <= 2:
				score += 0.6
			if engine.has_topic() and engine.library.fits(card.tag, engine.current_claim_tag()):
				score += 0.4
		elif card.card_type == LogicCard.CardType.PIVOT:
			score = 0.4
			if engine.spirit_of(side) <= 2:
				score += 1.6
				if attack_card.base_damage >= 2:
					score += 0.6
		if score > best_score:
			best_score = score
			best_index = i
	if best_index < 0:
		return -1
	if engine.rng.randf() >= rate:
		return -1
	return best_index


## 判断一张卡在当前局势下是否“完全没用”（例如条件不满足的终结技）。
static func _is_dead_card(engine: BattleEngine, side: int, card: LogicCard) -> bool:
	if card.effects.is_empty():
		return false
	var has_usable := false
	var has_gated_failure := false
	for op in card.effects:
		if not op is Dictionary:
			continue
		var kind := str((op as Dictionary).get("op", ""))
		if kind == "if":
			var cond: Variant = (op as Dictionary).get("cond", {})
			if cond is Dictionary and engine.check_condition(side, cond):
				has_usable = true
			else:
				has_gated_failure = true
		elif kind == "execute":
			if _execute_ready(engine, side, op as Dictionary):
				has_usable = true
			else:
				has_gated_failure = true
		else:
			has_usable = true
	return has_gated_failure and not has_usable


static func _execute_ready(engine: BattleEngine, side: int, op: Dictionary) -> bool:
	var enemy_side := engine.other_side(side)
	var mode := str(op.get("mode", "leading"))
	match mode:
		"leading":
			return engine.spirit_of(side) > engine.spirit_of(enemy_side) and engine.spirit_of(enemy_side) <= int(op.get("enemy_spirit_lte", 3))
		"enemy_below":
			return engine.spirit_of(enemy_side) <= int(op.get("v", 2))
		"chance_win":
			return engine.spirit_of(enemy_side) <= 2
	return false
