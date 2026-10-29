class_name FileLogger
extends Logger
## 把 Godot 引擎日志（含 push_error / 脚本报错 / 警告）收集到内存队列，
## 由 Feedback 自动落盘。不直接写文件，避免高频 IO。

var lines: Array[String] = []
var max_lines: int = 4000
var _mutex: Mutex = Mutex.new()


func _log_error(function: String, file: String, line: int, code: String, rationale: String, editor_notify: bool, error_type: int, script_backtraces: Array) -> void:
	var text := "[ERROR] %s:%d in %s | %s | %s" % [file, line, function, code, rationale]
	_append(text)


func _log_message(message: String, error: bool) -> void:
	_append(("[ERR] " if error else "[LOG] ") + message)


func _append(text: String) -> void:
	_mutex.lock()
	lines.append(text)
	while lines.size() > max_lines:
		lines.pop_front()
	_mutex.unlock()


func drain() -> Array[String]:
	_mutex.lock()
	var out := lines.duplicate()
	lines.clear()
	_mutex.unlock()
	return out
