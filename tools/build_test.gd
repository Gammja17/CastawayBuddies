extends Node
## 부품 건축 확인: godot --headless --path . tools/build_test.tscn

const T := preload("res://tools/tutil.gd")
const G := Build.G
const H := Build.H


func _ready() -> void:
	seed(20260926)   # 섬 모양을 매번 같게 (자리 운에 따라 결과가 흔들리지 않게)
	Net.pending = {"mode": "solo", "new": true, "slot": "buildtest"}
	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game)
	await _wait(1.0)
	var g: Game = Game.I
	var p: Player = g.local_player
	var st := g.structs
	g.hud._set_open("")
	# 1) 땅 위 기초 두 장 (나란히)
	var home := p.global_position
	var spot := _flat_spot(g, home + Vector3(3, 0, 0))
	var f1 := Build.free_spot("foundation", spot, 0.0, g.terrain)
	print("기초1 자리 ", f1.pos, " 문제 '", st.part_problem("foundation", f1.pos, 0.0), "'")
	_place(g, "foundation", f1.pos, 0.0)
	var p0: Vector3 = f1.pos
	var f2 := Build.find_snap("foundation", p0 + Vector3(G, 0, 0), 0.0, st.parts_near(p0, 8.0))
	print("기초2 붙는 자리 ", f2.get("pos", "없음"), " (기대 ", p0 + Vector3(G, 0, 0), ") 문제 '", st.part_problem("foundation", f2.pos, f2.rot), "'")
	_place(g, "foundation", f2.pos, f2.rot)
	await _wait(0.2)
	# 2) 벽 (공유 모서리는 비움): 서쪽 벽, 북쪽 창문 벽, 남쪽 문틀 + 문, 동쪽 벽...
	var walls := [
		["wall", p0 + Vector3(-G * 0.5, 0, 0), PI * 0.5],
		["window_wall", p0 + Vector3(0, 0, -G * 0.5), 0.0],
		["doorway", p0 + Vector3(0, 0, G * 0.5), 0.0],
		["wall", p0 + Vector3(G * 1.5, 0, 0), PI * 0.5],
		["wall", p0 + Vector3(G, 0, -G * 0.5), 0.0],
		["wall", p0 + Vector3(G, 0, G * 0.5), 0.0],
	]
	for w in walls:
		var prob := st.part_problem(w[0], w[1], w[2])
		if prob != "":
			print("  벽 문제: ", w[0], " '", prob, "'")
		_place(g, w[0], w[1], w[2])
	await _wait(0.2)
	print("벽 수 ", _count(g, Build.WALLS))
	# 공중에 벽 → 거절
	print("공중 벽 문제: '", st.part_problem("wall", p0 + Vector3(0, 5, 0), 0.0), "'")
	# 같은 자리 두 번 → 거절
	print("같은 자리 벽 문제: '", st.part_problem("wall", p0 + Vector3(-G * 0.5, 0, 0), PI * 0.5), "'")
	# 문: 문틀에 쏙
	var door_pos: Vector3 = p0 + Vector3(0, 0, G * 0.5)
	print("문 문제: '", st.placement_problem("door", door_pos), "'")
	_place(g, "door", door_pos, 0.0)
	await _wait(0.2)
	var did := st.near("door", door_pos + Vector3.UP * 0.5, 0.3)
	st.req_interact.rpc_id(1, did, "toggle", null)
	await _wait(0.2)
	print("문 열림? ", st.list[did].data.get("open", false), " 몸 레이어 ", (st.nodes[did].get_node("Body") as StaticBody3D).collision_layer)
	# 3) 지붕: 북쪽 벽 위에 걸쳐 남쪽으로 올라가게
	var r1 := Build.find_snap("roof", p0 + Vector3(0, H, -0.2), 0.0, st.parts_near(p0, 8.0))
	print("지붕1 자리 ", r1.get("pos", "없음"), " 방향 %.2f" % r1.get("rot", -1.0), " 문제 '", st.part_problem("roof", r1.pos, r1.rot) if not r1.is_empty() else "-", "'")
	if not r1.is_empty():
		_place(g, "roof", r1.pos, r1.rot)
	var r2 := Build.find_snap("roof", p0 + Vector3(G, H, -0.2), 0.0, st.parts_near(p0, 8.0))
	if not r2.is_empty():
		_place(g, "roof", r2.pos, r2.rot)
	# 기둥
	_place(g, "pillar", p0 + Vector3(G * 1.5, 0, G * 0.5), 0.0)
	await _wait(0.2)
	print("지붕 수 ", _count(g, ["roof"]), " 기둥 수 ", _count(g, ["pillar"]))
	# 4) 조준으로 붙이기 (실제 경로): 기초1 윗면 동쪽 끝을 보고 벽 들기 → 공유 모서리
	p.inv.slots[0] = {"id": "wall", "n": 3}
	p.hotbar_i = 0
	p._on_inv_changed()
	p.global_position = p0 + Vector3(0, 0.3, 0)
	await _wait(0.6)
	print("기초 위에 섬? 바닥 %s 높이차 %.2f" % [p.is_on_floor(), p.global_position.y - p0.y])
	var f1_id := _id_at(g, "foundation", p0)
	p.target = {"type": "struct", "id": f1_id, "normal": Vector3.UP, "pos": p0 + Vector3(0.8, 0, 0.2)}
	var pl: Dictionary = p._placement()
	print("조준 벽 → ", pl.get("pos", "없음"), " 방향 %.2f 문제 '%s' (기대 %s)" % [pl.get("rot", -1.0), pl.get("problem", "-"), p0 + Vector3(G * 0.5, 0, 0)])
	# 5) 기초 위에 작업대
	p.global_position = p0 + Vector3(-0.5, 0.1, 0.5)
	await _wait(0.2)
	var wb_pos: Vector3 = p0 + Vector3(G, 0, 0)
	print("기초 위 작업대 문제: '", st.placement_problem("workbench", wb_pos), "'")
	_place(g, "workbench", wb_pos, 0.0)
	# 6) 물 위 기초 → 땅 넓히기
	var land0 := g.quests.count("land")
	var w := T.shallow(g, home)
	var wf := Build.free_spot("foundation", w, 0.0, g.terrain)
	print("물 위 기초 자리 ", wf.pos, " 문제 '", st.part_problem("foundation", wf.pos, 0.0), "'")
	_place(g, "foundation", wf.pos, 0.0)
	await _wait(0.2)
	print("늘린 땅 %d → %d (물 위 기초 +4)" % [land0, g.quests.count("land")])
	# 7) 계단 오르기
	# 땅 모양과 상관없게: 기초 두 장을 깔고, 끝 장 위에 +x 로 올라가는 계단, 앞 장에서 출발
	var d0 := _flat_spot(g, Vector3(5, 0, 25))
	var f3 := Vector3(d0.x, Build.free_spot("foundation", d0, 0.0, g.terrain).pos.y, d0.z)
	_place(g, "foundation", f3, 0.0)
	_place(g, "foundation", f3 + Vector3(G, 0, 0), 0.0)
	await _wait(0.2)
	var s0 := f3 + Vector3(G, 0, 0)
	print("계단 문제: '", st.part_problem("stairs", s0, PI * 0.5), "'")
	_place(g, "stairs", s0, PI * 0.5)
	await _wait(0.2)
	p.global_position = f3 + Vector3(-0.4, 0.3, 0)
	p._yaw = -PI * 0.5
	await _wait(0.3)
	print("  계단 ", s0, " 출발 ", p.global_position, " 계단 수 ", _count(g, ["stairs"]))
	Input.action_press("move_forward")
	var max_y := -99.0
	for i in 12:
		await _wait(0.1)
		max_y = maxf(max_y, p.global_position.y - s0.y)
		if OS.get_cmdline_user_args().has("trace"):
			var hit := ""
			for k in p.get_slide_collision_count():
				var c: KinematicCollision3D = p.get_slide_collision(k)
				var o: Object = c.get_collider()
				var sk := ""
				if o is Node and (o as Node).has_meta("struct"):
					var sid: int = (o as Node).get_meta("struct")
					sk = "%s @%s" % [st.list[sid].kind, st.list[sid].pos - s0]
				hit += " [%s 높이 %.2f]" % [sk, c.get_position().y - s0.y]
			print("    ", p.global_position - s0, " 바닥 ", p.is_on_floor(), " 벽 ", p.is_on_wall(), hit)
	Input.action_release("move_forward")
	print("계단 오른 높이 %.2f (계단 %.1f)" % [max_y, H])
	# 8) 부수기 → 부품 돌려받기
	var wall_id := _id_at(g, "wall", p0 + Vector3(-G * 0.5, 0, 0))
	var n0 := p.inv.count("wall")
	st.req_remove.rpc_id(1, wall_id)
	await _wait(0.2)
	print("벽 걷음: 남아있음? ", st.list.has(wall_id), " 가방 벽 %d → %d" % [n0, p.inv.count("wall")])
	# 9) 저장
	g.save_game()
	var data := Game.load_save("buildtest")
	var parts := 0
	for id in data.structs.list:
		if Build.is_part(data.structs.list[id].kind):
			parts += 1
	print("저장된 부품 수 ", parts, " / 지금 ", _count(g, Build.PARTS.keys()))
	print("건축 테스트 끝")
	get_tree().quit()


func _place(g: Game, kind: String, pos: Vector3, rot: float) -> void:
	g.structs.req_place.rpc_id(1, kind, pos, rot, kind)


func _count(g: Game, kinds: Array) -> int:
	var n := 0
	for id in g.structs.list:
		if g.structs.list[id].kind in kinds:
			n += 1
	return n


func _id_at(g: Game, kind: String, pos: Vector3) -> int:
	for id in g.structs.list:
		if g.structs.list[id].kind == kind and (g.structs.list[id].pos as Vector3).distance_to(pos) < 0.2:
			return id
	return -1


func _flat_spot(g: Game, near: Vector3) -> Vector3:
	## 2x2 기초가 들어갈 평평한 땅 (물 아님)
	for r in range(0, 40):
		for i in 24:
			var a := i * TAU / 24.0
			var q := Vector3(near.x + cos(a) * r, 0, near.z + sin(a) * r)
			var ok := g.structs.parts_near(q, 4.0).is_empty() and g.structs.near_any(q, 4.5) < 0 and g.props.near_alive(q, 4.5) < 0   # 계단 앞길이 막히지 않게
			var top: float = Build.free_spot("foundation", q, 0.0, g.terrain).pos.y
			for c in [q, q + Vector3(G, 0, 0)]:
				var gr := Build.ground_range(c, 0.0, g.terrain)
				ok = ok and gr.x > Terrain.WATER_Y + 0.05 and gr.y - gr.x < 0.8
				ok = ok and g.structs.part_problem("foundation", Vector3(c.x, top, c.z), 0.0) == ""
			if ok:
				return q
	return near


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout
