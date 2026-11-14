extends Node
## Autoload "Sfx": background music, sound effects and vibration, each switchable in Settings.

const EFFECTS := ["click", "mark", "erase", "place", "region", "wrong", "star", "hint", "unlock", "win", "lose"]

var music_on := true
var sfx_on := true
var vibe_on := true

var _music: AudioStreamPlayer
var _pool: Array = []
var _next := 0
var _streams := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for e in EFFECTS:
		_streams[e] = load("res://assets/audio/%s.wav" % e)
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_music = AudioStreamPlayer.new()
	var stream := load("res://assets/audio/music.ogg") as AudioStreamOggVorbis
	if stream:
		stream.loop = true
	_music.stream = stream
	_music.volume_db = -13.0
	add_child(_music)


func play(effect: String, pitch := 1.0, volume_db := 0.0) -> void:
	if not sfx_on or not _streams.has(effect):
		return
	var p: AudioStreamPlayer = _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = _streams[effect]
	p.pitch_scale = pitch
	p.volume_db = volume_db
	p.play()


func vibrate(ms: int) -> void:
	if vibe_on:
		Input.vibrate_handheld(ms)


func set_music(on: bool) -> void:
	music_on = on
	if on and not _music.playing:
		_music.play()
		_music.volume_db = -40.0
		create_tween().tween_property(_music, "volume_db", -13.0, 1.5)
	elif not on:
		_music.stop()
