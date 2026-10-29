extends SceneTree
## headless 自动化测试套件。
##
## 运行：
##   Godot_v4.7-stable_win64_console.exe --headless --path <project> --script res://tests/test_battle.gd
## 退出码 0 = 全部通过。

var library: GameLibrary
var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	print("=== Sophistry headless test suite ===")
	library = GameLibrary.shared()
	_test_data_integrity()
	_test_fit_matrix()
	_test_initial_state()
	_test_debate_topic()
	_test_silence_damage()
	_test_perfect_counter()
	_test_partial_counter()
	_test_trade_and_polite_trap()
	_test_passives()
	_test_every_card()
	_test_ai_matches()
	print("SUMMARY checks=%d failures=%d" % [checks, failures])
	print("RESULT %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)


# ---------------------------------------------------------------------------
# 断言工具
# ---------------------------------------------------------------------------

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("  FAIL: " + label)


func check_eq(actual: Variant, expected: Variant, label: String) -> void:
	checks += 1
	if actual != expected:
		failures += 1
		print("  FAIL: %s (expected %s, got %s)" % [label, str(expected), str(actual)])


# ---------------------------------------------------------------------------
# 数据完整性
# ---------------------------------------------------------------------------

func _test_data_integrity() -> void:
	print("-- data integrity")
	check(library.load_errors.is_empty(), "load errors: %s" % str(library.load_errors))
	check_eq(library.cards.size(), 60, "card count")
	check_eq(library.characters.size(), 4, "character count")
	check_eq(library.scenarios.size(), 4, "scenario count")
	check(library.statuses.size() >= 25, "status count >= 25")
	check(library.topics.size() >= 1, "topic count >= 1")
	var missing := library.missing_status_references()
	check(missing.is_empty(), "missing status references: %s" % str(missing))
	for character_id in library.characters.keys():
		var character: CharacterResource = library.characters[character_id]
		check_eq(character.deck.size(), 15, "deck size of %s" % character_id)
		check(character.passive_id != "", "passive of %s" % character_id)
	for card_id in library.cards.keys():
		var card: LogicCard = library.cards[card_id]
		check(card.card_name != "" and card.dialogue != "", "%s has text" % card_id)
		check(card.cost >= 1 and card.cost <= 2, "%s cost in [1,2]" % card_id)
		check(card.base_damage >= 0 and card.base_damage <= 2, "%s damage sane" % card_id)
		check(
			card.base_damage > 0 or not card.effects.is_empty() or not card.counter_effects.is_empty(),
			"%s has an effect" % card_id
		)
		check(card.move_name != "", "%s has move name" % card_id)
		check(card.target_template != "", "%s has target template" % card_id)
		if card.card_type != LogicCard.CardType.CONSTRUCTION:
			check(card.reply_template != "", "%s has reply template" % card_id)


func _test_fit_matrix() -> void:
	print("-- fit matrix")
	var t := LogicCard.LogicTag
	check_eq(library.fit_multiplier(t.FACT, t.EMOTION), 2.0, "FACT beats EMOTION")
	check_eq(library.fit_multiplier(t.EMOTION, t.VALUE), 2.0, "EMOTION beats VALUE")
	check_eq(library.fit_multiplier(t.VALUE, t.LOGIC), 2.0, "VALUE beats LOGIC")
	check_eq(library.fit_multiplier(t.LOGIC, t.FACT), 2.0, "LOGIC beats FACT")
	check_eq(library.fit_multiplier(t.FACT, t.LOGIC), 1.0, "FACT does not beat LOGIC")
	check_eq(library.fit_multiplier(t.EMOTION, t.FACT), 1.0, "EMOTION does not beat FACT")


# ---------------------------------------------------------------------------
# 对局基础
# ---------------------------------------------------------------------------

func _fresh_engine(player_id: String, enemy_id: String, scenario_id: String, seed_value: int = 7) -> BattleEngine:
	var engine := BattleEngine.new()
	engine.setup_battle(player_id, enemy_id, scenario_id, seed_value)
	return engine


func _give_hand(engine: BattleEngine, side: int, cards: Array) -> void:
	var hand: Array = engine.hand_of(side)
	hand.clear()
	for card in cards:
		hand.append(card)
	var s: Dictionary = engine.sides[side]
	s.ap = 10


func _other_character(character_id: String) -> String:
	for key in library.characters.keys():
		if str(key) != character_id:
			return str(key)
	return character_id


func _test_initial_state() -> void:
	print("-- initial state")
	var engine := _fresh_engine("polite_assassin", "fact_checker", "office_pantry")
	check_eq(engine.state, BattleEngine.State.AWAITING_ACTION, "initial state")
	check_eq(engine.turn_side, BattleEngine.PLAYER, "player first")
	check_eq(engine.hand_of(engine.PLAYER).size(), 5, "player starting hand")
	check_eq(engine.hand_of(engine.ENEMY).size(), 6, "enemy starting hand (second player bonus)")
	check_eq(engine.spirit_of(engine.PLAYER), 5, "starting spirit")
	check_eq(engine.ap_of(engine.PLAYER), 2, "starting ap")


func _test_silence_damage() -> void:
	print("-- silence + evidence overwhelm")
	var engine := _fresh_engine("fact_checker", "empath", "office_pantry")
	_give_hand(engine, engine.PLAYER, [library.cards["fc01"]])
	var before := engine.spirit_of(engine.ENEMY)
	check(engine.play_card(engine.PLAYER, 0), "play fc01")
	check(engine.submit_response(engine.ENEMY, -1), "silence response")
	# base 1 * fit(FACT vs EMOTION) 2 * char 1.2 = 2.4 -> 2；沉默惩罚 1 * 1.5 -> 2；合计 4（命中上限）
	check_eq(engine.spirit_of(engine.ENEMY), before - 4, "silence total == 4")


func _test_perfect_counter() -> void:
	print("-- perfect counter")
	var engine := _fresh_engine("polite_assassin", "fact_checker", "office_pantry")
	_give_hand(engine, engine.PLAYER, [library.cards["pa01"]])
	_give_hand(engine, engine.ENEMY, [library.cards["em03"]])  # EMOTION 拆解，克制 VALUE
	check(engine.play_card(engine.PLAYER, 0), "play pa01")
	var defender_before := engine.spirit_of(engine.ENEMY)
	check(engine.submit_response(engine.ENEMY, 0), "perfect counter response")
	check_eq(engine.spirit_of(engine.ENEMY), defender_before, "perfect counter negates all damage")
	check(engine.spirit_of(engine.PLAYER) < 5, "perfect counter damages attacker")


func _test_partial_counter() -> void:
	print("-- partial counter")
	var engine := _fresh_engine("polite_assassin", "fact_checker", "office_pantry")
	_give_hand(engine, engine.PLAYER, [library.cards["pa01"]])  # VALUE 攻击
	_give_hand(engine, engine.ENEMY, [library.cards["pa04"]])  # LOGIC 拆解，不克制 VALUE
	check(engine.play_card(engine.PLAYER, 0), "play pa01")
	var defender_before := engine.spirit_of(engine.ENEMY)
	check(engine.submit_response(engine.ENEMY, 0), "partial counter response")
	check(engine.spirit_of(engine.ENEMY) < defender_before, "partial counter takes half damage")


func _test_trade_and_polite_trap() -> void:
	print("-- pivot trade + polite trap")
	# 攻击方是温和的杀手，用构建卡；对方用诡辩卡硬碰 -> 诡辩伤害减半
	var engine := _fresh_engine("polite_assassin", "contrarian", "office_pantry")
	_give_hand(engine, engine.PLAYER, [library.cards["pa01"]])
	_give_hand(engine, engine.ENEMY, [library.cards["pa07"]])
	check(engine.play_card(engine.PLAYER, 0), "play construction")
	var attacker_before := engine.spirit_of(engine.PLAYER)
	check(engine.submit_response(engine.ENEMY, 0), "pivot trade response")
	var trapped_loss := attacker_before - engine.spirit_of(engine.PLAYER)
	# 同样的对拼，但攻击方用拆解卡（不触发礼貌陷阱）
	var engine2 := _fresh_engine("polite_assassin", "contrarian", "office_pantry")
	_give_hand(engine2, engine2.PLAYER, [library.cards["pa04"]])
	_give_hand(engine2, engine2.ENEMY, [library.cards["pa07"]])
	check(engine2.play_card(engine2.PLAYER, 0), "play deconstruction")
	var attacker2_before := engine2.spirit_of(engine2.PLAYER)
	check(engine2.submit_response(engine2.ENEMY, 0), "pivot trade response 2")
	var normal_loss := attacker2_before - engine2.spirit_of(engine2.PLAYER)
	check(trapped_loss < normal_loss, "polite trap halves pivot damage (%d < %d)" % [trapped_loss, normal_loss])
	check(trapped_loss > 0, "trade still hurts attacker")


func _test_passives() -> void:
	print("-- passives")
	# 道德高地：共情怪用不契合的拆解 -> 攻击方额外 -1
	var engine := _fresh_engine("fact_checker", "empath", "office_pantry")
	_give_hand(engine, engine.PLAYER, [library.cards["fc01"]])
	_give_hand(engine, engine.ENEMY, [library.cards["em04"]])  # VALUE 拆解 VS FACT，不契合
	check(engine.play_card(engine.PLAYER, 0), "moral: play attack")
	var attacker_before := engine.spirit_of(engine.PLAYER)
	check(engine.submit_response(engine.ENEMY, 0), "moral: partial response")
	# 半伤反击 1 + 道德高地 1 = 2
	check_eq(attacker_before - engine.spirit_of(engine.PLAYER), 2, "moral high ground extra damage")

	# 反向快感：杠精之王被完美拆解 -> 回复 1
	var engine2 := _fresh_engine("contrarian", "empath", "office_pantry")
	_give_hand(engine2, engine2.PLAYER, [library.cards["cn08"]])  # LOGIC 攻击
	_give_hand(engine2, engine2.ENEMY, [library.cards["em04"]])   # VALUE 拆解，克制 LOGIC
	check(engine2.play_card(engine2.PLAYER, 0), "reverse: play attack")
	var attacker2_before := engine2.spirit_of(engine2.PLAYER)
	check(engine2.submit_response(engine2.ENEMY, 0), "reverse: perfect response")
	check(engine2.spirit_of(engine2.PLAYER) > attacker2_before - 2, "reverse pleasure heals back")


# ---------------------------------------------------------------------------
# 辩题层
# ---------------------------------------------------------------------------

func _test_debate_topic() -> void:
	print("-- debate topic layer")
	check(library.topics.size() >= 1, "topic library loaded")
	var topic: DebateTopic = library.topic_for_scene("new_year_dinner")
	check(topic != null, "new_year_dinner bound to a topic")
	if topic == null:
		return
	check_eq(topic.claim_count(), 3, "claim count")
	check(topic.claim_text(0) != "", "claim text")
	check(topic.claim_materials(0).size() > 0, "claim materials")
	var plain := _fresh_engine("polite_assassin", "fact_checker", "office_pantry")
	check(not plain.has_topic(), "scenario without topic has no debate layer")
	var engine := _fresh_engine("polite_assassin", "empath", "new_year_dinner", 11)
	check(engine.has_topic(), "engine attached topic")
	check_eq(engine.claim_index, 0, "first claim active")
	check_eq(engine.points_of(engine.PLAYER), 0, "no points yet")
	# 台词模板注入
	var card: LogicCard = library.cards["pa04"]
	var rendered := engine.render_card_line(card, true, engine.PLAYER)
	check(rendered.find("{claim}") == -1, "template placeholder replaced")
	check(rendered.find(engine.current_claim_text()) >= 0, "rendered line contains current claim")
	check(engine.render_card_line(card, false, engine.PLAYER).find("{material}") == -1, "material placeholder replaced")
	# 争点 0 的 tag 是 EMOTION，克制它的是 FACT
	check_eq(engine.current_claim_tag(), LogicCard.LogicTag.EMOTION, "claim 0 tag")
	check(engine.library.fits(LogicCard.LogicTag.FACT, engine.current_claim_tag()), "FACT counters claim 0")
	check_eq(engine.effective_tag_for_claim(), LogicCard.LogicTag.FACT, "effective tag for claim 0")
	# 用事实卡拿下第一个争点
	_give_hand(engine, engine.PLAYER, [library.cards["fc01"]])
	_give_hand(engine, engine.ENEMY, [])
	check(engine.play_card(engine.PLAYER, 0), "debate: play fact card")
	check(engine.submit_response(engine.ENEMY, -1), "debate: enemy silent")
	check_eq(engine.points_of(engine.PLAYER), 1, "player scored a claim")
	check_eq(engine.claim_index, 1, "advanced to claim 2")
	# 让回玩家回合，用情绪卡拿下第二争点（tag VALUE，由 EMOTION 克制）
	if engine.state == BattleEngine.State.AWAITING_ACTION:
		engine.pass_turn(engine.turn_side)
	var enemy: Dictionary = engine.sides[engine.ENEMY]
	enemy.spirit = 5
	_give_hand(engine, engine.PLAYER, [library.cards["em03"]])
	_give_hand(engine, engine.ENEMY, [])
	check(engine.play_card(engine.PLAYER, 0), "debate: play emotion card")
	check(engine.submit_response(engine.ENEMY, -1), "debate: enemy silent again")
	check_eq(engine.points_of(engine.PLAYER), 2, "player reached two points")
	check_eq(engine.state, BattleEngine.State.ENDED, "debate ended by arguments")
	check(engine.winner_side == engine.PLAYER, "player won the debate")
	check(engine.finish_reason.find("论点") >= 0, "finish reason mentions arguments")
	# 复盘数据
	var debrief := engine.debrief_for(engine.PLAYER)
	check(int(debrief["points"]) == 2, "debrief points")
	var moves: Dictionary = debrief["moves"]
	check(not moves.is_empty(), "debrief recorded moves")
	var claims_won: Array = debrief["claims_won"]
	check(not claims_won.is_empty(), "debrief claims won")


# ---------------------------------------------------------------------------
# 全卡覆盖
# ---------------------------------------------------------------------------

func _test_every_card() -> void:
	print("-- every card playable")
	for card_id in library.cards.keys():
		var card: LogicCard = library.cards[card_id]
		# 1) 作为主动牌
		var engine := _fresh_engine(card.owner_id, _other_character(card.owner_id), "office_pantry")
		_give_hand(engine, engine.PLAYER, [card])
		var played := engine.play_card(engine.PLAYER, 0)
		check(played, "active play: %s" % card_id)
		if played and engine.state == BattleEngine.State.WAITING_FOR_RESPONSE:
			check(engine.submit_response(engine.ENEMY, -1), "active settle: %s" % card_id)
		check(
			engine.state == BattleEngine.State.AWAITING_ACTION or engine.state == BattleEngine.State.ENDED,
			"active resolved: %s" % card_id
		)
		# 2) 作为响应牌（只有拆解 / 诡辩能响应）
		if card.card_type == LogicCard.CardType.CONSTRUCTION:
			continue
		var engine2 := _fresh_engine("polite_assassin", card.owner_id, "office_pantry")
		_give_hand(engine2, engine2.PLAYER, [library.cards["pa01"]])
		_give_hand(engine2, engine2.ENEMY, [card])
		var setup_ok := engine2.play_card(engine2.PLAYER, 0)
		check(setup_ok, "counter setup: %s" % card_id)
		if setup_ok:
			check(engine2.submit_response(engine2.ENEMY, 0), "counter play: %s" % card_id)
			check(
				engine2.state == BattleEngine.State.AWAITING_ACTION or engine2.state == BattleEngine.State.ENDED,
				"counter resolved: %s" % card_id
			)


# ---------------------------------------------------------------------------
# AI 全对局模拟
# ---------------------------------------------------------------------------

func _test_ai_matches() -> void:
	print("-- AI match simulation")
	var character_ids: Array[String] = []
	for key in library.characters.keys():
		character_ids.append(str(key))
	var scenario_ids: Array[String] = []
	for key in library.scenarios.keys():
		scenario_ids.append(str(key))
	var total := 0
	var player_wins := 0
	var enemy_wins := 0
	var draws := 0
	var max_steps := 0
	var max_rounds := 0
	for seed_value in range(1, 9):
		for player_id in character_ids:
			for enemy_id in character_ids:
				var scenario_id: String = scenario_ids[(seed_value + character_ids.find(player_id)) % scenario_ids.size()]
				var engine := _fresh_engine(player_id, enemy_id, scenario_id, seed_value)
				var steps := _drive(engine)
				total += 1
				check(engine.state == BattleEngine.State.ENDED, "match ended %s vs %s" % [player_id, enemy_id])
				check(steps < 5000, "match steps bound")
				check(engine.played_cards.size() > 0, "cards were played")
				check(engine.spirit_of(engine.PLAYER) >= 0 and engine.spirit_of(engine.PLAYER) <= 5, "player spirit bound")
				check(engine.spirit_of(engine.ENEMY) >= 0 and engine.spirit_of(engine.ENEMY) <= 5, "enemy spirit bound")
				if engine.winner_side == BattleEngine.PLAYER:
					player_wins += 1
				elif engine.winner_side == BattleEngine.ENEMY:
					enemy_wins += 1
				else:
					draws += 1
				max_steps = maxi(max_steps, steps)
				max_rounds = maxi(max_rounds, engine.turn_number)
	print("  matches=%d player=%d enemy=%d draw=%d max_steps=%d max_rounds=%d" % [
		total, player_wins, enemy_wins, draws, max_steps, max_rounds
	])
	check(total >= 64, "match count")
	check(player_wins > 0, "player can win")
	check(enemy_wins > 0, "enemy can win")
	check(max_rounds <= BattleEngine.MAX_TURNS, "round cap respected")
	check(max_steps < 5000, "no runaway matches")


func _drive(engine: BattleEngine) -> int:
	var steps := 0
	while engine.state != BattleEngine.State.ENDED and steps < 5000:
		steps += 1
		match engine.state:
			BattleEngine.State.AWAITING_ACTION:
				var side := engine.turn_side
				var index := AIController.choose_action(engine, side)
				if index < 0 or not engine.play_card(side, index):
					if not engine.pass_turn(side):
						break
			BattleEngine.State.WAITING_FOR_RESPONSE:
				var defender := engine.defender_side
				var attack_card: LogicCard = engine.active_card
				var index := AIController.choose_response(engine, defender, attack_card)
				if not engine.submit_response(defender, index):
					if not engine.submit_response(defender, -1):
						break
			_:
				break
	return steps
