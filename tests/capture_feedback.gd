extends SceneTree
## 截图：主菜单 → 打开反馈面板（给发布说明/README 用）。
## 运行：godot --fixed-fps 60 --path <project> --script res://tests/capture_feedback.gd

var _main: Control
var _frames: int = 0
var _stage: int = 0


func _initialize() -> void:
	print("=== feedback panel capture ===")
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frames += 1
	if _stage == 0:
		if _frames < 4:
			return
		var packed := load("res://scenes/main.tscn") as PackedScene
		_main = packed.instantiate()
		root.add_child(_main)
		_main._open_feedback()
		_stage = 1
		return
	if _stage == 1 and _frames > 40:
		var image := root.get_texture().get_image()
		var dir := ProjectSettings.globalize_path("res://screenshots")
		DirAccess.make_dir_recursive_absolute(dir)
		image.save_png(dir + "/21_feedback_panel.png")
		print("saved 21_feedback_panel.png")
		quit(0)
	if _frames > 600:
		print("TIMEOUT")
		quit(1)
