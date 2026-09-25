extends Node
## 묘목·밭·빗물받이·모래 포집기·통발·낚시·화덕 조합: godot --headless --path . tools/systems_test.tscn


func _ready() -> void:
	Net.pending = {"mode": "solo", "new": true, "slot": "systems"}
	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game)
	await _wait(1.0)
	var g: Game = Game.I
	var p: Player = g.local_player
	var st := g.structs
	var props_before := g.props.list.size()
	# 묘목
	var c := Vector3i(-2, g.terrain.top_y(-2, 2) + 1, 2)
	st.req_place.rpc_id(1, "sapling", c, 0, "sapling")
	await _wait(0.2)
	var sid := st.at_cell(c)
	print("묘목 설치: ", sid >= 0)
	st.list[sid].data.grow = 0.995
	await _wait(1.5)
	print("묘목→야자수: 채집물 %d → %d, 묘목 남음? %s" % [props_before, g.props.list.size(), st.list.has(sid)])
	# 밭 (흙 위)
	var fc := Vector3i(0, g.terrain.top_y(0, 0) + 1, 0)
	var below: String = Items.block(g.terrain.get_block(fc + Vector3i.DOWN)).id
	st.req_place.rpc_id(1, "farm_plot", fc, 0, "farm_plot")
	await _wait(0.2)
	var fid := st.at_cell(fc)
	print("밭 설치 (아래 %s): %s" % [below, fid >= 0])
	if fid >= 0:
		p.inv.add("potato", 1)
		p._interact_struct(fid)
		await _wait(0.2)
		st.list[fid].data.grow = 0.999
		await _wait(1.0)
		p._interact_struct(fid)
		await _wait(0.2)
		print("수확 뒤 감자: ", p.inv.count("potato"), " 수확 수 ", g.quests.count("harvests"))
	# 빗물받이
	var rc := Vector3i(1, g.terrain.top_y(1, 2) + 1, 2)
	st.req_place.rpc_id(1, "rain_collector", rc, 0, "rain_collector")
	await _wait(0.2)
	var rid := st.at_cell(rc)
	st.list[rid].data.stored = 2
	st._sync_data.rpc(rid, st.list[rid].data)
	p.inv.add("bottle", 1)
	var b0 := p.inv.count("bottle")
	p._interact_struct(rid)
	await _wait(0.2)
	print("빗물받이: 물 ", p.inv.count("fresh_water"), " 병 %d→%d" % [b0, p.inv.count("bottle")])
	# 물가 모래 포집기
	var wc := Vector3i.ZERO
	for x in range(-6, 7):
		for z in range(-6, 7):
			var t := g.terrain.top_y(x, z)
			if t >= 0 and st._next_to_water(Vector3i(x, t + 1, z)) and g.occupied(Vector3i(x, t + 1, z)) == "" and wc == Vector3i.ZERO:
				wc = Vector3i(x, t + 1, z)
	st.req_place.rpc_id(1, "sand_trap", wc, 0, "sand_trap")
	await _wait(0.2)
	var tid := st.at_cell(wc)
	print("모래 포집기 설치: ", tid >= 0, " at ", wc)
	if tid >= 0:
		st.list[tid].data.t = 17.9
		await _wait(0.6)
		var sand0 := p.inv.count("sand")
		p._interact_struct(tid)
		await _wait(0.2)
		print("모래 받음: ", p.inv.count("sand") - sand0)
	# 화덕 조합
	p.inv.add("stone", 12)
	p.inv.add("clay", 6)
	var fr: Dictionary = {}
	for r in Items.RECIPES:
		if r.out == "furnace":
			fr = r
	var wb := Vector3i(2, g.terrain.top_y(2, -1) + 1, -1)
	st.req_place.rpc_id(1, "workbench", wb, 0, "workbench")
	await _wait(0.2)
	p.global_position = Vector3(wb) + Vector3(0.5, 0.1, 1.5)
	await _wait(0.2)
	print("작업대 근처? ", p.station_near("workbench"), " 화덕 제작: ", p.craft(fr))
	# 낚시 (바다를 보게)
	p.inv.slots[0] = {"id": "fishing_rod", "n": 1, "d": 60}
	p.hotbar_i = 0
	p._on_inv_changed()
	p._cast_bobber(Vector3(-8.5, Terrain.WATER_Y, 0.5))
	p._fish_t = 0.1
	await _wait(0.5)
	print("입질 상태: ", p._fish_state)
	p._fish_click()
	print("낚은 뒤 가방 물고기류: ", p.inv.count("raw_fish") + p.inv.count("big_fish") + p.inv.count("seaweed") + p.inv.count("bottle") + p.inv.count("plastic") + p.inv.count("golden_shell"))
	# 압력판 위에 블록 놓기 (실제 조준 경로)
	var plate := -1
	for id in st.list:
		if st.list[id].kind == "plate":
			plate = id
			break
	var pcell: Vector3i = st.list[plate].cell
	p.inv.slots[1] = {"id": "stone_block", "n": 3}
	p.hotbar_i = 1
	p._on_inv_changed()
	p.target = {"type": "struct", "id": plate, "cell": pcell, "normal": Vector3.UP, "place": pcell + Vector3i.UP, "pos": Vector3(pcell)}
	var pl: Dictionary = p._placement()
	print("압력판 조준 → 놓일 칸 ", pl.get("cell", "없음"), " (판 칸 ", pcell, ")")
	# 동굴 바위: 혼자 맨손으로는 안 되고, 철곡괭이면 된다
	var rock := -1
	for id in st.list:
		if st.list[id].kind == "big_rock":
			rock = id
	p._interact_struct(rock)
	await _wait(0.2)
	print("바위 혼자 밀기 → 남아있음? ", st.list.has(rock))
	p.inv.add("iron_pick", 1)
	p._interact_struct(rock)
	await _wait(0.2)
	print("철곡괭이로 밀기 → 남아있음? ", st.list.has(rock))
	# 뗏목: 띄우고, 타고, 노 젓고, 내리기
	g.ents.req_raft_spawn.rpc_id(1, Vector3(-12.5, Terrain.WATER_Y, 0.5), 0.0)
	await _wait(0.2)
	var raft_id: int = g.ents.rafts.keys()[0] if not g.ents.rafts.is_empty() else -1
	print("뗏목 생김: ", raft_id)
	g.ents.req_raft_board.rpc_id(1, raft_id)
	await _wait(0.2)
	print("탔나? ", p.riding == raft_id)
	var start: Vector3 = g.ents.rafts[raft_id].pos
	Input.action_press("move_forward")
	await _wait(2.0)
	Input.action_release("move_forward")
	print("2초 노 저은 거리: %.2f  (플레이어-뗏목 거리 %.2f)" % [g.ents.rafts[raft_id].pos.distance_to(start), p.global_position.distance_to(g.ents.rafts[raft_id].node.global_position)])
	p._interact_press()
	await _wait(0.3)
	print("내렸나? ", p.riding == -1, " 위치 ", p.global_position)
	g.ents.req_raft_pickup.rpc_id(1, raft_id)
	await _wait(0.2)
	print("뗏목 걷음: ", not g.ents.rafts.has(raft_id), " 가방 뗏목 ", p.inv.count("raft"))
	get_tree().quit()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout
