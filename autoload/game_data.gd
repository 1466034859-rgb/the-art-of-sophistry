extends Node
## 静态数据 Autoload：启动时把 res://data/*.json 读进内存，供 UI 与引擎使用。


var library: GameLibrary


func _ready() -> void:
	library = GameLibrary.shared()
	if not library.load_errors.is_empty():
		for error_text in library.load_errors:
			push_error("[GameData] " + error_text)
	print("[Sophistry] 数据就绪：%d 张卡 / %d 名角色 / %d 个场景 / %d 种状态" % [
		library.cards.size(),
		library.characters.size(),
		library.scenarios.size(),
		library.statuses.size(),
	])


func character_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in library.characters.keys():
		ids.append(str(key))
	return ids


func scenario_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in library.scenarios.keys():
		ids.append(str(key))
	return ids
