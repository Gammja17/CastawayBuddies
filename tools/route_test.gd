extends Node
## 세 엔딩 루트를 실제 상호작용으로 끝까지 밀어 본다: godot --headless --path . tools/route_test.tscn -- turtle|adapt|escape


func _ready() -> void:
	var route: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "turtle"
	Net.pending = {"mode": "solo", "new": true, "slot": "route_" + route}
	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game)
	await _wait(1.0)
	var g: Game = Game.I
	var p: Player = g.local_player
	match route:
		"turtle": await _turtle(g, p)
		"adapt": await _adapt(g, p)
		"escape": await _escape(g, p)
	await _wait(0.5)
	print("[%s] 엔딩 플래그: %s  깃발들: %s" % [route, g.quests.flag("ending_" + route), g.quests.flags.keys()])
	get_tree().quit()


func _find(g: Game, kind: String) -> Array:
	var out: Array = []
	for id in g.structs.list:
		if g.structs.list[id].kind == kind:
			out.append(id)
	return out


func _turtle(g: Game, p: Player) -> void:
	# 압력판: 하나엔 블록, 하나엔 사람
	var plates := _find(g, "plate")
	var pc: Vector3i = g.structs.list[plates[0]].cell
	g.terrain.req_place.rpc_id(1, pc, Items.block_index["stone_block"], "stone_block")
	var pc2: Vector3i = g.structs.list[plates[1]].cell
	p.global_position = Vector3(pc2.x + 0.5, pc2.y + 0.05, pc2.z + 0.5)
	await _wait(1.0)
	print("신전 열림? ", g.quests.flag("temple_open"), " 문칸 ", g.terrain.get_block(g.gen.door_cells[0]))
	for id in _find(g, "tablet"):
		p._interact_struct(id)
		g.hud._set_open("")
	await _wait(0.3)
	print("석판 수 ", g.quests.count("tablets"), " 거북이 보임? ", g.quests.flag("turtle_seen"))
	var altar: int = _find(g, "altar")[0]
	p.inv.add("seaweed_feast", 1)
	p._interact_struct(altar)
	await _wait(0.2)
	p.inv.add("golden_shell", 3)
	for i in 3:
		p._interact_struct(altar)
		await _wait(0.1)
	print("제단: ", g.structs.list[altar].data, " 조개 바친 수 ", g.quests.count("shells_offered"))
	var bells := _find(g, "bell")
	if OS.get_cmdline_user_args().has("solo"):
		# 혼자: 태엽 종치기를 두 번째 종 옆에 두고 첫 번째 종만 친다
		var bc: Vector3i = g.structs.list[bells[1]].cell
		var rc := Vector3i(bc.x + 1, g.terrain.top_y(bc.x + 1, bc.z) + 1, bc.z)
		g.structs.req_place.rpc_id(1, "bell_ringer", rc, 0, "bell_ringer")
		await _wait(0.2)
		print("태엽 종치기 설치: ", g.structs.at_cell(rc) >= 0)
		g.structs.req_interact.rpc_id(1, bells[0], "ring", null)
		await _wait(1.0)
		return
	g.structs.req_interact.rpc_id(1, bells[0], "ring", null)
	await _wait(0.5)
	g.structs.req_interact.rpc_id(1, bells[1], "ring", null)
	await _wait(0.5)


func _adapt(g: Game, p: Player) -> void:
	var top := g.terrain.top_y(0, 0)
	g.structs.req_place.rpc_id(1, "totem", Vector3i(0, top + 1, 0), 0, "totem")
	await _wait(0.2)
	var totem: int = _find(g, "totem")[0]
	p._interact_struct(totem)
	await _wait(0.2)
	print("(조건 전 축제 시도 → 거절돼야 함) 엔딩? ", g.quests.flag("ending_adapt"))
	g.clock.day = 7
	g.quests.counts["blocks_placed"] = 150
	g.quests.counts["harvests"] = 10
	var t2 := g.terrain.top_y(-1, -1)
	g.structs.req_place.rpc_id(1, "bed", Vector3i(-1, t2 + 1, -1), 0, "bed")
	await _wait(0.2)
	p._interact_struct(totem)
	await _wait(0.3)


func _escape(g: Game, p: Player) -> void:
	for id in _find(g, "note_sign"):
		if g.structs.list[id].data.note == "captain_log":
			p._interact_struct(id)
			g.hud._set_open("")
	await _wait(0.2)
	print("탈출 루트 알게 됨? ", g.quests.flag("escape_known"))
	# 물가 자리 찾기
	var cell := Vector3i.ZERO
	var found := false
	for x in range(-6, 7):
		for z in range(-6, 7):
			var t := g.terrain.top_y(x, z)
			if t < 0 or found:
				continue
			var c := Vector3i(x, t + 1, z)
			if g.structs._next_to_water(c) and g.occupied(c) == "":
				cell = c
				found = true
	print("조선소 자리 ", cell, " 찾음? ", found)
	g.structs.req_place.rpc_id(1, "shipyard", cell, 0, "shipyard")
	await _wait(0.2)
	var sid: int = _find(g, "shipyard")[0]
	p.global_position = Vector3(cell) + Vector3(0.5, 0.2, 0.5)
	for part in Structs.SHIP_PARTS:
		for item in Structs.SHIP_PARTS[part].need:
			var n: int = Structs.SHIP_PARTS[part].need[item]
			var real: String = "cooked_fish" if item == "cooked" else item
			p.inv.add(real, n + 2)
	g.hud.open_shipyard(sid)
	for part in Structs.SHIP_PARTS:
		for item in Structs.SHIP_PARTS[part].need:
			g.hud._ship_give(part, item)
			await _wait(0.05)
	await _wait(0.5)
	print("배 완성? ", g.structs.ship_ready(sid), " 남은 판자 ", p.inv.count("plank"), " (2 여야 함)")
	g.hud._on_depart()
	await _wait(0.5)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout
