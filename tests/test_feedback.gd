extends SceneTree
## 反馈/日志/诊断自检：
##   * Feedback autoload 存在，F3 调试层与日志文件已创建
##   * log_event 会落盘；引擎 push_error 会被 FileLogger 捕获
##   * save_feedback 会生成 feedback.json / session.log / 系统信息
##   * FeedbackPanel 能实例化，不崩
## 运行：godot --headless --path <project> --script res://tests/test_feedback.gd

var _failures: int = 0
var _checks: int = 0
var _started: bool = false


func _initialize() -> void:
	print("=== feedback / diagnostics test ===")
	process_frame.connect(_tick)


func _tick() -> void:
	if _started:
		return
	_started = true
	_run_all()
	_finish()


func _run_all() -> void:
	var feedback := root.get_node_or_null("Feedback")
	_check(feedback != null, "Feedback autoload exists")
	if feedback == null:
		return
	feedback._ensure_ready()
	_check(feedback._logger != null, "FileLogger installed")
	_check(feedback._debug_layer != null, "debug overlay created")
	_check(FileAccess.file_exists(feedback.log_path), "session log file exists")
	feedback.log_event("test_event", {"hello": "world"})
	push_error("feedback-capture-test-error")
	feedback.flush_now()
	var log_text := _read_text(feedback.log_path)
	_check(log_text.contains("test_event"), "log_event written to file")
	_check(log_text.contains("feedback-capture-test-error"), "engine error captured by logger")
	var dir: String = feedback.save_feedback("建议", "这是一条自动化测试反馈", "tester@example.com")
	_check(DirAccess.dir_exists_absolute(dir), "feedback dir created")
	_check(FileAccess.file_exists(dir + "/feedback.json"), "feedback.json created")
	_check(FileAccess.file_exists(dir + "/session.log"), "session.log copied")
	var payload_text := _read_text(dir + "/feedback.json")
	_check(payload_text.contains("自动化测试反馈"), "feedback text saved")
	_check(payload_text.contains("godot"), "system info saved")
	var diag: String = feedback.export_diagnostics()
	_check(DirAccess.dir_exists_absolute(diag), "diagnostics dir created")
	_check(FileAccess.file_exists(diag + "/system.json"), "diagnostics system.json created")
	var panel := FeedbackPanel.new()
	root.add_child(panel)
	_check(panel.get_child_count() > 0, "feedback panel builds UI")
	panel.queue_free()


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		print("  FAIL: " + label)


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


func _finish() -> void:
	print("SUMMARY checks=%d failures=%d" % [_checks, _failures])
	print("RESULT %s" % ("PASS" if _failures == 0 else "FAIL"))
	quit(0 if _failures == 0 else 1)
