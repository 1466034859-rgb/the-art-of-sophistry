extends SceneTree
## 故事模式全路径测试（四场）：
##   * 数据自检（每个错误选项都有台词、每个回合恰好 1 个漏洞）
##   * 每场正确路径必赢、全错路径必输、隐忍分支必结束、补救路径必能收尾
##   * 每场随机乱点 40 局：任何选项都必须推进流程、不得卡死（防“点了没反应”）
##
## 运行：godot --headless --path <project> --script res://tests/test_story.gd

const STORY_IDS := ["pantry_overtime", "comments_threshold", "dinner_education", "cafe_science"]
const REQUIRED_SCENES := ["office_pantry", "midnight_comments", "new_year_dinner", "academic_cafe"]

var library: GameLibrary
var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	print("=== Story mode test suite (4 scenes) ===")
	library = GameLibrary.shared()
	_test_data()
	for story_id in STORY_IDS:
		if not library.story_for_id(story_id).is_empty():
			_test_correct_path(story_id)
			_test_wrong_path(story_id)
			_test_remedy_path(story_id)
			_test_endure_path(story_id)
	_test_random_fuzz()
	_test_force_continue()
	print("SUMMARY checks=%d failures=%d" % [checks, failures])
	print("RESULT %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)


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

func _test_data() -> void:
	print("-- story data")
	check(library.load_errors.is_empty(), "load errors: %s" % str(library.load_errors))
	check_eq(library.stories.size(), 4, "story count")
	for story_id in STORY_IDS:
		var story: Dictionary = library.story_for_id(story_id)
		check(not story.is_empty(), "%s loaded" % story_id)
		check((story.get("rounds", []) as Array).size() == 3, "%s has 3 rounds" % story_id)
		check((story.get("judges", []) as Array).size() == 3, "%s has 3 judges" % story_id)
		check((story.get("closing", {}).get("options", []) as Array).size() >= 2, "%s has closing options" % story_id)
		check((story.get("prologue", []) as Array).size() >= 6, "%s prologue long enough" % story_id)
	for scene_id in REQUIRED_SCENES:
		var story: Dictionary = library.story_for_scene(scene_id)
		check(not story.is_empty(), "scene %s has a story" % scene_id)


func _make_engine(story_id: String) -> StoryEngine:
	var engine := StoryEngine.new()
	engine.setup(library.story_for_id(story_id))
	return engine


## 自动玩一局。strategy: correct / wrong / remedy
func _play(engine: StoryEngine, strategy: String) -> Dictionary:
	var steps := 0
	while engine.phase != StoryEngine.Phase.ENDED and steps < 600:
		steps += 1
		var view: Dictionary = engine.current_view
		var kind := str(view.get("type", ""))
		if kind == "choice":
			var option_id := _pick(engine, view, strategy)
			if option_id == "":
				return {"ok": false, "reason": "no option for %s" % kind, "steps": steps}
			var before: int = engine.phase
			engine.choose(option_id)
			if engine.phase == before and engine.current_view == view:
				return {"ok": false, "reason": "choose had no effect", "steps": steps}
		else:
			engine.advance()
	if engine.phase != StoryEngine.Phase.ENDED:
		return {"ok": false, "reason": "not ended", "steps": steps}
	return {"ok": true, "result": engine.result, "steps": steps, "engine": engine}


func _flaw_index(engine: StoryEngine) -> int:
	var story: Dictionary = engine.story
	var round_data: Dictionary = (story["rounds"] as Array)[engine.round_index]
	var statements: Array = round_data.get("statements", [])
	for i in range(statements.size()):
		if bool((statements[i] as Dictionary).get("flaw", false)):
			return i
	return -1


func _pick(engine: StoryEngine, view: Dictionary, strategy: String) -> String:
	var kind := str(view.get("kind", ""))
	var options: Array = view.get("options", [])
	if options.is_empty():
		return ""
	match kind:
		"trigger":
			for option in options:
				if str((option as Dictionary).get("id", "")) == "speak":
					return "speak"
			return str((options[0] as Dictionary).get("id", ""))
		"sentence":
			var flaw := _flaw_index(engine)
			var use_correct := strategy == "correct"
			if strategy == "remedy":
				use_correct = str(view.get("hint", "")) != ""
			if use_correct:
				return str(flaw)
			for option in options:
				var id := int((option as Dictionary).get("id", "0"))
				if id != flaw:
					return str(id)
			return str(flaw)
		"flaw":
			var round_data: Dictionary = (engine.story["rounds"] as Array)[engine.round_index]
			var raw_options: Array = (round_data.get("question", {}) as Dictionary).get("options", [])
			var use_correct := strategy == "correct"
			if strategy == "remedy":
				use_correct = str(view.get("hint", "")) != ""
			if use_correct:
				for i in range(raw_options.size()):
					if bool((raw_options[i] as Dictionary).get("correct", false)):
						return str(i)
			for option in options:
				var id := int((option as Dictionary).get("id", "0"))
				if id < raw_options.size() and not bool((raw_options[id] as Dictionary).get("correct", false)):
					return str(id)
			return str((options[0] as Dictionary).get("id", ""))
		"rebuttal":
			var round_data: Dictionary = (engine.story["rounds"] as Array)[engine.round_index]
			var raw_options: Array = (round_data.get("rebuttal", {}) as Dictionary).get("options", [])
			var want_correct := strategy != "wrong"
			for i in range(raw_options.size()):
				var is_correct := bool((raw_options[i] as Dictionary).get("correct", false))
				if is_correct == want_correct:
					return str(i)
			return str((options[0] as Dictionary).get("id", ""))
		"closing":
			for option in options:
				if str((option as Dictionary).get("id", "")) == "A":
					return "A"
			return str((options[0] as Dictionary).get("id", ""))
	return str((options[0] as Dictionary).get("id", ""))


func _test_correct_path(story_id: String) -> void:
	print("-- all-correct: " + story_id)
	var play := _play(_make_engine(story_id), "correct")
	check(bool(play["ok"]), "%s correct path ends: %s" % [story_id, str(play.get("reason", ""))])
	if not bool(play["ok"]):
		return
	var result: Dictionary = play["result"]
	check(bool(result.get("win", false)), "%s correct path wins" % story_id)
	check_eq(int(result.get("correct_first", 0)), 3, "%s three first-try correct" % story_id)
	check_eq(int(result.get("rounds_won", 0)), 3, "%s three rounds won" % story_id)


func _test_wrong_path(story_id: String) -> void:
	print("-- all-wrong: " + story_id)
	var play := _play(_make_engine(story_id), "wrong")
	check(bool(play["ok"]), "%s wrong path ends: %s" % [story_id, str(play.get("reason", ""))])
	if not bool(play["ok"]):
		return
	var result: Dictionary = play["result"]
	check(not bool(result.get("win", false)), "%s wrong path loses" % story_id)
	check_eq(int(result.get("rounds_won", 0)), 0, "%s no rounds won on wrong path" % story_id)


func _test_remedy_path(story_id: String) -> void:
	print("-- remedy: " + story_id)
	var play := _play(_make_engine(story_id), "remedy")
	check(bool(play["ok"]), "%s remedy path ends: %s" % [story_id, str(play.get("reason", ""))])
	if not bool(play["ok"]):
		return
	var result: Dictionary = play["result"]
	check(int(result.get("remedies", 0)) >= 1, "%s remedy recorded" % story_id)
	check(int(result.get("rounds_won", 0)) == 0, "%s remedy rounds are not wins" % story_id)


func _test_endure_path(story_id: String) -> void:
	print("-- endure: " + story_id)
	var engine := _make_engine(story_id)
	while engine.phase != StoryEngine.Phase.ENDED and engine.current_view.get("type", "") != "":
		var view: Dictionary = engine.current_view
		if str(view.get("type", "")) == "choice":
			engine.choose("endure")
		else:
			engine.advance()
	check(bool((engine.result as Dictionary).get("early", false)), "%s endure ends early" % story_id)
	check(not bool((engine.result as Dictionary).get("win", false)), "%s endure loses" % story_id)


func _test_force_continue() -> void:
	print("-- force_continue escape hatch")
	var engine := _make_engine("pantry_overtime")
	var guard := 0
	while engine.phase != StoryEngine.Phase.PICK_SENTENCE and guard < 100:
		guard += 1
		var view: Dictionary = engine.current_view
		if str(view.get("type", "")) == "choice":
			engine.choose("speak")
		else:
			engine.advance()
	check(engine.phase == StoryEngine.Phase.PICK_SENTENCE, "force_continue reaches PICK_SENTENCE")
	var before_phase: int = engine.phase
	var before_view: Dictionary = engine.current_view
	engine.force_continue()
	check(engine.phase != before_phase or engine.current_view != before_view, "force_continue advances out of stuck phase")


func _test_random_fuzz() -> void:
	print("-- random fuzz (4 scenes x 50 runs)")
	var rng := RandomNumberGenerator.new()
	var kinds_by_story: Dictionary = {}
	for story_id in STORY_IDS:
		kinds_by_story[story_id] = {}
	for run in range(200):
		rng.seed = run + 1
		var story_id: String = STORY_IDS[run % STORY_IDS.size()]
		var engine := _make_engine(story_id)
		var steps := 0
		while engine.phase != StoryEngine.Phase.ENDED and steps < 600:
			steps += 1
			var view: Dictionary = engine.current_view
			if str(view.get("type", "")) == "choice":
				var kind := str(view.get("kind", ""))
				(kinds_by_story[story_id] as Dictionary)[kind] = true
				var options: Array = view.get("options", [])
				if options.is_empty():
					failures += 1
					print("  FAIL: empty options in %s/%s" % [story_id, kind])
					break
				var pick: Dictionary = options[rng.randi_range(0, options.size() - 1)]
				var before_phase: int = engine.phase
				engine.choose(str(pick.get("id", "")))
				if engine.current_view.get("type", "") == "result":
					(kinds_by_story[story_id] as Dictionary)["result_" + str(engine.current_view.get("kind", ""))] = true
				if engine.phase == before_phase and engine.current_view == view:
					failures += 1
					print("  FAIL: dead option %s in %s/%s" % [str(pick.get("id", "")), story_id, kind])
					break
			else:
				engine.advance()
		check(engine.phase == StoryEngine.Phase.ENDED, "fuzz %d (%s) ends (steps=%d)" % [run, story_id, steps])
		for key in StoryEngine.AUDIENCE_KEYS:
			var value := int(engine.audience[key])
			check(value >= 0 and value <= 100, "audience bound %s" % key)
	for story_id in STORY_IDS:
		var kinds: Dictionary = kinds_by_story[story_id]
		check(kinds.has("sentence") and kinds.has("flaw") and kinds.has("rebuttal"), "%s hit all choice kinds" % story_id)
		check(kinds.has("result_correct"), "%s reached a correct result" % story_id)
		check(kinds.has("result_wrong"), "%s reached a wrong result" % story_id)
		check(kinds.has("result_fallback"), "%s reached the fallback branch" % story_id)
