extends SceneTree
## UI 冒烟测试：走「主菜单 → 选人 → 战斗 → 结算」全链路，由脚本代打玩家侧。
##
## 运行：
##   godot --headless --fixed-fps 60 --path <project> --script res://tests/test_ui.gd

var _main: Control
var _screen: BattleScreen
var _frames: int = 0
var _phase: int = 0
var _end_frames: int = -1


func _initialize() -> void:
	print("=== UI smoke test ===")
	process_frame.connect(_on_frame)


func _boot() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		print("UI smoke: FAIL cannot load main scene")
		quit(1)
		return
	_main = packed.instantiate()
	root.add_child(_main)
	# main._ready 已经跑过（主菜单构建完成），这里再走一遍选人 → 开战
	_main._show_select()
	_main._player_choice = "empath"
	_main._enemy_choice = "polite_assassin"
	_main._scenario_choice = "new_year_dinner"
	_main._start_battle()
	_screen = _main._screen as BattleScreen
	if _screen == null or _screen.engine == null:
		print("UI smoke: FAIL battle screen not created")
		quit(1)
		return
	var engine: BattleEngine = _screen.engine
	print("UI smoke: battle ready (%s vs %s)" % [
		engine.character_of(0).char_name,
		engine.character_of(1).char_name,
	])
	print("UI smoke: debate topic=%s claim=%s debate_panel=%s" % [
		engine.topic.title if engine.has_topic() else "<none>",
		engine.current_claim_text(),
		str(_screen._debate_panel.visible),
	])


func _on_frame() -> void:
	_frames += 1
	if _phase == 0:
		if _frames >= 4:
			_phase = 1
			_boot()
		return
	if _phase != 1 or _screen == null or _screen.engine == null:
		return
	var engine: BattleEngine = _screen.engine
	if _screen._ended:
		if _end_frames < 0:
			_end_frames = _frames
			print("UI smoke: battle ended at frame %d, spirit=%d/%d, cards=%d" % [
				_frames, engine.spirit_of(0), engine.spirit_of(1), engine.played_cards.size()
			])
		elif _frames - _end_frames > 90:
			var overlay_ok: bool = _screen._result_layer != null and _screen._result_layer.visible
			var debrief_ok: bool = _screen._result_debrief != null and _screen._result_debrief.text != ""
			print("UI smoke: result overlay visible=%s debrief=%s" % [str(overlay_ok), str(debrief_ok)])
			print("UI smoke: RESULT %s" % ("PASS" if overlay_ok and debrief_ok else "FAIL"))
			quit(0 if overlay_ok and debrief_ok else 1)
		return
	# 模拟玩家操作：能出牌就出牌，能回应就回应，否则沉默
	if engine.state == BattleEngine.State.AWAITING_ACTION and engine.turn_side == BattleEngine.PLAYER:
		var acted := false
		for i in range(engine.hand_of(BattleEngine.PLAYER).size()):
			if engine.can_play(BattleEngine.PLAYER, i):
				_screen._on_card_clicked(i)
				acted = true
				break
		if not acted:
			_screen._on_silence_pressed()
	elif engine.state == BattleEngine.State.WAITING_FOR_RESPONSE and engine.defender_side == BattleEngine.PLAYER:
		var responded := false
		for i in range(engine.hand_of(BattleEngine.PLAYER).size()):
			if engine.can_respond(BattleEngine.PLAYER, i):
				_screen._on_card_clicked(i)
				responded = true
				break
		if not responded:
			_screen._on_silence_pressed()
	if _frames > 9000:
		print("UI smoke: FAIL timeout frames=%d state=%d" % [_frames, engine.state])
		quit(1)
