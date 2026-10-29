extends SceneTree
## 四场故事 UI 全链路测试（headless，走真实界面回调）：
##   对每个故事：创建 StoryScreen → 用按钮回调推进 → 正确路径 → 校验抵达复盘。
## 这样能覆盖「UI 点击 → 引擎 → 视图刷新」整条链路，而不只是引擎单测。
##
## 运行：godot --headless --fixed-fps 60 --path <project> --script res://tests/test_story_ui.gd

const STORY_IDS := ["pantry_overtime", "comments_threshold", "dinner_education", "cafe_science"]

var library: GameLibrary
var _index: int = 0
var _screen: StoryScreen = null
var _frames: int = 0
var _total_frames: int = 0
var _failures: int = 0
var _reports: Array[String] = []
var _pause_checked: bool = false


func _initialize() -> void:
	print("=== Story UI full-play test (4 scenes) ===")
	library = GameLibrary.shared()
	process_frame.connect(_tick)
	_start_next()


func _start_next() -> void:
	if _screen != null:
		_screen.queue_free()
		_screen = null
	if _index >= STORY_IDS.size():
		print("SUMMARY checks=%d failures=%d" % [_index * 4 + 6, _failures])
		for report in _reports:
			print("  " + report)
		print("RESULT %s" % ("PASS" if _failures == 0 else "FAIL"))
		quit(0 if _failures == 0 else 1)
		return
	_screen = StoryScreen.new()
	_screen.setup(STORY_IDS[_index])
	root.add_child(_screen)
	_frames = 0


func _tick() -> void:
	if _screen == null:
		return
	_frames += 1
	_total_frames += 1
	if _frames < 3:
		return
	if not _pause_checked:
		_pause_checked = true
		_check_pause()
	var engine: StoryEngine = _screen.engine
	if engine == null:
		return
	var view: Dictionary = engine.current_view
	if str(view.get("type", "")) == "debrief":
		_check_debrief(engine)
		_reports.append("%s: %d frames (~%.1fs)" % [STORY_IDS[_index], _frames, float(_frames) / 60.0])
		_index += 1
		_start_next()
		return
	if engine.phase == StoryEngine.Phase.ENDED:
		_failures += 1
		print("  FAIL: %s ended without debrief" % STORY_IDS[_index])
		_index += 1
		_start_next()
		return
	if str(view.get("type", "")) == "choice":
		_screen._on_option_pressed(_pick(engine, view))
	else:
		_screen._on_continue_pressed()
	if _frames > 20000:
		_failures += 1
		print("  FAIL: %s timeout phase=%d view=%s" % [STORY_IDS[_index], engine.phase, str(view.get("type", ""))])
		_index += 1
		_start_next()


func _check_pause() -> void:
	_screen._toggle_pause()
	if not _screen._paused or not _screen._pause_overlay.visible:
		_failures += 1
		print("  FAIL: pause overlay did not open")
	_screen._toggle_pause()
	if _screen._paused or _screen._pause_overlay.visible:
		_failures += 1
		print("  FAIL: pause overlay did not close")


func _check_debrief(engine: StoryEngine) -> void:
	var result: Dictionary = engine.result
	var ok := true
	if not bool(result.get("win", false)):
		ok = false
		print("  FAIL: %s correct path did not win" % STORY_IDS[_index])
	if (engine.history as Array).size() < 9:
		ok = false
		print("  FAIL: %s history too short (%d)" % [STORY_IDS[_index], engine.history.size()])
	if not ok:
		_failures += 1


func _flaw_index(engine: StoryEngine) -> int:
	var round_data: Dictionary = (engine.story["rounds"] as Array)[engine.round_index]
	var statements: Array = round_data.get("statements", [])
	for i in range(statements.size()):
		if bool((statements[i] as Dictionary).get("flaw", false)):
			return i
	return -1


func _pick(engine: StoryEngine, view: Dictionary) -> String:
	var kind := str(view.get("kind", ""))
	var options: Array = view.get("options", [])
	if options.is_empty():
		return ""
	match kind:
		"trigger":
			return "speak"
		"sentence":
			return str(_flaw_index(engine))
		"flaw":
			var round_data: Dictionary = (engine.story["rounds"] as Array)[engine.round_index]
			var raw_options: Array = (round_data.get("question", {}) as Dictionary).get("options", [])
			for i in range(raw_options.size()):
				if bool((raw_options[i] as Dictionary).get("correct", false)):
					return str(i)
			return str((options[0] as Dictionary).get("id", ""))
		"rebuttal":
			var round_data: Dictionary = (engine.story["rounds"] as Array)[engine.round_index]
			var raw_options: Array = (round_data.get("rebuttal", {}) as Dictionary).get("options", [])
			for i in range(raw_options.size()):
				if bool((raw_options[i] as Dictionary).get("correct", false)):
					return str(i)
			return str((options[0] as Dictionary).get("id", ""))
		"closing":
			return "A"
	return str((options[0] as Dictionary).get("id", ""))
