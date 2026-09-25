extends Node
## 화면 찍기: godot --path . tools/shot.tscn -- <출력폴더> [장면]
## 장면: start(시작섬), wide(하늘에서), night, ui(가방 열기), map, title


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "user://shots"
	var what: String = args[1] if args.size() > 1 else "start"
	DirAccess.make_dir_recursive_absolute(out_dir)
	if what == "title" or what == "slots":
		var t: Node = load("res://scenes/ui/title.tscn").instantiate()
		get_tree().root.add_child.call_deferred(t)
		await _wait(3.0)
		if what == "slots":
			t._open_slots("host")
			await _wait(0.5)
		_save(out_dir + "/%s.png" % what)
		get_tree().quit()
		return
	Net.pending = {"mode": "solo", "new": true, "slot": "shot", "intro": what == "intro"}
	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game)
	await _wait(1.5)
	var g: Game = Game.I
	var p: Player = g.local_player
	p.inv.add("stone_axe", 1)
	p.inv.add("plank_block", 20)
	p.inv.add("torch", 5)
	p.inv.add("cooked_fish", 3)
	match what:
		"start":
			p._yaw = deg_to_rad(200)
			p._pitch = -0.25
			await _wait(1.5)
			_save(out_dir + "/start.png")
		"wide":
			var cam := Camera3D.new()
			g.add_child(cam)
			cam.global_position = Vector3(-10, 38, 55)
			cam.look_at(Vector3(6, 0, 8))
			cam.current = true
			await _wait(1.5)
			_save(out_dir + "/wide.png")
		"night":
			g.clock.hour = 22.0
			p._yaw = deg_to_rad(200)
			p._pitch = -0.3
			p.hotbar_i = 2
			p._on_inv_changed()
			await _wait(2.0)
			_save(out_dir + "/night.png")
		"ui":
			g.hud.open_inventory("")
			await _wait(1.0)
			_save(out_dir + "/ui.png")
		"journal":
			g.quests.find_note("captain_log", 1)
			await _wait(0.5)
			g.hud._set_open("journal")
			await _wait(1.0)
			_save(out_dir + "/journal.png")
		"map":
			g.hud._set_open("map")
			await _wait(1.0)
			_save(out_dir + "/map.png")
		"ruins":
			var cam2 := Camera3D.new()
			g.add_child(cam2)
			cam2.global_position = Vector3(31, 12, 36)
			cam2.look_at(Vector3(31, 2, 18))
			cam2.current = true
			await _wait(2.0)
			_save(out_dir + "/ruins.png")
		"chest":
			var top := g.terrain.top_y(1, 2)
			g.structs.req_place.rpc_id(1, "chest", Vector3i(1, top + 1, 2), 0, "chest")
			await _wait(0.3)
			g.hud.open_chest(g.structs.near("chest", Vector3(1.5, top + 1, 2.5), 2.0))
			await _wait(1.0)
			_save(out_dir + "/chest.png")
		"ship":
			var top2 := g.terrain.top_y(3, 0)
			g.structs.req_place.rpc_id(1, "shipyard", Vector3i(3, top2 + 1, 0), 1, "shipyard")
			await _wait(0.3)
			p.inv.add("plank", 30)
			p.inv.add("rope", 12)
			g.hud.open_shipyard(g.structs.near("shipyard", Vector3(3.5, top2 + 1, 0.5), 2.0))
			await _wait(1.0)
			_save(out_dir + "/ship.png")
		"ending_escape", "ending_adapt", "ending_turtle":
			var kind: String = what.substr(7)
			var where := -1
			if kind == "escape":
				var top3 := g.terrain.top_y(3, 0)
				g.structs.req_place.rpc_id(1, "shipyard", Vector3i(3, top3 + 1, 0), 1, "shipyard")
				await _wait(0.3)
				where = g.structs.near("shipyard", Vector3(3.5, top3 + 1, 0.5), 2.0)
			elif kind == "adapt":
				var top4 := g.terrain.top_y(0, 0)
				g.structs.req_place.rpc_id(1, "totem", Vector3i(0, top4 + 1, 0), 0, "totem")
				await _wait(0.3)
			g.start_ending(kind, where)
			await _wait(5.0)
			_save(out_dir + "/%s_mid.png" % what)
			await _wait(9.0)
			_save(out_dir + "/%s_end.png" % what)
		"raft":
			g.ents.req_raft_spawn.rpc_id(1, Vector3(-9.5, Terrain.WATER_Y, 3.5), 0.6)
			await _wait(0.3)
			var rr: int = g.ents.rafts.keys()[0]
			g.ents.req_raft_board.rpc_id(1, rr)
			await _wait(0.3)
			Input.action_press("move_forward")
			p._yaw = 0.6 + PI * 0.85
			p._pitch = -0.35
			await _wait(1.5)
			_save(out_dir + "/raft.png")
			Input.action_release("move_forward")
		"hats":
			# 모자 넷을 쓴 가짜 손님들
			var hats := ["captain", "flower", "turtle", "crab"]
			for i in hats.size():
				var pid := 100 + i
				Net.players[pid] = {"name": Settings.HATS[hats[i]].name, "color": i + 1, "hat": hats[i]}
				g._spawn_player(pid, Vector3(-1.5 + i * 1.0, 2.0, -0.5), {})
				g.players[pid].model.rotation.y = PI
			var cam6 := Camera3D.new()
			g.add_child(cam6)
			cam6.global_position = Vector3(0.0, 3.4, 3.2)
			cam6.look_at(Vector3(0.0, 2.9, -0.5))
			cam6.make_current()
			p.visible = false
			await _wait(1.0)
			_save(out_dir + "/hats.png")
		"intro":
			await _wait(1.5)
			_save(out_dir + "/intro_a.png")
			await _wait(3.0)
			_save(out_dir + "/intro_b.png")
			await _wait(4.0)
			_save(out_dir + "/intro_c.png")
		"juice":
			# 구름 + 쓰러지는 야자수 + 데미지 숫자
			var palm := -1
			for i in g.props.list.size():
				if g.props.list[i].kind == "palm":
					palm = i
					break
			var cid := g.ents.spawn_enemy("crab", Vector3(-1.5, 1.0, 3.0))
			g.ents.enemies[cid].state = "x"
			p._yaw = PI
			p._pitch = 0.25
			for i in 12:
				g.props.req_hit.rpc_id(1, palm, "")
			g.ents.req_hit_enemy.rpc_id(1, cid, 5, p.global_position)
			await _wait(0.45)
			_save(out_dir + "/juice.png")
		"cave":
			var cam5 := Camera3D.new()
			g.add_child(cam5)
			cam5.global_position = Vector3(-14.5, 3.2, 10.0)
			cam5.look_at(Vector3(-21, 1.5, 9.8))
			cam5.current = true
			await _wait(1.5)
			_save(out_dir + "/cave.png")
		"storm":
			g.clock._sync.rpc(g.clock.hour, g.clock.day, true)
			g.clock._set_storm.rpc(true)
			p._yaw = deg_to_rad(200)
			p._pitch = -0.1
			await _wait(2.0)
			g.clock._flash = 0.8
			await get_tree().process_frame
			_save(out_dir + "/storm.png")
		"enemies":
			var base := Vector3(2, 1, 4)
			g.ents.spawn_enemy("crab", base + Vector3(-2, 0, 0))
			g.ents.spawn_enemy("night_crab", base + Vector3(0, 0, 0))
			g.ents.spawn_enemy("gull", base + Vector3(2, 1.5, 0))
			var kid := g.ents.spawn_enemy("king", base + Vector3(-1, 0, -4))
			var sid := g.ents.spawn_enemy("shark", Vector3(-6, Terrain.WATER_Y - 0.15, 4))
			for id in g.ents.enemies:
				g.ents.enemies[id].state = "frozen"
			set_process(false)
			var cam4 := Camera3D.new()
			g.add_child(cam4)
			cam4.global_position = base + Vector3(3, 4, 9)
			cam4.look_at(base + Vector3(-2, 0.5, -1))
			cam4.current = true
			await _wait(1.5)
			_save(out_dir + "/enemies.png")
		"wreck":
			var cam3 := Camera3D.new()
			g.add_child(cam3)
			cam3.global_position = Vector3(14, 8, 36)
			cam3.look_at(Vector3(5, 1, 27))
			cam3.current = true
			await _wait(2.0)
			_save(out_dir + "/wreck.png")
	get_tree().quit()


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("saved ", path, "  FPS ", Engine.get_frames_per_second(), "  draw calls ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout
