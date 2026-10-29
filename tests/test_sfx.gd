extends SceneTree
## 程序化音效自检：确认 8 个音效流都已合成且非空，调用不会崩。
## 运行：godot --headless --path <project> --script res://tests/test_sfx.gd

func _initialize() -> void:
	var failures := 0
	var checks := 0
	var sfx := root.get_node_or_null("Sfx")
	if sfx == null:
		print("RESULT FAIL (Sfx autoload missing)")
		quit(1)
		return
	sfx._ensure_streams()
	var streams: Dictionary = sfx._streams
	var names := ["click", "confirm", "correct", "wrong", "vote_you", "vote_other", "win", "lose"]
	for sound_name in names:
		checks += 1
		if not streams.has(sound_name):
			failures += 1
			print("  FAIL: missing stream " + sound_name)
			continue
		var wav: AudioStreamWAV = streams[sound_name]
		if wav == null or wav.data.size() == 0:
			failures += 1
			print("  FAIL: empty stream " + sound_name)
	sfx.click()
	sfx.confirm()
	sfx.correct()
	sfx.wrong()
	sfx.vote(true)
	sfx.vote(false)
	sfx.win()
	sfx.lose()
	checks += 1
	if sfx.toggle() != false:
		failures += 1
		print("  FAIL: toggle did not turn sound off")
	sfx.enabled = true
	print("SUMMARY checks=%d failures=%d" % [checks, failures])
	print("RESULT %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
