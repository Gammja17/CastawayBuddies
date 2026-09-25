extends Node3D
## 보기만 좋은 것들 (각자 화면에서만): 네모 구름, 가끔 뛰어오르는 물고기.

const CLOUDS := 22
const SPAN := 140.0

var _clouds: Array = []
var _fish_t := 4.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(1, 1, 1, 0.92)
	white.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	white.roughness = 1.0
	white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in CLOUDS:
		var c := Node3D.new()
		var parts := _rng.randi_range(3, 6)
		for j in parts:
			var b := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(_rng.randf_range(5, 11), _rng.randf_range(1.2, 2.2), _rng.randf_range(4, 9))
			b.mesh = bm
			b.material_override = white
			b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			b.position = Vector3(_rng.randf_range(-6, 6), _rng.randf_range(-0.5, 0.8), _rng.randf_range(-5, 5))
			c.add_child(b)
		c.position = Vector3(_rng.randf_range(-SPAN, SPAN), _rng.randf_range(38, 50), _rng.randf_range(-SPAN, SPAN))
		add_child(c)
		_clouds.append(c)


func _process(delta: float) -> void:
	var g := Game.I
	if g == null or not g.world_ready:
		return
	# 구름은 바람 따라 천천히 (폭풍이면 빨리), 밤엔 어둡게
	var wind := 3.0 if g.clock.storm else 1.1
	var night := g.clock.is_night()
	for c: Node3D in _clouds:
		c.position.x += wind * delta
		if c.position.x > SPAN:
			c.position.x = -SPAN
	var tint := Color(0.35, 0.38, 0.5, 0.85) if night else (Color(0.75, 0.78, 0.82, 0.95) if g.clock.raining else Color(1, 1, 1, 0.92))
	var m: StandardMaterial3D = (_clouds[0].get_child(0) as MeshInstance3D).material_override
	m.albedo_color = m.albedo_color.lerp(tint, clampf(delta, 0, 1))
	# 물고기 점프
	_fish_t -= delta
	if _fish_t <= 0.0 and g.local_player:
		_fish_t = _rng.randf_range(4.0, 9.0)
		_jump_fish(g)


func _jump_fish(g: Game) -> void:
	var me := g.local_player.global_position
	for i in 8:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(6.0, 22.0)
		var p := Vector3(me.x + cos(a) * r, Terrain.WATER_Y, me.z + sin(a) * r)
		if g.terrain.height_at(p.x, p.z) > Terrain.WATER_Y - 1.0:
			continue
		var fish := Vis.fit_model("survival/fish", 0.25)
		add_child(fish)
		fish.global_position = p
		var dir := Vector3(cos(a + 1.3), 0, sin(a + 1.3)) * 1.4
		fish.rotation.y = atan2(dir.x, dir.z)
		var tw := create_tween().set_parallel(true)
		tw.tween_method(func(t: float):
			fish.global_position = p + dir * t + Vector3.UP * sin(t * PI) * 1.1
			fish.rotation.x = lerpf(-0.9, 0.9, t), 0.0, 1.0, 0.8)
		tw.chain().tween_callback(func():
			g.fx_splash(fish.global_position)
			Audio.play_at("splash", fish.global_position, -12.0, 1.5)
			fish.queue_free())
		Audio.play_at("splash", p, -14.0, 1.7)
		return
