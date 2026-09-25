extends Node
## 두 프로세스 멀티 테스트
##   호스트: godot --headless --path . tools/mp_test.tscn -- host
##   손님:   godot --headless --path . tools/mp_test.tscn -- client

const T := preload("res://tools/tutil.gd")


func _ready() -> void:
	var role: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "host"
	if role == "host":
		Net.pending = {"mode": "host", "new": true, "slot": "mptest", "port": 24681, "upnp": false}
	else:
		Settings.player_name = "손님"
		Net.pending = {"mode": "join", "ip": "127.0.0.1", "port": 24681}
	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game)
	if role == "host":
		await _host()
	else:
		await _client()
	get_tree().quit()


func _host() -> void:
	await _wait(1.0)
	var g: Game = Game.I
	print("[호스트] 준비 ", g.world_ready, " 플레이어 ", g.players.size())
	var t := 0.0
	while g.players.size() < 2 and t < 15.0:
		await _wait(0.5)
		t += 0.5
	print("[호스트] 손님 들어옴: ", g.players.size(), " 이름들 ", Net.players)
	await _wait(8.0)
	print("[호스트] 지형 ", _terrain_sig(g), " 설치물 수 ", g.structs.list.size())
	var cp: Player = null
	for id in g.players:
		if id != 1:
			cp = g.players[id]
	if cp:
		print("[호스트] 손님 위치 ", cp.global_position, " 든 것 ", cp.held_id, " 손님 몸 레이어 ", cp.collision_layer)
		# 친구 머리 밟기
		var me: Player = g.local_player
		me.global_position = cp.global_position + Vector3.UP * 2.4
		me.velocity = Vector3.ZERO
		await _wait(0.8)
		print("[호스트] 친구 머리 위? 높이차 %.2f 바닥 %s" % [me.global_position.y - cp.global_position.y, me.is_on_floor()])
	print("[호스트] 손님 저장 데이터: ", g.player_saves.keys())
	for rid in g.ents.rafts:
		print("[호스트] 뗏목 ", rid, " 위치 ", g.ents.rafts[rid].pos, " 탄 사람 ", g.ents.rafts[rid].riders)
	await _wait(3.0)
	print("[호스트] 끝")


func _client() -> void:
	var t := 0.0
	while (Game.I == null or not Game.I.world_ready) and t < 15.0:
		await _wait(0.25)
		t += 0.25
	var g: Game = Game.I
	print("[손님] 월드 받음 ", g.world_ready, " 지형 조각 ", g.terrain._chunks.size(), " 채집물 ", g.props.list.size(), " 설치물 ", g.structs.list.size(), " 플레이어 ", g.players.size())
	await _wait(1.0)
	var p: Player = g.local_player
	print("[손님] 내 캐릭터 ", p != null, " 위치 ", p.global_position if p else Vector3.ZERO)
	# 상자 열기 → 아이템 받기
	for id in g.structs.list:
		if g.structs.list[id].kind == "loot_crate":
			g.structs.req_interact.rpc_id(1, id, "open", null)
			break
	await _wait(0.5)
	print("[손님] 상자 뒤 가방 코코넛 ", p.inv.count("coconut"))
	# 땅 파기 + 물 메우기
	var home := p.global_position
	g.terrain.req_dig.rpc_id(1, T.spot(g, "workbench", home + Vector3(2, 0, -2)), "shovel")
	var w := T.shallow(g, home)
	p.inv.add("sand", 2)
	p.inv.remove("sand", 1)
	g.terrain.req_fill.rpc_id(1, w, "sand")
	# 구조물 설치
	g.structs.req_place.rpc_id(1, "campfire", T.spot(g, "campfire", home + Vector3(-1.5, 0, -1.5)), 0.0, "campfire")
	# 물 위에 기초 + 벽 (손님이 지어도 호스트에 똑같이)
	var fw := Build.free_spot("foundation", T.shallow(g, home + Vector3(0, 0, -3)), 0.0, g.terrain)
	print("[손님] 물 위 기초 ", fw.pos, " 문제 '", g.structs.part_problem("foundation", fw.pos, 0.0), "'")
	g.structs.req_place.rpc_id(1, "foundation", fw.pos, 0.0, "foundation")
	g.structs.req_place.rpc_id(1, "wall", fw.pos + Vector3(0, 0, -Build.G * 0.5), 0.0, "wall")
	# 걷기
	p.hotbar_i = 0
	p.inv.add("torch", 1)
	p._on_inv_changed()
	Input.action_press("move_forward")
	await _wait(1.0)
	Input.action_release("move_forward")
	await _wait(1.0)
	print("[손님] 지형 ", _terrain_sig(g), " 설치물 수 ", g.structs.list.size(), " 위치 ", p.global_position, " 가방 모래 ", p.inv.count("sand"))
	# 문 설치 + 열기
	var dp := T.spot(g, "door", home + Vector3(1, 0, -2.5))
	p.inv.add("door", 1)
	p.inv.remove("door", 1)
	g.structs.req_place.rpc_id(1, "door", dp, 0.0, "door")
	await _wait(0.5)
	var did := g.structs.near("door", dp, 1.5)
	g.structs.req_interact.rpc_id(1, did, "toggle", null)
	await _wait(0.5)
	print("[손님] 문 열림? ", g.structs.list[did].data.get("open", false))
	# 호스트 때리기
	var host_p: Player = g.players[1]
	host_p.net_bonk.rpc_id(1, p.global_position)
	# 뗏목
	g.ents.req_raft_spawn.rpc_id(1, T.deep(g, home), 0.0)
	await _wait(0.6)
	var raft_id: int = g.ents.rafts.keys()[0] if not g.ents.rafts.is_empty() else -1
	print("[손님] 뗏목 보임 ", raft_id)
	g.ents.req_raft_board.rpc_id(1, raft_id)
	await _wait(0.5)
	print("[손님] 탔나 ", p.riding == raft_id)
	g.hud._set_open("")   # 쪽지 창이 떠 있으면 입력이 막힌다
	var r0: Vector3 = g.ents.rafts[raft_id].node.global_position
	Input.action_press("move_forward")
	await _wait(2.5)
	Input.action_release("move_forward")
	print("[손님] 뗏목 이동(손님 화면) %.2f, 나-뗏목 거리 %.2f" % [g.ents.rafts[raft_id].node.global_position.distance_to(r0), p.global_position.distance_to(g.ents.rafts[raft_id].node.global_position)])
	# 채팅
	g.send_chat("안녕 호스트!")
	await _wait(1.5)
	print("[손님] 끝")


func _terrain_sig(g: Game) -> String:
	## 호스트와 손님 지형이 똑같은지 비교용
	var d: Dictionary = g.terrain.diff_data()
	var sum := 0.0
	for v in d.h:
		sum += v
	var parts := 0
	for id in g.structs.list:
		if Build.is_part(g.structs.list[id].kind):
			parts += 1
	return "바뀐 꼭짓점 %d / 높이합 %.3f / 땅 %d / 부품 %d / 섬넓히기 %d" % [d.i.size(), sum, g.terrain.land_gain(), parts, g.quests.count("land")]


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout
