extends SceneTree

func _initialize() -> void:
	print("class Logger exists: " + str(ClassDB.class_exists("Logger")))
	print("OS.add_logger: " + str(OS.has_method("add_logger")))
	print("OS.get_version: " + OS.get_version())
	print("user dir: " + OS.get_user_data_dir())
	print("has get_screen_count: " + str(DisplayServer.has_method("get_screen_count")))
	quit(0)
