class_name Props
extends Node3D
## 채집물: 나무, 덤불, 바위, 해초. 패면 없어지고 시간이 지나면 다시 자란다.

# drops: [아이템, 최소, 최대] (최소 0 이면 운)
const DEFS := {
	"palm": {"name": "야자수", "hp": 10, "tool": "axe", "need": "", "model": "pirate/palm-straight", "alt": "pirate/palm-bend", "h": 4.4,
		"drops": [["wood", 2, 3], ["palm_leaf", 2, 3], ["coconut", 0, 2], ["sapling", 0, 1]], "regrow": 240.0, "stump": true, "r": 0.3, "solid": true},
	"tree": {"name": "정글 나무", "hp": 16, "tool": "axe", "need": "axe", "model": "nature/tree_default", "alt": "nature/tree_detailed", "h": 5.0,
		"drops": [["wood", 4, 5], ["stick", 1, 2]], "regrow": 300.0, "stump": true, "r": 0.35, "solid": true},
	"bush": {"name": "덤불", "hp": 2, "tool": "", "need": "", "model": "nature/plant_bushLarge", "h": 0.9,
		"drops": [["fiber", 2, 3], ["berries", 0, 1]], "regrow": 120.0, "r": 0.45, "solid": false},
	"berry_bush": {"name": "산딸기 덤불", "hp": 2, "tool": "", "need": "", "model": "nature/plant_bushDetailed", "h": 0.9, "berries": true,
		"drops": [["berries", 2, 4], ["fiber", 1, 2]], "regrow": 150.0, "r": 0.45, "solid": false},
	"boulder": {"name": "바위", "hp": 12, "tool": "pick", "need": "pick", "model": "survival/rock-b", "alt": "survival/rock-a", "h": 1.1,
		"drops": [["stone", 3, 4], ["flint", 0, 2]], "regrow": 360.0, "r": 0.55, "solid": true},
	"iron_rock": {"name": "철광석 바위", "hp": 18, "tool": "pick", "need": "pick", "model": "nature/stone_tallA", "h": 1.4, "ore": true,
		"drops": [["iron_ore", 2, 3], ["stone", 1, 2]], "regrow": 600.0, "r": 0.55, "solid": true},
	"seaweed": {"name": "해초", "hp": 1, "tool": "", "need": "", "h": 0.9,
		"drops": [["seaweed", 1, 2]], "regrow": 90.0, "r": 0.35, "solid": false},
}

const NEED_NAMES := {"axe": "도끼", "pick": "곡괭이", "shovel": "삽"}

var list: Array = []    # id -> {"kind", "pos", "hp", "alive", "t"}
var nodes: Array = []   # id -> Node3D
var _rng := RandomNumberGenerator.new()


func build(gen_props: Array, snap: Array) -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.queue_free()
	list = []
	nodes = []
	var src := snap if not snap.is_empty() else gen_props
	for p in src:
		var e := {"kind": p.kind, "pos": p.pos, "hp": p.get("hp", DEFS[p.kind].hp), "alive": p.get("alive", true), "t": p.get("t", 0.0)}
		list.append(e)
		nodes.append(_make_node(list.size() - 1))


func snapshot() -> Array:
	var out: Array = []
	for e in list:
		out.append(e.duplicate())
	return out


func _make_node(id: int) -> Node3D:
	var e: Dictionary = list[id]
	var def: Dictionary = DEFS[e.kind]
	var root := Node3D.new()
	root.name = "P%d" % id
	add_child(root)
	root.position = e.pos
	var r := RandomNumberGenerator.new()
	r.seed = id * 7919 + 13
	var model: Node3D
	if e.kind == "seaweed":
		model = Node3D.new()
		for i in 3:
			var h := r.randf_range(0.5, 1.0)
			var b := Vis.box(Vector3(0.08, h, 0.05), Color("2f7d4f").lightened(r.randf() * 0.2))
			b.position = Vector3(r.randf_range(-0.2, 0.2), h * 0.5, r.randf_range(-0.2, 0.2))
			b.rotation_degrees.z = r.randf_range(-12, 12)
			model.add_child(b)
	else:
		var path: String = def.model
		if def.has("alt") and r.randf() < 0.35:
			path = def.alt
		model = Vis.fit_model(path, def.h * r.randf_range(0.85, 1.15))
		if def.get("berries", false):
			for i in 5:
				var s := Vis.mesh_node(Vis._sphere(Vector3(0.12, 0.12, 0.12)), Vis.mat(Color("d8324a")))
				s.position = Vector3(r.randf_range(-0.35, 0.35), r.randf_range(0.35, 0.7), r.randf_range(-0.35, 0.35))
				model.add_child(s)
		if def.get("ore", false):
			for i in 6:
				var s := Vis.box(Vector3(0.18, 0.18, 0.18), Color("d08a4e"))
				s.position = Vector3(r.randf_range(-0.35, 0.35), r.randf_range(0.2, 1.1), r.randf_range(-0.3, 0.3))
				s.rotation_degrees = Vector3(r.randf() * 90, r.randf() * 90, 0)
				model.add_child(s)
	model.name = "Model"
	model.rotation.y = r.randf() * TAU
	root.add_child(model)
	if def.get("stump", false):
		var stump := Vis.fit_model("nature/stump_round", 0.45)
		stump.name = "Stump"
		root.add_child(stump)
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = 2 if def.solid else 32
	body.collision_mask = 0
	body.set_meta("prop", id)
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = def.r
	sh.height = minf(def.h, 2.5) if def.solid else maxf(def.h, 0.8)
	cs.shape = sh
	cs.position.y = sh.height * 0.5
	body.add_child(cs)
	root.add_child(body)
	_apply_visual(id)
	return root


func _apply_visual(id: int) -> void:
	var e: Dictionary = list[id]
	var n: Node3D = nodes[id] if id < nodes.size() else get_node_or_null("P%d" % id)
	if n == null:
		return
	n.get_node("Model").visible = e.alive
	if n.has_node("Stump"):
		n.get_node("Stump").visible = not e.alive
	var body: StaticBody3D = n.get_node("Body")
	body.get_child(0).disabled = not e.alive


func def_of(id: int) -> Dictionary:
	if id < 0 or id >= list.size():
		return {}
	return DEFS[list[id].kind]


func is_alive(id: int) -> bool:
	return id >= 0 and id < list.size() and list[id].alive


func occupies(c: Vector3i) -> bool:
	for e in list:
		if e.alive and int(floor(e.pos.x)) == c.x and int(floor(e.pos.z)) == c.z and int(floor(e.pos.y + 0.01)) == c.y:
			return true
	return false


func _process(delta: float) -> void:
	if not multiplayer.is_server() or Game.I == null or not Game.I.world_ready:
		return
	for id in list.size():
		var e: Dictionary = list[id]
		if e.alive:
			continue
		e.t -= delta * (1.5 if Game.I.clock.raining and e.kind != "boulder" and e.kind != "iron_rock" else 1.0)
		if e.t <= 0.0:
			var c := Vector3i(int(floor(e.pos.x)), int(floor(e.pos.y + 0.01)), int(floor(e.pos.z)))
			if Game.I.terrain.is_solid(c) or not Game.I.terrain.is_solid(c + Vector3i.DOWN):
				e.t = 30.0   # 누가 위에 뭘 지었거나 땅이 없어졌으면 나중에
				continue
			e.alive = true
			e.hp = DEFS[e.kind].hp
			_set_state.rpc(id, true, e.hp)


# ── 네트워크 ──

@rpc("any_peer", "call_local", "reliable")
func req_hit(id: int, item_id: String) -> void:
	if not multiplayer.is_server() or not is_alive(id):
		return
	var from := multiplayer.get_remote_sender_id()
	var e: Dictionary = list[id]
	var def: Dictionary = DEFS[e.kind]
	var tool := Items.tool_of(item_id)
	var kind: String = tool.get("kind", "")
	if def.need != "" and kind != def.need:
		Game.I.toast_to(from, "%s 필요해! (%s)" % [Items.josa(NEED_NAMES.get(def.need, def.need), "이", "가"), def.name])
		_hit_fx.rpc(id, false)
		return
	var dmg: int = tool.get("power", 1) if (kind == def.tool and def.tool != "") else 1
	e.hp -= dmg
	if e.kind == "palm" and _rng.randf() < 0.18:
		Game.I.ents.spawn_pickup("coconut", 1, e.pos + Vector3(0, 3.5, 0), Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)))
	if e.hp <= 0:
		e.alive = false
		e.t = def.regrow
		for d in def.drops:
			var n := _rng.randi_range(d[1], d[2])
			if d[1] == 0 and _rng.randf() < 0.5:
				n = 0
			if n > 0:
				Game.I.give_to(from, d[0], n)
		Game.I.stat_add("gathered", 1)
		_set_state.rpc(id, false, 0)
	else:
		_set_state.rpc(id, true, e.hp)
	_hit_fx.rpc(id, true)


@rpc("authority", "call_local", "reliable")
func _set_state(id: int, alive: bool, hp: int) -> void:
	if id >= list.size():
		return
	var was_alive: bool = list[id].alive
	list[id].alive = alive
	list[id].hp = hp
	if was_alive and not alive and list[id].kind in ["palm", "tree"]:
		_fall(id)
	_apply_visual(id)


func _fall(id: int) -> void:
	## 나무가 쿵 쓰러지는 연출 (모양만 복사해서 넘어뜨린다)
	if DisplayServer.get_name() == "headless" or id >= nodes.size():
		return
	var n: Node3D = nodes[id]
	var ghost: Node3D = n.get_node("Model").duplicate()
	add_child(ghost)
	ghost.global_transform = n.get_node("Model").global_transform
	var axis := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	var tw := create_tween()
	tw.tween_method(func(t: float): ghost.global_basis = Basis(axis, t * t * PI * 0.48) * n.get_node("Model").global_basis, 0.0, 1.0, 0.9)
	tw.tween_callback(func():
		Audio.play_at("chop", ghost.global_position, 2.0, 0.55)
		Game.I.shake_camera(0.15, ghost.global_position)
		Game.I.fx_break(ghost.global_position + axis * 2.0 + Vector3.UP * 0.3, Color("a0764a"), 12))
	tw.tween_property(ghost, "scale", Vector3(1, 0.01, 1), 0.5).set_delay(0.4)
	tw.tween_callback(ghost.queue_free)


@rpc("authority", "call_local", "reliable")
func _hit_fx(id: int, ok: bool) -> void:
	if id >= nodes.size():
		return
	var n: Node3D = nodes[id]
	var e: Dictionary = list[id]
	var def: Dictionary = DEFS[e.kind]
	var snd := "punch"
	match def.tool:
		"axe": snd = "chop"
		"pick": snd = "mine"
		"": snd = "leaves"
	if not ok:
		snd = "mine"
	Audio.play_at(snd, n.global_position + Vector3.UP, 0.0, 1.0 if ok else 1.4)
	var m: Node3D = n.get_node("Model")
	var tw := create_tween()
	tw.tween_property(m, "rotation:z", 0.08, 0.05)
	tw.tween_property(m, "rotation:z", -0.06, 0.07)
	tw.tween_property(m, "rotation:z", 0.0, 0.08)
	Game.I.fx_break(n.global_position + Vector3.UP * minf(def.h * 0.4, 1.2), Color("7cc26a") if def.tool == "" else Color("a0764a"), 5)


func add_prop_server(kind: String, pos: Vector3) -> void:
	if multiplayer.is_server():
		_add_prop.rpc(kind, pos)


@rpc("authority", "call_local", "reliable")
func _add_prop(kind: String, pos: Vector3) -> void:
	list.append({"kind": kind, "pos": pos, "hp": DEFS[kind].hp, "alive": true, "t": 0.0})
	nodes.append(_make_node(list.size() - 1))
	var n: Node3D = nodes.back()
	n.scale = Vector3.ONE * 0.2
	create_tween().tween_property(n, "scale", Vector3.ONE, 0.8).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
