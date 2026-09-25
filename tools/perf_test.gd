extends Node
## 프레임 시간 재기 (웹과 같은 렌더러로):
##   godot --path . --rendering-method gl_compatibility --resolution 1280x720 tools/perf_test.tscn -- [초] [끌 것...]
## 끌 것: clouds, decor, water, shadows, hud, pickups, ents (어느 게 느린지 하나씩 꺼 보며 비교)
## 캐릭터가 시작섬 둘레를 천천히 걸으며 두리번거리고, 중간에 밤이 된다.

var _secs := 30.0
var _off: Array = []
var _frames: Array = []   # [시각, 프레임ms, 스크립트ms, 물리ms, 렌더CPUms, 그리기 수]
var _t := 0.0


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)   # 진짜 걸리는 시간을 보려고
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0].is_valid_float():
		_secs = args[0].to_float()
	_off = Array(args).filter(func(a): return not a.is_valid_float())
	Net.pending = {"mode": "solo", "new": true, "slot": "perftest"}
	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game)
	await get_tree().create_timer(2.0).timeout
	var g: Game = Game.I
	g.hud._set_open("")
	g.clock.hour = 16.5
	_apply_off(g)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	Input.action_press("move_forward")
	await get_tree().create_timer(1.0).timeout   # 몸풀기
	_frames.clear()
	_t = 0.0
	set_process(true)


func _apply_off(g: Game) -> void:
	for o in _off:
		match o:
			"clouds":
				for c in g.find_children("*", "Node3D", true, false):
					if c.get_script() and str(c.get_script().resource_path).ends_with("ambience_fx.gd"):
						c.visible = false
						c.set_process(false)
			"decor":
				for c in g.get_node("Decor").get_children():
					c.visible = false
			"water":
				g.ocean.visible = false
			"shadows":
				g.get_node("Sun").shadow_enabled = false
			"hud":
				g.hud.visible = false
				g.hud.set_process(false)
			"pickups":
				g.ents.set_process(false)
			"ents":
				g.ents.set_process(false)
				g.ents.set_physics_process(false)
	print("끈 것: ", _off)


func _process(delta: float) -> void:
	if Game.I == null or Game.I.local_player == null:
		return
	_t += delta
	var p := Game.I.local_player
	# 천천히 돌며 걷고 두리번
	p._yaw += delta * 0.35
	p._pitch = -0.15 + sin(_t * 0.7) * 0.25
	if _t > _secs * 0.5 and Game.I.clock.hour < 20.0:
		Game.I.clock.hour = 21.0   # 밤 (게가 나온다)
	var vp := get_viewport().get_viewport_rid()
	_frames.append([_t, delta * 1000.0,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu(),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
	if _t >= _secs:
		set_process(false)
		_report()
		get_tree().quit()


func _report() -> void:
	var ms: Array = _frames.map(func(f): return f[1])
	var sorted := ms.duplicate()
	sorted.sort()
	var n := sorted.size()
	var avg := 0.0
	for v in ms:
		avg += v
	avg /= n
	var cols := ["스크립트", "물리", "렌더CPU", "그리기"]
	var line := "프레임 %d개 / 평균 %.1fms (%.0f FPS) / 중간 %.1f / 95%% %.1f / 99%% %.1f / 최악 %.1f" % [n, avg, 1000.0 / avg, sorted[n / 2], sorted[int(n * 0.95)], sorted[int(n * 0.99)], sorted[n - 1]]
	print(line)
	for c in 4:
		var s := 0.0
		var mx := 0.0
		for f in _frames:
			s += f[c + 2]
			mx = maxf(mx, f[c + 2])
		print("  %s 평균 %.2f / 최대 %.2f" % [cols[c], s / n, mx])
	# 튀는 프레임 (중간값의 2배 이상)
	var spikes := _frames.filter(func(f): return f[1] > maxf(sorted[n / 2] * 2.0, 25.0))
	print("  튀는 프레임 %d개" % spikes.size())
	for f in spikes.slice(0, 25):
		print("    %.2f초: %.1fms (스크립트 %.1f 물리 %.1f 렌더 %.1f 그리기 %d)" % [f[0], f[1], f[2], f[3], f[4], f[5]])
