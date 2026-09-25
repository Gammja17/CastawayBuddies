extends Node
## 화면 찍기: godot --path . tools/shot.tscn -- <출력폴더> [장면]
## 장면: start(시작섬), wide(하늘에서), night, ui(가방 열기), map, title, dig(삽질), third(3인칭)
##       banner_wide / banner_house / banner_raft (배너용: 화면 글자 없이 연출)

const T := preload("res://tools/tutil.gd")


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
		if OS.get_cmdline_user_args().has("update"):   # 업데이트 알림 모양 보기
			var up: Control = t.get_node("UI/Root/UpdatePanel")
			up.info.text = "새 버전 v2.1.0 나왔다! (지금 v2.0.0)\n받으면 알아서 다시 켜진다. 친구도 같이 업데이트!"
			up.visible = true
			await _wait(0.3)
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
	p.inv.add("shovel", 1)
	p.inv.add("torch", 5)
	p.inv.add("cooked_fish", 3)
	p.inv.add("sand", 12)
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
		"ui", "craft":
			if what == "craft":
				p.inv.add("plank", 30)
				p.inv.add("stick", 10)
				p.inv.add("rope", 3)
			g.hud.open_inventory("workbench" if what == "craft" else "")
			await _wait(1.0)
			_save(out_dir + "/%s.png" % what)
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
			var cpos := T.spot(g, "chest", p.global_position + Vector3(1, 0, 1))
			g.structs.req_place.rpc_id(1, "chest", cpos, 0.0, "chest")
			await _wait(0.3)
			g.hud.open_chest(g.structs.near("chest", cpos, 1.0))
			await _wait(1.0)
			_save(out_dir + "/chest.png")
		"ship":
			var spos := T.spot(g, "shipyard", p.global_position)
			g.structs.req_place.rpc_id(1, "shipyard", spos, 0.0, "shipyard")
			await _wait(0.3)
			p.inv.add("plank", 30)
			p.inv.add("rope", 12)
			g.hud.open_shipyard(g.structs.near("shipyard", spos, 1.0))
			await _wait(1.0)
			_save(out_dir + "/ship.png")
		"ending_escape", "ending_adapt", "ending_turtle":
			var kind: String = what.substr(7)
			var where := -1
			if kind == "escape":
				var epos := T.spot(g, "shipyard", p.global_position)
				g.structs.req_place.rpc_id(1, "shipyard", epos, 0.0, "shipyard")
				await _wait(0.3)
				where = g.structs.near("shipyard", epos, 1.0)
			elif kind == "adapt":
				g.structs.req_place.rpc_id(1, "totem", T.spot(g, "totem", p.global_position + Vector3(1.5, 0, 0)), 0.0, "totem")
				await _wait(0.3)
			g.start_ending(kind, where)
			await _wait(5.0)
			_save(out_dir + "/%s_mid.png" % what)
			await _wait(9.0)
			_save(out_dir + "/%s_end.png" % what)
		"raft":
			g.ents.req_raft_spawn.rpc_id(1, T.deep(g, p.global_position), 0.6)
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
		"dig", "third":
			# 물가를 몇 번 메우고 구덩이 하나 판 뒤, 삽 들고 땅을 본다
			var w := T.shallow(g, p.global_position)
			for i in 5:
				g.terrain.req_fill.rpc_id(1, w + Vector3(i * 0.6, 0, 0), "sand")
			var d := T.spot(g, "workbench", p.global_position + Vector3(-1.5, 0, -1.5))
			for i in 3:
				g.terrain.req_dig.rpc_id(1, d, "shovel")
			for i in 9:
				if p.inv.slots[i] != null and p.inv.slots[i].id == "shovel":
					p.hotbar_i = i
			p._on_inv_changed()
			var to := (d if what == "dig" else w) - p.global_position
			p._yaw = atan2(-to.x, -to.z)
			p._pitch = -0.75 if what == "dig" else -0.55
			p.first_person = what == "dig"
			await _wait(2.0)
			_save(out_dir + "/%s.png" % what)
		"house", "house_in":
			# 숲섬에 작은 집: 기초 2장 + 벽/창문/문틀+문 + 지붕 + 앞 계단 + 물 위 부두
			var st := g.structs
			var c := Vector3(5, 0, 27)
			var p0 := Vector3.INF
			for r in range(0, 30):
				for i in 24:
					var q := c + Vector3(cos(i * TAU / 24.0), 0, sin(i * TAU / 24.0)) * r
					var top: float = Build.free_spot("foundation", q, 0.0, g.terrain).pos.y
					if p0 == Vector3.INF and st.parts_near(q, 4.0).is_empty() and st.part_problem("foundation", Vector3(q.x, top, q.z), 0.0) == "" 							and st.part_problem("foundation", Vector3(q.x + Build.G, top, q.z), 0.0) == "":
						p0 = Vector3(q.x, top, q.z)
			var G := Build.G
			var H := Build.H
			var parts := [
				["foundation", p0, 0.0], ["foundation", p0 + Vector3(G, 0, 0), 0.0],
				["wall", p0 + Vector3(-G * 0.5, 0, 0), PI * 0.5], ["window_wall", p0 + Vector3(0, 0, -G * 0.5), 0.0],
				["doorway", p0 + Vector3(0, 0, G * 0.5), 0.0], ["wall", p0 + Vector3(G * 1.5, 0, 0), PI * 0.5],
				["wall", p0 + Vector3(G, 0, -G * 0.5), 0.0], ["window_wall", p0 + Vector3(G, 0, G * 0.5), 0.0],
				["roof", p0 + Vector3(0, H, 0), PI], ["roof", p0 + Vector3(G, H, 0), PI],
			]
			for q in parts:
				st.req_place.rpc_id(1, q[0], q[1], q[2], q[0])
			st.req_place.rpc_id(1, "door", p0 + Vector3(0, 0, G * 0.5), 0.0, "door")
			st.req_place.rpc_id(1, "workbench", p0 + Vector3(G + 0.3, 0, -0.3), 0.0, "workbench")
			st.req_place.rpc_id(1, "bed", p0 + Vector3(-0.3, 0, -0.2), PI * 0.5, "bed")
			await _wait(0.5)
			if what == "house":
				p.first_person = false
				p.global_position = g.safe_spot(p0 + Vector3(G * 0.5 + 2.0, 0.5, G * 3.2))
				p._yaw = deg_to_rad(25)
				p._pitch = -0.15
			else:
				p.global_position = p0 + Vector3(G + 0.4, 0.1, 0.4)
				p._yaw = deg_to_rad(80)
				p._pitch = -0.05
			await _wait(1.5)
			_save(out_dir + "/%s.png" % what)
		"fire":
			# 밤, 비 맞아 젖은 채 모닥불 앞 (석쇠에 날것/익은 것/탄 것)
			var fpos := T.spot(g, "campfire", p.global_position + Vector3(-2.2, 0, 1.2))
			g.structs.req_place.rpc_id(1, "campfire", fpos, 0.0, "campfire")
			await _wait(0.2)
			var fid := g.structs.near("campfire", fpos + Vector3.UP * 0.5, 1.0)
			var fd: Dictionary = g.structs.list[fid].data
			fd.fuel = 240.0
			fd.lit = true
			fd.grill = [["raw_fish", 5.0], ["raw_fish", 30.0], ["crab_meat", 70.0]]
			g.structs._sync_data.rpc(fid, fd)
			g.clock.hour = 21.5
			p.cond.wet = 0.8
			p.cond.cold = 0.6
			p.cond.bleed = 20.0
			for i in 9:
				if p.inv.slots[i] != null and p.inv.slots[i].id == "torch":
					p.hotbar_i = i
			p._on_inv_changed()
			var to := fpos - p.global_position
			p._yaw = atan2(-to.x, -to.z)
			p._pitch = -0.45
			await _wait(1.5)
			_save(out_dir + "/fire.png")
		"assemble":
			for it in [["flint", 3], ["stone", 4], ["rope", 4], ["fiber", 4], ["stick", 6], ["shark_tooth", 2], ["cloth", 1], ["coconut_shell", 1]]:
				p.inv.add(it[0], it[1])
			g.hud.open_inventory("")
			g.hud.assemble_toggle.button_pressed = true
			g.hud._asm = {"shape": "spear", "mat": "shark_tooth", "bind": "cloth", "handle": "stick"}
			g.hud._rebuild_assembly()
			await _wait(1.0)
			_save(out_dir + "/assemble.png")
		"logs":
			# 물에 나란히 띄운 통나무 셋 + 하나 더 놓는 중
			var st2 := g.structs
			var w2 := T.shallow(g, p.global_position)
			var dir := Vector3(w2.x - p.global_position.x, 0, w2.z - p.global_position.z).normalized()
			var c2 := w2 + dir * 2.5
			var ls := st2.log_snap(c2, atan2(dir.x, dir.z))
			for i in 3:
				st2.req_place.rpc_id(1, "float_log", ls.pos, ls.rot, "wood")
				ls = st2.log_snap(ls.pos + Basis(Vector3.UP, ls.rot) * Vector3(Structs.LOG_GAP, 0, 0), 0.0)
			p.inv.add("wood", 5)
			for i in 9:
				if p.inv.slots[i] != null and p.inv.slots[i].id == "wood":
					p.hotbar_i = i
			p._on_inv_changed()
			var to2 := c2 - p.global_position
			p._yaw = atan2(-to2.x, -to2.z)
			p._pitch = -0.5
			await _wait(1.5)
			_save(out_dir + "/logs.png")
		"banner_wide", "banner_house", "banner_raft":
			await _banner(g, p, what, out_dir)
		"wreck":
			var cam3 := Camera3D.new()
			g.add_child(cam3)
			cam3.global_position = Vector3(14, 8, 36)
			cam3.look_at(Vector3(5, 1, 27))
			cam3.current = true
			await _wait(2.0)
			_save(out_dir + "/wreck.png")
	get_tree().quit()


func _banner(g: Game, p: Player, what: String, out_dir: String) -> void:
	## 배너용 장면: 화면 글자는 숨기고, 가짜 친구들을 세워 연출한다
	g.hud.visible = false
	g.clock.raining = false
	g.clock.storm = false
	p.visible = false
	var st := g.structs
	var G := Build.G
	var H := Build.H
	var cam := Camera3D.new()
	cam.fov = 58.0
	cam.far = 400.0
	g.add_child(cam)
	match what:
		"banner_wide":
			# 해 질 녘 군도: 시작섬엔 작은 오두막과 모닥불
			g.clock.hour = 16.6
			var hut := T.hut(g, Vector3(0, 0, 1.5))
			_fire(g, T.spot(g, "campfire", hut + Vector3(2.2, 0, 1.0)))
			cam.global_position = Vector3(-26, 17, 44)
			cam.look_at(Vector3(9, 0, 6))
		"banner_house":
			# 난파선 모래톱: 친구 셋이 집 앞 모닥불에 모였다
			g.clock.hour = 18.1
			var c := Vector3(5, 0, 27)
			var p0 := Vector3.INF
			for r in range(0, 30):
				for i in 24:
					var q := c + Vector3(cos(i * TAU / 24.0), 0, sin(i * TAU / 24.0)) * r
					var top: float = Build.free_spot("foundation", q, 0.0, g.terrain).pos.y
					if p0 == Vector3.INF and st.parts_near(q, 4.0).is_empty() and st.part_problem("foundation", Vector3(q.x, top, q.z), 0.0) == "" \
							and st.part_problem("foundation", Vector3(q.x + G, top, q.z), 0.0) == "":
						p0 = Vector3(q.x, top, q.z)
			for q in [["foundation", p0, 0.0], ["foundation", p0 + Vector3(G, 0, 0), 0.0],
					["wall", p0 + Vector3(-G * 0.5, 0, 0), PI * 0.5], ["window_wall", p0 + Vector3(0, 0, -G * 0.5), 0.0],
					["doorway", p0 + Vector3(0, 0, G * 0.5), 0.0], ["wall", p0 + Vector3(G * 1.5, 0, 0), PI * 0.5],
					["wall", p0 + Vector3(G, 0, -G * 0.5), 0.0], ["window_wall", p0 + Vector3(G, 0, G * 0.5), 0.0],
					["roof", p0 + Vector3(0, H, 0), PI], ["roof", p0 + Vector3(G, H, 0), PI]]:
				st.req_place.rpc_id(1, q[0], q[1], q[2], q[0])
			st.req_place.rpc_id(1, "door", p0 + Vector3(0, 0, G * 0.5), 0.0, "door")
			var fire := T.spot(g, "campfire", p0 + Vector3(G * 0.5, 0, G * 1.9))
			_fire(g, fire)
			var cpos := fire + Vector3(4.4, 2.8, 5.6)
			var look := (fire + cpos) * 0.5   # 모닥불과 카메라 사이를 본다
			var spots := [fire + Vector3(-1.5, 0, 0.9), fire + Vector3(1.6, 0, -0.8), fire + Vector3(-0.5, 0, -1.6)]
			var gear := ["torch", "cooked_fish", Items.tool_id("axe", "flint", "rope", "stick")]
			for i in 3:
				var sp: Vector3 = spots[i]
				sp.y = g.terrain.height_at(sp.x, sp.z)
				var to: Vector3 = look - sp
				_buddy(g, i, ["captain", "flower", "straw"][i], sp, atan2(-to.x, -to.z), gear[i], 128 if i == 0 else 0)
			cam.global_position = cpos
			cam.look_at(fire + Vector3(-0.6, 1.1, -1.6))
		"banner_raft":
			# 한낮, 셋이 뗏목을 저어 숲섬으로
			g.clock.hour = 10.5
			var rp := T.deep(g, Vector3(9, 0, -3))
			g.ents.req_raft_spawn.rpc_id(1, rp, 0.9)
			await _wait(0.3)
			var rid: int = g.ents.rafts.keys()[0]
			var yaw: float = g.ents.rafts[rid].yaw
			for i in 3:
				_buddy(g, i, ["captain", "flower", "turtle"][i], g.ents.raft_seat_pos(rid, i), yaw, "" if i != 1 else "fishing_rod", 2 | 32)
			cam.make_current()
			# 뗏목은 물결 따라 움직이니, 친구들과 카메라가 따라간다
			for f in 150:
				var rn: Node3D = g.ents.rafts[rid].node
				var ry: float = rn.global_rotation.y
				for i in 3:
					g.players[200 + i].apply_remote(g.ents.raft_seat_pos(rid, i), ry, 2 | 32 | 64, "" if i != 1 else "fishing_rod", 100.0)
					g.players[200 + i].global_position = g.ents.raft_seat_pos(rid, i)
				var face := Vector3(-sin(ry), 0, -cos(ry))   # 친구들이 보는 쪽 (얼굴이 보이게 앞에서)
				var right := Vector3(-face.z, 0, face.x)
				cam.global_position = rn.global_position + face * 3.4 + right * 3.6 + Vector3.UP * 1.8
				cam.look_at(rn.global_position + Vector3.UP * 0.9)
				await get_tree().process_frame
			await _save(out_dir + "/%s.png" % what)
			return
	cam.make_current()
	await _wait(2.5)
	_save(out_dir + "/%s.png" % what)


func _fire(g: Game, pos: Vector3) -> void:
	## 불붙은 모닥불 (석쇠엔 생선 둘)
	g.structs.req_place.rpc_id(1, "campfire", pos, 0.0, "campfire")
	var fid := g.structs.near("campfire", pos + Vector3.UP * 0.5, 1.0)
	if fid < 0:
		return
	var d: Dictionary = g.structs.list[fid].data
	d.fuel = 400.0
	d.lit = true
	d.grill = [["raw_fish", 30.0], ["crab_meat", 25.0]]
	g.structs._sync_data.rpc(fid, d)


func _buddy(g: Game, i: int, hat: String, pos: Vector3, yaw: float, held: String, flags: int) -> void:
	## 가짜 친구 (모자·색·든 물건·자세)
	var pid := 200 + i
	Net.players[pid] = {"name": ["선장님", "꽃님", "나무꾼"][i], "color": [1, 5, 3][i], "hat": hat}
	g._spawn_player(pid, pos, {})
	var b: Player = g.players[pid]
	b.name_tag.visible = false
	b.apply_remote(pos, yaw, flags | 64, held, 100.0)
	b.model.rotation.y = yaw


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("saved ", path, "  FPS ", Engine.get_frames_per_second(), "  draw calls ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout
