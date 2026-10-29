extends Node
## 程序化音效：运行时合成 PCM 波形，不依赖任何外部音频素材。
## 用法：Sfx.click() / Sfx.correct() / Sfx.wrong() / Sfx.vote(true) / Sfx.win() / Sfx.lose()
## 全部短音（<0.5s），16bit / 22050Hz 单声道。

const RATE := 22050
const PLAYER_POOL := 8

var enabled: bool = true

var _players: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}
var _next_player: int = 0
var _built: bool = false


func _ready() -> void:
	for i in range(PLAYER_POOL):
		var player := AudioStreamPlayer.new()
		player.volume_db = -8.0
		add_child(player)
		_players.append(player)
	_ensure_streams()


## 首次需要发声时再合成（headless 测试里也不会白算一遍）。
func _ensure_streams() -> void:
	if _built:
		return
	_built = true
	_streams["click"] = _sequence([{"freq": 880.0, "dur": 0.04, "vol": 0.22}])
	_streams["confirm"] = _sequence([{"freq": 660.0, "dur": 0.05, "vol": 0.22}, {"freq": 990.0, "dur": 0.06, "vol": 0.18}])
	_streams["correct"] = _sequence([{"freq": 660.0, "dur": 0.08, "vol": 0.26}, {"freq": 990.0, "dur": 0.11, "vol": 0.24}])
	_streams["wrong"] = _sequence([{"freq": 220.0, "dur": 0.10, "vol": 0.26, "wave": "square"}, {"freq": 165.0, "dur": 0.14, "vol": 0.22, "wave": "square"}])
	_streams["vote_you"] = _sequence([{"freq": 520.0, "dur": 0.05, "vol": 0.20}, {"freq": 780.0, "dur": 0.05, "vol": 0.16}])
	_streams["vote_other"] = _sequence([{"freq": 330.0, "dur": 0.05, "vol": 0.20}, {"freq": 247.0, "dur": 0.06, "vol": 0.16}])
	_streams["win"] = _sequence([
		{"freq": 523.0, "dur": 0.09, "vol": 0.24},
		{"freq": 659.0, "dur": 0.09, "vol": 0.24},
		{"freq": 784.0, "dur": 0.16, "vol": 0.26},
	])
	_streams["lose"] = _sequence([
		{"freq": 330.0, "dur": 0.12, "vol": 0.24},
		{"freq": 262.0, "dur": 0.12, "vol": 0.22},
		{"freq": 196.0, "dur": 0.18, "vol": 0.20},
	])


func click() -> void:
	_play("click")


func confirm() -> void:
	_play("confirm")


func correct() -> void:
	_play("correct")


func wrong() -> void:
	_play("wrong")


func vote(you: bool) -> void:
	_play("vote_you" if you else "vote_other")


func win() -> void:
	_play("win")


func lose() -> void:
	_play("lose")


func toggle() -> bool:
	enabled = not enabled
	return enabled


func _play(sound_name: String) -> void:
	_ensure_streams()
	if not enabled:
		return
	var stream: AudioStream = _streams.get(sound_name)
	if stream == null:
		return
	if _players.is_empty():
		return
	var player := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	player.stream = stream
	player.play()


func _sequence(notes: Array) -> AudioStreamWAV:
	var total := 0
	for note in notes:
		total += int(RATE * float((note as Dictionary).get("dur", 0.1)))
	var data := PackedByteArray()
	data.resize(total * 2)
	var cursor := 0
	for note in notes:
		var record: Dictionary = note
		var freq := float(record.get("freq", 440.0))
		var dur := float(record.get("dur", 0.1))
		var vol := float(record.get("vol", 0.25))
		var wave := str(record.get("wave", "sine"))
		var count := int(RATE * dur)
		for i in range(count):
			var t := float(i) / RATE
			var attack := minf(1.0, float(i) / 64.0)
			var release := 1.0 - float(i) / float(maxi(1, count))
			var envelope := attack * release * release
			var sample := 0.0
			if wave == "square":
				sample = 1.0 if sin(TAU * freq * t) >= 0.0 else -1.0
			else:
				sample = sin(TAU * freq * t)
			var value := int(clampf(sample * vol * envelope, -1.0, 1.0) * 32767.0)
			data[cursor] = value & 0xFF
			data[cursor + 1] = (value >> 8) & 0xFF
			cursor += 2
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	return stream
