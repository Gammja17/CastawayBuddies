extends Node
## 혼자 하기로 게임을 켜서 기본 동작을 두루 눌러 본다: godot --headless --path . tools/smoke.tscn

const T := preload("res://tools/tutil.gd")


func _ready() -> void:
	Net.pending = {"mode": "solo", "new": true, "slot": "smoke"}
	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game)
	await get_tree().create_timer(1.0).timeout
	var g: Game = Game.I
	print("월드 준비: ", g.world_ready, " 지형 조각 ", g.terrain._chunks.size(), " 채집물 ", g.props.list.size(), " 설치물 ", g.structs.list.size())
	var p: Player = g.local_player
	print("플레이어: ", p != null, " 위치 ", p.global_position)
	await _wait(1.0)
	print("1초 뒤 위치 ", p.global_position, " 바닥? ", p.is_on_floor())
	# 시작 상자 열기
	var crate := -1
	for id in g.structs.list:
		if g.structs.list[id].kind == "loot_crate":
			crate = id
			break
	g.structs.req_interact.rpc_id(1, crate, "open", null)
	await _wait(0.2)
	print("상자 연 뒤 가방: ", _inv(p), "  쪽지 창(혼자면 일시정지): ", g.hud._open, " ", get_tree().paused)
	g.hud._set_open("")
	# 야자수 패기
	var palm := -1
	for i in g.props.list.size():
		if g.props.list[i].kind == "palm":
			palm = i
			break
	for i in 12:
		g.props.req_hit.rpc_id(1, palm, "")
	await _wait(0.2)
	print("야자수 팬 뒤: ", _inv(p), " 살아있음? ", g.props.list[palm].alive)
	# 조합
	p.inv.add("wood", 6)
	p.inv.add("stone", 6)
	var wb: Dictionary = {}
	for r in Items.RECIPES:
		if r.out == "workbench":
			wb = r
	print("작업대 만들기: ", p.craft(wb))
	# 땅 파기 / 물 메우기
	var sp := p.global_position
	var sand0 := p.inv.count("sand")
	var dig_at := T.spot(g, "workbench", sp + Vector3(3, 0, 3))
	var h0 := g.terrain.height_at(dig_at.x, dig_at.z)
	g.terrain.req_dig.rpc_id(1, dig_at, "shovel")
	await _wait(0.1)
	print("파기: 높이 %.2f -> %.2f / 모래 +%d 흙 %d" % [h0, g.terrain.height_at(dig_at.x, dig_at.z), p.inv.count("sand") - sand0, p.inv.count("dirt")])
	var w := T.shallow(g, sp)
	var land0 := g.terrain.land_gain()
	for i in 6:
		g.terrain.req_fill.rpc_id(1, w, "sand")
	await _wait(0.1)
	print("메우기: %s 높이 %.2f 아직 물? %s / 늘어난 땅 %d -> %d" % [w, g.terrain.height_at(w.x, w.z), g.terrain.is_water(w.x, w.z), land0, g.terrain.land_gain()])
	# 구조물 설치
	var wbp := T.spot(g, "workbench", sp + Vector3(-2, 0, 2))
	g.structs.req_place.rpc_id(1, "workbench", wbp, 0.0, "workbench")
	await _wait(0.1)
	print("작업대 설치됨? ", g.structs.near("workbench", wbp, 1.0) >= 0, " ", wbp)
	# 밤 / 게
	g.clock.hour = 21.0
	await _wait(3.0)
	print("밤? ", g.clock.is_night(), " 적 수 ", g.ents.enemies.size())
	# 피해 / 기절
	p.net_hurt.rpc_id(1, 150, p.global_position + Vector3(1, 0, 0))
	await _wait(0.1)
	print("기절? ", p.downed)
	await _wait(3.5)
	print("깨어남? ", not p.downed, " hp ", p.hp)
	# 갈매기 도둑 (낮에 음식 들고 있기)
	g.clock.hour = 10.0
	await _wait(0.5)
	p.inv.slots[0] = {"id": "cooked_fish", "n": 3}
	p.hotbar_i = 0
	p._on_inv_changed()
	g.ents._gull_t = 0.0
	await _wait(5.0)
	print("갈매기 뒤 구운 생선: ", p.inv.count("cooked_fish"), " (2 면 도둑맞음) 갈매기 수 ", g.ents.count_kind("gull"))
	# 저장 / 불러오기
	g.save_game()
	var data := Game.load_save("smoke")
	print("저장 크기 키: ", data.keys())
	# 스냅샷 직렬화 (손님이 받을 것)
	var snap := {"terrain": g.terrain.diff_data(), "props": g.props.snapshot(), "structs": g.structs.snapshot(), "ents": g.ents.snapshot()}
	print("스냅샷 바이트: ", var_to_bytes(snap).size())
	print("스모크 끝")
	get_tree().quit()


func _inv(p: Player) -> String:
	var parts: Array = []
	for s in p.inv.slots:
		if s != null:
			parts.append("%s×%d" % [s.id, s.n])
	return ", ".join(parts)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout
