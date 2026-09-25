extends Node
## 두 프로세스 멀티 테스트
##   호스트: godot --headless --path . tools/mp_test.tscn -- host
##   손님:   godot --headless --path . tools/mp_test.tscn -- client


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
	print("[호스트] 블록(5,0,5)=", g.terrain.get_block(Vector3i(5, 0, 5)), " 설치물 수 ", g.structs.list.size())
	var cp: Player = null
	for id in g.players:
		if id != 1:
			cp = g.players[id]
	if cp:
		print("[호스트] 손님 위치 ", cp.global_position, " 든 것 ", cp.held_id)
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
	print("[손님] 월드 받음 ", g.world_ready, " 블록 ", g.terrain.get_used_cells().size(), " 채집물 ", g.props.list.size(), " 설치물 ", g.structs.list.size(), " 플레이어 ", g.players.size())
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
	# 블록 설치
	p.inv.add("sand", 2)
	p.inv.remove("sand", 1)
	g.terrain.req_place.rpc_id(1, Vector3i(5, 0, 5), Items.block_index["sand"], "sand")
	# 구조물 설치
	var top := g.terrain.top_y(-1, -1)
	g.structs.req_place.rpc_id(1, "campfire", Vector3i(-1, top + 1, -1), 0, "campfire")
	# 걷기
	p.hotbar_i = 0
	p.inv.add("torch", 1)
	p._on_inv_changed()
	Input.action_press("move_forward")
	await _wait(1.0)
	Input.action_release("move_forward")
	await _wait(1.0)
	print("[손님] 블록(5,0,5)=", g.terrain.get_block(Vector3i(5, 0, 5)), " 설치물 수 ", g.structs.list.size(), " 위치 ", p.global_position)
	# 문 설치 + 열기
	var t2 := g.terrain.top_y(1, -2)
	p.inv.add("door", 1)
	p.inv.remove("door", 1)
	g.structs.req_place.rpc_id(1, "door", Vector3i(1, t2 + 1, -2), 0, "door")
	await _wait(0.5)
	var did := g.structs.near("door", Vector3(1.5, t2 + 1, -1.5), 2.0)
	g.structs.req_interact.rpc_id(1, did, "toggle", null)
	await _wait(0.5)
	print("[손님] 문 열림? ", g.structs.list[did].data.get("open", false))
	# 호스트 때리기
	var host_p: Player = g.players[1]
	host_p.net_bonk.rpc_id(1, p.global_position)
	# 뗏목
	g.ents.req_raft_spawn.rpc_id(1, Vector3(-12.5, Terrain.WATER_Y, 0.5), 0.0)
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


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout
