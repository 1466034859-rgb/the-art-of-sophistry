extends Node
## 反馈 / 日志 / 诊断（Autoload: Feedback）
## - 自动把 Godot 引擎日志（含报错）与游戏事件写入 user://logs/session_*.log
## - 玩家可在游戏内提交反馈：保存到 user://feedback/<目录>/（feedback.json + 会话日志 + 截图 + 系统信息）
## - data/distribution.json 里配置 webhook_url 后，保存反馈会自动 POST 到你的服务器/机器人
## - F3 打开调试浮层（FPS / 场景 / 状态 / 最近事件 / 日志路径）

const VERSION_FALLBACK := "0.6-playtest"

var session_id: String = ""
var log_path: String = ""
var version: String = VERSION_FALLBACK
var webhook_url: String = ""
var feedback_form_url: String = ""

var _config: Dictionary = {}
var _logger: FileLogger = null
var _log_file: FileAccess = null
var _buffer: Array[String] = []
var _last_events: Array[Dictionary] = []
var _state_provider: Callable = Callable()
var _debug_layer: CanvasLayer = null
var _debug_label: RichTextLabel = null
var _debug_visible: bool = false
var _flush_elapsed: float = 0.0


var _ready_done: bool = false


func _ready() -> void:
	_ensure_ready()


## 幂等初始化：autoload 的 _ready 在某些 --script 测试模式下会晚于脚本执行，
## 因此所有公开入口都先调用它；正常游戏里就是 _ready 里跑一次。
func _ensure_ready() -> void:
	if _ready_done:
		return
	_ready_done = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_config()
	_setup_session()
	_install_logger()
	_build_debug_overlay()
	set_process(true)
	set_process_input(true)
	log_event("session_start", _system_info())


func _load_config() -> void:
	var path := "res://data/distribution.json"
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_config = parsed
		version = str(_config.get("version", VERSION_FALLBACK))
		webhook_url = str(_config.get("webhook_url", ""))
		feedback_form_url = str(_config.get("feedback_form_url", ""))


func _setup_session() -> void:
	DirAccess.make_dir_recursive_absolute("user://logs")
	DirAccess.make_dir_recursive_absolute("user://feedback")
	session_id = Time.get_datetime_string_from_system().replace("-", "").replace(":", "").replace(" ", "_")
	log_path = "user://logs/session_%s.log" % session_id
	_log_file = FileAccess.open(log_path, FileAccess.WRITE)
	if _log_file != null:
		_log_file.store_line("# 诡辩之术 %s · session %s" % [version, session_id])
		_log_file.flush()


func _install_logger() -> void:
	_logger = FileLogger.new()
	OS.add_logger(_logger)


func _process(delta: float) -> void:
	if _logger != null:
		var pending := _logger.drain()
		if not pending.is_empty():
			_buffer.append_array(pending)
	_flush_elapsed += delta
	if _flush_elapsed >= 0.5:
		_flush_elapsed = 0.0
		flush_now()
	if _debug_visible and _debug_label != null:
		_update_debug_text()


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_F3:
			_debug_visible = not _debug_visible
			if _debug_layer != null:
				_debug_layer.visible = _debug_visible
			if _debug_visible:
				_update_debug_text()
			get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# 日志
# ---------------------------------------------------------------------------

func log_event(kind: String, data: Dictionary = {}) -> void:
	_ensure_ready()
	var entry := {
		"ts": Time.get_datetime_string_from_system(),
		"session": session_id,
		"kind": kind,
		"data": data,
	}
	_buffer.append(JSON.stringify(entry))
	_last_events.append(entry)
	while _last_events.size() > 120:
		_last_events.pop_front()


func log_error(message: String, data: Dictionary = {}) -> void:
	var payload := data.duplicate(true)
	payload["message"] = message
	log_event("error", payload)


func flush_now() -> void:
	if _logger != null:
		_buffer.append_array(_logger.drain())
	if _log_file == null:
		return
	if _buffer.is_empty():
		_log_file.flush()
		return
	for line in _buffer:
		_log_file.store_line(line)
	_buffer.clear()
	_log_file.flush()


func get_log_path() -> String:
	_ensure_ready()
	return ProjectSettings.globalize_path(log_path)


func get_recent_events(count: int = 30) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var start := maxi(0, _last_events.size() - count)
	for i in range(start, _last_events.size()):
		out.append(_last_events[i])
	return out


func register_state_provider(provider: Callable) -> void:
	_state_provider = provider


# ---------------------------------------------------------------------------
# 反馈与诊断
# ---------------------------------------------------------------------------

func webhook_configured() -> bool:
	return webhook_url.begins_with("http")


func save_feedback(category: String, text: String, contact: String = "") -> String:
	_ensure_ready()
	var stamp := Time.get_datetime_string_from_system().replace("-", "").replace(":", "").replace(" ", "_")
	var dir := "user://feedback/%s_%s" % [session_id, stamp]
	DirAccess.make_dir_recursive_absolute(dir)
	flush_now()
	var payload := {
		"version": version,
		"session_id": session_id,
		"category": category,
		"text": text,
		"contact": contact,
		"system": _system_info(),
		"events": get_recent_events(80),
	}
	var feedback_file := FileAccess.open(dir + "/feedback.json", FileAccess.WRITE)
	if feedback_file != null:
		feedback_file.store_string(JSON.stringify(payload, "  "))
		feedback_file.close()
	_copy_text(log_path, dir + "/session.log")
	if DisplayServer.get_name() != "headless":
		var viewport := get_viewport()
		if viewport != null:
			var image := viewport.get_texture().get_image()
			if image != null:
				image.save_png(dir + "/screenshot.png")
	_write_readme(dir)
	log_event("feedback_saved", {"category": category, "dir": ProjectSettings.globalize_path(dir)})
	if webhook_configured():
		_upload_feedback(dir, payload)
	return ProjectSettings.globalize_path(dir)


func export_diagnostics() -> String:
	_ensure_ready()
	flush_now()
	var dir := "user://diagnostics"
	DirAccess.make_dir_recursive_absolute(dir)
	var stamp := Time.get_datetime_string_from_system().replace("-", "").replace(":", "").replace(" ", "_")
	var bundle_dir := "%s/%s" % [dir, stamp]
	DirAccess.make_dir_recursive_absolute(bundle_dir)
	_copy_text(log_path, bundle_dir + "/session.log")
	var info := FileAccess.open(bundle_dir + "/system.json", FileAccess.WRITE)
	if info != null:
		info.store_string(JSON.stringify(_system_info(), "  "))
		info.close()
	var events := FileAccess.open(bundle_dir + "/events.json", FileAccess.WRITE)
	if events != null:
		events.store_string(JSON.stringify(get_recent_events(120), "  "))
		events.close()
	_write_readme(bundle_dir)
	return ProjectSettings.globalize_path(bundle_dir)


func open_feedback_folder() -> void:
	_ensure_ready()
	DirAccess.make_dir_recursive_absolute("user://feedback")
	OS.shell_open(ProjectSettings.globalize_path("user://feedback"))


func open_form_url() -> void:
	if feedback_form_url.begins_with("http"):
		OS.shell_open(feedback_form_url)


func _upload_feedback(dir: String, payload: Dictionary) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		log_event("upload_result", {"result": result, "code": code, "body": body.get_string_from_utf8().left(300)})
		var status := FileAccess.open(dir + "/upload.txt", FileAccess.WRITE)
		if status != null:
			status.store_line("result=%d code=%d" % [result, code])
			status.close()
		http.queue_free()
	)
	var headers := PackedStringArray(["Content-Type: application/json"])
	var error := http.request(webhook_url, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		log_error("webhook request failed to start", {"error": error})


func _system_info() -> Dictionary:
	var info := {
		"version": version,
		"godot": str(Engine.get_version_info().get("string", "")),
		"os": "%s %s" % [OS.get_name(), OS.get_version()],
		"locale": OS.get_locale(),
		"session_id": session_id,
		"project": str(ProjectSettings.get_setting("application/config/name", "")),
		"user_dir": ProjectSettings.globalize_path("user://"),
	}
	if DisplayServer.get_name() != "headless":
		info["screen"] = "%dx%d" % [DisplayServer.screen_get_size().x, DisplayServer.screen_get_size().y]
		info["window"] = "%dx%d" % [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y]
		info["refresh_rate"] = DisplayServer.screen_get_refresh_rate()
	return info


func _copy_text(source: String, target: String) -> void:
	if not FileAccess.file_exists(source):
		return
	var input := FileAccess.open(source, FileAccess.READ)
	var output := FileAccess.open(target, FileAccess.WRITE)
	if input == null or output == null:
		return
	output.store_string(input.get_as_text())
	output.close()


func _write_readme(dir: String) -> void:
	var readme := FileAccess.open(dir + "/如何反馈.txt", FileAccess.WRITE)
	if readme == null:
		return
	readme.store_line("感谢试玩《诡辩之术》！")
	readme.store_line("")
	readme.store_line("这个文件夹里是这次的反馈材料：")
	readme.store_line("- feedback.json：反馈正文 + 系统信息 + 最近事件")
	readme.store_line("- session.log：本次会话日志（含引擎报错）")
	readme.store_line("- screenshot.png：提交反馈时的画面")
	readme.store_line("")
	readme.store_line("请把整个文件夹打包，发给开发者即可。")
	readme.close()


# ---------------------------------------------------------------------------
# F3 调试浮层
# ---------------------------------------------------------------------------

func _build_debug_overlay() -> void:
	_debug_layer = CanvasLayer.new()
	_debug_layer.layer = 128
	_debug_layer.visible = false
	add_child(_debug_layer)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 12
	panel.offset_top = 80
	panel.offset_right = 560
	panel.offset_bottom = 360
	_debug_layer.add_child(panel)
	_debug_label = RichTextLabel.new()
	_debug_label.bbcode_enabled = true
	_debug_label.scroll_active = true
	_debug_label.add_theme_font_size_override("normal_font_size", 12)
	panel.add_child(_debug_label)


func _update_debug_text() -> void:
	if _debug_label == null:
		return
	var lines: Array[String] = []
	lines.append("[b]F3 调试[/b]  FPS %d" % Engine.get_frames_per_second())
	lines.append("版本 %s · 会话 %s" % [version, session_id])
	lines.append("日志 " + get_log_path())
	var scene := get_tree().current_scene if get_tree() != null else null
	if scene != null:
		lines.append("场景 " + str(scene.name))
	if _state_provider.is_valid():
		lines.append("状态 " + str(_state_provider.call()))
	lines.append("— 最近事件 —")
	var recent := get_recent_events(10)
	for entry in recent:
		var data_text := JSON.stringify(entry.get("data", {}))
		if data_text.length() > 90:
			data_text = data_text.left(90) + "…"
		lines.append("%s %s %s" % [str(entry.get("ts", "")).substr(11), str(entry.get("kind", "")), data_text])
	_debug_label.text = "\n".join(lines)
