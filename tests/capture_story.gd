extends SceneTree
## 故事模式 UI 冒烟 + 自动截图（需要真实渲染，不要加 --headless）。
## 走「主菜单 → 故事模式 → 正确路径 → 复盘」全链路，并在关键节点保存截图。
##
## 运行：godot --fixed-fps 60 --path <project> --script res://tests/capture_story.gd

var _main: Control
var _screen: StoryScreen
var _frames: int = 0
var _wait: int = 0
var _last_key: String = ""
var _saved: Dictionary = {}
var _phase: int = 0
var _shot_dir := "res://screenshots"


func _initialize() -> void:
	var absolute := ProjectSettings.globalize_path(_shot_dir)
	DirAccess.make_dir_recursive_absolute(absolute)
	print("=== story capture ===")
	process_frame.connect(_on_frame)


func _save(name: String) -> void:
	var image := root.get_texture().get_image()
	if image == null:
		print("capture: FAIL null image ", name)
		return
	var path := ProjectSettings.globalize_path("%s/%s.png" % [_shot_dir, name])
	image.save_png(path)
	print("capture: %s -> %s" % [name, path])


func _boot() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_main = packed.instantiate()
	root.add_child(_main)
	_main._show_story("pantry_overtime")
	_screen = _main._screen as StoryScreen
	if _screen == null or _screen.engine == null:
		print("capture: FAIL story screen not created")
		quit(1)


func _on_frame() -> void:
	_frames += 1
	if _phase == 0:
		if _frames >= 4:
			_phase = 1
			_boot()
		return
	if _screen == null or _screen.engine == null:
		return
	var engine: StoryEngine = _screen.engine
	var view: Dictionary = engine.current_view
	var key := "%s:%d:%d" % [str(view.get("type", "")), engine.phase, engine.round_index]
	if key != _last_key:
		_last_key = key
		_wait = 0
	var delay := 90 if str(view.get("type", "")) == "judging" else (40 if str(view.get("type", "")) in ["dialogue", "result"] else 12)
	_wait += 1
	if _wait == delay:
		_try_save(view)
	if _wait >= delay + 10:
		# 打字机还在跑就先补全，下一帧再推进（避免截图脚本自己把打字动画跳过去）
		if _screen._try_finish_typing():
			return
		_act(view)
	if engine.phase == StoryEngine.Phase.ENDED:
		if not _saved.has("19_debrief"):
			_try_save(view)
		print("capture: story finished, win=%s" % str((engine.result as Dictionary).get("win", false)))
		print("capture: RESULT %s" % ("PASS" if _saved.has("19_debrief") else "FAIL"))
		quit(0 if _saved.has("19_debrief") else 1)
	if _frames > 6000:
		print("capture: FAIL timeout view=%s phase=%d" % [str(view.get("type", "")), engine.phase])
		quit(1)


func _try_save(view: Dictionary) -> void:
	var type := str(view.get("type", ""))
	var name := ""
	match type:
		"scene_card":
			name = "10_scene_card"
		"dialogue":
			name = "11_prologue"
		"choice":
			match str(view.get("kind", "")):
				"sentence":
					name = "12_find_flaw"
				"flaw":
					name = "13_fallacy_choice"
				"rebuttal":
					name = "14_rebuttal"
				"closing":
					name = "15_closing"
		"result":
			name = "16_correct" if str(view.get("kind", "")) in ["correct", "remedy_ok"] else "16_result"
		"audience":
			name = "17_audience"
		"judging":
			name = "18_judging"
		"debrief":
			name = "19_debrief"
	if name == "" or _saved.has(name):
		return
	_saved[name] = true
	_save(name)


func _act(view: Dictionary) -> void:
	# 走 UI 的真实交互入口（按钮回调），而不是直接调用引擎，顺便验证 UI 链路
	if str(view.get("type", "")) == "choice":
		_screen._on_option_pressed(_pick(engine_of(), view))
	else:
		_screen._on_continue_pressed()


func engine_of() -> StoryEngine:
	return _screen.engine


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
