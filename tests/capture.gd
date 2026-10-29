extends SceneTree
## 自动截图脚本（需要真实渲染，不要加 --headless）。
## 运行：
##   godot --fixed-fps 60 --path <project> --script res://tests/capture.gd
## 输出：res://screenshots/*.png

var _main: Control
var _frames: int = 0
var _phase: int = 0
var _shot_dir: String = "res://screenshots"
var _captured_response := false
var _captured_result := false
var _capture_started := false


func _initialize() -> void:
	var absolute := ProjectSettings.globalize_path(_shot_dir)
	DirAccess.make_dir_recursive_absolute(absolute)
	print("=== capture ===")
	process_frame.connect(_on_frame)


func _save(shot_name: String) -> void:
	var image := root.get_texture().get_image()
	if image == null:
		print("capture: FAIL null image for ", shot_name)
		return
	var path := ProjectSettings.globalize_path("%s/%s.png" % [_shot_dir, shot_name])
	var error := image.save_png(path)
	print("capture: %s -> %s (err=%d)" % [shot_name, path, error])


func _auto_play() -> void:
	if _main == null:
		return
	var screen: BattleScreen = _main._screen as BattleScreen
	if screen == null or screen.engine == null or screen._ended:
		return
	var engine: BattleEngine = screen.engine
	if engine.state == BattleEngine.State.AWAITING_ACTION and engine.turn_side == BattleEngine.PLAYER:
		for i in range(engine.hand_of(BattleEngine.PLAYER).size()):
			if engine.can_play(BattleEngine.PLAYER, i):
				screen._on_card_clicked(i)
				return
		screen._on_silence_pressed()
	elif engine.state == BattleEngine.State.WAITING_FOR_RESPONSE and engine.defender_side == BattleEngine.PLAYER:
		if not _captured_response and screen._response_panel.visible:
			_captured_response = true
			_save("04_response_window")
		for i in range(engine.hand_of(BattleEngine.PLAYER).size()):
			if engine.can_respond(BattleEngine.PLAYER, i):
				screen._on_card_clicked(i)
				return
		screen._on_silence_pressed()


func _on_frame() -> void:
	_frames += 1
	match _phase:
		0:
			if _frames == 2:
				var packed := load("res://scenes/main.tscn") as PackedScene
				_main = packed.instantiate()
				root.add_child(_main)
			elif _frames == 25:
				_save("01_menu")
				_phase = 1
				_frames = 0
		1:
			if _frames == 2:
				_main._player_choice = "polite_assassin"
				_main._enemy_choice = "empath"
				_main._scenario_choice = "new_year_dinner"
				_main._show_select()
			elif _frames == 18:
				_save("02_select")
				_phase = 2
				_frames = 0
		2:
			if _frames == 2:
				_main._start_battle()
			elif _frames == 30:
				_save("03_battle_start")
				_phase = 3
				_frames = 0
		3:
			_auto_play()
			if _frames == 120:
				if not _captured_response:
					_save("04_response_window_fallback")
				_save("05_battle_mid")
				_phase = 4
				_frames = 0
		4:
			_auto_play()
			var screen: BattleScreen = _main._screen as BattleScreen
			if screen != null and screen._ended:
				if screen._result_layer != null and screen._result_layer.visible and not _captured_result:
					_captured_result = true
					# 结算浮层有淡入动画，等它稳定后再截图
					await create_timer(0.6).timeout
					_save("06_result")
					quit(0)
			if _frames > 3000:
				_save("06_result_timeout")
				quit(1)
