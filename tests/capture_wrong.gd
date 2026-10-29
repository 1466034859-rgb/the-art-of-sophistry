extends SceneTree
## 复现「选错之后卡住」：真实渲染 + 截图错误结果页与补救选择页。

var _main: Control
var _screen: StoryScreen
var _frames: int = 0
var _wait: int = 0
var _last_key: String = ""
var _stage: int = 0


func _initialize() -> void:
	var dir := ProjectSettings.globalize_path("res://screenshots")
	DirAccess.make_dir_recursive_absolute(dir)
	print("=== wrong path capture ===")
	process_frame.connect(_on_frame)


func _save(name: String) -> void:
	var image := root.get_texture().get_image()
	if image == null:
		print("FAIL null image")
		return
	var path := ProjectSettings.globalize_path("res://screenshots/%s.png" % name)
	image.save_png(path)
	print("saved " + path)


func _boot() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_main = packed.instantiate()
	root.add_child(_main)
	_main._show_story("pantry_overtime")
	_screen = _main._screen as StoryScreen


func _on_frame() -> void:
	_frames += 1
	if _stage == 0:
		if _frames >= 4:
			_stage = 1
			_boot()
		return
	if _screen == null or _screen.engine == null:
		return
	var engine: StoryEngine = _screen.engine
	var view: Dictionary = engine.current_view
	var key := "%s:%s:%d" % [str(view.get("type", "")), str(view.get("kind", "")), engine.phase]
	if key != _last_key:
		_last_key = key
		_wait = 0
		print("view f%d %s options=%d" % [_frames, key, (view.get("options", []) as Array).size()])
		if str(view.get("type", "")) == "choice" and (view.get("options", []) as Array).is_empty():
			print("  EMPTY CHOICE FULL=" + str(view))
			print("  engine removed=" + str(engine._removed_sentence) + " remedy=" + str(engine._sentence_remedy) + " round_index=" + str(engine.round_index) + " round_id=" + str(engine._round.get("id", "?")) + " pending=" + str(engine._pending_after) + " attempts=" + str(engine._sentence_attempts))
			print("  screen options=" + str(_screen._choice_options.size()) + " buttons=" + str(_screen._choice_buttons.size()))
	_wait += 1
	if _wait == 20:
		if str(view.get("type", "")) == "choice" and str(view.get("kind", "")) == "sentence" and str(view.get("hint", "")) != "":
			_save("20_wrong_remedy")
			quit(0)
		elif str(view.get("type", "")) == "result" and str(view.get("kind", "")) == "wrong":
			_save("20_wrong_result")
	if _wait >= 30:
		if str(view.get("type", "")) == "choice":
			# 第一次选句：故意选错
			var flaw := _flaw_index(engine)
			for option in (view.get("options", []) as Array):
				var id := int((option as Dictionary).get("id", "0"))
				if id != flaw:
					_screen._on_option_pressed(str(id))
					break
		else:
			_screen._on_continue_pressed()
	if _frames > 2000:
		print("TIMEOUT view=" + key)
		quit(1)


func _flaw_index(engine: StoryEngine) -> int:
	var round_data: Dictionary = (engine.story["rounds"] as Array)[engine.round_index]
	var statements: Array = round_data.get("statements", [])
	for i in range(statements.size()):
		if bool((statements[i] as Dictionary).get("flaw", false)):
			return i
	return -1
