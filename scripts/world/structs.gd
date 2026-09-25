class_name Structs
extends Node3D
## 설치물(작업대, 상자, 침대...)과 월드 고정물(석판, 종, 제단, 난파선 상자...).
## 상호작용은 전부 호스트가 판정한다. 손님은 "먼저 내고(아이템 차감) 실패하면 돌려받는" 방식.

const MODEL_H := {
	"workbench": 0.95, "campfire": 0.4, "chest": 0.8, "bed": 0.3, "rain_collector": 1.0, "loot_crate": 0.8, "loot_barrel": 1.0,
	"captain_chest": 0.85, "tablet": 1.1, "altar": 1.8, "shipyard": 1.3, "note_sign": 1.3, "big_rock": 1.9,
}
const SOLID_H := {"workbench": 0.9, "chest": 0.8, "rain_collector": 1.0, "loot_crate": 0.8, "loot_barrel": 1.0, "captain_chest": 0.85,
	"tablet": 1.1, "altar": 1.6, "note_sign": 1.2, "furnace": 1.1, "totem": 2.6, "bell": 2.4}

const SHIP_PARTS := {
	"hull": {"name": "선체", "need": {"plank": 40, "rope": 6}},
	"sail": {"name": "돛과 돛대", "need": {"wood": 12, "cloth": 8, "rope": 6}},
	"compass": {"name": "나침반", "need": {"compass": 1}},
	"food": {"name": "항해 식량", "need": {"cooked": 10, "fresh_water": 8}},
}
const COOKED := ["cooked_fish", "cooked_big_fish", "cooked_crab", "baked_potato", "fish_soup"]

const FIXED_LOOT := {
	"start": [["coconut", 2], ["bottle", 2], ["rope", 1], ["fiber", 2], ["wood", 2]],
	"wreck_crate": [["cloth", 5], ["rope", 2], ["potato", 3], ["scrap", 2], ["bottle", 1]],
	"temple": [["golden_shell", 1], ["iron", 2]],
	"captain": [["compass", 1], ["clockwork", 1], ["cloth", 2], ["iron", 2]],
	"treasure": [["golden_shell", 1], ["iron", 3], ["bottle", 1], ["shark_tooth", 1]],
}
const LOOT_NOTES := {"start": "note_start", "captain": "treasure_map", "treasure": "treasure_note", "temple": ""}

const CHEST_SLOTS := 18

var list := {}          # id -> {"kind", "cell", "rot", "data"}
var nodes := {}         # id -> Node3D
var next_id := 0
var viewers := {}       # chest id -> {peer: true}
var sleepers := {}      # peer -> true
var _bell_rung := {}    # bell index -> 시간(초)
var _pushes := {}       # peer -> 바위 민 시간(초)
var _tick := 0.0
var _rng := RandomNumberGenerator.new()


func build(gen_structs: Array, snap: Dictionary) -> void:
	for id in nodes:
		if is_instance_valid(nodes[id]):
			nodes[id].queue_free()
	nodes.clear()
	list.clear()
	if snap.is_empty():
		next_id = 0
		for s in gen_structs:
			list[next_id] = {"kind": s.kind, "cell": s.cell, "rot": s.rot, "data": _init_data(s.kind, s.data.duplicate(true))}
			next_id += 1
	else:
		next_id = snap.next_id
		for id in snap.list:
			list[int(id)] = snap.list[id].duplicate(true)
	for id in list:
		_make_node(id)


func snapshot() -> Dictionary:
	return {"next_id": next_id, "list": list.duplicate(true)}


func _init_data(kind: String, data: Dictionary) -> Dictionary:
	match kind:
		"chest":
			if not data.has("items"):
				var arr: Array = []
				arr.resize(CHEST_SLOTS)
				data.items = arr
		"rain_collector", "trap", "sand_trap":
			data.stored = data.get("stored", 0)
			data.t = 0.0
		"farm_plot":
			data.crop = ""
			data.grow = 0.0
		"sapling":
			data.grow = 0.0
		"shipyard":
			data.parts = {}
			for p in SHIP_PARTS:
				data.parts[p] = {}
		"altar":
			data.feast = false
			data.shells = 0
		"plate":
			data.pressed = false
		"door":
			data.open = false
	return data


# ── 모양 ──

func _make_node(id: int) -> void:
	var s: Dictionary = list[id]
	var kind: String = s.kind
	var def: Dictionary = Items.STRUCTS.get(kind, {})
	var root := Node3D.new()
	root.name = "S%d" % id
	add_child(root)
	root.position = Vector3(s.cell.x + 0.5, s.cell.y, s.cell.z + 0.5)
	root.rotation.y = s.rot * PI * 0.5
	var model: Node3D
	if def.has("model"):
		model = Vis.fit_model(def.model, MODEL_H.get(kind, 1.0))
	else:
		model = Vis.make(def.get("vis", {"s": "box", "c": "ff00ff"}))
	model.name = "Model"
	root.add_child(model)
	# 충돌 / 조준용 몸통
	var body := StaticBody3D.new()
	body.name = "Body"
	var solid: bool = def.get("solid", false)
	body.collision_layer = 2 if solid else 32
	body.collision_mask = 0
	body.set_meta("struct", id)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	var h: float = SOLID_H.get(kind, 0.5)
	sh.size = Vector3(0.9, h, 0.9)
	if kind == "bed":
		sh.size = Vector3(0.8, 0.35, 1.6)
	elif kind == "plate":
		sh.size = Vector3(0.9, 0.15, 0.9)
	elif kind == "door":
		sh.size = Vector3(0.95, 1.95, 0.25)
	elif kind == "big_rock":
		sh.size = Vector3(1.0, 2.0, 2.0)   # 두 칸 너비 굴을 통째로 막는다
		model.position.z = 0.5
		model.scale = Vector3(1.0, 1.0, 1.6)
	cs.shape = sh
	cs.position.y = sh.size.y * 0.5
	if kind == "big_rock":
		cs.position.z = 0.5
	body.add_child(cs)
	root.add_child(body)
	# 빛
	var light_r: float = def.get("light", 0.0)
	if light_r > 0.0:
		var l := OmniLight3D.new()
		l.name = "Light"
		l.light_color = Color(1.0, 0.72, 0.4)
		l.omni_range = light_r
		l.light_energy = 1.6
		l.position.y = 0.9
		l.shadow_enabled = false
		root.add_child(l)
		if kind == "campfire":
			_add_fire(root)
	# 이름표 (상태 표시용)
	if kind in ["rain_collector", "trap", "sand_trap", "farm_plot", "shipyard", "altar"]:
		var lb := Label3D.new()
		lb.name = "Info"
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.position.y = 1.5 if kind != "shipyard" else 2.2
		lb.font_size = 40
		lb.outline_size = 10
		lb.pixel_size = 0.006
		lb.font = Vis.font()
		root.add_child(lb)
	if kind == "shipyard":
		var ship := Vis.fit_model("pirate/ship-small", 5.5)
		ship.name = "Ship"
		ship.position = Vector3(0, -1.2, 4.2)
		ship.rotation.y = PI * 0.5
		root.add_child(ship)
	nodes[id] = root
	_refresh(id)


func _add_fire(root: Node3D) -> void:
	var p := CPUParticles3D.new()
	p.name = "Fire"
	p.amount = 18
	p.lifetime = 0.7
	p.mesh = Vis._cone(0.07, 0.18)
	p.material_override = Vis.mat(Color("ffa030"), true)
	p.direction = Vector3.UP
	p.spread = 12.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.2
	p.gravity = Vector3(0, 0.5, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.15
	p.position.y = 0.15
	root.add_child(p)


func _refresh(id: int) -> void:
	## 데이터에 맞게 모양 갱신
	var s: Dictionary = list.get(id, {})
	var n: Node3D = nodes.get(id)
	if s.is_empty() or n == null:
		return
	var d: Dictionary = s.data
	var info: Label3D = n.get_node_or_null("Info")
	match s.kind:
		"rain_collector":
			info.text = "물 %d/3" % d.stored if d.stored > 0 else ""
		"trap":
			info.text = "통발 %d" % d.stored if d.stored > 0 else ""
		"sand_trap":
			info.text = "모래 %d" % d.stored if d.stored > 0 else ""
		"farm_plot":
			_refresh_farm(n, d)
			info.text = "다 자람!" if d.crop != "" and d.grow >= 1.0 else ""
		"sapling":
			var m: Node3D = n.get_node("Model")
			m.scale = Vector3.ONE * (0.8 + d.grow * 1.2)
		"loot_crate", "loot_barrel", "captain_chest":
			if d.get("opened", false):
				_set_alpha(n.get_node("Model"), 0.35)
		"dig_spot":
			var shown: bool = Game.I != null and Game.I.quests.flag("treasure_map") and not d.get("dug", false)
			n.visible = shown
			n.get_node("Body").get_child(0).disabled = not shown
		"plate":
			var m: Node3D = n.get_node("Model")
			m.position.y = -0.05 if d.pressed else 0.0
		"door":
			var m: Node3D = n.get_node("Model")
			var open: bool = d.get("open", false)
			m.rotation.y = -PI * 0.5 if open else 0.0
			m.position = Vector3(-0.42, 0, 0.42) if open else Vector3.ZERO
			(n.get_node("Body") as StaticBody3D).collision_layer = 32 if open else 2
		"shipyard":
			var total := 0
			var done := 0
			for part in SHIP_PARTS:
				for item in SHIP_PARTS[part].need:
					total += SHIP_PARTS[part].need[item]
					done += mini(d.parts[part].get(item, 0), SHIP_PARTS[part].need[item])
			var pct := int(100.0 * done / total)
			info.text = "탈출선 %d%%" % pct
			var ship: Node3D = n.get_node("Ship")
			ship.visible = part_done(id, "hull")
			ship.scale = Vector3(1, 0.55 if not ship_ready(id) else 1.0, 1)
		"altar":
			var t := ""
			if d.feast:
				t += "잔치상 OK  "
			if d.shells > 0:
				t += "황금 조개 %d/3" % d.shells
			info.text = t


func refresh_all(kind: String) -> void:
	for id in list:
		if list[id].kind == kind:
			_refresh(id)


func _refresh_farm(n: Node3D, d: Dictionary) -> void:
	var old := n.get_node_or_null("Crop")
	if old:
		old.queue_free()
	if d.crop == "":
		return
	var crop := Node3D.new()
	crop.name = "Crop"
	var stage := 0 if d.grow < 0.34 else (1 if d.grow < 1.0 else 2)
	var col := Color("7ddc6a")
	for i in 4:
		var h := 0.12 + stage * 0.15
		var b := Vis.box(Vector3(0.08, h, 0.08), col)
		b.position = Vector3(-0.2 + (i % 2) * 0.4, 0.15 + h * 0.5, -0.2 + (i / 2) * 0.4)
		crop.add_child(b)
		if stage == 2:
			var fruit_c := Color("c9a35e") if d.crop == "potato" else Color("d8324a")
			var f := Vis.mesh_node(Vis._sphere(Vector3(0.14, 0.14, 0.14)), Vis.mat(fruit_c))
			f.position = b.position + Vector3(0.06, h * 0.4, 0)
			crop.add_child(f)
	n.add_child(crop)


func _set_alpha(model: Node3D, a: float) -> void:
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).transparency = 1.0 - a


func at_cell(c: Vector3i) -> int:
	for id in list:
		if list[id].cell == c:
			return id
	return -1


func kind_of(id: int) -> String:
	return list.get(id, {}).get("kind", "")


func near(kind: String, pos: Vector3, radius: float) -> int:
	var best := -1
	var bd := radius
	for id in list:
		if list[id].kind != kind:
			continue
		var c: Vector3i = list[id].cell
		var d := pos.distance_to(Vector3(c.x + 0.5, c.y + 0.5, c.z + 0.5))
		if d <= bd:
			bd = d
			best = id
	return best


func part_done(id: int, part: String) -> bool:
	var d: Dictionary = list[id].data
	for item in SHIP_PARTS[part].need:
		if d.parts[part].get(item, 0) < SHIP_PARTS[part].need[item]:
			return false
	return true


func ship_ready(id: int) -> bool:
	for p in SHIP_PARTS:
		if not part_done(id, p):
			return false
	return true


func count_kind(kind: String) -> int:
	var n := 0
	for id in list:
		if list[id].kind == kind:
			n += 1
	return n


# ── 호스트 틱 ──

func _process(delta: float) -> void:
	if not multiplayer.is_server() or Game.I == null or not Game.I.world_ready:
		return
	_tick += delta
	if _tick < 0.25:
		return
	var dt := _tick
	_tick = 0.0
	var rain: bool = Game.I.clock.raining
	for id in list.keys():
		if not list.has(id):
			continue
		var s: Dictionary = list[id]
		var d: Dictionary = s.data
		match s.kind:
			"rain_collector":
				if d.stored < 3:
					d.t += dt * (4.0 if rain else 1.0)
					if d.t >= 110.0:
						d.t = 0.0
						d.stored += 1
						_sync_data.rpc(id, d)
			"trap":
				if d.stored < 3:
					d.t += dt
					if d.t >= 75.0:
						d.t = 0.0
						d.stored += 1
						_sync_data.rpc(id, d)
			"sand_trap":
				if d.stored < 8:
					d.t += dt
					if d.t >= 18.0:
						d.t = 0.0
						d.stored += 1
						_sync_data.rpc(id, d)
			"farm_plot":
				if d.crop != "" and d.grow < 1.0:
					var before: float = d.grow
					d.grow = minf(1.0, d.grow + dt / 150.0 * (1.6 if rain else 1.0))
					if (before < 0.34 and d.grow >= 0.34) or d.grow >= 1.0:
						_sync_data.rpc(id, d)
			"sapling":
				d.grow += dt / 140.0 * (1.5 if rain else 1.0)
				if d.grow >= 1.0:
					var pos := Vector3(s.cell.x + 0.5, s.cell.y, s.cell.z + 0.5)
					_remove.rpc(id)
					Game.I.props.add_prop_server("palm", pos)
			"plate":
				var pressed := Game.I.terrain.is_solid(s.cell) or Game.I.player_on_cell(s.cell)
				if pressed != d.pressed:
					d.pressed = pressed
					_sync_data.rpc(id, d)
					if pressed:
						Game.I.sfx_all("click", Vector3(s.cell))
					_check_plates()


func _check_plates() -> void:
	if Game.I.quests.flag("temple_open"):
		return
	var n := 0
	var total := 0
	for id in list:
		if list[id].kind == "plate":
			total += 1
			if list[id].data.pressed:
				n += 1
	if total > 0 and n == total:
		for c in Game.I.gen.door_cells:
			Game.I.terrain.set_block_server(c, Terrain.EMPTY)
		Game.I.quests.set_flag("temple_open")
		Game.I.broadcast_toast("쿠구구궁... 신전의 문이 열렸다!", "rumble")


# ── 네트워크: 설치 / 제거 ──

@rpc("any_peer", "call_local", "reliable")
func req_place(kind: String, cell: Vector3i, rot: int, item_id: String) -> void:
	if not multiplayer.is_server():
		return
	var from := multiplayer.get_remote_sender_id()
	var def: Dictionary = Items.STRUCTS.get(kind, {})
	var t := Game.I.terrain
	var reason := ""
	if def.is_empty() or def.get("world", false):
		reason = "설치할 수 없는 물건"
	elif t.is_solid(cell) or Game.I.occupied(cell) != "":
		reason = "자리가 없어!"
	elif not t.is_solid(cell + Vector3i.DOWN):
		reason = "단단한 땅 위에 놓아야 해"
	elif def.has("on") and not (Items.block(t.get_block(cell + Vector3i.DOWN)).get("id", "") in def.on):
		reason = "여기엔 못 심어 (모래/흙/잔디 위에)" if kind == "sapling" else "흙이나 잔디 위에 놓아야 해"
	elif def.get("water", false) and not _next_to_water(cell):
		reason = "물가에 놓아야 해"
	elif def.get("solid", false) and Game.I.player_in_cell(cell):
		reason = "누가 서 있어!"
	if reason != "":
		Game.I.toast_to(from, reason)
		Game.I.give_to(from, item_id, 1)
		return
	var id := next_id
	next_id += 1
	_add.rpc(id, kind, cell, rot, _init_data(kind, {}))
	Game.I.quests.on_struct_placed(kind)


func _next_to_water(cell: Vector3i) -> bool:
	for dir in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		var c: Vector3i = cell + dir
		if Game.I.terrain.top_y(c.x, c.z) < 0 and not Game.I.terrain.is_solid(Vector3i(c.x, maxi(cell.y - 1, 0), c.z)):
			return true
	return false


@rpc("authority", "call_local", "reliable")
func _add(id: int, kind: String, cell: Vector3i, rot: int, data: Dictionary) -> void:
	list[id] = {"kind": kind, "cell": cell, "rot": rot, "data": data}
	next_id = maxi(next_id, id + 1)
	_make_node(id)
	var n: Node3D = nodes[id]
	Audio.play_at("craft", n.global_position)
	n.scale = Vector3(1.2, 0.6, 1.2)
	create_tween().tween_property(n, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


@rpc("any_peer", "call_local", "reliable")
func req_remove(id: int) -> void:
	if not multiplayer.is_server() or not list.has(id):
		return
	var from := multiplayer.get_remote_sender_id()
	var s: Dictionary = list[id]
	var def: Dictionary = Items.STRUCTS.get(s.kind, {})
	if def.get("world", false):
		return
	var pos := Vector3(s.cell.x + 0.5, s.cell.y + 0.5, s.cell.z + 0.5)
	if s.kind == "chest":
		for it in s.data.items:
			if it != null:
				Game.I.ents.spawn_pickup(it.id, it.n, pos, Vector3(_rng.randf_range(-1.5, 1.5), 3, _rng.randf_range(-1.5, 1.5)), it.get("d", -1))
	var item_id: String = def.get("item", s.kind)
	if s.kind == "shipyard" or s.kind == "totem":
		Game.I.toast_to(from, "이건 너무 소중해서 부술 수 없어!")
		return
	Game.I.give_to(from, item_id, 1)
	_remove.rpc(id)


@rpc("authority", "call_local", "reliable")
func _remove(id: int) -> void:
	if nodes.has(id):
		Game.I.fx_break(nodes[id].global_position + Vector3.UP * 0.4, Color("a0764a"), 8)
		nodes[id].queue_free()
		nodes.erase(id)
	list.erase(id)
	viewers.erase(id)


@rpc("authority", "call_local", "reliable")
func _sync_data(id: int, data: Dictionary) -> void:
	if not list.has(id):
		return
	list[id].data = data
	_refresh(id)


# ── 네트워크: 상호작용 ──

@rpc("any_peer", "call_local", "reliable")
func req_interact(id: int, action: String, arg: Variant) -> void:
	if not multiplayer.is_server():
		return
	var from := multiplayer.get_remote_sender_id()
	if not list.has(id):
		_refund_missing(from, action, arg)
		return
	var s: Dictionary = list[id]
	var d: Dictionary = s.data
	var pos := Vector3(s.cell.x + 0.5, s.cell.y + 0.5, s.cell.z + 0.5)
	match [s.kind, action]:
		["rain_collector", "take"]:
			if d.stored > 0:
				d.stored -= 1
				Game.I.give_to(from, "fresh_water", 1)
				_sync_data.rpc(id, d)
			else:
				Game.I.give_to(from, "bottle", 1)
				Game.I.toast_to(from, "아직 물이 안 고였어")
		["trap", "take"]:
			if d.stored <= 0:
				Game.I.toast_to(from, "아직 비었어")
				return
			for i in d.stored:
				for l in Items.roll_loot("trap", _rng):
					Game.I.give_to(from, l[0], l[1])
			d.stored = 0
			_sync_data.rpc(id, d)
		["sand_trap", "take"]:
			if d.stored <= 0:
				Game.I.toast_to(from, "파도가 모래를 쌓는 중...")
				return
			Game.I.give_to(from, "sand", d.stored)
			d.stored = 0
			_sync_data.rpc(id, d)
		["farm_plot", "plant"]:
			if d.crop == "":
				d.crop = arg
				d.grow = 0.0
				_sync_data.rpc(id, d)
			else:
				Game.I.give_to(from, arg, 1)
		["farm_plot", "harvest"]:
			if d.crop != "" and d.grow >= 1.0:
				Game.I.give_to(from, d.crop, _rng.randi_range(3, 4))
				d.crop = ""
				d.grow = 0.0
				_sync_data.rpc(id, d)
				Game.I.quests.add_count("harvests", 1)
				Game.I.sfx_all("pickup", pos)
		["loot_crate", "open"], ["loot_barrel", "open"], ["captain_chest", "open"], ["dig_spot", "dig"]:
			if d.get("opened", false) or d.get("dug", false):
				Game.I.toast_to(from, "이미 비어 있어")
				return
			if s.kind == "dig_spot":
				d.dug = true
			else:
				d.opened = true
			var table: String = d.get("loot", "captain")
			if FIXED_LOOT.has(table):
				for l in FIXED_LOOT[table]:
					Game.I.give_to(from, l[0], l[1])
			else:
				for l in Items.roll_loot(table, _rng, 3):
					Game.I.give_to(from, l[0], l[1])
			var note: String = LOOT_NOTES.get(table, "")
			if note != "":
				Game.I.quests.find_note(note, from)
			if s.kind == "captain_chest":
				Game.I.broadcast_toast("%s 선장의 금고를 비틀어 열었다!" % Items.josa(Net.player_name(from), "이", "가"), "jingle_found")
			if s.kind == "dig_spot":
				Game.I.broadcast_toast("%s 보물을 파냈다!!" % Items.josa(Net.player_name(from), "이", "가"), "jingle_found")
			_sync_data.rpc(id, d)
			Game.I.sfx_all("chest_open", pos)
		["tablet", "read"], ["note_sign", "read"]:
			Game.I.quests.find_note(d.note, from)
		["bed", "sleep"]:
			Game.I.set_spawn_for(from, Vector3(s.cell.x + 0.5, s.cell.y + 0.3, s.cell.z + 0.5))
			if Game.I.clock.is_night():
				sleepers[from] = true
				Game.I.check_sleep()
			else:
				Game.I.toast_to(from, "여기서 다시 깨어나게 된다. (잠은 밤에만)")
		["bed", "wake"]:
			sleepers.erase(from)
		["bell", "ring"]:
			_ring_bell(id)
		["altar", "feast"]:
			if d.feast:
				Game.I.give_to(from, "seaweed_feast", 1)
				Game.I.toast_to(from, "잔치상은 이미 차려져 있어")
				return
			d.feast = true
			_sync_data.rpc(id, d)
			Game.I.quests.set_flag("feast_offered")
			Game.I.broadcast_toast("거북 제단에 해초 잔치상이 차려졌다. 어디선가 꿀꺽하는 소리가...", "rumble")
		["altar", "shell"]:
			if d.shells >= 3:
				Game.I.give_to(from, "golden_shell", 1)
				return
			d.shells += 1
			_sync_data.rpc(id, d)
			Game.I.quests.set_count("shells_offered", d.shells)
			Game.I.sfx_all("quest", pos)
		["shipyard", "give"]:
			_contribute(id, from, arg)
		["shipyard", "depart"]:
			if not ship_ready(id):
				Game.I.toast_to(from, "탈출선이 아직 완성되지 않았어")
				return
			Game.I.try_depart(id)
		["big_rock", "push"]:
			# 둘이 1.5초 안에 같이 밀거나, 철곡괭이를 지렛대로 쓰면 굴러간다
			var now := Time.get_ticks_msec() / 1000.0
			_pushes[from] = now
			var n := 0
			for pid in _pushes:
				if now - _pushes[pid] <= 1.5 and Game.I.players.has(pid):
					n += 1
			if n >= 2 or arg == "iron_pick":
				_pushes.clear()
				_remove.rpc(id)
				Game.I.broadcast_toast("쿠르릉! 바위가 굴러가고 동굴이 열렸다!" if n >= 2 else "철곡괭이를 지렛대 삼아 바위를 밀어냈다!", "rumble")
			else:
				Game.I.toast_to(from, "끄응... 혼자서는 꿈쩍도 안 한다. 친구랑 동시에 E! (혼자라면 철곡괭이를 지렛대로)")
				Game.I.sfx_all("mine", pos)
		["door", "toggle"]:
			d.open = not d.get("open", false)
			_sync_data.rpc(id, d)
			Game.I.sfx_all("chest_open" if d.open else "chest_close", pos)
		["totem", "activate"]:
			Game.I.quests.try_adapt_ending(from)


func _refund_missing(from: int, action: String, arg: Variant) -> void:
	## 그새 부서진 설치물에 먼저 낸 아이템 돌려주기
	match action:
		"take", "plant":
			if arg is String and arg != "":
				Game.I.give_to(from, arg, 1)
		"feast":
			Game.I.give_to(from, "seaweed_feast", 1)
		"shell":
			Game.I.give_to(from, "golden_shell", 1)
		"give":
			if arg is Array and arg.size() == 3:
				Game.I.give_to(from, arg[1], arg[2])


func _contribute(id: int, from: int, arg: Array) -> void:
	## arg = [부품, 아이템, 개수]. 필요 이상은 돌려준다.
	var part: String = arg[0]
	var item: String = arg[1]
	var n: int = arg[2]
	var d: Dictionary = list[id].data
	if not SHIP_PARTS.has(part):
		Game.I.give_to(from, item, n)
		return
	var key := "cooked" if item in COOKED else item
	var need: int = SHIP_PARTS[part].need.get(key, 0)
	var have: int = d.parts[part].get(key, 0)
	var take := clampi(need - have, 0, n)
	if take < n:
		Game.I.give_to(from, item, n - take)
	if take <= 0:
		return
	d.parts[part][key] = have + take
	_sync_data.rpc(id, d)
	Game.I.sfx_all("craft", Vector3(list[id].cell))
	if part_done(id, part):
		Game.I.broadcast_toast("탈출선: [%s] 완성!" % SHIP_PARTS[part].name, "jingle_found")
		Game.I.quests.set_flag("ship_" + part)


func _ring_bell(id: int) -> void:
	var s: Dictionary = list[id]
	var idx: int = s.data.get("bell", 0)
	var now := Time.get_ticks_msec() / 1000.0
	_bell_fx.rpc(id)
	_bell_rung[idx] = now
	# 제단이 다 차 있는데 혼자 울렸으면 알려 준다
	get_tree().create_timer(2.2).timeout.connect(func():
		var q := Game.I.quests
		if _bell_rung.get(idx, -1.0) == now and q.flag("feast_offered") and q.count("shells_offered") >= 3 and not q.flag("ending_turtle"):
			Game.I.broadcast_toast("종소리가 홀로 울리다 사라졌다... 두 종을 동시에 울려야 할 것 같다", ""))
	# 태엽 종치기: 다른 종 옆에 있으면 0.4초 뒤 따라 울린다
	for other in list:
		if list[other].kind == "bell" and other != id:
			if _ringer_near(list[other].cell):
				get_tree().create_timer(0.4).timeout.connect(func():
					_bell_fx.rpc(other)
					_bell_rung[list[other].data.get("bell", 0)] = Time.get_ticks_msec() / 1000.0
					_check_bells())
	_check_bells()


func _ringer_near(c: Vector3i) -> bool:
	for id in list:
		if list[id].kind == "bell_ringer":
			var o: Vector3i = list[id].cell
			if absi(o.x - c.x) <= 2 and absi(o.z - c.z) <= 2 and absi(o.y - c.y) <= 1:
				return true
	return false


func _check_bells() -> void:
	if _bell_rung.size() < 2:
		return
	var a: float = _bell_rung.get(0, -100.0)
	var b: float = _bell_rung.get(1, -100.0)
	if absf(a - b) <= 2.0:
		_bell_rung.clear()
		Game.I.quests.on_bells_together()


@rpc("authority", "call_local", "reliable")
func _bell_fx(id: int) -> void:
	if not nodes.has(id):
		return
	var n: Node3D = nodes[id]
	var bell: Node3D = n.get_node_or_null("Model/Bell")
	if bell == null:
		for c in n.find_children("Bell", "", true, false):
			bell = c
	if bell:
		var tw := create_tween()
		tw.tween_property(bell, "rotation:z", 0.5, 0.15)
		tw.tween_property(bell, "rotation:z", -0.35, 0.3)
		tw.tween_property(bell, "rotation:z", 0.0, 0.4)
	Audio.play_at("bell", n.global_position + Vector3.UP * 2, 4.0)


# ── 상자 ──

@rpc("any_peer", "call_local", "reliable")
func req_chest(id: int, op: String, arg: Variant) -> void:
	if not multiplayer.is_server():
		return
	var from := multiplayer.get_remote_sender_id()
	if not list.has(id) or list[id].kind != "chest":
		# 상자가 그새 부서졌다: 넣으려던 건 돌려준다
		if op == "put" and arg is Dictionary:
			Game.I.give_to(from, arg.id, arg.n, arg.get("d", -1))
		return
	var items: Array = list[id].data.items
	match op:
		"open":
			if not viewers.has(id):
				viewers[id] = {}
			viewers[id][from] = true
			Game.I.sfx_all("chest_open", Vector3(list[id].cell))
		"close":
			if viewers.has(id):
				viewers[id].erase(from)
			return
		"put":
			# arg = {"id", "n", "d"} 손님은 이미 가방에서 뺐다
			var left := Inventory.add_to_slots(items, arg.id, arg.n, arg.get("d", -1))
			if left > 0:
				Game.I.give_to(from, arg.id, left, arg.get("d", -1))
				Game.I.toast_to(from, "상자가 가득 찼어")
		"take":
			var slot: int = arg
			if slot >= 0 and slot < items.size() and items[slot] != null:
				var it: Dictionary = items[slot]
				items[slot] = null
				Game.I.give_to(from, it.id, it.n, it.get("d", -1))
	for peer in viewers.get(id, {}):
		_chest_view.rpc_id(peer, id, items)


@rpc("authority", "call_local", "reliable")
func _chest_view(id: int, items: Array) -> void:
	if list.has(id):
		list[id].data.items = items
	if Game.I and Game.I.hud:
		Game.I.hud.on_chest_view(id, items)
