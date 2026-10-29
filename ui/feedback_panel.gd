class_name FeedbackPanel
extends Control
## 游戏内反馈面板：玩家写完会保存到 user://feedback/<会话>_<时间>/，
## 里面包含反馈正文、会话日志、截图、系统信息；配置 webhook 后会自动上传。

signal closed

var _category: OptionButton
var _text: TextEdit
var _contact: LineEdit
var _status: Label
var _save_button: Button
var _form_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.03, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := UiKit.panel(UiKit.COL_ACCENT, UiKit.COL_PANEL_DARK)
	panel.custom_minimum_size = Vector2(620, 0)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	column.add_child(UiKit.title("反馈 / 问题上报", 26))
	column.add_child(UiKit.wrapped("卡住了、文案不对、难度不合适、或者单纯想骂两句，都可以写在这里。保存后会生成一个文件夹，打包发给开发者即可。", 13, UiKit.COL_INK_DIM))

	var category_row := HBoxContainer.new()
	column.add_child(category_row)
	category_row.add_child(UiKit.label("类型", 13, UiKit.COL_INK_DIM))
	_category = OptionButton.new()
	_category.add_theme_font_size_override("font_size", 13)
	for item in ["卡住了 / 选不了", "文案 / 错别字", "难度 / 节奏", "建议", "其他"]:
		_category.add_item(item)
	_category.custom_minimum_size = Vector2(260, 36)
	category_row.add_child(_category)

	_text = TextEdit.new()
	_text.placeholder_text = "发生了什么？在哪个场景、哪一步？你当时想做什么？"
	_text.custom_minimum_size = Vector2(0, 170)
	_text.add_theme_font_size_override("font_size", 14)
	column.add_child(_text)

	_contact = LineEdit.new()
	_contact.placeholder_text = "联系方式（可选，方便追问）"
	_contact.custom_minimum_size = Vector2(0, 36)
	_contact.add_theme_font_size_override("font_size", 13)
	column.add_child(_contact)

	_status = UiKit.wrapped("", 12, UiKit.COL_GOOD)
	column.add_child(_status)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)
	_save_button = UiKit.button("保存反馈（含日志/截图）", 15, 42)
	_save_button.custom_minimum_size = Vector2(260, 42)
	_save_button.pressed.connect(_on_save)
	buttons.add_child(_save_button)
	var open_button := UiKit.button("打开反馈文件夹", 13, 42)
	open_button.custom_minimum_size = Vector2(160, 42)
	open_button.pressed.connect(_on_open_folder)
	buttons.add_child(open_button)
	_form_button = UiKit.button("在线问卷", 13, 42)
	_form_button.custom_minimum_size = Vector2(140, 42)
	_form_button.visible = false
	_form_button.pressed.connect(_on_open_form)
	buttons.add_child(_form_button)
	var close_button := UiKit.button("关闭", 13, 42)
	close_button.custom_minimum_size = Vector2(100, 42)
	close_button.pressed.connect(func() -> void: closed.emit())
	buttons.add_child(close_button)

	column.add_child(UiKit.wrapped("提示：游戏中按 F3 可打开调试浮层，截图时会带上帧率与最近事件。", 12, UiKit.COL_INK_DIM))
	_refresh_form_button()


func _refresh_form_button() -> void:
	var feedback := get_node_or_null("/root/Feedback")
	if feedback != null:
		var url := str(feedback.feedback_form_url)
		_form_button.visible = url.begins_with("http")


func _on_save() -> void:
	var feedback := get_node_or_null("/root/Feedback")
	if feedback == null:
		_status.text = "反馈模块未加载，请重启游戏后再试。"
		_status.add_theme_color_override("font_color", UiKit.COL_DANGER)
		return
	var text := _text.text.strip_edges()
	if text == "":
		_status.text = "至少写一句发生了什么，再保存。"
		_status.add_theme_color_override("font_color", UiKit.COL_DANGER)
		return
	_save_button.disabled = true
	_status.text = "正在保存……"
	var category := _category.get_item_text(_category.selected)
	var path: String = feedback.save_feedback(category, text, _contact.text.strip_edges())
	_status.add_theme_color_override("font_color", UiKit.COL_GOOD)
	if feedback.webhook_configured():
		_status.text = "已保存，并尝试上传到服务器。\n本地路径：%s" % path
	else:
		_status.text = "已保存。把整个文件夹打包发给开发者即可。\n本地路径：%s" % path
	_save_button.disabled = false
	_text.text = ""


func _on_open_folder() -> void:
	var feedback := get_node_or_null("/root/Feedback")
	if feedback != null:
		feedback.open_feedback_folder()


func _on_open_form() -> void:
	var feedback := get_node_or_null("/root/Feedback")
	if feedback != null:
		feedback.open_form_url()
