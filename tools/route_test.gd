extends Node
## 세 엔딩 루트를 실제 상호작용으로 끝까지 밀어 본다: godot --headless --path . tools/route_test.tscn -- turtle|adapt|escape

const T := preload("res://tools/tutil.gd")


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
	# 압력판: 하나엔 상자, 하나엔 사람
	var plates := _find(g, "plate")
	var pc: Vector3 = g.structs.list[plates[0]].pos
	print("압력판 위 상자 놓기 문제: '%s'" % g.structs.placement_problem("chest", pc))
	g.structs.req_place.rpc_id(1, "chest", pc, 0.0, "chest")
	var pc2: Vector3 = g.structs.list[plates[1]].pos
	p.global_position = pc2 + Vector3.UP * 0.05
	await _wait(1.0)
	var temple: int = _find(g, "temple")[0]
	var door_shape: CollisionShape3D = g.structs.nodes[temple].get_node("Door/DoorBody/Shape")
	print("신전 열림? ", g.quests.flag("temple_open"), " 문 통과 가능? ", door_shape.disabled)
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
		var bc: Vector3 = g.structs.list[bells[1]].pos
		var rc := T.spot(g, "bell_ringer", bc + Vector3(1.2, 0, 0), 2.0)
		g.structs.req_place.rpc_id(1, "bell_ringer", rc, 0.0, "bell_ringer")
		await _wait(0.2)
		print("태엽 종치기 설치: ", g.structs.near("bell_ringer", rc, 1.0) >= 0, " 종까지 %.2f" % rc.distance_to(bc))
		g.structs.req_interact.rpc_id(1, bells[0], "ring", null)
		await _wait(1.0)
		return
	g.structs.req_interact.rpc_id(1, bells[0], "ring", null)
	await _wait(0.5)
	g.structs.req_interact.rpc_id(1, bells[1], "ring", null)
	await _wait(0.5)


func _adapt(g: Game, p: Player) -> void:
	g.structs.req_place.rpc_id(1, "totem", T.spot(g, "totem", p.global_position + Vector3(1.5, 0, 0)), 0.0, "totem")
	await _wait(0.2)
	var totem: int = _find(g, "totem")[0]
	p._interact_struct(totem)
	await _wait(0.2)
	print("(조건 전 축제 시도 → 거절돼야 함) 엔딩? ", g.quests.flag("ending_adapt"))
	g.clock.day = 7
	g.quests.counts["harvests"] = 10
	g.structs.req_place.rpc_id(1, "bed", T.spot(g, "bed", p.global_position + Vector3(-1.5, 0, -1)), 0.0, "bed")
	await _wait(0.2)
	print("(밖에 둔 침대 → 지붕 아래 침대 수) ", g.quests.count("beds"))
	# 오두막 (기초 + 기둥 넷 + 지붕) 안에 침대
	var hut := T.hut(g, p.global_position + Vector3(0, 0, 4))
	await _wait(0.2)
	print("오두막 기초 ", hut, " 부품 수 ", g.structs.parts_near(hut, 4.0).size(), " 침대 문제 '", g.structs.placement_problem("bed", hut + Vector3(0.3, 0, 0)), "'")
	g.structs.req_place.rpc_id(1, "bed", hut + Vector3(0.3, 0, 0), 0.0, "bed")
	await _wait(0.2)
	print("지붕 아래 침대 수 ", g.quests.count("beds"))
	p._interact_struct(_find(g, "totem")[0])
	await _wait(0.2)
	print("(땅 넓히기 전 → 거절돼야 함) 엔딩? ", g.quests.flag("ending_adapt"), " 늘린 땅 ", g.quests.count("land"))
	# 진짜로 물을 메워서 섬 넓히기
	# 똑똑한 플레이어처럼: 매번 제일 얕은 물 꼭짓점에 붓는다
	var fills := 0
	var bad := {}   # 거절된 자리 (나무·설치물 옆)
	while g.quests.count("land") < Quests.LAND_GOAL and fills < 600:
		var best := Vector3.INF
		var best_h := -99.0
		for x in range(-40, 41):
			for z in range(-40, 41):
				var hh: float = g.terrain.h[Terrain.idx(x, z)]
				if hh < Terrain.WATER_Y - 0.1 and hh > best_h and not bad.has(Vector2i(x, z)):
					best_h = hh
					best = Vector3(x, Terrain.WATER_Y, z)
		var before := g.terrain.height_at(best.x, best.z)
		g.terrain.req_fill.rpc_id(1, best, "sand")
		if g.terrain.height_at(best.x, best.z) <= before:
			bad[Vector2i(int(best.x), int(best.z))] = true
		fills += 1
	print("땅 %d칸 늘리는 데 모래 %d번 부음" % [g.quests.count("land"), fills])
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
	var cell := T.spot(g, "shipyard", p.global_position)
	print("조선소 자리 ", cell)
	g.structs.req_place.rpc_id(1, "shipyard", cell, 0.0, "shipyard")
	await _wait(0.2)
	var sid: int = _find(g, "shipyard")[0]
	p.global_position = cell + Vector3.UP * 0.2
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
