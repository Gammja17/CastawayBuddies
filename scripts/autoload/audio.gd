extends Node
## 음악(교차 페이드) · 환경음 · 효과음(2D/3D).

const SFX_DIR := "res://assets/audio/sfx/"
const K := "res://assets/audio/kenney/"

# 이름 -> 후보 파일들 (무작위로 하나)
var SFX := {
	"chop": [K + "rpg/chop.ogg", K + "impact/impactWood_medium_000.ogg", K + "impact/impactWood_medium_001.ogg", K + "impact/impactWood_medium_002.ogg"],
	"mine": [K + "impact/impactMining_000.ogg", K + "impact/impactMining_001.ogg", K + "impact/impactMining_002.ogg", K + "impact/impactMining_003.ogg"],
	"dig": [K + "impact/impactSoft_heavy_000.ogg", K + "impact/impactSoft_heavy_001.ogg", K + "impact/impactSoft_heavy_002.ogg"],
	"punch": [K + "impact/impactPunch_medium_000.ogg", K + "impact/impactPunch_medium_001.ogg", K + "impact/impactPunch_medium_002.ogg"],
	"leaves": [K + "rpg/cloth1.ogg", K + "rpg/cloth2.ogg", K + "rpg/cloth3.ogg"],
	"metal": [K + "impact/impactMetal_medium_000.ogg", K + "impact/impactMetal_medium_001.ogg"],
	"step_sand": [K + "impact/footstep_snow_000.ogg", K + "impact/footstep_snow_001.ogg", K + "impact/footstep_snow_002.ogg", K + "impact/footstep_snow_003.ogg"],
	"step_grass": [K + "impact/footstep_grass_000.ogg", K + "impact/footstep_grass_001.ogg", K + "impact/footstep_grass_002.ogg", K + "impact/footstep_grass_003.ogg"],
	"step_wood": [K + "impact/footstep_wood_000.ogg", K + "impact/footstep_wood_001.ogg", K + "impact/footstep_wood_002.ogg"],
	"step_stone": [K + "impact/footstep_concrete_000.ogg", K + "impact/footstep_concrete_001.ogg", K + "impact/footstep_concrete_002.ogg"],
	"click": [K + "ui/click_002.ogg", K + "ui/click_003.ogg"],
	"open": [K + "ui/open_001.ogg"],
	"close": [K + "ui/close_001.ogg"],
	"error": [K + "ui/error_004.ogg"],
	"select": [K + "ui/select_002.ogg"],
	"chest_open": [K + "rpg/doorOpen_1.ogg"],
	"chest_close": [K + "rpg/doorClose_1.ogg"],
	"book": [K + "rpg/bookFlip1.ogg", K + "rpg/bookFlip2.ogg"],
	"coins": [K + "rpg/handleCoins.ogg"],
	"jingle_good": [K + "jingles/jingles_STEEL00.ogg"],
	"jingle_found": [K + "jingles/jingles_STEEL04.ogg"],
	"jingle_bad": [K + "jingles/jingles_PIZZI10.ogg"],
}
# assets/audio/sfx/<이름>.wav 는 이름 그대로 쓴다 (splash, bell, eat ...)

var MUSIC := {
	"title": "res://assets/audio/music/title.wav",
	"day": "res://assets/audio/music/day.wav",
	"night": "res://assets/audio/music/night.wav",
	"danger": "res://assets/audio/music/danger.wav",
	"ending": "res://assets/audio/music/ending.wav",
}

var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_cur := ""
var _amb := {}          # 이름 -> AudioStreamPlayer
var _pool2d: Array = []
var _pool3d: Array = []
var _cache := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus in ["Music", "SFX", "Amb"]:
		if AudioServer.get_bus_index(bus) == -1:
			var i := AudioServer.bus_count
			AudioServer.add_bus(i)
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")
	_music_a = _mk_player("Music")
	_music_b = _mk_player("Music")
	for i in 10:
		_pool2d.append(_mk_player("SFX"))
	for i in 20:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.unit_size = 5.0
		p.max_distance = 45.0
		p.attenuation_filter_cutoff_hz = 20500
		add_child(p)
		_pool3d.append(p)
	apply_volumes()


func _mk_player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p


func apply_volumes() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(Settings.master_vol, 0.0001)))
	var m := AudioServer.get_bus_index("Music")
	var s := AudioServer.get_bus_index("SFX")
	var a := AudioServer.get_bus_index("Amb")
	if m >= 0: AudioServer.set_bus_volume_db(m, linear_to_db(maxf(Settings.music_vol, 0.0001)))
	if s >= 0: AudioServer.set_bus_volume_db(s, linear_to_db(maxf(Settings.sfx_vol, 0.0001)))
	if a >= 0: AudioServer.set_bus_volume_db(a, linear_to_db(maxf(Settings.sfx_vol * 0.8, 0.0001)))


func _load(path: String, loop: bool) -> AudioStream:
	var key := path + ("#L" if loop else "")
	if _cache.has(key):
		return _cache[key]
	if not ResourceLoader.exists(path):
		_cache[key] = null
		return null
	var st: AudioStream = load(path)
	if loop and st:
		st = st.duplicate()
		if st is AudioStreamWAV:
			var w: AudioStreamWAV = st
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = int(w.get_length() * w.mix_rate)
		elif st is AudioStreamOggVorbis:
			st.loop = true
	_cache[key] = st
	return st


func _sfx_stream(name: String) -> AudioStream:
	var list: Array = SFX.get(name, [])
	if list.is_empty():
		return _load(SFX_DIR + name + ".wav", false)
	return _load(list[randi() % list.size()], false)


func play(name: String, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var st := _sfx_stream(name)
	if st == null:
		return
	for p: AudioStreamPlayer in _pool2d:
		if not p.playing:
			p.stream = st
			p.volume_db = vol_db
			p.pitch_scale = pitch * randf_range(0.95, 1.05)
			p.play()
			return


func play_at(name: String, pos: Vector3, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var st := _sfx_stream(name)
	if st == null:
		return
	for p: AudioStreamPlayer3D in _pool3d:
		if not p.playing:
			p.stream = st
			p.global_position = pos
			p.volume_db = vol_db
			p.pitch_scale = pitch * randf_range(0.92, 1.08)
			p.play()
			return


func music(name: String, fade: float = 2.0) -> void:
	if name == _music_cur:
		return
	_music_cur = name
	var st: AudioStream = null
	if name != "":
		st = _load(MUSIC.get(name, ""), name != "ending")
	var old := _music_a if _music_a.playing else _music_b
	var new := _music_b if old == _music_a else _music_a
	if old.playing:
		var tw := create_tween()
		tw.tween_property(old, "volume_db", -40.0, fade)
		tw.tween_callback(old.stop)
	if st:
		new.stream = st
		new.volume_db = -40.0
		new.play()
		var tw2 := create_tween()
		tw2.tween_property(new, "volume_db", 0.0, fade)


func ambience(name: String, on: bool, vol_db: float = 0.0) -> void:
	var p: AudioStreamPlayer = _amb.get(name)
	if p == null:
		var st := _load("res://assets/audio/amb/%s.wav" % name, true)
		if st == null:
			return
		p = _mk_player("Amb")
		p.stream = st
		p.volume_db = -40.0
		_amb[name] = p
	var target := vol_db if on else -40.0
	if on and not p.playing:
		p.play()
	var tw := create_tween()
	tw.tween_property(p, "volume_db", target, 1.5)
	if not on:
		tw.tween_callback(p.stop)


func stop_all_ambience() -> void:
	for n in _amb:
		ambience(n, false)
