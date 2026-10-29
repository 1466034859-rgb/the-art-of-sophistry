class_name BattleEngine
extends RefCounted
## 《诡辩之术》战斗内核。
##
## 纯逻辑、无 UI 依赖、可 headless 驱动：
##   * 状态机：AWAITING_ACTION -> WAITING_FOR_RESPONSE -> SETTLING -> 下一回合 / 结束
##   * 响应窗口由外部控制器（玩家 UI 或 AI）倒计时后调用 submit_response()
##   * 所有可见变化都通过 signal 广播，UI 只做表现层
##
## 伤害公式（与设计文档一致）：
##   Final = (Base * Fit * CharBonus + Flat) * OutMult * ScenarioMult
##   之后再乘以目标的 IncomingMult（统一在 _apply_damage 中处理）

signal battle_started(scenario_id: String)
signal turn_started(side: int, turn_number: int)
signal action_needed(side: int)
signal card_played(side: int, card: LogicCard)
signal response_requested(defender_side: int, attack_card: LogicCard, window_seconds: float)
signal response_committed(defender_side: int, card: LogicCard)
signal resolution_finished(info: Dictionary)
signal spirit_changed(side: int, old_value: int, new_value: int)
signal status_changed(side: int, status: Dictionary, added: bool)
signal log_line(text: String, kind: String)
signal battle_ended(winner_side: int, reason: String)
## 辩题层：一个新争点开始 / 一个争点判出胜负。
signal claim_announced(index: int, total: int, claim_text: String, effective_tag: String, npc_line: String)
signal claim_resolved(index: int, winner_side: int, points: Array)

const PLAYER := 0
const ENEMY := 1

const MAX_SPIRIT := 5
const HAND_SIZE := 5
const MAX_HAND := 8
const AP_PER_TURN := 2
const BASE_RESPONSE_WINDOW := 3.0
const MIN_RESPONSE_WINDOW := 1.2
const MAX_TURNS := 60
const FATIGUE_DAMAGE := 1
## 后手补偿：AI 起手多 1 张牌、首回合多 1 点 AP，抵消先手优势。
const SECOND_PLAYER_EXTRA_CARDS := 1
const SECOND_PLAYER_EXTRA_AP := 1
## 单次心气损失上限：防止「克制×角色加成×状态」叠出 5 点一击秒杀。
const DAMAGE_CAP := 4
## 辩题层：先赢下 2 个争点者赢下整场辩论；单个争点最多拉扯 4 次交换。
const CLAIMS_TO_WIN := 2
const CLAIM_MAX_EXCHANGES := 4
## 争点判定时，出手标签克制争点标签的一方获得的「论点压力」加成。
const CLAIM_FIT_BONUS := 2

enum State { IDLE, AWAITING_ACTION, WAITING_FOR_RESPONSE, SETTLING, ENDED }
enum Outcome { SILENCE, PARTIAL, PERFECT, TRADE }

var library: GameLibrary
var rng := RandomNumberGenerator.new()
var scenario: ScenarioResource = null
var sides: Array = []
var state: State = State.IDLE
var turn_side: int = PLAYER
var turn_number: int = 1
var active_card: LogicCard = null
var attacker_side: int = -1
var defender_side: int = -1
var response_window: float = BASE_RESPONSE_WINDOW
var winner_side: int = -1
var finish_reason: String = ""
var event_log: Array[Dictionary] = []
var played_cards: Array[String] = []

## 辩题层状态
var topic: DebateTopic = null
var claim_index: int = -1          # 当前争点下标；-1 = 没有辩题
var claim_exchanges: int = 0       # 当前争点已经拉扯了几次
var claims_state: Array = []       # 每个争点：-1 未决 / 0 玩家赢 / 1 对手赢
var arg_points: Array = [0, 0]  # 论点分
var used_moves: Array[Dictionary] = []  # 复盘用：谁用过什么手法
var last_line: String = ""         # 最近一次渲染出来的台词（UI 直接取用）
var last_speaker_side: int = -1

var _extra_turn: bool = false
var _last_move_name: String = ""
var _last_card_name: String = ""


# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------

func setup_battle(player_id: String, enemy_id: String, scenario_id: String, seed_value: int = -1, topic_id: String = "") -> void:
	library = GameLibrary.shared()
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	scenario = library.scenarios.get(scenario_id)
	if scenario == null:
		for key in library.scenarios.keys():
			scenario = library.scenarios[key]
			break
	# 辩题：显式指定优先，否则按场景自动匹配（没有绑定辩题则退化为纯卡牌对战）
	if topic_id != "":
		topic = library.topic_for_id(topic_id)
	else:
		topic = library.topic_for_scene(scenario_id)
	sides.clear()
	sides.append(_make_side(player_id))
	sides.append(_make_side(enemy_id))
	var start_spirit := MAX_SPIRIT
	if scenario != null:
		start_spirit = int(scenario.mods.get("spirit_start", MAX_SPIRIT))
	for side in [PLAYER, ENEMY]:
		var s: Dictionary = sides[side]
		s.spirit = start_spirit
		s.max_spirit = start_spirit
		_shuffle(s.deck)
	event_log.clear()
	played_cards.clear()
	winner_side = -1
	finish_reason = ""
	active_card = null
	attacker_side = -1
	defender_side = -1
	_extra_turn = false
	turn_number = 1
	claim_index = -1
	claim_exchanges = 0
	claims_state.clear()
	arg_points = [0, 0]
	used_moves.clear()
	last_line = ""
	last_speaker_side = -1
	_last_move_name = ""
	_last_card_name = ""
	if topic != null:
		for i in range(topic.claim_count()):
			claims_state.append(-1)
	_draw_cards(PLAYER, HAND_SIZE)
	_draw_cards(ENEMY, HAND_SIZE + SECOND_PLAYER_EXTRA_CARDS)
	sides[ENEMY].ap_delta = SECOND_PLAYER_EXTRA_AP
	state = State.AWAITING_ACTION
	var scenario_name := scenario.scenario_name if scenario != null else "虚空"
	_emit_log("【%s】%s 与 %s 的对峙开始了。" % [
		scenario_name,
		sides[PLAYER].character.char_name,
		sides[ENEMY].character.char_name,
	], "system")
	battle_started.emit(scenario.id if scenario != null else "")
	if topic != null:
		_emit_log("【辩题】%s" % topic.proposition, "topic")
		_emit_log("你的立场：%s" % topic.your_side, "topic")
		_emit_log("对手的立场：%s" % topic.npc_side, "topic")
		var npc_opening := topic.opening_line("npc")
		if npc_opening != "":
			_emit_log("对方：%s" % npc_opening, "npc")
		_announce_claim(0)
	_begin_turn(PLAYER, true)


func _make_side(character_id: String) -> Dictionary:
	var character: CharacterResource = library.characters.get(character_id)
	if character == null:
		character = CharacterResource.from_dict({"id": character_id, "name": character_id})
	var deck: Array = []
	for card in character.deck:
		deck.append(card)
	return {
		"character": character,
		"spirit": MAX_SPIRIT,
		"max_spirit": MAX_SPIRIT,
		"hand": [],
		"deck": deck,
		"discard": [],
		"in_flight": [],
		"ap": 0,
		"ap_delta": 0,
		"statuses": [],
		"last_damage_taken": 0,
		"cards_played": 0,
	}


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


# ---------------------------------------------------------------------------
# 查询辅助（UI / AI 共用）
# ---------------------------------------------------------------------------

func character_of(side: int) -> CharacterResource:
	return sides[side].character


func spirit_of(side: int) -> int:
	return int(sides[side].spirit)


func max_spirit_of(side: int) -> int:
	return int(sides[side].max_spirit)


func ap_of(side: int) -> int:
	return int(sides[side].ap)


func hand_of(side: int) -> Array:
	return sides[side].hand


func statuses_of(side: int) -> Array:
	return sides[side].statuses


func other_side(side: int) -> int:
	return 1 - side


func discard_of(side: int) -> Array:
	return sides[side].discard


## 聚合该侧所有状态的数值修正。
func mods_of(side: int) -> Dictionary:
	var agg := {
		"outgoing_damage_flat": 0,
		"outgoing_damage_mult": 0.0,
		"incoming_damage_mult": 0.0,
		"counter_damage_flat": 0,
		"dot": 0,
		"heal_per_turn": 0,
		"ap_delta": 0,
		"ap_cost_delta": 0,
		"response_time_delta": 0.0,
		"silence_penalty_mult": 1.0,
		"enemy_response_chance_delta": 0.0,
		"on_attack_self_damage_chance": 0.0,
		"on_attack_self_damage": 0,
		"ban_response": 0,
		"banned_types": [],
	}
	for status in sides[side].statuses:
		var mods: Dictionary = status.get("mods", {})
		for key in mods.keys():
			var mod_value: Variant = mods[key]
			match str(key):
				"outgoing_damage_flat", "counter_damage_flat", "dot", "heal_per_turn", "ap_delta", "ap_cost_delta", "on_attack_self_damage":
					agg[key] = int(agg[key]) + int(mod_value)
				"outgoing_damage_mult", "incoming_damage_mult", "response_time_delta", "enemy_response_chance_delta", "on_attack_self_damage_chance":
					agg[key] = float(agg[key]) + float(mod_value)
				"silence_penalty_mult":
					agg[key] = float(agg[key]) * float(mod_value)
				"ban_response":
					agg[key] = 1
				"ban_type":
					var banned := str(mod_value)
					var banned_list: Array = agg["banned_types"]
					if not banned_list.has(banned):
						banned_list.append(banned)
	return agg


func is_type_banned(side: int, card_type: int) -> bool:
	var banned_list: Array = mods_of(side).get("banned_types", [])
	for entry in banned_list:
		if LogicCard.type_from_string(str(entry)) == card_type:
			return true
	return false


func card_cost(side: int, card: LogicCard) -> int:
	var mods: Dictionary = mods_of(side)
	return maxi(0, card.cost + int(mods.get("ap_cost_delta", 0)))


func can_play(side: int, hand_index: int) -> bool:
	if state != State.AWAITING_ACTION or side != turn_side:
		return false
	var hand: Array = sides[side].hand
	if hand_index < 0 or hand_index >= hand.size():
		return false
	var card: LogicCard = hand[hand_index]
	if is_type_banned(side, card.card_type):
		return false
	return card_cost(side, card) <= ap_of(side)


func can_respond(side: int, hand_index: int) -> bool:
	if state != State.WAITING_FOR_RESPONSE or side != defender_side:
		return false
	var hand: Array = sides[side].hand
	if hand_index < 0 or hand_index >= hand.size():
		return false
	if int(mods_of(side).get("ban_response", 0)) == 1:
		return false
	var card: LogicCard = hand[hand_index]
	if card.card_type == LogicCard.CardType.CONSTRUCTION:
		return false
	if is_type_banned(side, card.card_type):
		return false
	return card_cost(side, card) <= ap_of(side)


func can_respond_at_all(side: int) -> bool:
	if state != State.WAITING_FOR_RESPONSE or side != defender_side:
		return false
	if int(mods_of(side).get("ban_response", 0)) == 1:
		return false
	for i in range(sides[side].hand.size()):
		if can_respond(side, i):
			return true
	return false


func fits(attacker_tag: int, defender_tag: int) -> bool:
	return library.fit_multiplier(attacker_tag, defender_tag) > 1.0


## 供 AI / 测试查询条件是否成立。
func check_condition(side: int, cond: Dictionary, ctx: Dictionary = {}) -> bool:
	return _check_cond(side, cond, ctx)


# ---------------------------------------------------------------------------
# 辩题 / 台词 / 复盘
# ---------------------------------------------------------------------------

func has_topic() -> bool:
	return topic != null


func current_claim_text() -> String:
	if topic == null or claim_index < 0 or claim_index >= topic.claim_count():
		return ""
	return topic.claim_text(claim_index)


func current_claim_tag() -> int:
	if topic == null or claim_index < 0 or claim_index >= topic.claim_count():
		return LogicCard.LogicTag.LOGIC
	return topic.claim_tag(claim_index)


## 能赢下当前争点的「有效手法」标签：即克制争点标签的那个标签。
func effective_tag_for_claim() -> int:
	var claim_tag := current_claim_tag()
	for tag in [
		LogicCard.LogicTag.FACT,
		LogicCard.LogicTag.EMOTION,
		LogicCard.LogicTag.VALUE,
		LogicCard.LogicTag.LOGIC,
	]:
		if library.fits(tag, claim_tag):
			return tag
	return claim_tag


func claim_progress() -> Vector2i:
	var total := topic.claim_count() if topic != null else 0
	return Vector2i(clampi(claim_index + 1, 0, total), total)


func points_of(side: int) -> int:
	return int(arg_points[side])


func claims_won_by(side: int) -> int:
	var count := 0
	for value in claims_state:
		if int(value) == side:
			count += 1
	return count


## 渲染一张卡的台词：把 {claim} {material} {last_move} 等变量替换成当前局势。
func render_card_line(card: LogicCard, is_reply: bool, speaker_side: int = -1) -> String:
	if card == null:
		return ""
	var template := card.reply_template if is_reply else card.target_template
	if template == "":
		return card.dialogue
	var claim_text := current_claim_text()
	var material := ""
	var materials: Array = []
	if topic != null and claim_index >= 0:
		materials = topic.claim_materials(claim_index)
	if not materials.is_empty():
		material = str(materials[rng.randi_range(0, materials.size() - 1)])
	var npc_name := ""
	if speaker_side >= 0:
		npc_name = sides[other_side(speaker_side)].character.char_name
	var values := {
		"claim": claim_text,
		"material": material,
		"topic": topic.title if topic != null else "",
		"last_move": _last_move_name,
		"last_card": _last_card_name,
		"npc": npc_name,
	}
	var text := template
	for key in values.keys():
		text = text.replace("{%s}" % key, str(values[key]))
	return text


## 战后复盘：该侧用过的手法、踩到的谬误、赢下/丢掉的争点与教训。
func debrief_for(side: int) -> Dictionary:
	var moves: Dictionary = {}
	var fallacies: Dictionary = {}
	var fallacy_lessons: Dictionary = {}
	for entry in used_moves:
		if int(entry.get("side", -1)) != side:
			continue
		var move_name := str(entry.get("name", ""))
		if move_name != "":
			moves[move_name] = int(moves.get(move_name, 0)) + 1
		var fallacy := str(entry.get("fallacy", ""))
		if fallacy != "":
			fallacies[fallacy] = int(fallacies.get(fallacy, 0)) + 1
			var lesson := str(entry.get("lesson", ""))
			if lesson != "":
				fallacy_lessons[fallacy] = lesson
	var claims_won: Array[String] = []
	var lessons: Array[String] = []
	if topic != null:
		for i in range(topic.claim_count()):
			var value := int(claims_state[i]) if i < claims_state.size() else -1
			if value == side:
				claims_won.append(topic.claim_text(i))
			elif value == other_side(side):
				lessons.append(topic.claim_lesson(i))
	return {
		"moves": moves,
		"fallacies": fallacies,
		"fallacy_lessons": fallacy_lessons,
		"claims_won": claims_won,
		"lessons": lessons,
		"points": int(arg_points[side]),
		"opp_points": int(arg_points[other_side(side)]),
	}


# ---------------------------------------------------------------------------
# 回合动作
# ---------------------------------------------------------------------------

func play_card(side: int, hand_index: int) -> bool:
	if not can_play(side, hand_index):
		return false
	var s: Dictionary = sides[side]
	var card: LogicCard = s.hand[hand_index]
	var cost := card_cost(side, card)
	s.ap = int(s.ap) - cost
	s.hand.remove_at(hand_index)
	s.in_flight.append(card)
	s.cards_played = int(s.cards_played) + 1
	played_cards.append(card.id)
	_extra_turn = false
	active_card = card
	attacker_side = side
	defender_side = other_side(side)
	state = State.WAITING_FOR_RESPONSE
	last_line = render_card_line(card, false, side)
	last_speaker_side = side
	used_moves.append({
		"side": side,
		"name": card.move_name,
		"fallacy": card.move_fallacy,
		"lesson": card.move_lesson,
		"card": card.id,
		"claim": claim_index,
	})
	card_played.emit(side, card)
	_emit_log("%s【%s】%s" % [s.character.char_name, card.move_label(), last_line], "attack")
	_last_move_name = card.move_name
	_last_card_name = card.card_name
	var window := _response_window_for(defender_side)
	response_window = window
	response_requested.emit(defender_side, card, window)
	return true


func pass_turn(side: int) -> bool:
	if state != State.AWAITING_ACTION or side != turn_side:
		return false
	_extra_turn = false
	_emit_log("%s 选择沉默，把话题让了出去。" % sides[side].character.char_name, "system")
	_advance_after_action()
	return true


## hand_index = -1 表示哑口无言（放弃响应）。
func submit_response(side: int, hand_index: int) -> bool:
	if state != State.WAITING_FOR_RESPONSE or side != defender_side:
		return false
	var s: Dictionary = sides[side]
	var card: LogicCard = null
	if hand_index >= 0:
		if not can_respond(side, hand_index):
			return false
		card = s.hand[hand_index]
		var cost := card_cost(side, card)
		s.ap = int(s.ap) - cost
		s.hand.remove_at(hand_index)
		s.in_flight.append(card)
		played_cards.append(card.id)
	if card != null:
		last_line = render_card_line(card, true, side)
		last_speaker_side = side
		used_moves.append({
			"side": side,
			"name": card.move_name,
			"fallacy": card.move_fallacy,
			"lesson": card.move_lesson,
			"card": card.id,
			"claim": claim_index,
		})
		response_committed.emit(side, card)
		_last_move_name = card.move_name
		_last_card_name = card.card_name
		_emit_log("%s 接话【%s】%s" % [s.character.char_name, card.move_label(), last_line], "response")
	else:
		last_line = "……（沉默）"
		last_speaker_side = side
		response_committed.emit(side, null)
		_last_move_name = "沉默"
		_last_card_name = "沉默"
		_emit_log("%s 没有接话。" % s.character.char_name, "silence")
	_resolve(side, card)
	return true


func _begin_turn(side: int, first_turn: bool = false) -> void:
	if state == State.ENDED:
		return
	state = State.AWAITING_ACTION
	turn_side = side
	_tick_turn_start(side)
	if state == State.ENDED:
		return
	var s: Dictionary = sides[side]
	s.ap = maxi(0, AP_PER_TURN + int(s.ap_delta))
	s.ap_delta = 0
	if not first_turn:
		_draw_cards(side, 1)
		if side == PLAYER:
			turn_number += 1
	if turn_number > MAX_TURNS:
		_finish_by_timeout()
		return
	turn_started.emit(side, turn_number)
	_emit_log("—— 第 %d 回合 · %s ——" % [turn_number, s.character.char_name], "turn")
	if state != State.ENDED:
		action_needed.emit(side)


func _tick_turn_start(side: int) -> void:
	var s: Dictionary = sides[side]
	for status in s.statuses.duplicate():
		if state == State.ENDED:
			return
		var mods: Dictionary = status.get("mods", {})
		var dot := int(mods.get("dot", 0))
		if dot > 0:
			_emit_log("%s 因【%s】心力流失 %d" % [s.character.char_name, status.get("name", ""), dot], "dot")
			_deal_direct_damage(side, dot)
		var heal := int(mods.get("heal_per_turn", 0))
		if heal > 0:
			_heal(side, heal)


func _advance_after_action(extra_side: int = -1) -> void:
	if state == State.ENDED:
		return
	var finished_side := turn_side
	var was_extra := _extra_turn
	_extra_turn = false
	_end_turn(finished_side)
	if state == State.ENDED:
		return
	if was_extra and extra_side >= 0:
		_emit_log("%s 乘胜追击，获得额外回合。" % sides[extra_side].character.char_name, "system")
		_begin_turn(extra_side)
	else:
		_begin_turn(other_side(finished_side))


func _end_turn(side: int) -> void:
	var s: Dictionary = sides[side]
	var remaining: Array = []
	for status in s.statuses:
		var duration := int(status.get("duration", 1)) - 1
		if duration <= 0:
			status_changed.emit(side, status, false)
			_emit_log("【%s】从 %s 身上消退。" % [status.get("name", ""), s.character.char_name], "status")
		else:
			status["duration"] = duration
			remaining.append(status)
	s.statuses = remaining


func _response_window_for(side: int) -> float:
	var window := BASE_RESPONSE_WINDOW
	window += float(mods_of(side).get("response_time_delta", 0.0))
	if scenario != null:
		window += float(scenario.mods.get("response_time_delta", 0.0))
	return clampf(window, MIN_RESPONSE_WINDOW, 8.0)


# ---------------------------------------------------------------------------
# 抽牌 / 资源
# ---------------------------------------------------------------------------

func _draw_cards(side: int, count: int) -> void:
	var s: Dictionary = sides[side]
	for i in range(count):
		if state == State.ENDED:
			return
		if s.hand.size() >= MAX_HAND:
			return
		if s.deck.is_empty():
			if s.discard.is_empty():
				_emit_log("%s 的思路枯竭了。" % s.character.char_name, "system")
				_deal_direct_damage(side, FATIGUE_DAMAGE)
				continue
			s.deck = s.discard.duplicate()
			s.discard.clear()
			_shuffle(s.deck)
			_emit_log("%s 把旧话术重新翻了出来（洗牌）。" % s.character.char_name, "system")
		if s.deck.is_empty():
			continue
		s.hand.append(s.deck.pop_back())


func _discard_random(side: int, count: int) -> void:
	var s: Dictionary = sides[side]
	for i in range(count):
		if s.hand.is_empty():
			return
		var index := rng.randi_range(0, s.hand.size() - 1)
		var card: LogicCard = s.hand[index]
		s.hand.remove_at(index)
		s.discard.append(card)
		_emit_log("%s 丢掉了「%s」。" % [s.character.char_name, card.card_name], "system")


func _shuffle_hand(side: int) -> void:
	var s: Dictionary = sides[side]
	var count: int = (s.hand as Array).size()
	for card in s.hand:
		s.deck.append(card)
	s.hand.clear()
	_shuffle(s.deck)
	_emit_log("%s 的话题被彻底带偏了。" % s.character.char_name, "system")
	_draw_cards(side, count)


# ---------------------------------------------------------------------------
# 响应结算
# ---------------------------------------------------------------------------

func _resolve(def_side: int, def_card: LogicCard) -> void:
	state = State.SETTLING
	var atk_side := attacker_side
	var attack_card: LogicCard = active_card
	var outcome: int = Outcome.SILENCE
	if def_card != null:
		if def_card.card_type == LogicCard.CardType.DECONSTRUCTION:
			outcome = Outcome.PERFECT if library.fits(def_card.tag, attack_card.tag) else Outcome.PARTIAL
		elif def_card.card_type == LogicCard.CardType.PIVOT:
			outcome = Outcome.TRADE
	var ctx := {"outcome": outcome, "attack_card": attack_card, "def_card": def_card}
	var dmg_to_defender := 0
	var dmg_to_attacker := 0
	var was_silence := false

	match outcome:
		Outcome.SILENCE:
			was_silence = true
			var silence_raw := _calc_damage(atk_side, attack_card, def_side, false)
			var penalty := _silence_penalty(atk_side, attack_card)
			dmg_to_defender = silence_raw + penalty
			if dmg_to_defender > 0:
				_emit_log("%s 哑口无言，没能接住这一击。" % sides[def_side].character.char_name, "silence")
			_apply_damage(def_side, dmg_to_defender)
			_run_effects(atk_side, attack_card.effects, ctx)
			_apply_self_damage(atk_side, attack_card)
			if dmg_to_defender >= 2:
				_add_status(def_side, "st_breakdown", 1)
		Outcome.PERFECT:
			_emit_log("%s 精准拆解了这一击，反手一击！" % sides[def_side].character.char_name, "perfect")
			dmg_to_attacker = _calc_damage(def_side, def_card, atk_side, true)
			_apply_damage(atk_side, dmg_to_attacker)
			_run_effects(def_side, def_card.counter_effects, ctx)
			_apply_self_damage(def_side, def_card)
			_apply_scenario_counter_heal(def_side, def_card)
		Outcome.PARTIAL:
			_emit_log("%s 勉强挡下一半，但没能完全拆掉。" % sides[def_side].character.char_name, "partial")
			var partial_raw := _calc_damage(atk_side, attack_card, def_side, false)
			dmg_to_defender = ceili(float(partial_raw) * 0.5)
			_apply_damage(def_side, dmg_to_defender)
			_run_effects(atk_side, attack_card.effects, ctx)
			_apply_self_damage(atk_side, attack_card)
			var counter_raw := _calc_damage(def_side, def_card, atk_side, true)
			dmg_to_attacker = ceili(float(counter_raw) * 0.5)
			_apply_damage(atk_side, dmg_to_attacker)
			_run_effects(def_side, def_card.counter_effects, ctx)
			_apply_self_damage(def_side, def_card)
			_apply_scenario_counter_heal(def_side, def_card)
		Outcome.TRADE:
			_emit_log("%s 用诡辩硬碰硬，双方都不体面。" % sides[def_side].character.char_name, "trade")
			var trade_raw := _calc_damage(atk_side, attack_card, def_side, false)
			dmg_to_defender = ceili(float(trade_raw) * 0.7)
			_apply_damage(def_side, dmg_to_defender)
			var pivot_dmg := _calc_damage(def_side, def_card, atk_side, false)
			pivot_dmg = ceili(float(pivot_dmg) * 0.7)
			var atk_char: CharacterResource = sides[atk_side].character
			if atk_char.passive_id == "polite_trap" and attack_card.card_type == LogicCard.CardType.CONSTRUCTION:
				pivot_dmg = ceili(float(pivot_dmg) * 0.5)
				_emit_log("【礼貌陷阱】对方被礼貌卸了力，诡辩只打出一半效果。", "passive")
			dmg_to_attacker = pivot_dmg
			_apply_damage(atk_side, dmg_to_attacker)
			_run_effects(def_side, def_card.effects, ctx)
			_apply_self_damage(def_side, def_card)
			_run_effects(atk_side, attack_card.effects, ctx)
			_apply_self_damage(atk_side, attack_card)

	_finish_resolution(atk_side, def_side, attack_card, def_card, outcome, dmg_to_defender, dmg_to_attacker, was_silence)


func _finish_resolution(atk_side: int, def_side: int, attack_card: LogicCard, def_card: LogicCard, outcome: int, dmg_to_defender: int, dmg_to_attacker: int, was_silence: bool) -> void:
	var finished_attacker := atk_side
	_apply_passives(outcome)
	var claim_winner := -1
	if topic != null and state != State.ENDED:
		claim_winner = _resolve_claim(atk_side, def_side, attack_card, def_card, dmg_to_defender, dmg_to_attacker)
	for side in [PLAYER, ENEMY]:
		var s: Dictionary = sides[side]
		for card in s.in_flight:
			s.discard.append(card)
		s.in_flight.clear()
	active_card = null
	attacker_side = -1
	defender_side = -1
	var info := {
		"attacker_side": atk_side,
		"defender_side": def_side,
		"attack_card": attack_card,
		"defender_card": def_card,
		"outcome": outcome,
		"damage_to_defender": dmg_to_defender,
		"damage_to_attacker": dmg_to_attacker,
		"silence": was_silence,
		"claim_winner": claim_winner,
		"claim_index": claim_index,
		"arg_points": arg_points.duplicate(),
	}
	resolution_finished.emit(info)
	if state == State.ENDED:
		return
	state = State.AWAITING_ACTION
	_advance_after_action(finished_attacker)


func _calc_damage(side: int, card: LogicCard, target_side: int, is_counter: bool) -> int:
	if card.base_damage <= 0:
		return 0
	var defender_tag: int
	if is_counter and active_card != null:
		defender_tag = active_card.tag
	else:
		defender_tag = sides[target_side].character.affinity_tag
	var fit := library.fit_multiplier(card.tag, defender_tag)
	var char_bonus := 1.0
	if card.tag == sides[side].character.affinity_tag:
		char_bonus = 1.2
	var mods: Dictionary = mods_of(side)
	var flat := float(mods.get("outgoing_damage_flat", 0))
	if is_counter:
		flat += float(mods.get("counter_damage_flat", 0))
	var mult := 1.0 + float(mods.get("outgoing_damage_mult", 0.0))
	var scenario_mult := 1.0
	if scenario != null:
		scenario_mult = scenario.damage_mult_for(card.tag)
	var raw := (float(card.base_damage) * fit * char_bonus + flat) * mult * scenario_mult
	return maxi(0, roundi(raw))


func _silence_penalty(side: int, card: LogicCard) -> int:
	var base := card.silence_penalty
	if base <= 0:
		return 0
	var mult := float(mods_of(side).get("silence_penalty_mult", 1.0))
	var character: CharacterResource = sides[side].character
	if character.passive_id == "evidence_overwhelm" and card.tag == LogicCard.LogicTag.FACT:
		mult *= 1.5
		_emit_log("【证据压制】事实卡的沉默惩罚被放大。", "passive")
	return maxi(0, roundi(float(base) * mult))


func _apply_self_damage(side: int, card: LogicCard) -> void:
	if card == null or card.self_damage <= 0:
		return
	var amount := float(card.self_damage)
	if card.card_type == LogicCard.CardType.PIVOT and scenario != null:
		amount *= float(scenario.mods.get("pivot_self_damage_mult", 1.0))
	var final_amount := maxi(1, roundi(amount))
	_emit_log("%s 为这张诡辩付出了代价。" % sides[side].character.char_name, "system")
	_deal_direct_damage(side, final_amount)


func _apply_scenario_counter_heal(side: int, card: LogicCard) -> void:
	if scenario == null:
		return
	var table: Variant = scenario.mods.get("counter_heal_by_tag", {})
	if not table is Dictionary:
		return
	for key in (table as Dictionary).keys():
		if LogicCard.tag_from_string(str(key)) == card.tag:
			var amount := int((table as Dictionary)[key])
			if amount > 0:
				_heal(side, amount)
				_emit_log("【%s】%s 的拆解得到环境加持，回复 %d 心气。" % [scenario.scenario_name, sides[side].character.char_name, amount], "system")


func _apply_passives(outcome: int) -> void:
	var atk_char: CharacterResource = sides[attacker_side].character
	var def_char: CharacterResource = sides[defender_side].character
	if def_char.passive_id == "moral_high_ground" and outcome == Outcome.PARTIAL:
		_emit_log("【道德高地】%s 拆得不够彻底，反被道德压力反噬。" % def_char.char_name, "passive")
		_deal_direct_damage(attacker_side, 1)
	if atk_char.passive_id == "reverse_pleasure" and outcome == Outcome.PERFECT:
		_emit_log("【反向快感】%s 被成功拆解，反而越战越勇。" % atk_char.char_name, "passive")
		_heal(attacker_side, 1)
	var def_mods: Dictionary = mods_of(defender_side)
	var chance := float(def_mods.get("on_attack_self_damage_chance", 0.0))
	if chance > 0.0 and rng.randf() < chance:
		var amount := maxi(1, int(def_mods.get("on_attack_self_damage", 1)))
		_emit_log("【道德高地】%s 的攻击被反噬，自己先乱了阵脚。" % atk_char.char_name, "passive")
		_deal_direct_damage(attacker_side, amount)


# ---------------------------------------------------------------------------
# 心气改动
# ---------------------------------------------------------------------------

func _apply_damage(target_side: int, amount: int) -> void:
	if amount <= 0 or state == State.ENDED:
		return
	var incoming := 1.0 + float(mods_of(target_side).get("incoming_damage_mult", 0.0))
	var final_amount := maxi(0, roundi(float(amount) * incoming))
	final_amount = mini(final_amount, DAMAGE_CAP)
	if final_amount <= 0:
		return
	_change_spirit(target_side, -final_amount)
	if state == State.ENDED:
		return
	sides[target_side].last_damage_taken = final_amount
	_emit_log("%s 心气 -%d" % [sides[target_side].character.char_name, final_amount], "damage")


func _deal_direct_damage(target_side: int, amount: int) -> void:
	if amount <= 0 or state == State.ENDED:
		return
	_change_spirit(target_side, -mini(amount, DAMAGE_CAP))
	if state == State.ENDED:
		return
	_emit_log("%s 心气 -%d" % [sides[target_side].character.char_name, amount], "damage")


func _heal(side: int, amount: int) -> void:
	if amount <= 0 or state == State.ENDED:
		return
	var s: Dictionary = sides[side]
	var old := int(s.spirit)
	var new_value := mini(int(s.max_spirit), old + amount)
	if new_value == old:
		return
	s.spirit = new_value
	spirit_changed.emit(side, old, new_value)
	_emit_log("%s 心气 +%d" % [s.character.char_name, new_value - old], "heal")


func _change_spirit(side: int, delta: int) -> void:
	var s: Dictionary = sides[side]
	var old := int(s.spirit)
	var new_value := clampi(old + delta, 0, int(s.max_spirit))
	if new_value == old:
		return
	s.spirit = new_value
	spirit_changed.emit(side, old, new_value)
	if new_value <= 0:
		_end_battle(other_side(side), "%s 破防" % s.character.char_name)


# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------

func _add_status(side: int, status_id: String, duration: int = -1) -> void:
	if status_id == "":
		return
	var definition: StatusDef = library.statuses.get(status_id)
	if definition == null:
		push_warning("BattleEngine: 未定义的状态 '%s'" % status_id)
		return
	var s: Dictionary = sides[side]
	for existing in s.statuses:
		if str(existing.get("id", "")) == status_id:
			var refreshed := duration if duration > 0 else definition.default_duration
			existing["duration"] = maxi(int(existing.get("duration", 1)), refreshed)
			status_changed.emit(side, existing, true)
			return
	var runtime := definition.make_runtime(duration)
	s.statuses.append(runtime)
	status_changed.emit(side, runtime, true)
	_emit_log("%s 陷入【%s】" % [s.character.char_name, definition.display_name], "status")


func _clear_status(side: int, kind: String) -> void:
	var s: Dictionary = sides[side]
	var remaining: Array = []
	var removed_any := false
	for status in s.statuses:
		var status_kind := str(status.get("kind", "debuff"))
		if kind == "all" or status_kind == kind:
			status_changed.emit(side, status, false)
			removed_any = true
		else:
			remaining.append(status)
	s.statuses = remaining
	if removed_any:
		_emit_log("%s 身上的状态被清除了。" % s.character.char_name, "status")


# ---------------------------------------------------------------------------
# 效果解释器
# ---------------------------------------------------------------------------

func _run_effects(owner_side: int, effects: Variant, ctx: Dictionary) -> void:
	if not effects is Array:
		return
	for op in (effects as Array):
		if state == State.ENDED:
			return
		if op is Dictionary:
			_run_op(owner_side, op, ctx)


func _run_op(owner_side: int, op: Dictionary, ctx: Dictionary) -> void:
	var kind := str(op.get("op", ""))
	var default_target := "enemy"
	if kind in ["heal", "draw", "extra_turn"]:
		default_target = "self"
	var chosen_target := str(op.get("target", default_target))
	var target_side := owner_side if chosen_target == "self" else other_side(owner_side)
	match kind:
		"damage":
			_apply_damage(target_side, int(op.get("amount", 0)))
		"heal":
			_heal(target_side, int(op.get("amount", 1)))
		"lose_spirit":
			_deal_direct_damage(target_side, int(op.get("amount", 1)))
		"status":
			_add_status(target_side, str(op.get("id", "")), int(op.get("dur", -1)))
		"clear_status":
			_clear_status(target_side, str(op.get("kind", "all")))
		"draw":
			_draw_cards(target_side, int(op.get("amount", 1)))
		"discard":
			_discard_random(target_side, int(op.get("count", 1)))
		"ap":
			var s: Dictionary = sides[target_side]
			var delta := int(op.get("amount", -1))
			s.ap_delta = int(s.ap_delta) + delta
			_emit_log("%s 下回合 AP %+d" % [s.character.char_name, delta], "system")
		"extra_turn":
			_extra_turn = true
			_emit_log("%s 抓住了话头，获得额外回合。" % sides[owner_side].character.char_name, "system")
		"shuffle":
			_shuffle_hand(target_side)
		"reflect_damage":
			var mult := float(op.get("mult", 1.0))
			var minimum := int(op.get("min", 2))
			var reflected := maxi(minimum, int(round(float(sides[owner_side].last_damage_taken) * mult)))
			_emit_log("伤害被原样反弹了回去。", "system")
			_apply_damage(target_side, reflected)
		"execute":
			_run_execute(owner_side, op)
		"random":
			var options: Variant = op.get("options", [])
			if options is Array and (options as Array).size() > 0:
				var picked: Variant = (options as Array)[rng.randi_range(0, (options as Array).size() - 1)]
				_run_effects(owner_side, picked, ctx)
		"if":
			var cond: Variant = op.get("cond", {})
			if cond is Dictionary and _check_cond(owner_side, cond, ctx):
				_run_effects(owner_side, op.get("then", []), ctx)
			else:
				_run_effects(owner_side, op.get("else", []), ctx)
		"log":
			_emit_log(str(op.get("text", "")), "flavor")
		_:
			push_warning("BattleEngine: 未知效果操作 '%s'" % kind)


func _check_cond(owner_side: int, cond: Dictionary, ctx: Dictionary) -> bool:
	var kind := str(cond.get("c", ""))
	match kind:
		"self_spirit_lte":
			return int(sides[owner_side].spirit) <= int(cond.get("v", 2))
		"enemy_spirit_lte":
			return int(sides[other_side(owner_side)].spirit) <= int(cond.get("v", 2))
		"self_leading":
			return int(sides[owner_side].spirit) > int(sides[other_side(owner_side)].spirit)
		"self_behind":
			return int(sides[owner_side].spirit) < int(sides[other_side(owner_side)].spirit)
		"enemy_has_status":
			return _has_status(other_side(owner_side), str(cond.get("id", "")))
		"self_has_status":
			return _has_status(owner_side, str(cond.get("id", "")))
		"enemy_hand_has_tag":
			var wanted := LogicCard.tag_from_string(str(cond.get("v", "FACT")))
			for card in sides[other_side(owner_side)].hand:
				if card.tag == wanted:
					return true
			return false
		"enemy_lost_spirit":
			var enemy: Dictionary = sides[other_side(owner_side)]
			return int(enemy.max_spirit) - int(enemy.spirit) >= int(cond.get("v", 3))
		"outcome":
			return int(ctx.get("outcome", -1)) == int(cond.get("v", -1))
	return true


func _has_status(side: int, status_id: String) -> bool:
	for status in sides[side].statuses:
		if str(status.get("id", "")) == status_id:
			return true
	return false


func _run_execute(owner_side: int, op: Dictionary) -> void:
	var mode := str(op.get("mode", "leading"))
	var enemy_side := other_side(owner_side)
	match mode:
		"leading":
			var threshold := int(op.get("enemy_spirit_lte", 3))
			if int(sides[owner_side].spirit) > int(sides[enemy_side].spirit) and int(sides[enemy_side].spirit) <= threshold:
				_end_battle(owner_side, "体面离场")
		"enemy_below":
			if int(sides[enemy_side].spirit) <= int(op.get("v", 2)):
				_end_battle(owner_side, "定论宣告")
		"chance_win":
			if rng.randf() < float(op.get("chance", 0.2)):
				_emit_log("运气站在了 %s 这边。" % sides[owner_side].character.char_name, "system")
				_end_battle(owner_side, "概率绝杀")


# ---------------------------------------------------------------------------
# 争点推进
# ---------------------------------------------------------------------------

func _announce_claim(index: int) -> void:
	if topic == null or index < 0 or index >= topic.claim_count():
		return
	claim_index = index
	claim_exchanges = 0
	var effective_label := LogicCard.tag_label_of(effective_tag_for_claim())
	var npc_line := ""
	var lines := topic.claim_npc_lines(index)
	if not lines.is_empty():
		npc_line = str(lines[rng.randi_range(0, lines.size() - 1)])
	claim_announced.emit(index, topic.claim_count(), topic.claim_text(index), effective_label, npc_line)
	_emit_log("【争点 %d/%d】%s（对题手法：%s，额外 +%d 压力）" % [
		index + 1, topic.claim_count(), topic.claim_text(index), effective_label, CLAIM_FIT_BONUS
	], "claim")
	if npc_line != "":
		_emit_log("对方：%s" % npc_line, "npc")


## 判定这一手是否赢下当前争点。
## 规则：比「论点压力」= 本回合造成的伤害 + 标签对题加成；
##       平手时看谁的出手标签克制争点标签。这样任何角色都能靠施压争点，
##       而选对标签依旧是显著优势（+2 压力，常常直接决定胜负）。
func _resolve_claim(atk_side: int, def_side: int, attack_card: LogicCard, def_card: LogicCard, dmg_to_defender: int, dmg_to_attacker: int) -> int:
	if topic == null or claim_index < 0 or claim_index >= topic.claim_count():
		return -1
	if int(claims_state[claim_index]) != -1:
		return -1
	var claim_tag := current_claim_tag()
	var attacker_fit: bool = library.fits(attack_card.tag, claim_tag)
	var defender_fit: bool = def_card != null and library.fits(def_card.tag, claim_tag)
	var attacker_pressure := dmg_to_defender + (CLAIM_FIT_BONUS if attacker_fit else 0)
	var defender_pressure := dmg_to_attacker + (CLAIM_FIT_BONUS if defender_fit else 0)
	var winner := -1
	if attacker_pressure > defender_pressure:
		winner = atk_side
	elif defender_pressure > attacker_pressure:
		winner = def_side
	elif attacker_pressure > 0:
		if attacker_fit and not defender_fit:
			winner = atk_side
		elif defender_fit and not attacker_fit:
			winner = def_side
	if winner >= 0:
		claims_state[claim_index] = winner
		arg_points[winner] = int(arg_points[winner]) + 1
		var winner_card: LogicCard = attack_card if winner == atk_side else def_card
		var tag_note := ""
		if (winner == atk_side and attacker_fit) or (winner == def_side and defender_fit):
			tag_note = "（对题加成）"
		_emit_log("【争点判定】%s 用【%s】赢下『%s』%s（论点 %d : %d）" % [
			sides[winner].character.char_name,
			winner_card.move_label(),
			current_claim_text(),
			tag_note,
			int(arg_points[PLAYER]),
			int(arg_points[ENEMY]),
		], "claim")
		claim_resolved.emit(claim_index, winner, arg_points.duplicate())
		_advance_claim()
		return winner
	claim_exchanges += 1
	if claim_exchanges >= CLAIM_MAX_EXCHANGES:
		_emit_log("【争点判定】『%s』僵持不下，双方都没拿下。" % current_claim_text(), "claim")
		claim_resolved.emit(claim_index, -1, arg_points.duplicate())
		_advance_claim()
	return -1


func _advance_claim() -> void:
	if topic == null:
		return
	if int(arg_points[PLAYER]) >= CLAIMS_TO_WIN or int(arg_points[ENEMY]) >= CLAIMS_TO_WIN:
		_finish_by_points()
		return
	if claim_index + 1 >= topic.claim_count():
		_finish_by_points()
		return
	_announce_claim(claim_index + 1)


func _finish_by_points() -> void:
	var player_points := int(arg_points[PLAYER])
	var enemy_points := int(arg_points[ENEMY])
	if player_points > enemy_points:
		_end_battle(PLAYER, "论点 %d : %d，你赢下了这场辩论" % [player_points, enemy_points])
	elif enemy_points > player_points:
		_end_battle(ENEMY, "论点 %d : %d，你被说服了" % [player_points, enemy_points])
	else:
		var player_spirit := spirit_of(PLAYER)
		var enemy_spirit := spirit_of(ENEMY)
		if player_spirit > enemy_spirit:
			_end_battle(PLAYER, "论点持平，心气更高者胜")
		elif enemy_spirit > player_spirit:
			_end_battle(ENEMY, "论点持平，心气更高者胜")
		else:
			_end_battle(-1, "论点与心气都持平，这顿饭谁也没说服谁")


# ---------------------------------------------------------------------------
# 胜负
# ---------------------------------------------------------------------------

func _end_battle(winner: int, reason: String) -> void:
	if state == State.ENDED:
		return
	state = State.ENDED
	winner_side = winner
	finish_reason = reason
	_emit_log("—— %s ——" % reason, "system")
	battle_ended.emit(winner_side, finish_reason)


func _finish_by_timeout() -> void:
	var p := int(sides[PLAYER].spirit)
	var e := int(sides[ENEMY].spirit)
	if p > e:
		_end_battle(PLAYER, "话题耗尽，心气更高者胜")
	elif e > p:
		_end_battle(ENEMY, "话题耗尽，心气更高者胜")
	else:
		_end_battle(-1, "话题耗尽，平局")


func _emit_log(text: String, kind: String = "info") -> void:
	event_log.append({"text": text, "kind": kind, "turn": turn_number})
	log_line.emit(text, kind)
