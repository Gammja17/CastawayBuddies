class_name Ents
extends Node3D
## 움직이는 것들: 떨어진 아이템, 떠다니는 잔해, 게, 상어, 게 왕.
## 호스트가 움직이고 0.1초마다 위치를 뿌린다. 손님은 부드럽게 따라간다.

const PICKUP_LIFE := 600.0
const CRAB_HP := 6
const NIGHT_CRAB_HP := 9
const KING_HP := 140
const SHARK_HP := 40

var pickups := {}     # id -> {"items": [[id, n, d]], "pos", "t", "natural", "node", "vel", "rest"}
var flotsam := {}     # id -> {"type", "pos", "vel", "node"}
var enemies := {}     # id -> {"kind", "pos", "yaw", "hp", "max", "node", "target_pos", ... (호스트: 상태)}
var next_id := 1
var _sync_t := 0.0
var _flot_t := 5.0
var _nat_t := 20.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func snapshot() -> Dictionary:
	var p: Array = []
	for id in pickups:
		var e: Dictionary = pickups[id]
		p.append({"id": id, "items": e.items, "pos": e.pos, "natural": e.get("natural", false), "t": e.t, "keep": e.get("keep", false)})
	var f: Array = []
	for id in flotsam:
		f.append({"id": id, "type": flotsam[id].type, "pos": flotsam[id].pos, "vel": flotsam[id].vel})
	var en: Array = []
	for id in enemies:
		var e: Dictionary = enemies[id]
		en.append({"id": id, "kind": e.kind, "pos": e.pos, "hp": e.hp, "max": e.max})
	var rf: Array = []
	for id in rafts:
		rf.append({"id": id, "pos": rafts[id].pos, "yaw": rafts[id].yaw, "riders": rafts[id].riders})
	return {"next_id": next_id, "pickups": p, "flotsam": f, "enemies": en, "rafts": rf}


func load_snapshot(s: Dictionary, include_live: bool) -> void:
	for id in pickups.keys():
		_free_pickup(id)
	for id in flotsam.keys():
		_free_flotsam(id)
	for id in enemies.keys():
		_free_enemy(id)
	for id in rafts.keys():
		_free_raft(id)
	next_id = s.get("next_id", 1)
	for r in s.get("rafts", []):
		_make_raft(r.id, r.pos, r.yaw)
		rafts[r.id].riders = r.get("riders", {})   # 저장 파일엔 없고, 도중 참가 스냅샷에만 있다
	for p in s.get("pickups", []):
		_make_pickup(p.id, p.items, p.pos, Vector3.ZERO, p.get("natural", false))
		pickups[p.id].t = p.get("t", 0.0)
		pickups[p.id].rest = true
		pickups[p.id].keep = p.get("keep", false)
	if include_live:
		for f in s.get("flotsam", []):
			_spawn_flotsam(f.id, f.type, f.pos, f.vel)
		for e in s.get("enemies", []):
			_spawn_enemy(e.id, e.kind, e.pos, e.hp, e.max)


func _new_id() -> int:
	next_id += 1
	return next_id


# ═════════ 떨어진 아이템 ═════════

func spawn_pickup(item: String, n: int, pos: Vector3, vel: Vector3 = Vector3.ZERO, d: int = -1, natural := false) -> void:
	spawn_bag([[item, n, d]], pos, vel, natural)


func spawn_bag(items: Array, pos: Vector3, vel: Vector3 = Vector3.ZERO, natural := false, keep := false) -> void:
	if not multiplayer.is_server() or items.is_empty():
		return
	_add_pickup.rpc(_new_id(), items, pos, vel, natural, keep)


@rpc("authority", "call_local", "reliable")
func _add_pickup(id: int, items: Array, pos: Vector3, vel: Vector3, natural: bool, keep: bool) -> void:
	next_id = maxi(next_id, id)
	_make_pickup(id, items, pos, vel, natural)
	pickups[id].keep = keep


func _make_pickup(id: int, items: Array, pos: Vector3, vel: Vector3, natural: bool) -> void:
	var root := Node3D.new()
	root.name = "I%d" % id
	add_child(root)
	root.position = pos
	var vis: Node3D
	if items.size() > 1:
		vis = Vis.make({"s": "sphere", "c": "8a6a42", "sz": [0.45, 0.4, 0.45]})
		var tie := Vis.box(Vector3(0.12, 0.12, 0.12), Color("c7a86b"))
		tie.position.y = 0.22
		vis.add_child(tie)
	else:
		vis = Vis.item_node(items[0][0], 0.38)
	vis.name = "Vis"
	vis.position.y = 0.22
	root.add_child(vis)
	pickups[id] = {"items": items, "pos": pos, "t": 0.0, "natural": natural, "node": root, "vel": vel, "rest": vel == Vector3.ZERO}


func _free_pickup(id: int) -> void:
	var e: Dictionary = pickups.get(id, {})
	if e.has("node") and is_instance_valid(e.node):
		e.node.queue_free()
	pickups.erase(id)


@rpc("any_peer", "call_local", "reliable")
func req_pickup(id: int) -> void:
	if not multiplayer.is_server() or not pickups.has(id):
		return
	var from := multiplayer.get_remote_sender_id()
	var e: Dictionary = pickups[id]
	for it in e.items:
		Game.I.give_to(from, it[0], it[1], it[2] if it.size() > 2 else -1)
	_remove_pickup.rpc(id, from)


@rpc("authority", "call_local", "reliable")
func _remove_pickup(id: int, by: int) -> void:
	var e: Dictionary = pickups.get(id, {})
	if e.has("node") and is_instance_valid(e.node):
		var n: Node3D = e.node
		var who := Game.I.player_node(by)
		if who:
			var tw := create_tween()
			tw.tween_property(n, "global_position", who.global_position + Vector3.UP, 0.15)
			tw.tween_callback(n.queue_free)
		else:
			n.queue_free()
		if by == Net.my_id():
			Audio.play("pickup", -4.0, randf_range(0.9, 1.2))
	pickups.erase(id)


@rpc("any_peer", "call_local", "reliable")
func req_drop(items: Array, pos: Vector3, vel: Vector3, keep: bool = false) -> void:
	if multiplayer.is_server():
		spawn_bag(items, pos, vel, false, keep)


func _process_pickups(delta: float) -> void:
	var t := Game.I.terrain
	var now := Time.get_ticks_msec() / 1000.0
	for id in pickups:
		var e: Dictionary = pickups[id]
		e.t += delta
		var n: Node3D = e.node
		if not is_instance_valid(n):
			continue
		if not e.rest:
			e.vel.y -= 18.0 * delta
			var np: Vector3 = n.position + e.vel * delta
			var g := t.ground_at(np + Vector3.UP * 0.3)
			var floor_y := maxf(g, Terrain.WATER_Y - 0.25) if g < Terrain.WATER_Y else g
			if np.y <= floor_y:
				np.y = floor_y
				e.vel = Vector3.ZERO
				e.rest = true
			n.position = np
			e.pos = np
		else:
			# 발밑 블록이 없어지면 다시 떨어진다
			var g2 := t.ground_at(n.position + Vector3.UP * 0.3)
			var fy := maxf(g2, Terrain.WATER_Y - 0.25) if g2 < Terrain.WATER_Y else g2
			if n.position.y > fy + 0.05:
				e.rest = false
		var vis: Node3D = n.get_node("Vis")
		vis.rotation.y += delta * 1.5
		vis.position.y = 0.22 + sin(now * 2.5 + id) * 0.06


# ═════════ 떠다니는 잔해 ═════════

const FLOTSAM_TYPES := ["plank", "plank", "barrel", "plastic", "crate", "barrel", "palm", "bottle_msg"]


func _server_flotsam(delta: float) -> void:
	_flot_t -= delta
	if _flot_t <= 0.0 and flotsam.size() < 10:
		_flot_t = _rng.randf_range(10.0, 18.0)
		var z := _rng.randf_range(-25.0, 38.0)
		var pos := Vector3(-60, Terrain.WATER_Y - 0.1, z)
		var vel := Vector3(_rng.randf_range(0.7, 1.1), 0, _rng.randf_range(-0.12, 0.12))
		var type: String = FLOTSAM_TYPES[_rng.randi() % FLOTSAM_TYPES.size()]
		if type == "bottle_msg" and _rng.randf() < 0.5:
			type = "plank"
		_add_flotsam.rpc(_new_id(), type, pos, vel)


@rpc("authority", "call_local", "reliable")
func _add_flotsam(id: int, type: String, pos: Vector3, vel: Vector3) -> void:
	next_id = maxi(next_id, id)
	_spawn_flotsam(id, type, pos, vel)


func _spawn_flotsam(id: int, type: String, pos: Vector3, vel: Vector3) -> void:
	var root := Node3D.new()
	root.name = "F%d" % id
	add_child(root)
	root.position = pos
	var m: Node3D
	match type:
		"plank": m = Vis.fit_model("survival/resource-planks", 0.25)
		"barrel": m = Vis.fit_model("survival/barrel", 0.9)
		"crate": m = Vis.fit_model("pirate/crate", 0.7)
		"plastic": m = Vis.make({"s": "box", "c": "5ec8e5", "sz": [0.5, 0.1, 0.35]})
		"palm": m = Vis.make({"s": "box", "c": "4caf3f", "sz": [0.9, 0.05, 0.4]})
		"bottle_msg":
			m = Vis.fit_model("survival/bottle", 0.45)
			m.rotation.z = PI * 0.5
		_: m = Vis.box(Vector3(0.4, 0.2, 0.4), Color.WHITE)
	m.name = "M"
	root.add_child(m)
	if type == "plank":
		m.scale = Vector3(2, 2, 2)
	flotsam[id] = {"type": type, "pos": pos, "vel": vel, "node": root}


func _free_flotsam(id: int) -> void:
	var e: Dictionary = flotsam.get(id, {})
	if e.has("node") and is_instance_valid(e.node):
		e.node.queue_free()
	flotsam.erase(id)


func _process_flotsam(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for id in flotsam.keys():
		var e: Dictionary = flotsam[id]
		e.pos += e.vel * delta
		var n: Node3D = e.node
		if is_instance_valid(n):
			n.position = e.pos + Vector3(0, sin(now * 1.7 + id) * 0.08, 0)
			n.rotation = Vector3(sin(now * 1.3 + id) * 0.12, n.rotation.y + delta * 0.2, cos(now * 1.1 + id) * 0.1)
		if e.pos.x > 62.0:
			_free_flotsam(id)


@rpc("any_peer", "call_local", "reliable")
func req_grab_flotsam(id: int) -> void:
	if not multiplayer.is_server() or not flotsam.has(id):
		return
	var from := multiplayer.get_remote_sender_id()
	var type: String = flotsam[id].type
	match type:
		"plank": Game.I.give_to(from, "plank", _rng.randi_range(2, 3))
		"plastic": Game.I.give_to(from, "plastic", _rng.randi_range(1, 2))
		"palm":
			Game.I.give_to(from, "palm_leaf", 2)
			if _rng.randf() < 0.5:
				Game.I.give_to(from, "coconut", 1)
		"barrel":
			for l in Items.roll_loot("flotsam", _rng, 2):
				Game.I.give_to(from, l[0], l[1])
		"crate":
			for l in Items.roll_loot("barrel", _rng, 3):
				Game.I.give_to(from, l[0], l[1])
		"bottle_msg":
			Game.I.give_to(from, "bottle", 1)
			Game.I.quests.find_bottle_note(from)
	Game.I.stat_add("flotsam", 1)
	_grabbed.rpc(id, from)


@rpc("authority", "call_local", "reliable")
func _grabbed(id: int, by: int) -> void:
	var e: Dictionary = flotsam.get(id, {})
	if e.has("node") and is_instance_valid(e.node):
		Audio.play_at("splash", e.node.global_position, -6.0, 1.3)
		var n: Node3D = e.node
		var who := Game.I.player_node(by)
		var tw := create_tween()
		if who:
			tw.tween_property(n, "global_position", who.global_position + Vector3.UP, 0.25)
		tw.tween_callback(n.queue_free)
	flotsam.erase(id)


func flotsam_near(pos: Vector3, dir: Vector3, max_d: float, max_angle_deg: float) -> int:
	var best := -1
	var bd := max_d
	for id in flotsam:
		var p: Vector3 = flotsam[id].pos
		var to := p - pos
		var d := to.length()
		if d > bd:
			continue
		if d > 2.2 and rad_to_deg(dir.angle_to(to)) > max_angle_deg:
			continue
		bd = d
		best = id
	return best


# ═════════ 적 ═════════

func spawn_enemy(kind: String, pos: Vector3) -> int:
	if not multiplayer.is_server():
		return -1
	var hp := CRAB_HP
	match kind:
		"night_crab": hp = NIGHT_CRAB_HP
		"king": hp = KING_HP
		"shark": hp = SHARK_HP
		"gull": hp = 3
	var id := _new_id()
	_add_enemy.rpc(id, kind, pos, hp, hp)
	return id


@rpc("authority", "call_local", "reliable")
func _add_enemy(id: int, kind: String, pos: Vector3, hp: int, max_hp: int) -> void:
	next_id = maxi(next_id, id)
	_spawn_enemy(id, kind, pos, hp, max_hp)


func _spawn_enemy(id: int, kind: String, pos: Vector3, hp: int, max_hp: int) -> void:
	var root := Node3D.new()
	root.name = "E%d" % id
	add_child(root)
	root.position = pos
	var m: Node3D
	if kind == "shark":
		m = _shark_model()
	elif kind == "gull":
		m = _gull_model()
	else:
		m = _crab_model(kind)
	m.name = "M"
	root.add_child(m)
	enemies[id] = {"kind": kind, "pos": pos, "yaw": 0.0, "hp": hp, "max": max_hp, "node": root, "target_pos": pos, "target_yaw": 0.0,
		"state": "idle", "t": 0.0, "cd": 0.0, "home": pos, "aggro": 0.0, "anim": 0.0, "flash": 0.0}


func _crab_model(kind: String) -> Node3D:
	var n := Node3D.new()
	var col := Color("e8603c") if kind == "crab" else Color("b0302a")
	if kind == "king":
		col = Color("c4402a")
	var body := Vis.mesh_node(Vis._sphere(Vector3(0.55, 0.28, 0.45)), Vis.mat(col))
	body.position.y = 0.22
	body.name = "Body"
	n.add_child(body)
	for side in [-1, 1]:
		var claw := Vis.box(Vector3(0.16, 0.12, 0.2), col.lightened(0.1))
		claw.position = Vector3(side * 0.28, 0.24, 0.25)
		claw.name = "Claw%d" % (side + 1)
		n.add_child(claw)
		var eye := Vis.mesh_node(Vis._sphere(Vector3(0.08, 0.08, 0.08)), Vis.mat(Color.WHITE))
		eye.position = Vector3(side * 0.08, 0.42, 0.14)
		n.add_child(eye)
		var pupil := Vis.box(Vector3(0.03, 0.03, 0.03), Color.BLACK)
		pupil.position = Vector3(side * 0.08, 0.43, 0.18)
		n.add_child(pupil)
		for i in 3:
			var leg := Vis.box(Vector3(0.22, 0.04, 0.04), col.darkened(0.2))
			leg.position = Vector3(side * 0.3, 0.12, -0.1 + i * 0.1)
			leg.rotation.z = side * -0.5
			leg.name = "Leg%d_%d" % [side + 1, i]
			n.add_child(leg)
	if kind == "king":
		var crown := Node3D.new()
		for i in 5:
			var spike := Vis.mesh_node(Vis._cone(0.05, 0.14), Vis.mat(Color("ffd23f")))
			spike.position = Vector3(cos(i * TAU / 5) * 0.12, 0.47, sin(i * TAU / 5) * 0.12 - 0.02)
			crown.add_child(spike)
		var band := Vis.mesh_node(Vis._cyl(0.14, 0.05, 10), Vis.mat(Color("ffd23f")))
		band.position = Vector3(0, 0.42, -0.02)
		crown.add_child(band)
		n.add_child(crown)
		n.scale = Vector3.ONE * 3.2
		var lb := Label3D.new()
		lb.text = "게 왕"
		lb.font = Vis.font()
		lb.font_size = 48
		lb.outline_size = 12
		lb.modulate = Color("ffd23f")
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.position.y = 0.75
		lb.pixel_size = 0.004
		n.add_child(lb)
	elif kind == "night_crab":
		n.scale = Vector3.ONE * 1.25
	return n


func _gull_model() -> Node3D:
	var n := Node3D.new()
	var body := Vis.box(Vector3(0.22, 0.2, 0.5), Color("f4f4f0"))
	n.add_child(body)
	var head := Vis.box(Vector3(0.18, 0.18, 0.18), Color.WHITE)
	head.position = Vector3(0, 0.1, 0.3)
	n.add_child(head)
	var beak := Vis.mesh_node(Vis._cone(0.04, 0.16), Vis.mat(Color("ffa22a")))
	beak.rotation.x = PI * 0.5
	beak.position = Vector3(0, 0.08, 0.46)
	n.add_child(beak)
	for side in [-1, 1]:
		var eye := Vis.box(Vector3(0.03, 0.04, 0.03), Color.BLACK)
		eye.position = Vector3(side * 0.09, 0.14, 0.34)
		n.add_child(eye)
		var wing := Vis.box(Vector3(0.6, 0.03, 0.26), Color("c8ccd2"))
		wing.position = Vector3(side * 0.38, 0.05, 0.0)
		wing.name = "Wing%d" % (side + 1)
		n.add_child(wing)
	var loot := Node3D.new()
	loot.name = "Loot"
	loot.position = Vector3(0, -0.12, 0.42)
	n.add_child(loot)
	return n


func _shark_model() -> Node3D:
	var n := Node3D.new()
	var grey := Color("6f7f8f")
	var body := Vis.mesh_node(Vis._sphere(Vector3(0.7, 0.6, 2.4)), Vis.mat(grey))
	body.scale = Vector3(1, 1, 1)
	body.position.y = -0.35
	n.add_child(body)
	var fin := PrismMesh.new()
	fin.size = Vector3(0.5, 0.6, 0.08)
	fin.left_to_right = 0.2
	var f := Vis.mesh_node(fin, Vis.mat(grey.darkened(0.15)))
	f.rotation.y = PI * 0.5
	f.position = Vector3(0, 0.15, -0.1)
	n.add_child(f)
	var tail := Vis.mesh_node(fin.duplicate(), Vis.mat(grey.darkened(0.15)))
	tail.rotation = Vector3(0, PI * 0.5, PI * 0.5)
	tail.position = Vector3(0, -0.3, -1.3)
	tail.name = "Tail"
	n.add_child(tail)
	var belly := Vis.box(Vector3(0.45, 0.1, 1.6), Color("e8ecef"))
	belly.position.y = -0.62
	n.add_child(belly)
	return n


func _free_enemy(id: int) -> void:
	var e: Dictionary = enemies.get(id, {})
	if e.has("node") and is_instance_valid(e.node):
		e.node.queue_free()
	enemies.erase(id)


func count_kind(kind: String) -> int:
	var n := 0
	for id in enemies:
		if enemies[id].kind == kind:
			n += 1
	return n


func enemy_near(pos: Vector3, dir: Vector3, reach: float) -> int:
	## 앞쪽 부채꼴 안에서 제일 가까운 적
	var best := -1
	var bd := 99.0
	for id in enemies:
		var e: Dictionary = enemies[id]
		var p: Vector3 = e.node.global_position if is_instance_valid(e.node) else e.pos
		var r := 0.4
		if e.kind == "king":
			r = 1.4
		elif e.kind == "shark":
			r = 1.0
		var to := p + Vector3.UP * 0.3 - pos
		var d := to.length() - r
		if d > reach:
			continue
		var flat := Vector3(to.x, 0, to.z)
		if flat.length() > 0.5 and rad_to_deg(Vector3(dir.x, 0, dir.z).angle_to(flat)) > 55.0:
			continue
		if d < bd:
			bd = d
			best = id
	return best


@rpc("any_peer", "call_local", "reliable")
func req_hit_enemy(id: int, dmg: int, from_pos: Vector3) -> void:
	if not multiplayer.is_server() or not enemies.has(id):
		return
	var from := multiplayer.get_remote_sender_id()
	var e: Dictionary = enemies[id]
	e.hp -= dmg
	e.aggro = 25.0
	e.target_peer = from
	var push: Vector3 = (e.pos - from_pos)
	push.y = 0
	if e.kind != "king":
		e.pos += push.normalized() * (0.6 if e.kind != "shark" else 1.2)
	if e.kind == "shark":
		e.state = "flee"
		e.t = 8.0
	_enemy_hit.rpc(id, e.hp)
	if e.hp <= 0:
		_kill(id, from)


func _kill(id: int, by: int) -> void:
	var e: Dictionary = enemies[id]
	var pos: Vector3 = e.pos + Vector3.UP * 0.5
	match e.kind:
		"crab", "night_crab":
			spawn_bag([["crab_meat", 1, -1]], pos, Vector3(0, 3, 0))
			if _rng.randf() < 0.4:
				spawn_pickup("shell", 1, pos, Vector3(1, 3, 0))
			Game.I.stat_add("crabs", 1)
		"king":
			spawn_bag([["golden_shell", 2, -1], ["crab_meat", 5, -1], ["shell", 5, -1]], pos, Vector3(0, 4, 0))
			Game.I.quests.set_flag("king_defeated")
			Game.I.unlock_hat_all("crab")
			Game.I.broadcast_toast("게 왕을 쓰러뜨렸다!! 황금 조개가 굴러 나왔다!", "jingle_good")
			Game.I.stat_add("crabs", 1)
		"shark":
			spawn_bag([["shark_tooth", 3, -1], ["big_fish", 1, -1]], Vector3(pos.x, Terrain.WATER_Y + 0.2, pos.z), Vector3(0, 3, 0))
			Game.I.broadcast_toast("%s 상어를 물리쳤다!" % Items.josa(Net.player_name(by), "이", "가"), "jingle_found")
			_shark_respawn = 240.0
		"gull":
			if e.get("loot", "") != "":
				spawn_pickup(e.loot, 1, pos, Vector3(0, 2, 0))
				Game.I.broadcast_toast("%s 갈매기한테서 %s 되찾았다!" % [Items.josa(Net.player_name(by), "이", "가"), Items.josa(Items.name_of(e.loot), "을", "를")], "jingle_found")
			if _rng.randf() < 0.5:
				spawn_pickup("palm_leaf", 1, pos, Vector3(1, 2, 0))
	_remove_enemy.rpc(id, true)


@rpc("authority", "call_local", "reliable")
func _enemy_hit(id: int, hp: int) -> void:
	var e: Dictionary = enemies.get(id, {})
	if e.is_empty():
		return
	var dmg: int = e.hp - hp
	e.hp = hp
	e.flash = 0.15
	var p: Vector3 = e.node.global_position
	Audio.play_at("punch", p, 0.0, 1.2 if e.kind != "king" else 0.7)
	if e.kind != "shark":
		Audio.play_at("crab", p, -4.0)
	Game.I.fx_break(p + Vector3.UP * 0.4, Color("ffd0c0"), 6)
	if dmg > 0 and DisplayServer.get_name() != "headless":
		# 데미지 숫자가 퐁 떠오른다
		var lb := Label3D.new()
		lb.text = "-%d" % dmg
		lb.font = Vis.font()
		lb.font_size = 64
		lb.outline_size = 14
		lb.modulate = Color("ffe08a") if dmg >= 8 else Color.WHITE
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.no_depth_test = true
		lb.pixel_size = 0.005
		get_parent().add_child(lb)
		var top := 1.0 if e.kind != "king" else 2.6
		lb.global_position = p + Vector3(randf_range(-0.3, 0.3), top, randf_range(-0.3, 0.3))
		var tw := lb.create_tween().set_parallel(true)
		tw.tween_property(lb, "global_position:y", lb.global_position.y + 0.9, 0.7)
		tw.tween_property(lb, "modulate:a", 0.0, 0.7).set_delay(0.3)
		tw.chain().tween_callback(lb.queue_free)


@rpc("authority", "call_local", "reliable")
func _remove_enemy(id: int, died: bool) -> void:
	var e: Dictionary = enemies.get(id, {})
	if e.has("node") and is_instance_valid(e.node):
		var n: Node3D = e.node
		if died:
			Game.I.fx_break(n.global_position + Vector3.UP * 0.3, Color("e8603c"), 14)
		var tw := create_tween()
		tw.tween_property(n, "scale", Vector3(1.4, 0.05, 1.4) * n.scale.x, 0.25)
		tw.tween_callback(n.queue_free)
	enemies.erase(id)


# ── 호스트 AI ──

var _shark_respawn := 30.0
var _king_spawned := false


func _server_ai(delta: float) -> void:
	var g := Game.I
	var t := g.terrain
	var night := g.clock.is_night()
	# 상어 한 마리 유지
	if count_kind("shark") == 0:
		_shark_respawn -= delta
		if _shark_respawn <= 0.0:
			_shark_respawn = 60.0
			spawn_enemy("shark", Vector3(-10, Terrain.WATER_Y - 0.15, 18))
	# 게 왕: 유적 해변에 한 번
	if not _king_spawned and not g.quests.flag("king_defeated"):
		_king_spawned = true
		if count_kind("king") == 0:
			spawn_enemy("king", g.gen.crab_king_home)
	# 낮 게 / 밤 게
	var day_crabs := count_kind("crab")
	if day_crabs < 5:
		_crab_spawn_t -= delta
		if _crab_spawn_t <= 0.0:
			_crab_spawn_t = 25.0
			var spot := _random_beach(["jungle", "wreck", "ruins"])
			if spot != Vector3.INF:
				spawn_enemy("crab", spot)
	if night and count_kind("night_crab") < 2 + 2 * g.players.size():
		_crab_spawn_t2 -= delta
		if _crab_spawn_t2 <= 0.0:
			_crab_spawn_t2 = 9.0
			var p := g.random_player()
			if p:
				var spot := _beach_near(p.global_position, 9.0, 16.0)
				if spot != Vector3.INF:
					spawn_enemy("night_crab", spot)
	if not night:
		for id in enemies.keys():
			if enemies.has(id) and enemies[id].kind == "night_crab":
				_remove_enemy.rpc(id, false)   # 아침이면 모래 속으로 쏙
		# 갈매기 도둑: 낮에 음식을 들고 땅에 서 있으면 가끔 날아온다
		_gull_t -= delta
		if _gull_t <= 0.0:
			_gull_t = _rng.randf_range(70.0, 130.0)
			if count_kind("gull") == 0:
				for pid in g.players:
					var pl = g.players[pid]
					if Items.food_of(pl.held_id).is_empty() or pl.swimming or pl.downed:
						continue
					var from: Vector3 = pl.global_position + Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized() * 28.0 + Vector3.UP * 12.0
					var gid := spawn_enemy("gull", from)
					enemies[gid].target_peer = pid
					enemies[gid].state = "dive"
					Game.I.sfx_all("gull", from)
					break
	for id in enemies.keys():
		if not enemies.has(id):
			continue
		var e: Dictionary = enemies[id]
		e.cd = maxf(0.0, e.cd - delta)
		e.aggro = maxf(0.0, e.aggro - delta)
		match e.kind:
			"crab", "night_crab": _ai_crab(id, e, delta, night)
			"king": _ai_king(id, e, delta)
			"shark": _ai_shark(id, e, delta)
			"gull": _ai_gull(id, e, delta)
		# 땅 높이 맞추기 (상어·갈매기 제외)
		if e.kind != "shark" and e.kind != "gull" and enemies.has(id):
			var gy := t.ground_at(e.pos + Vector3.UP * 1.2)
			if gy > -50.0:
				e.pos.y = maxf(gy, Terrain.WATER_Y - 0.6) if gy < 0.0 else gy


var _crab_spawn_t := 5.0
var _crab_spawn_t2 := 3.0
var _gull_t := 90.0


func _ai_gull(id: int, e: Dictionary, delta: float) -> void:
	var g := Game.I
	var target: Node3D = g.players.get(e.get("target_peer", -1))
	match e.state:
		"dive":
			if target == null or Items.food_of(target.held_id).is_empty():
				e.state = "flee"
				e.t = 6.0
				return
			var aim: Vector3 = target.global_position + Vector3.UP * 1.3
			var to: Vector3 = aim - e.pos
			e.pos += to.normalized() * minf(9.0 * delta, to.length())
			e.yaw = atan2(to.x, to.z)
			if to.length() < 1.0:
				# 진짜로 뺏겼는지는 손님이 확인해 준다 (req_gull_got)
				target.net_stolen.rpc_id(target.peer_id, target.held_id, id)
				e.state = "flee"
				e.t = 9.0
				e.flee_dir = Vector3(to.x, 0, to.z).normalized().rotated(Vector3.UP, _rng.randf_range(-0.6, 0.6))
		_:
			var fd: Vector3 = e.get("flee_dir", Vector3(1, 0, 0))
			e.pos += (fd * 6.0 + Vector3.UP * 1.5) * delta
			e.yaw = atan2(fd.x, fd.z)
			e.t -= delta
			if e.t <= 0.0:
				_remove_enemy.rpc(id, false)


@rpc("any_peer", "call_local", "reliable")
func req_gull_got(id: int, item: String) -> void:
	if not multiplayer.is_server():
		return
	if not enemies.has(id) or enemies[id].kind != "gull":
		# 그새 갈매기가 맞아 죽었다: 음식은 그 자리에 떨어진다
		var who := Game.I.player_node(multiplayer.get_remote_sender_id())
		if who:
			spawn_pickup(item, 1, who.global_position + Vector3.UP * 1.5, Vector3(0, 2, 0))
		return
	enemies[id].loot = item
	_gull_loot.rpc(id, item)


@rpc("authority", "call_local", "reliable")
func _gull_loot(id: int, item: String) -> void:
	var e: Dictionary = enemies.get(id, {})
	if e.is_empty() or not is_instance_valid(e.node):
		return
	var slot: Node3D = e.node.get_node("M/Loot")
	slot.add_child(Vis.item_node(item, 0.3))
	Audio.play_at("gull", e.node.global_position, 3.0)


func _random_beach(keys: Array) -> Vector3:
	var g := Game.I
	for i in 20:
		var isl: Dictionary = WorldGen.ISLANDS[_rng.randi() % WorldGen.ISLANDS.size()]
		if not isl.key in keys:
			continue
		var a := _rng.randf() * TAU
		var r: float = isl.r * _rng.randf_range(0.5, 0.95)
		var x := int(floor(isl.c.x + cos(a) * r))
		var z := int(floor(isl.c.y + sin(a) * r))
		var top := g.terrain.top_y(x, z)
		if top >= 0 and top <= 2 and not g.terrain.is_solid(Vector3i(x, top + 1, z)):
			return Vector3(x + 0.5, top + 1, z + 0.5)
	return Vector3.INF


func _beach_near(pos: Vector3, rmin: float, rmax: float) -> Vector3:
	var g := Game.I
	for i in 16:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(rmin, rmax)
		var x := int(floor(pos.x + cos(a) * r))
		var z := int(floor(pos.z + sin(a) * r))
		var top := g.terrain.top_y(x, z)
		if top >= 0 and not g.terrain.is_solid(Vector3i(x, top + 1, z)) and not g.near_light(Vector3(x, top + 1, z), 6.0):
			return Vector3(x + 0.5, top + 1, z + 0.5)
	return Vector3.INF


func _walkable(from: Vector3, to: Vector3, allow_shallow: bool) -> bool:
	var t := Game.I.terrain
	var x := int(floor(to.x))
	var z := int(floor(to.z))
	var top := t.top_y(x, z)
	if top < (-1 if allow_shallow else 0):
		return false
	var gy := t.ground_at(to + Vector3.UP * 1.2)
	if absf(gy - from.y) > 1.05:
		return false
	# 닫힌 문이나 단단한 설치물은 게도 못 지나간다
	var sid := Game.I.structs.at_cell(Vector3i(x, int(floor(gy + 0.01)), z))
	if sid >= 0:
		var s: Dictionary = Game.I.structs.list[sid]
		if Items.STRUCTS.get(s.kind, {}).get("solid", false) and not s.data.get("open", false):
			return false
	return true


func _move_toward(e: Dictionary, target: Vector3, speed: float, delta: float, allow_shallow: bool) -> bool:
	var to: Vector3 = target - e.pos
	to.y = 0
	if to.length() < 0.05:
		return true
	var step := to.normalized() * minf(speed * delta, to.length())
	var np: Vector3 = e.pos + step
	if _walkable(e.pos, np, allow_shallow):
		e.pos = Vector3(np.x, e.pos.y, np.z)
		e.yaw = atan2(step.x, step.z)
		return true
	# 옆으로 비껴 가기
	for ang in [0.8, -0.8, 1.6, -1.6]:
		var alt := step.rotated(Vector3.UP, ang)
		np = e.pos + alt
		if _walkable(e.pos, np, allow_shallow):
			e.pos = Vector3(np.x, e.pos.y, np.z)
			e.yaw = atan2(alt.x, alt.z)
			return true
	return false


func _ai_crab(id: int, e: Dictionary, delta: float, night: bool) -> void:
	var g := Game.I
	var hunting: bool = e.kind == "night_crab" or e.aggro > 0.0
	var target: Node3D = null
	if hunting:
		target = g.nearest_player(e.pos, 11.0 if e.kind == "night_crab" else 14.0)
		if target and e.kind == "night_crab" and g.near_light(target.global_position, 4.5) and e.aggro <= 0.0:
			# 불빛 근처는 무서워서 가까이 못 간다
			var away: Vector3 = e.pos - target.global_position
			away.y = 0
			if away.length() < 5.5:
				_move_toward(e, e.pos + away.normalized() * 2.0, 2.0, delta, true)
			e.state = "scared"
			return
	if target:
		var d := Vector3(target.global_position.x - e.pos.x, 0, target.global_position.z - e.pos.z).length()
		if d > 1.0:
			_move_toward(e, target.global_position, 3.0 if e.kind == "night_crab" else 2.6, delta, true)
			e.state = "chase"
		elif e.cd <= 0.0:
			e.cd = 1.3
			g.hurt_player(target, 7 if e.kind == "crab" else 9, e.pos)
			_enemy_attack.rpc(id)
	else:
		e.t -= delta
		if e.t <= 0.0:
			e.t = _rng.randf_range(2.0, 5.0)
			var a := _rng.randf() * TAU
			e.wander = e.pos + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(1.0, 3.0)
		if e.has("wander"):
			_move_toward(e, e.wander, 1.0, delta, false)
		e.state = "idle"


func _ai_king(id: int, e: Dictionary, delta: float) -> void:
	var g := Game.I
	var home: Vector3 = e.home
	# 한번 싸움이 붙으면(맞으면) 멀리서도 쫓아오지만, 평소엔 7m 안에 와야 알아챈다
	var target := g.nearest_player(e.pos, 12.0 if e.aggro > 0.0 else 7.0)
	if target and home.distance_to(target.global_position) > 18.0:
		target = null
	if target:
		e.idle_t = 0.0
	else:
		e.idle_t = e.get("idle_t", 0.0) + delta
	match e.state:
		"windup":
			e.t -= delta
			if e.t <= 0.0:
				e.state = "idle"
				e.cd = 2.6
				for pid in g.players:
					var p: Node3D = g.players[pid]
					if p.global_position.distance_to(e.pos) <= 3.2:
						g.hurt_player(p, 18, e.pos)
				_king_slam.rpc(id)
			return
	if target:
		var d := Vector3(target.global_position.x - e.pos.x, 0, target.global_position.z - e.pos.z).length()
		if d > 2.2:
			_move_toward(e, target.global_position, 2.1, delta, true)
		elif e.cd <= 0.0:
			e.state = "windup"
			e.t = 0.9
			_king_windup.rpc(id)
		# 체력이 줄면 부하 소환
		var frac: float = float(e.hp) / e.max
		var summons: int = e.get("summons", 0)
		if (frac < 0.66 and summons == 0) or (frac < 0.33 and summons == 1):
			e.summons = summons + 1
			for i in 2:
				# 낮에도 안 사라지게 보통 게를 성난 상태로
				var cid := spawn_enemy("crab", e.pos + Vector3(_rng.randf_range(-2, 2), 0.3, _rng.randf_range(-2, 2)))
				enemies[cid].aggro = 30.0
			Game.I.broadcast_toast("게 왕: 크랩크랩! (부하들이 튀어나왔다)", "crab")
	else:
		if e.pos.distance_to(home) > 1.0:
			_move_toward(e, home, 1.5, delta, true)
		elif e.hp < e.max and e.idle_t > 60.0:
			# 1분 동안 아무도 없으면 초당 3씩 천천히 회복 (모두에게 알림)
			e.regen = e.get("regen", 0.0) + delta * 3.0
			if e.regen >= 1.0:
				var add := int(e.regen)
				e.regen -= add
				e.hp = mini(e.max, e.hp + add)
				_enemy_hp.rpc(id, e.hp)


@rpc("authority", "call_local", "reliable")
func _enemy_hp(id: int, hp: int) -> void:
	if enemies.has(id):
		enemies[id].hp = hp


func _ai_shark(id: int, e: Dictionary, delta: float) -> void:
	var g := Game.I
	var t := g.terrain
	e.pos.y = Terrain.WATER_Y - 0.15
	if e.state == "flee":
		e.t -= delta
		var away: Vector3 = e.get("flee_dir", Vector3(1, 0, 0))
		_shark_move(e, e.pos + away * 3.0, 5.0, delta)
		if e.t <= 0.0:
			e.state = "idle"
		return
	var prey: Node3D = null
	var best := 22.0
	for pid in g.players:
		var p = g.players[pid]
		if not p.swimming or p.downed or p.deep_time < 2.5:
			continue
		var d: float = p.global_position.distance_to(e.pos)
		if d < best:
			best = d
			prey = p
	if prey:
		e.state = "hunt"
		var pp := Vector3(prey.global_position.x, e.pos.y, prey.global_position.z)
		_shark_move(e, pp, 5.2, delta)
		if pp.distance_to(e.pos) < 1.5 and e.cd <= 0.0:
			e.cd = 2.0
			g.hurt_player(prey, 22, e.pos)
			_enemy_attack.rpc(id)
			e.state = "flee"
			e.t = 5.0
			e.flee_dir = (e.pos - pp).normalized()
	else:
		e.state = "idle"
		e.t -= delta
		if e.t <= 0.0 or not e.has("wander"):
			e.t = _rng.randf_range(4.0, 8.0)
			for i in 10:
				var cand := Vector3(_rng.randf_range(-45, 50), e.pos.y, _rng.randf_range(-35, 45))
				if t.top_y(int(cand.x), int(cand.z)) < -1:
					e.wander = cand
					break
		if e.has("wander"):
			_shark_move(e, e.wander, 2.2, delta)


func _shark_move(e: Dictionary, target: Vector3, speed: float, delta: float) -> void:
	var t := Game.I.terrain
	var to: Vector3 = target - e.pos
	to.y = 0
	if to.length() < 0.1:
		return
	var desired := to.normalized()
	var cur := Vector3(sin(e.yaw), 0, cos(e.yaw))
	var dir := cur.slerp(desired, clampf(delta * 2.5, 0, 1)).normalized()
	var np: Vector3 = e.pos + dir * speed * delta
	if t.top_y(int(floor(np.x)), int(floor(np.z))) < -1:
		e.pos = np
	else:
		dir = dir.rotated(Vector3.UP, 1.2)
		e.wander = e.pos + dir * 6.0
	e.yaw = atan2(dir.x, dir.z)


@rpc("authority", "call_local", "reliable")
func _enemy_attack(id: int) -> void:
	var e: Dictionary = enemies.get(id, {})
	if e.is_empty() or not is_instance_valid(e.node):
		return
	e.anim_atk = 0.3
	Audio.play_at("bite" if e.kind == "shark" else "crab", e.node.global_position)


@rpc("authority", "call_local", "reliable")
func _king_windup(id: int) -> void:
	var e: Dictionary = enemies.get(id, {})
	if e.is_empty() or not is_instance_valid(e.node):
		return
	var ring := Vis.mesh_node(Vis._cyl(3.2, 0.05, 20), Vis.mat(Color(1, 0.2, 0.1, 0.35), true))
	ring.position = e.node.global_position + Vector3.UP * 0.05
	get_parent().add_child(ring)
	get_tree().create_timer(0.9).timeout.connect(ring.queue_free)
	var m: Node3D = e.node.get_node("M")
	create_tween().tween_property(m, "position:y", 1.2, 0.8).set_ease(Tween.EASE_OUT)


@rpc("authority", "call_local", "reliable")
func _king_slam(id: int) -> void:
	var e: Dictionary = enemies.get(id, {})
	if e.is_empty() or not is_instance_valid(e.node):
		return
	var m: Node3D = e.node.get_node("M")
	create_tween().tween_property(m, "position:y", 0.0, 0.1)
	Audio.play_at("rumble", e.node.global_position, 4.0)
	Game.I.fx_break(e.node.global_position + Vector3.UP * 0.2, Color("ecd592"), 24)
	Game.I.shake_camera(0.35, e.node.global_position)


# ═════════ 공통 틱 ═════════

const NO_DESPAWN := ["compass", "clockwork", "golden_shell", "seaweed_feast", "crowbar", "shark_spear", "iron_axe", "iron_pick", "iron_spear"]


func _expires(e: Dictionary) -> bool:
	## 자연 아이템, 기절 가방(여러 개), 귀한 물건은 사라지지 않는다
	if e.get("natural", false) or e.get("keep", false) or e.items.size() > 1:
		return false
	for it in e.items:
		if it[0] in NO_DESPAWN:
			return false
	return true


func _process(delta: float) -> void:
	if Game.I == null or not Game.I.world_ready:
		return
	_process_pickups(delta)
	_process_flotsam(delta)
	_process_rafts(delta)
	if multiplayer.is_server():
		_server_flotsam(delta)
		_server_ai(delta)
		_server_natural(delta)
		for id in pickups.keys():
			if pickups.has(id) and pickups[id].t > PICKUP_LIFE and _expires(pickups[id]):
				_remove_pickup.rpc(id, 0)
		_sync_t -= delta
		if _sync_t <= 0.0:
			_sync_t = 0.1
			var arr := PackedFloat32Array()
			for id in enemies:
				var e: Dictionary = enemies[id]
				arr.append_array([id, e.pos.x, e.pos.y, e.pos.z, e.yaw, 1.0 if e.state in ["chase", "hunt"] else 0.0])
			if not arr.is_empty():
				_sync_enemies.rpc(arr)
	_animate_enemies(delta)


func _server_natural(delta: float) -> void:
	_nat_t -= delta
	if _nat_t > 0.0:
		return
	_nat_t = 40.0
	var n := 0
	for id in pickups:
		if pickups[id].get("natural", false):
			n += 1
	if n >= 16:
		return
	var spot := _random_beach(["home", "jungle", "rocky", "wreck"])
	if spot != Vector3.INF:
		var items := ["stick", "stick", "stone", "stone", "shell", "flint", "coconut"]
		spawn_pickup(items[_rng.randi() % items.size()], 1, spot + Vector3(0, 0.05, 0), Vector3.ZERO, -1, true)


@rpc("authority", "call_remote", "unreliable_ordered")
func _sync_enemies(arr: PackedFloat32Array) -> void:
	var i := 0
	while i + 5 < arr.size():
		var id := int(arr[i])
		if enemies.has(id):
			var e: Dictionary = enemies[id]
			e.target_pos = Vector3(arr[i + 1], arr[i + 2], arr[i + 3])
			e.target_yaw = arr[i + 4]
			e.state = "chase" if arr[i + 5] > 0.5 else "idle"
		i += 6


func _animate_enemies(delta: float) -> void:
	var server := multiplayer.is_server()
	var now := Time.get_ticks_msec() / 1000.0
	for id in enemies:
		var e: Dictionary = enemies[id]
		var n: Node3D = e.node
		if not is_instance_valid(n):
			continue
		var tp: Vector3 = e.pos if server else e.target_pos
		var ty: float = e.yaw if server else e.target_yaw
		var before := n.position
		n.position = n.position.lerp(tp, clampf(delta * 10.0, 0, 1))
		if not server:
			e.pos = n.position
		n.rotation.y = lerp_angle(n.rotation.y, ty, clampf(delta * 8.0, 0, 1))
		var moving := before.distance_to(n.position) > 0.002
		var m: Node3D = n.get_node("M")
		if e.kind == "gull":
			var flap := sin(now * 14.0 + id) * 0.7
			m.get_node("Wing0").rotation.z = -flap
			m.get_node("Wing2").rotation.z = flap
		elif e.kind == "shark":
			var tail: Node3D = m.get_node_or_null("Tail")
			if tail:
				tail.rotation.y = PI * 0.5 + sin(now * (9.0 if e.state == "hunt" else 4.0)) * 0.4
			m.rotation.z = sin(now * 1.3 + id) * 0.08
		else:
			if moving:
				e.anim += delta * 14.0
			for c in m.get_children():
				if c.name.begins_with("Leg"):
					c.rotation.x = sin(e.anim + c.name.hash() % 7) * 0.5
				elif c.name.begins_with("Claw"):
					c.rotation.x = -0.6 if e.get("anim_atk", 0.0) > 0.0 else sin(now * 3.0 + id) * 0.15
		e.anim_atk = maxf(0.0, e.get("anim_atk", 0.0) - delta)
		if e.flash > 0.0:
			e.flash -= delta
			m.scale = Vector3.ONE * (1.15 if e.flash > 0.0 else 1.0) * (3.2 if e.kind == "king" else (1.25 if e.kind == "night_crab" else 1.0))


# ═════════ 뗏목 ═════════
# 탄 사람들이 각자 W/S(노 젓기) A/D(방향)를 누르면 합쳐서 움직인다. 같이 저을수록 빠르다.

const RAFT_SEATS := [Vector3(-0.5, 0.28, 0.55), Vector3(0.5, 0.28, 0.55), Vector3(-0.5, 0.28, -0.25), Vector3(0.5, 0.28, -0.25)]

var rafts := {}   # id -> {"pos", "yaw", "vel", "node", "riders": {peer: seat}, "input": {peer: Vector2}, "tpos", "tyaw"}
var _raft_sync_t := 0.0


func _make_raft(id: int, pos: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	root.name = "R%d" % id
	add_child(root)
	root.position = pos
	root.rotation.y = yaw
	var m := Vis.raft_node()
	m.name = "M"
	root.add_child(m)
	var body := StaticBody3D.new()
	body.collision_layer = 32
	body.collision_mask = 0
	body.set_meta("raft", id)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(2.2, 0.6, 2.6)
	cs.shape = sh
	cs.position.y = 0.1
	body.add_child(cs)
	root.add_child(body)
	rafts[id] = {"pos": pos, "yaw": yaw, "vel": Vector3.ZERO, "node": root, "riders": {}, "input": {}, "tpos": pos, "tyaw": yaw}


func _free_raft(id: int) -> void:
	var r: Dictionary = rafts.get(id, {})
	if r.has("node") and is_instance_valid(r.node):
		r.node.queue_free()
	rafts.erase(id)


func raft_near(pos: Vector3, radius: float) -> int:
	var best := -1
	var bd := radius
	for id in rafts:
		var d: float = (rafts[id].node as Node3D).global_position.distance_to(pos)
		if d < bd:
			bd = d
			best = id
	return best


func raft_seat_pos(id: int, seat: int) -> Vector3:
	var r: Dictionary = rafts.get(id, {})
	if r.is_empty() or not is_instance_valid(r.node):
		return Vector3.INF
	var n: Node3D = r.node
	return n.global_position + n.global_basis * RAFT_SEATS[clampi(seat, 0, 3)]


@rpc("any_peer", "call_local", "reliable")
func req_raft_spawn(pos: Vector3, yaw: float) -> void:
	if not multiplayer.is_server():
		return
	var from := multiplayer.get_remote_sender_id()
	var t := Game.I.terrain
	var ok := true
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			if t.top_y(int(floor(pos.x)) + dx, int(floor(pos.z)) + dz) >= 0:
				ok = false
	if not ok:
		Game.I.toast_to(from, "뗏목은 조금 더 넓은 물 위에 띄워야 해")
		Game.I.give_to(from, "raft", 1)
		return
	_add_raft.rpc(_new_id(), Vector3(pos.x, Terrain.WATER_Y - 0.08, pos.z), yaw)


@rpc("authority", "call_local", "reliable")
func _add_raft(id: int, pos: Vector3, yaw: float) -> void:
	next_id = maxi(next_id, id)
	_make_raft(id, pos, yaw)
	Audio.play_at("splash", pos)


@rpc("any_peer", "call_local", "reliable")
func req_raft_board(id: int) -> void:
	if not multiplayer.is_server() or not rafts.has(id):
		return
	var from := multiplayer.get_remote_sender_id()
	var r: Dictionary = rafts[id]
	if r.riders.has(from):
		return
	drop_rider(from)
	if r.riders.size() >= RAFT_SEATS.size():
		Game.I.toast_to(from, "자리가 없어! (4명까지)")
		return
	var used: Array = r.riders.values()
	for s in RAFT_SEATS.size():
		if not s in used:
			r.riders[from] = s
			break
	_raft_riders.rpc(id, r.riders)


@rpc("any_peer", "call_local", "reliable")
func req_raft_leave(id: int) -> void:
	if not multiplayer.is_server() or not rafts.has(id):
		return
	var from := multiplayer.get_remote_sender_id()
	rafts[id].riders.erase(from)
	rafts[id].input.erase(from)
	_raft_riders.rpc(id, rafts[id].riders)


func drop_rider(peer: int) -> void:
	## 호스트: 다른 뗏목에 타 있거나 나간 사람 내리기
	for id in rafts:
		if rafts[id].riders.has(peer):
			rafts[id].riders.erase(peer)
			rafts[id].input.erase(peer)
			_raft_riders.rpc(id, rafts[id].riders)


@rpc("authority", "call_local", "reliable")
func _raft_riders(id: int, riders: Dictionary) -> void:
	if not rafts.has(id):
		return
	rafts[id].riders = riders
	var me: Player = Game.I.local_player
	if me == null:
		return
	if riders.has(Net.my_id()):
		me.start_ride(id, riders[Net.my_id()])
	elif me.riding == id:
		me.stop_ride()


@rpc("any_peer", "call_local", "unreliable_ordered")
func req_raft_input(id: int, v: Vector2) -> void:
	if not multiplayer.is_server() or not rafts.has(id):
		return
	var from := multiplayer.get_remote_sender_id()
	if rafts[id].riders.has(from):
		rafts[id].input[from] = v.limit_length(1.0)


@rpc("any_peer", "call_local", "reliable")
func req_raft_pickup(id: int) -> void:
	if not multiplayer.is_server() or not rafts.has(id):
		return
	var from := multiplayer.get_remote_sender_id()
	if not rafts[id].riders.is_empty():
		Game.I.toast_to(from, "누가 타고 있어!")
		return
	_remove_raft.rpc(id)
	Game.I.give_to(from, "raft", 1)


@rpc("authority", "call_local", "reliable")
func _remove_raft(id: int) -> void:
	var me: Player = Game.I.local_player if Game.I else null
	if me and me.riding == id:
		me.stop_ride()
	_free_raft(id)


@rpc("authority", "call_remote", "unreliable_ordered")
func _sync_rafts(arr: PackedFloat32Array) -> void:
	var i := 0
	while i + 3 < arr.size():
		var id := int(arr[i])
		if rafts.has(id):
			rafts[id].tpos = Vector3(arr[i + 1], Terrain.WATER_Y - 0.08, arr[i + 2])
			rafts[id].tyaw = arr[i + 3]
		i += 4


func _process_rafts(delta: float) -> void:
	var server := multiplayer.is_server()
	var t := Game.I.terrain
	var now := Time.get_ticks_msec() / 1000.0
	for id in rafts:
		var r: Dictionary = rafts[id]
		if server:
			var thr := 0.0
			var steer := 0.0
			var paddlers := 0
			for peer in r.input:
				var v: Vector2 = r.input[peer]
				thr += -v.y
				steer += -v.x
				if v.length() > 0.1:
					paddlers += 1
			var n := maxi(1, r.input.size())
			thr = clampf(thr / n, -0.5, 1.0)
			steer = clampf(steer / n, -1.0, 1.0)
			var speed := thr * (2.2 + 1.2 * maxi(0, paddlers - 1))
			r.yaw += steer * 1.3 * delta
			var fwd := Vector3(-sin(r.yaw), 0, -cos(r.yaw))
			r.vel = r.vel.lerp(fwd * speed, clampf(delta * 1.8, 0, 1))
			var np: Vector3 = r.pos + r.vel * delta
			var blocked := false
			for off in [Vector3(1, 0, 1), Vector3(-1, 0, 1), Vector3(1, 0, -1), Vector3(-1, 0, -1)]:
				var q: Vector3 = np + off * 0.9
				if t.top_y(int(floor(q.x)), int(floor(q.z))) >= 0:
					blocked = true
			if blocked:
				r.vel = -r.vel * 0.3
			else:
				r.pos = Vector3(clampf(np.x, -70, 70), r.pos.y, clampf(np.z, -70, 70))
			r.tpos = r.pos
			r.tyaw = r.yaw
		var node: Node3D = r.node
		if not is_instance_valid(node):
			continue
		node.position = node.position.lerp(r.tpos, clampf(delta * 10.0, 0, 1)) if not server else r.pos
		node.position.y = Terrain.WATER_Y - 0.08 + sin(now * 1.6 + id) * 0.05
		node.rotation.y = lerp_angle(node.rotation.y, r.tyaw, clampf(delta * 10.0, 0, 1)) if not server else r.yaw
		node.rotation.x = sin(now * 1.2 + id) * 0.03
		node.rotation.z = cos(now * 1.0 + id) * 0.03
	if server and not rafts.is_empty():
		_raft_sync_t -= delta
		if _raft_sync_t <= 0.0:
			_raft_sync_t = 0.1
			var arr := PackedFloat32Array()
			for id in rafts:
				arr.append_array([id, rafts[id].pos.x, rafts[id].pos.z, rafts[id].yaw])
			_sync_rafts.rpc(arr)
