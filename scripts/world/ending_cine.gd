extends Node3D
## 엔딩 연출. 카메라를 뺏어서 보여주고, 끝나면 엔딩 창을 띄운다.

const TEXTS := {
	"escape": {
		"title": "탈출 엔딩 - 집에 가자!",
		"body": "삐걱대는 탈출선이 수평선을 향해 나아갔다.\n선장의 나침반은 끝까지 이상한 쪽을 가리켰지만, 다행히 바람이 대충 맞는 쪽으로 불어 주었다.\n\n사흘 뒤, 일행은 무사히 육지에 닿았다.\n그리고 그들이 머물던 섬 바로 옆 섬이 5성급 리조트였다는 사실을 알게 된다.\n\n조식 뷔페 포함이었다.",
	},
	"adapt": {
		"title": "적응 엔딩 - 여기가 우리 집이다",
		"body": "마을 토템 아래에서 밤새 축제가 열렸다. 코코넛 주스가 강처럼 흘렀다.\n\n몇 달 뒤, 지나가던 구조선이 손을 흔들었다.\n일행은 해먹에 누운 채로 \"괜찮아요~ 여기 살아요~\" 하고 같이 손을 흔들어 주었다.\n\n이 섬은 이제 지도에 [color=#ffe08a]버디즈 공화국[/color]으로 표기된다.\n국가는 게가 집게를 딱딱거리는 소리다.",
	},
	"turtle": {
		"title": "??? 엔딩 - 거북이 택시",
		"body": "두 종소리가 겹쳐 울리자, 섬이... 일어났다.\n\n섬은 처음부터 거대한 거북이의 등이었던 것이다.\n해초 잔치로 배를 든든히 채운 거북이는 느긋하게 헤엄쳐,\n일행을 육지 해수욕장 한가운데에 내려주었다. 피서객들의 비명과 함께.\n\n거북이는 윙크를 한 번 하고 다시 바다로 돌아갔다.\n가끔 해변에 황금 조개가 떠밀려 온다는 소문이 있다.",
	},
}

var _cam: Camera3D
var _kind := ""
var _stats := {}
var _where := Vector3.ZERO
var _extra: Array = []
var _moved: Array = []


func play(kind: String, stats: Dictionary, where: Vector3) -> void:
	_kind = kind
	_stats = stats
	_where = where
	var g := Game.I
	g.hud.set_cinematic(true)
	Audio.music("", 1.0)
	_cam = Camera3D.new()
	_cam.fov = 60.0
	_cam.far = 400.0
	add_child(_cam)
	_cam.current = true
	match kind:
		"escape": await _escape()
		"adapt": await _adapt()
		"turtle": await _turtle()
	Audio.music("ending", 0.5)
	var t: Dictionary = TEXTS.get(kind, TEXTS.escape)
	var hat_id: String = {"escape": "captain", "adapt": "flower", "turtle": "turtle"}.get(kind, "")
	var hat_line := ""
	if Settings.unlock_hat(hat_id):
		hat_line = "\n\n[color=#ffe08a]새 모자 해금: %s! (타이틀 메뉴에서 쓸 수 있다)[/color]" % Settings.HATS[hat_id].name
	var body: String = t.body + "\n\n[color=#a8e4ff]-- 기록 --[/color]\n%d일 생존 / 땅 %d칸 늘림 / 게 %d마리 / 물고기 %d마리 / 기절 %d번 / 친구 %d번 살림" % [
		stats.get("day", 1), g.quests.count("land"), stats.get("crabs", 0), stats.get("fish", 0), stats.get("downs", 0), stats.get("revives", 0)]
	body += hat_line
	body += "\n\n[color=#8a8070][font_size=17]다른 엔딩도 있다. 섬에는 아직 비밀이 남아 있을지도?\n만든 이: 무인도 버디즈 팀 / 에셋: Kenney (CC0) / 글꼴: Jua (OFL)[/font_size][/color]"
	g.hud.show_ending(t.title, body)
	g.hud.set_cinematic(false)
	g.hud.game_ui.visible = false
	g.hud.ending.tree_exiting.connect(_cleanup)
	g.hud.ending.visibility_changed.connect(func():
		if not g.hud.ending.visible:
			_cleanup())


func _cleanup() -> void:
	for m in _moved:
		if is_instance_valid(m[0]):
			m[0].position = m[1]
	_moved.clear()
	for e in _extra:
		if is_instance_valid(e):
			e.queue_free()
	if Game.I and Game.I.local_player:
		Game.I.local_player.camera.current = true
	Audio.music("day")
	queue_free()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _escape() -> void:
	var g := Game.I
	var sid := g.structs.near("shipyard", _where + Vector3.UP, 3.0)
	var ship: Node3D = null
	if sid >= 0:
		ship = g.structs.nodes[sid].get_node_or_null("Ship")
	if ship == null:
		ship = Vis.fit_model("pirate/ship-small", 5.5)
		g.add_child(ship)
		ship.global_position = _where + Vector3(0, -1.2, 4)
		_extra.append(ship)
	ship.visible = true
	ship.scale = Vector3.ONE
	_moved.append([ship, ship.position])
	# 사람들을 배 위에 태운다 (색깔 상자)
	var i := 0
	for id in g.players:
		var b := Vis.box(Vector3(0.4, 0.8, 0.4), Net.player_color(id))
		ship.add_child(b)
		b.position = Vector3(-1.0 + i * 0.7, 1.7, 0.0)
		i += 1
	var start := ship.global_position
	var dir := (start - _where)
	dir.y = 0
	dir = dir.normalized() if dir.length() > 0.1 else Vector3(0, 0, 1)
	_cam.global_position = start + Vector3(-9, 5, -9)
	_cam.look_at(start + Vector3.UP * 2)
	Audio.play("boat_horn", 2.0)
	var tw := create_tween()
	tw.tween_property(ship, "global_position", start + dir * 70.0, 11.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	var t := 0.0
	while t < 11.0:
		var dt := get_process_delta_time()
		t += dt
		_cam.global_position = _cam.global_position.lerp(ship.global_position + Vector3(-10, 6, -10) + dir * -4.0, dt * 0.8)
		_cam.look_at(ship.global_position + Vector3.UP * 2.5)
		await get_tree().process_frame
	await _wait(0.5)


func _adapt() -> void:
	var g := Game.I
	var center := _where + Vector3.UP * 1.5
	var t := 0.0
	var next_fw := 0.0
	Audio.play("levelup", 2.0)
	while t < 11.0:
		var dt := get_process_delta_time()
		t += dt
		var a := t * 0.35
		_cam.global_position = center + Vector3(cos(a) * 11.0, 5.5, sin(a) * 11.0)
		_cam.look_at(center)
		next_fw -= dt
		if next_fw <= 0.0:
			next_fw = 0.45
			var p := center + Vector3(randf_range(-6, 6), randf_range(7, 12), randf_range(-6, 6))
			var col := Color.from_hsv(randf(), 0.7, 1.0)
			g.fx_break(p, col, 40)
			Audio.play_at("pickup", p, 4.0, randf_range(0.5, 0.8))
		await get_tree().process_frame


func _turtle() -> void:
	var g := Game.I
	var home := Vector3(8, 0, 6)
	# 거대 거북이 머리와 지느러미
	var turtle := Node3D.new()
	g.add_child(turtle)
	_extra.append(turtle)
	var green := Vis.mat(Color("4f8f4a"))
	var head := Vis.mesh_node(Vis._sphere(Vector3(14, 11, 17)), green)
	head.position = Vector3(4, -10, -24)
	head.rotation.y = PI
	turtle.add_child(head)
	for side in [-1, 1]:
		var eye := Vis.mesh_node(Vis._sphere(Vector3(3.0, 3.0, 3.0)), Vis.mat(Color.WHITE))
		eye.position = Vector3(side * 3.6, 2.6, 6.6)
		head.add_child(eye)
		var pupil := Vis.mesh_node(Vis._sphere(Vector3(1.5, 1.5, 1.5)), Vis.mat(Color.BLACK))
		pupil.position = Vector3(side * 3.6, 2.8, 7.9)
		head.add_child(pupil)
	var mouth := Vis.box(Vector3(6, 0.5, 0.5), Color("2d5a2a"))
	mouth.position = Vector3(0, -1.5, 8.2)
	head.add_child(mouth)
	var flips: Array = []
	for p in [Vector3(-36, -6, -18), Vector3(50, -6, -14), Vector3(-34, -6, 42), Vector3(52, -6, 40)]:
		var f := Vis.mesh_node(Vis._sphere(Vector3(24, 3, 10)), green)
		f.position = p
		turtle.add_child(f)
		flips.append(f)
	var tail := Vis.mesh_node(Vis._cone(4.0, 12.0), green)
	tail.rotation.x = PI * 0.5
	tail.position = Vector3(8, -6, 52)
	turtle.add_child(tail)
	flips.append(tail)
	_cam.global_position = home + Vector3(-26, 22, 30)
	_cam.look_at(home + Vector3(0, 2, -12))
	Audio.play("turtle", 4.0)
	g.shake_camera(1.5, Vector3.INF)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(head, "position:y", 3.0, 3.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for f in flips:
		tw.tween_property(f, "position:y", 0.5, 3.0)
	# 섬 전체가 떠오른다
	var world: Array = [g.terrain, g.props, g.structs, g.decor_root, g.players_root, g.ents]
	for n in world:
		_moved.append([n, n.position])
		tw.tween_property(n, "position:y", n.position.y + 3.0, 3.5).set_trans(Tween.TRANS_SINE)
	await _wait(3.6)
	Audio.play("rumble", 3.0)
	var t := 0.0
	while t < 8.0:
		var dt := get_process_delta_time()
		t += dt
		for n in world:
			n.position.z -= dt * 6.0
		turtle.position.z -= dt * 6.0
		for i in flips.size():
			flips[i].rotation.y = sin(t * 3.0 + i) * 0.5
		_cam.look_at(home + Vector3(0, 3, -t * 6.0))
		await get_tree().process_frame
