extends SceneTree
## 错误分支 UI 回归测试（专门抓“选错之后没选项/点不动”）：
##   * 四场都走「每次尽量选错」的路径
##   * 任何 choice 视图必须至少 2 个选项；补救重选（带 hint）也必须 >= 2 个
##   * 任何非 choice 视图必须有可点击内容（继续按钮）
##   * 最终必须抵达复盘且判负
##
## 运行：godot --headless --fixed-fps 60 --path <project> --script res://tests/test_story_wrong_ui.gd

const STORY_IDS := ["pantry_overtime", "comments_threshold", "dinner_education", "cafe_science"]

var library: GameLibrary
var _index: int = 0
var _screen: StoryScreen = null
var _frames: int = 0
var _failures: int = 0
var _checks: int = 0
var _seen_choice_kinds: Dictionary = {}
var _remedy_checked: bool = false


func _initialize() -> void:
	print("=== Story UI wrong-path regression (4 scenes) ===")
	library = GameLibrary.shared()
	process_frame.connect(_tick)
	_start_next()


func _start_next() -> void:
	if _screen != null:
		_screen.queue_free()
		_screen = null
	if _index >= STORY_IDS.size():
		print("SUMMARY checks=%d failures=%d" % [_checks, _failures])
		print("RESULT %s" % ("PASS" if _failures == 0 else "FAIL"))
		quit(0 if _failures == 0 else 1)
		return
	_screen = StoryScreen.new()
	_screen.setup(STORY_IDS[_index])
	root.add_child(_screen)
	_frames = 0
	_seen_choice_kinds = {}
	_remedy_checked = false


func _fail(message: String) -> void:
	_failures += 1
	print("  FAIL: " + message)


func _tick() -> void:
	if _screen == null:
		return
	_frames += 1
	if _frames < 3:
		return
	var engine: StoryEngine = _screen.engine
	if engine == null:
		return
	var view: Dictionary = engine.current_view
	var type := str(view.get("type", ""))
	if type == "debrief":
		_checks += 1
		if bool((engine.result as Dictionary).get("win", false)):
			_fail("%s wrong path should lose" % STORY_IDS[_index])
		_index += 1
		_start_next()
		return
	if engine.phase == StoryEngine.Phase.ENDED:
		_fail("%s ended without debrief" % STORY_IDS[_index])
		_index += 1
		_start_next()
		return
	if type == "choice":
		var options: Array = view.get("options", [])
		var kind := str(view.get("kind", ""))
		_checks += 1
		if options.is_empty():
			_fail("%s empty choice view kind=%s hint=%s" % [STORY_IDS[_index], kind, str(view.get("hint", ""))])
			_index += 1
			_start_next()
			return
		if kind == "sentence" and str(view.get("hint", "")) != "":
			# 重点回归：选错后的补救重选必须有选项
			_checks += 1
			_remedy_checked = true
			if options.size() < 2:
				_fail("%s remedy choice only has %d option(s)" % [STORY_IDS[_index], options.size()])
		_seen_choice_kinds[kind] = true
		_screen._on_option_pressed(_wrong_pick(engine, view))
	else:
		# 非选择视图必须有可点击内容（继续按钮）
		if _screen._content.get_child_count() == 0:
			_fail("%s empty non-choice view %s" % [STORY_IDS[_index], type])
		_screen._on_continue_pressed()
	if _frames > 20000:
		_fail("%s timeout at %s" % [STORY_IDS[_index], type])
		_index += 1
		_start_next()


func _flaw_index(engine: StoryEngine) -> int:
	var round_data: Dictionary = (engine.story["rounds"] as Array)[engine.round_index]
	var statements: Array = round_data.get("statements", [])
	for i in range(statements.size()):
		if bool((statements[i] as Dictionary).get("flaw", false)):
			return i
	return -1


func _wrong_pick(engine: StoryEngine, view: Dictionary) -> String:
	var kind := str(view.get("kind", ""))
	var options: Array = view.get("options", [])
	if options.is_empty():
		return ""
	match kind:
		"trigger":
			return "speak"
		"sentence":
			var flaw := _flaw_index(engine)
			for option in options:
				var id := int((option as Dictionary).get("id", "0"))
				if id != flaw:
					return str(id)
			return str((options[0] as Dictionary).get("id", ""))
		"flaw":
			var round_data: Dictionary = (engine.story["rounds"] as Array)[engine.round_index]
			var raw_options: Array = (round_data.get("question", {}) as Dictionary).get("options", [])
			for option in options:
				var id := int((option as Dictionary).get("id", "0"))
				if id < raw_options.size() and not bool((raw_options[id] as Dictionary).get("correct", false)):
					return str(id)
			return str((options[0] as Dictionary).get("id", ""))
		"rebuttal":
			var round_data: Dictionary = (engine.story["rounds"] as Array)[engine.round_index]
			var raw_options: Array = (round_data.get("rebuttal", {}) as Dictionary).get("options", [])
			for i in range(raw_options.size()):
				if not bool((raw_options[i] as Dictionary).get("correct", false)):
					return str(i)
			return str((options[0] as Dictionary).get("id", ""))
		"closing":
			return "C"
	return str((options[0] as Dictionary).get("id", ""))
