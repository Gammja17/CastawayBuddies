class_name Clock
extends Node
## 하루 = 12분. 해와 하늘 색, 비, 지진(거북이 루트 복선).

signal day_started(day: int)
signal night_started

const DAY_SECONDS := 720.0      # 24시간 = 12분 -> 1시간 = 30초
const NIGHT_START := 20.5
const NIGHT_END := 5.5

var hour := 7.0
var day := 1
var raining := false
var storm := false
var _flash := 0.0
var _flash_t := 3.0
var _rain_t := 320.0
var _sync_t := 0.0
var _was_night := false
var _quake_done := {}

@onready var sun: DirectionalLight3D = get_node("../Sun")
@onready var env: WorldEnvironment = get_node("../Env")
var _rain_fx: GPUParticles3D


func snapshot() -> Dictionary:
	return {"hour": hour, "day": day, "raining": raining, "storm": storm, "quakes": _quake_done}


func apply(s: Dictionary) -> void:
	hour = s.get("hour", 7.0)
	day = s.get("day", 1)
	raining = s.get("raining", false)
	storm = s.get("storm", false) and raining
	_quake_done = s.get("quakes", {})
	_was_night = is_night()
	_update_visuals(true)
	_apply_storm()


func is_night() -> bool:
	return hour >= NIGHT_START or hour < NIGHT_END


func time_text() -> String:
	var h := int(hour)
	var m := int((hour - h) * 60.0) / 10 * 10
	return "%d일째  %02d:%02d" % [day, h, m]


func _process(delta: float) -> void:
	if Game.I == null or not Game.I.world_ready:
		return
	hour += delta * 24.0 / DAY_SECONDS
	if hour >= 24.0:
		hour -= 24.0
		if multiplayer.is_server():
			day += 1
			_sync.rpc(hour, day, raining)
			day_started.emit(day)
	if multiplayer.is_server():
		_server_tick(delta)
	var night := is_night()
	if night != _was_night:
		_was_night = night
		if night:
			night_started.emit()
			Audio.play("night", -2.0)
			Game.I.hud.toast("밤이 되었다... 게들이 사나워진다", Color("9fb6ff"))
		else:
			Audio.play("morning", -2.0)
	_lightning(delta)
	_update_visuals(false)


func _server_tick(delta: float) -> void:
	_sync_t -= delta
	if _sync_t <= 0.0:
		_sync_t = 5.0
		_sync.rpc(hour, day, raining)
	# 비: 하루에 한두 번 몇 분씩
	_rain_t -= delta
	if _rain_t <= 0.0:
		if raining:
			raining = false
			_rain_t = randf_range(240.0, 480.0)
		else:
			raining = randf() < 0.45
			_rain_t = randf_range(90.0, 180.0) if raining else randf_range(200.0, 400.0)
		_sync.rpc(hour, day, raining)
		var st := raining and day >= 2 and randf() < 0.35
		if st != storm:
			_set_storm.rpc(st)
	# 지진: 2, 4, 6일째 오후 2시
	if day in [2, 4, 6] and hour >= 14.0 and hour < 15.0 and not _quake_done.has(str(day)):
		_quake_done[str(day)] = true
		_quake.rpc(day)
		Game.I.quests.on_quake()


@rpc("authority", "call_local", "reliable")
func _sync(h: float, d: int, rain: bool) -> void:
	if not multiplayer.is_server():
		hour = h
	var new_day := d != day and not multiplayer.is_server()
	day = d
	if rain != raining:
		raining = rain
		if Game.I and Game.I.hud:
			Game.I.hud.toast("비가 내린다" if rain else "비가 그쳤다", Color("a8e4ff"))
	if new_day:
		day_started.emit(day)


@rpc("authority", "call_local", "reliable")
func _set_storm(on: bool) -> void:
	storm = on
	_apply_storm()
	if on and Game.I and Game.I.hud:
		Game.I.hud.toast("폭풍이 몰려온다! 파도가 높아졌다", Color("a8c8ff"))


func _apply_storm() -> void:
	Audio.ambience("wind", storm, -8.0)
	if Game.I and Game.I.ocean:
		var m: ShaderMaterial = (Game.I.ocean.mesh as PlaneMesh).material
		if m:
			m.set_shader_parameter("wave_amp", 0.18 if storm else 0.07)


func _lightning(delta: float) -> void:
	## 폭풍 번개: 번쩍 → 조금 뒤 우르릉 (각자 화면에서 따로)
	_flash = maxf(0.0, _flash - delta * 3.0)
	if not storm:
		return
	_flash_t -= delta
	if _flash_t <= 0.0:
		_flash_t = randf_range(5.0, 12.0)
		_flash = 1.0
		get_tree().create_timer(randf_range(0.4, 1.6)).timeout.connect(func(): Audio.play("rumble", 2.0, 0.75))


func skip_to_morning() -> void:
	## 호스트 전용: 모두 잤다
	if not multiplayer.is_server():
		return
	if hour >= NIGHT_START:
		day += 1
	hour = 6.0
	_sync.rpc(hour, day, raining)
	_morning.rpc(day)


@rpc("authority", "call_local", "reliable")
func _morning(d: int) -> void:
	day = d
	day_started.emit(day)
	if Game.I and Game.I.hud:
		Game.I.hud.toast("%d일째 아침이 밝았다" % d, Color("ffe08a"))


@rpc("authority", "call_local", "reliable")
func _quake(d: int) -> void:
	Audio.play("rumble", 3.0)
	if Game.I:
		Game.I.shake_camera(1.6, Vector3.INF)
		var lines := ["섬 전체가 꿈틀거렸다...?!", "땅이... 숨을 쉬는 것 같다?", "지진이다! 섬이 한쪽으로 기우뚱했다가 돌아왔다..."]
		Game.I.hud.toast(lines[clampi(d / 2 - 1, 0, 2)], Color("ffb07a"))


func _update_visuals(force: bool) -> void:
	if sun == null or env == null:
		return
	# 해 각도: 6시 해돋이, 18시 해넘이
	var t := (hour - 6.0) / 12.0   # 0..1 낮
	var ang := t * PI
	sun.rotation = Vector3(-sin(ang) * 1.2 - 0.15, deg_to_rad(-35.0), 0.0)
	var dayness := clampf(sin(ang) * 1.6, 0.0, 1.0)
	if is_night():
		dayness = 0.0
	var dusk := clampf(1.0 - absf(hour - 19.0) / 1.8, 0.0, 1.0) + clampf(1.0 - absf(hour - 6.0) / 1.5, 0.0, 1.0)
	sun.light_energy = lerpf(0.08, 1.25, dayness) * (0.55 if raining else 1.0)
	sun.light_color = Color(1.0, 0.95, 0.85).lerp(Color(1.0, 0.55, 0.35), clampf(dusk, 0, 1)).lerp(Color(0.55, 0.62, 1.0), 1.0 - dayness if is_night() else 0.0)
	var e := env.environment
	var sky_mat: ProceduralSkyMaterial = e.sky.sky_material
	var top_day := Color(0.28, 0.58, 0.92)
	var hor_day := Color(0.7, 0.86, 0.95)
	var top_night := Color(0.03, 0.04, 0.12)
	var hor_night := Color(0.1, 0.12, 0.25)
	var top := top_night.lerp(top_day, dayness)
	var hor := hor_night.lerp(hor_day, dayness).lerp(Color(1.0, 0.6, 0.4), clampf(dusk, 0, 1) * 0.6)
	if raining:
		top = top.lerp(Color(0.4, 0.44, 0.5), 0.6 * dayness)
		hor = hor.lerp(Color(0.55, 0.58, 0.62), 0.6 * dayness)
	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = hor
	sky_mat.ground_horizon_color = hor
	sky_mat.ground_bottom_color = top.darkened(0.3)
	e.ambient_light_energy = lerpf(0.35, 1.0, dayness) + _flash * 2.5
	if _flash > 0.0:
		sky_mat.sky_top_color = top.lerp(Color(0.85, 0.9, 1.0), _flash * 0.7)
		sky_mat.sky_horizon_color = hor.lerp(Color(0.9, 0.93, 1.0), _flash * 0.7)
	e.fog_light_color = hor
	e.fog_density = 0.004 + (0.01 if raining else 0.0) + (0.004 if is_night() else 0.0)
	# 비 효과는 카메라 따라다님
	if Game.I and Game.I.local_player:
		if raining and _rain_fx == null:
			_rain_fx = _make_rain()
		if _rain_fx:
			_rain_fx.emitting = raining
			_rain_fx.global_position = Game.I.local_player.global_position + Vector3.UP * 12.0
	if raining != _rain_amb or force:
		_rain_amb = raining
		Audio.ambience("rain", raining, -6.0)


var _rain_amb := false


func _make_rain() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 900
	p.lifetime = 1.2
	p.visibility_aabb = AABB(Vector3(-20, -20, -20), Vector3(40, 40, 40))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(16, 1, 16)
	pm.direction = Vector3(0.1, -1, 0)
	pm.spread = 3.0
	pm.initial_velocity_min = 18.0
	pm.initial_velocity_max = 22.0
	pm.gravity = Vector3(0, -10, 0)
	p.process_material = pm
	var q := BoxMesh.new()
	q.size = Vector3(0.02, 0.4, 0.02)
	p.draw_pass_1 = q
	p.material_override = Vis.mat(Color(0.75, 0.85, 1.0, 0.5), true)
	Game.I.add_child(p)
	return p
