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

var list := {}          # id -> {"kind", "pos": Vector3, "rot": float(라디안), "data"}
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
			list[next_id] = {"kind": s.kind, "pos": s.pos, "rot": s.rot, "data": _init_data(s.kind, s.data.duplicate(true))}
			next_id += 1
	else:
		next_id = snap.next_id
		for id in snap.list:
			list[int(id)] = snap.list[id].duplicate(true)
			if list[int(id)].kind == "campfire":
				_init_data("campfire", list[int(id)].data)   # 불 이전 저장 파일 대비
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
		"campfire":
			data.lit = data.get("lit", false)
			data.fuel = data.get("fuel", 0.0)
			data.grill = data.get("grill", [])   # [[날것 id, 구운 시간], ...] 최대 3개
	return data


# ── 모양 ──

func _make_node(id: int) -> void:
	var s: Dictionary = list[id]
	var kind: String = s.kind
	var def: Dictionary = Items.STRUCTS.get(kind, {})
	var root := Node3D.new()
	root.name = "S%d" % id
	add_child(root)
	root.position = s.pos
	root.rotation.y = s.rot
	if kind == "temple" or kind == "cave_roof":
		_make_ruin(root, id, kind, s.data)
		nodes[id] = root
		_refresh(id)
		return
	if Build.is_part(kind):
		_make_part(root, id, kind)
		nodes[id] = root
		return
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
	elif kind == "float_log":
		sh.size = Vector3(0.4, 0.4, 2.6)   # 위에 올라설 수 있다
	elif kind == "big_rock":
		sh.size = Vector3(1.4, 2.6, 3.0)   # 굴 폭을 통째로 막는다
		model.scale = Vector3(1.0, 1.2, 1.7)
	cs.shape = sh
	cs.position.y = sh.size.y * 0.5
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
	if kind == "campfire":
		var grill := Node3D.new()
		grill.name = "Grill"
		grill.position.y = 0.35
		root.add_child(grill)
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


func _make_part(root: Node3D, id: int, kind: String) -> void:
	var model := Build.visual(kind)
	model.name = "Model"
	root.add_child(model)
	if kind == "foundation":
		root.add_child(Build.legs(list[id].pos, list[id].rot, Game.I.terrain))
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = 2
	body.collision_mask = 0
	body.set_meta("struct", id)
	for sh in Build.shapes(kind):
		var cs := CollisionShape3D.new()
		cs.shape = sh[0]
		cs.transform = sh[1]
		body.add_child(cs)
	root.add_child(body)


func _make_ruin(root: Node3D, id: int, kind: String, data: Dictionary) -> void:
	## 고대 신전 (문은 압력판으로 열린다) / 돌섬 동굴 지붕
	var stone := Vis.mat(Color("6f8f7a")) if kind == "temple" else Vis.mat(Color("7f7d78"))
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = 2
	body.collision_mask = 0
	body.set_meta("struct", id)
	root.add_child(body)
	var boxes: Array = []   # [크기, 위치]
	if kind == "temple":
		var w := 6.4
		var hh := 3.2
		var t := 0.5
		boxes.append([Vector3(w, hh, t), Vector3(0, hh * 0.5, -w * 0.5 + t * 0.5)])
		boxes.append([Vector3(t, hh, w), Vector3(-w * 0.5 + t * 0.5, hh * 0.5, 0)])
		boxes.append([Vector3(t, hh, w), Vector3(w * 0.5 - t * 0.5, hh * 0.5, 0)])
		var door_w := 1.8
		var side := (w - door_w) * 0.5
		boxes.append([Vector3(side, hh, t), Vector3(-w * 0.5 + side * 0.5, hh * 0.5, w * 0.5 - t * 0.5)])
		boxes.append([Vector3(side, hh, t), Vector3(w * 0.5 - side * 0.5, hh * 0.5, w * 0.5 - t * 0.5)])
		boxes.append([Vector3(door_w, hh - 2.3, t), Vector3(0, 2.3 + (hh - 2.3) * 0.5, w * 0.5 - t * 0.5)])
		boxes.append([Vector3(w + 0.8, 0.5, w + 0.8), Vector3(0, hh + 0.25, 0)])
		for cx in [-1, 1]:
			for cz in [-1, 1]:
				boxes.append([Vector3(0.8, hh + 1.0, 0.8), Vector3(cx * (w * 0.5 + 0.2), (hh + 1.0) * 0.5, cz * (w * 0.5 + 0.2))])
		# 문 (따로 열린다)
		var door := Node3D.new()
		door.name = "Door"
		root.add_child(door)
		var dm := Vis.mesh_node(_box_mesh(Vector3(door_w, 2.3, 0.35)), Vis.mat(Color("566e60")))
		dm.position = Vector3(0, 1.15, 0)
		door.add_child(dm)
		var glyph := Vis.box(Vector3(0.7, 0.7, 0.05), Color("c9e0a8"))
		glyph.position = Vector3(0, 1.3, 0.19)
		glyph.rotation.z = PI * 0.25
		door.add_child(glyph)
		door.position = Vector3(0, 0, w * 0.5 - t * 0.5)
		var db := StaticBody3D.new()
		db.name = "DoorBody"
		db.collision_layer = 2
		db.collision_mask = 0
		var dcs := CollisionShape3D.new()
		dcs.name = "Shape"
		var dsh := BoxShape3D.new()
		dsh.size = Vector3(door_w, 2.3, 0.4)
		dcs.shape = dsh
		dcs.position = Vector3(0, 1.15, 0)
		db.add_child(dcs)
		door.add_child(db)
	else:
		var ln: float = data.get("len", 10.0)
		boxes.append([Vector3(ln, 1.4, 4.2), Vector3(0, 3.0, 0)])
		boxes.append([Vector3(ln * 0.6, 1.0, 3.0), Vector3(-ln * 0.1, 4.0, 0.3)])
	for b in boxes:
		var mi := Vis.mesh_node(_box_mesh(b[0]), stone)
		mi.position = b[1]
		root.add_child(mi)
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = b[0]
		cs.shape = sh
		cs.position = b[1]
		body.add_child(cs)


func _box_mesh(size: Vector3) -> BoxMesh:
	var bm := BoxMesh.new()
	bm.size = size
	return bm


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
		"temple":
			var door: Node3D = n.get_node("Door")
			var open: bool = Game.I != null and Game.I.quests.flag("temple_open")
			door.visible = not open
			(door.get_node("DoorBody/Shape") as CollisionShape3D).disabled = open
		"campfire":
			var lit: bool = d.get("lit", false)
			n.get_node("Light").visible = lit
			(n.get_node("Fire") as CPUParticles3D).emitting = lit
			var grill: Node3D = n.get_node("Grill")
			for c in grill.get_children():
				c.queue_free()
			var i := 0
			for gi in d.get("grill", []):
				var t: float = gi[1]
				var col := Color("f08a7a") if t < Items.COOK_T else (Color("c77b36") if t < Items.BURN_T else Color("2a2420"))
				var b := Vis.box(Vector3(0.22, 0.07, 0.12), col)
				b.position = Vector3(-0.2 + i * 0.2, 0, 0)
				grill.add_child(b)
				i += 1
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


func near_any(pos: Vector3, radius: float, solid_only: bool = false, skip_parts: bool = false) -> int:
	## 가로 거리로 가장 가까운 설치물 (고대 신전·동굴 지붕·압력판·보물 자리는 빼고)
	var best := -1
	var bd := radius
	for id in list:
		var k: String = list[id].kind
		if k in ["temple", "cave_roof", "plate", "dig_spot"]:
			continue
		if skip_parts and Build.is_part(k):
			continue
		if solid_only and not Items.STRUCTS.get(k, {}).get("solid", false):
			continue
		var p: Vector3 = list[id].pos
		var d := Vector2(p.x - pos.x, p.z - pos.z).length()
		if d <= bd and absf(p.y - pos.y) < 2.0:
			bd = d
			best = id
	return best


func kind_of(id: int) -> String:
	return list.get(id, {}).get("kind", "")


func near(kind: String, pos: Vector3, radius: float) -> int:
	var best := -1
	var bd := radius
	for id in list:
		if list[id].kind != kind:
			continue
		var d := pos.distance_to(list[id].pos + Vector3.UP * 0.5)
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


func count_roofed(kind: String) -> int:
	var n := 0
	for id in list:
		if list[id].kind == kind and roofed(list[id].pos):
			n += 1
	return n


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
					var pos: Vector3 = s.pos
					_remove.rpc(id)
					Game.I.props.add_prop_server("palm", pos)
			"campfire":
				_tick_fire(id, s, d, dt, rain)
			"plate":
				var pressed := Game.I.player_on_spot(s.pos, 0.65) or _heavy_on(s.pos)
				if pressed != d.pressed:
					d.pressed = pressed
					_sync_data.rpc(id, d)
					if pressed:
						Game.I.sfx_all("click", s.pos)
					_check_plates()


func _tick_fire(id: int, s: Dictionary, d: Dictionary, dt: float, rain: bool) -> void:
	if not d.get("lit", false):
		return
	var changed := false
	var wet := rain and not roofed(s.pos)
	d.fuel = maxf(0.0, d.fuel - dt * (2.0 if wet else 1.0))   # 비 맞으면 장작이 두 배로 빨리 준다
	for gi in d.grill:
		var before: float = gi[1]
		gi[1] = before + dt
		if (before < Items.COOK_T and gi[1] >= Items.COOK_T) or (before < Items.BURN_T and gi[1] >= Items.BURN_T):
			changed = true
			Game.I.sfx_all("fish_bite" if gi[1] < Items.BURN_T else "error", s.pos)
	if d.fuel <= 0.0:
		d.lit = false
		changed = true
		Game.I.sfx_all("splash", s.pos)
	d.sync_t = d.get("sync_t", 0.0) + dt
	if changed or d.sync_t >= 5.0:
		d.sync_t = 0.0
		_sync_data.rpc(id, d)


func roofed(pos: Vector3) -> bool:
	## 위에 지붕이 있나 (모닥불이 비 맞는지, 침대가 집 안인지)
	var from := pos + Vector3.UP * 1.0
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.UP * 8.0, 1 | 2)
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func is_lit(id: int) -> bool:
	return list.has(id) and list[id].data.get("lit", false)


func _heavy_on(pos: Vector3) -> bool:
	## 압력판 위의 무거운 것: 설치물이나, 물건 5개 이상 든 꾸러미
	if near_any(pos, 0.75) >= 0:
		return true
	for pid in Game.I.ents.pickups:
		var e: Dictionary = Game.I.ents.pickups[pid]
		var p: Vector3 = e.pos
		if Vector2(p.x - pos.x, p.z - pos.z).length() < 0.6:
			var n := 0
			for it in e.items:
				n += it[1]
			if n >= 5:
				return true
	return false


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
		Game.I.quests.set_flag("temple_open")
		_open_temple.rpc()
		Game.I.broadcast_toast("쿠구구궁... 신전의 문이 열렸다!", "rumble")


# ── 네트워크: 설치 / 제거 ──

@rpc("authority", "call_local", "reliable")
func _open_temple() -> void:
	refresh_all("temple")
	for id in list:
		if list[id].kind == "temple" and nodes.has(id):
			Audio.play_at("rumble", nodes[id].global_position, 4.0)
			Game.I.shake_camera(0.4, nodes[id].global_position)


@rpc("any_peer", "call_local", "reliable")
func req_place(kind: String, pos: Vector3, rot: float, item_id: String) -> void:
	if not multiplayer.is_server():
		return
	var from := multiplayer.get_remote_sender_id()
	var reason := part_problem(kind, pos, rot) if Build.is_part(kind) else placement_problem(kind, pos)
	if reason != "":
		Game.I.toast_to(from, reason)
		Game.I.give_to(from, item_id, 1)
		return
	var id := next_id
	next_id += 1
	_add.rpc(id, kind, pos, rot, _init_data(kind, {}))
	Game.I.quests.on_struct_placed(kind)


func placement_problem(kind: String, pos: Vector3) -> String:
	## 여기 놓을 수 있나? 문제가 있으면 이유를 돌려준다 (손님 미리보기에도 쓴다)
	var def: Dictionary = Items.STRUCTS.get(kind, {})
	var t := Game.I.terrain
	var ground := t.height_at(pos.x, pos.z)
	if def.is_empty() or def.get("world", false):
		return "설치할 수 없는 물건"
	if kind == "float_log":
		return _log_problem(pos)
	if kind == "door" and _part_at("doorway", pos) >= 0:
		return "이미 문이 달려 있어" if near("door", pos + Vector3.UP * 0.5, 0.3) >= 0 else ""
	var on_deck := absf(pos.y - deck_top(pos)) <= 0.2   # 기초·바닥 위
	if not on_deck:
		if absf(pos.y - ground) > 0.35:
			return "땅 위에 놓아야 해"
		if ground < Terrain.WATER_Y - 0.05:
			return "물속엔 못 놓는다"
		if t.slope_at(pos.x, pos.z) > 0.35:
			return "너무 비탈져서 못 놓는다"
	if near_any(pos, 0.85, false, true) >= 0 or Game.I.props.near_alive(pos, 0.8) >= 0:
		return "자리가 없어!"
	if def.has("on") and (on_deck or not (Terrain.MAT_KEYS[t.material_at(pos.x, pos.z)] in def.on)):
		return "여기엔 못 심어 (모래/흙/풀밭 위에)" if kind == "sapling" else "흙이나 풀밭 위에 놓아야 해"
	if def.get("water", false) and not _next_to_water(pos):
		return "물가에 놓아야 해"
	if def.get("solid", false) and Game.I.player_on_spot(pos, 0.6):
		return "누가 서 있어!"
	return ""


# ── 통나무 뗏목 ──

const LOG_GAP := 0.42   # 나란히 띄운 통나무 간격 (뗏목 모양과 같게)


func _log_problem(pos: Vector3) -> String:
	var t := Game.I.terrain
	if t.height_at(pos.x, pos.z) > Terrain.WATER_Y - 0.3:
		return "물 위에 띄워야 해"
	for id in list:
		if list[id].kind == "float_log" and (list[id].pos as Vector3).distance_to(pos) < 0.35:
			return "이미 통나무가 있어"
	return ""


func log_snap(aim: Vector3, want_rot: float) -> Dictionary:
	## 근처 통나무 옆에 나란히 (없으면 조준점에 바로)
	var best := {}
	var bd := 0.8
	for id in list:
		var s: Dictionary = list[id]
		if s.kind != "float_log":
			continue
		var b := Basis(Vector3.UP, s.rot)
		for side in [-1.0, 1.0]:
			var c: Vector3 = s.pos + b * Vector3(side * LOG_GAP, 0, 0)
			var dd := Vector2(c.x - aim.x, c.z - aim.z).length()
			if dd < bd:
				bd = dd
				best = {"pos": c, "rot": s.rot}
	if best.is_empty():
		return {"pos": Vector3(aim.x, Terrain.WATER_Y - 0.25, aim.z), "rot": want_rot}
	return best


func log_group(id: int) -> Array:
	## 서로 붙어 있는 통나무 묶음
	var out: Array = [id]
	var i := 0
	while i < out.size():
		var p: Vector3 = list[out[i]].pos
		for oid in list:
			if list[oid].kind == "float_log" and not (oid in out) and (list[oid].pos as Vector3).distance_to(p) <= LOG_GAP + 0.1:
				out.append(oid)
		i += 1
	return out


func log_ropes_needed(n: int) -> int:
	return int(ceil(n / 2.0))


func log_ropes_have(group: Array) -> int:
	var have := 0
	for lid in group:
		have += list[lid].data.get("ropes", 0)
	return have


# ── 건축 부품 ──

func part_problem(kind: String, pos: Vector3, rot: float) -> String:
	## 부품을 여기 붙일 수 있나? (호스트 판정, 손님 미리보기에도 쓴다)
	var t := Game.I.terrain
	var slot: String = Build.PARTS[kind]
	for id in list:
		if Build.PARTS.get(list[id].kind, "") == slot and (list[id].pos as Vector3).distance_to(pos) < 0.3:
			return "이미 있어!"
	var on_ground := absf(pos.y - t.height_at(pos.x, pos.z)) < 0.3 and not t.is_water(pos.x, pos.z)
	if kind in Build.DECKS:
		for id in list:
			var q: Vector3 = list[id].pos
			if list[id].kind in Build.DECKS and absf(q.y - pos.y) < 0.5 and Vector2(q.x - pos.x, q.z - pos.z).length() < Build.G - 0.15:
				return "다른 바닥이랑 겹쳐"
	match kind:
		"foundation":
			var gr := Build.ground_range(pos, rot, t)
			if pos.y < gr.y + 0.05:
				return "땅에 파묻힌다. 삽으로 땅을 고르거나 다른 데 붙여 봐"
			if pos.y - gr.x > Build.LEG_MAX:
				return "너무 깊어서 다리가 안 닿아"
			if near_any(pos, 1.3, false, true) >= 0 or Game.I.props.near_alive(pos, 1.2) >= 0:
				return "자리가 없어!"
		"pillar", "stairs":
			if not on_ground and not _part_supported(kind, pos):
				return "땅이나 바닥 위에 놓아야 해"
		_:
			if not _part_supported(kind, pos):
				return "기초나 바닥 가장자리에 붙여야 해" if kind in Build.WALLS else "받쳐 줄 벽이나 기둥이 없어"
	if _player_in_part(kind, pos, rot):
		return "누가 서 있어!"
	return ""


func _part_supported(kind: String, pos: Vector3) -> bool:
	## 붙어 있을 부품이 있나 (자리 계산과 같은 규칙, 오차 0.15)
	var G := Build.G
	var H := Build.H
	for id in list:
		var k: String = list[id].kind
		if not Build.is_part(k):
			continue
		var p: Vector3 = list[id].pos
		var hd := Vector2(p.x - pos.x, p.z - pos.z).length()
		var same := absf(p.y - pos.y) < 0.05
		var below_top := absf(p.y + H - pos.y) < 0.05   # 그 부품 꼭대기가 내 바닥
		match kind:
			"floor":
				if k in Build.DECKS and same and absf(hd - G) < 0.15: return true
				if k in Build.WALLS and below_top and absf(hd - G * 0.5) < 0.15: return true
				if k == "pillar" and below_top and absf(hd - G * 0.7071) < 0.15: return true
			"roof":
				if k in Build.WALLS and below_top and absf(hd - G * 0.5) < 0.15: return true
				if k == "pillar" and below_top and absf(hd - G * 0.7071) < 0.15: return true
				if k == "roof" and same and absf(hd - G) < 0.15: return true
			"wall", "window_wall", "doorway":
				if k in Build.DECKS and same and absf(hd - G * 0.5) < 0.15: return true
				if k in Build.WALLS and below_top and hd < 0.15: return true
			"pillar":
				if k in Build.DECKS and same and absf(hd - G * 0.7071) < 0.15: return true
				if k == "pillar" and below_top and hd < 0.15: return true
			"stairs":
				if k in Build.DECKS and same and hd < 0.15: return true
	return false


func _player_in_part(kind: String, pos: Vector3, rot: float) -> bool:
	var box := Build.bounds(kind)
	if box.size == Vector3.ZERO:
		return false
	var inv := Basis(Vector3.UP, rot).inverse()
	for pid in Game.I.players:
		var lp: Vector3 = inv * (Game.I.players[pid].global_position - pos)
		if AABB(lp + Vector3(-0.3, 0.05, -0.3), Vector3(0.6, 1.7, 0.6)).intersects(box):
			return true
	return false


func _part_at(kind: String, pos: Vector3) -> int:
	for id in list:
		if list[id].kind == kind and (list[id].pos as Vector3).distance_to(pos) < 0.1:
			return id
	return -1


func deck_top(pos: Vector3) -> float:
	## pos 가 기초·바닥 위면 그 윗면 높이, 아니면 -INF
	for id in list:
		var s: Dictionary = list[id]
		if not (s.kind in Build.DECKS):
			continue
		var p: Vector3 = s.pos
		if absf(p.y - pos.y) > 0.5:
			continue
		var lp: Vector3 = Basis(Vector3.UP, s.rot).inverse() * (pos - p)
		if absf(lp.x) <= Build.G * 0.5 and absf(lp.z) <= Build.G * 0.5:
			return p.y
	return -INF


func parts_near(pos: Vector3, r: float) -> Array:
	var out: Array = []
	for id in list:
		var s: Dictionary = list[id]
		if Build.is_part(s.kind) and (s.pos as Vector3).distance_to(pos) <= r:
			out.append(s)
	return out


func water_area() -> int:
	## 물 위에 깐 기초 넓이 (섬 넓히기에 친다)
	var n := 0
	for id in list:
		var s: Dictionary = list[id]
		if s.kind == "foundation" and Game.I.terrain.is_water(s.pos.x, s.pos.z):
			n += int(Build.G * Build.G)
	return n


func _next_to_water(pos: Vector3) -> bool:
	for i in 8:
		var a := i * TAU / 8.0
		if Game.I.terrain.is_water(pos.x + cos(a) * 1.6, pos.z + sin(a) * 1.6):
			return true
	return false


@rpc("authority", "call_local", "reliable")
func _add(id: int, kind: String, pos: Vector3, rot: float, data: Dictionary) -> void:
	list[id] = {"kind": kind, "pos": pos, "rot": rot, "data": data}
	next_id = maxi(next_id, id + 1)
	_make_node(id)
	var n: Node3D = nodes[id]
	Audio.play_at("craft", n.global_position)
	if Build.is_part(kind):
		Game.I.fx_break(n.global_position + Vector3.UP * 0.3, Build.WOOD, 6)   # 부품은 찌그러뜨리면 물리 엔진이 싫어한다
		return
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
	var pos: Vector3 = s.pos + Vector3.UP * 0.5
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
	var pos: Vector3 = s.pos + Vector3.UP * 0.5
	match [s.kind, action]:
		["rain_collector", "take"]:
			var cup: String = arg if arg is String and arg != "" else "bottle"
			if d.stored > 0:
				d.stored -= 1
				Game.I.give_to(from, "shell_water" if cup == "coconut_shell" else "fresh_water", 1)
				_sync_data.rpc(id, d)
			else:
				Game.I.give_to(from, cup, 1)
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
			Game.I.set_spawn_for(from, s.pos + Vector3.UP * 0.3)
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
		["campfire", "fuel"]:
			if d.fuel >= Items.FUEL_MAX:
				Game.I.give_to(from, arg, 1)
				Game.I.toast_to(from, "장작이 꽉 찼어")
				return
			d.fuel = minf(Items.FUEL_MAX, d.fuel + Items.FUEL.get(arg, 0.0))
			_sync_data.rpc(id, d)
			Game.I.sfx_all("chop", pos)
		["campfire", "light"]:
			if d.lit:
				return
			if d.fuel <= 0.0:
				Game.I.toast_to(from, "장작부터 넣어야 해 (나무/막대/야자잎을 들고 E)")
				return
			if Game.I.clock.raining and not roofed(s.pos):
				Game.I.toast_to(from, "비 때문에 불이 안 붙는다... 지붕 밑에 피우자")
				return
			d.lit = true
			_sync_data.rpc(id, d)
			Game.I.sfx_all("levelup", pos)
			Game.I.toast_to(from, "불이 붙었다!! 장작이 떨어지지 않게 조심")
			Game.I.quests.set_flag("first_fire")
		["campfire", "grill"]:
			if not d.lit or d.grill.size() >= 3:
				Game.I.give_to(from, arg, 1)
				Game.I.toast_to(from, "불이 꺼져 있어" if not d.lit else "석쇠가 꽉 찼어 (3개)")
				return
			d.grill.append([arg, 0.0])
			_sync_data.rpc(id, d)
			Game.I.sfx_all("splash", pos)
		["campfire", "take_grill"]:
			if d.grill.is_empty():
				return
			# 제일 오래 구운 것부터
			var best := 0
			for i in d.grill.size():
				if d.grill[i][1] > d.grill[best][1]:
					best = i
			var gi: Array = d.grill[best]
			d.grill.remove_at(best)
			var t: float = gi[1]
			var out: String = gi[0] if t < Items.COOK_T else (Items.GRILL.get(gi[0], gi[0]) if t < Items.BURN_T else "burnt_food")
			Game.I.give_to(from, out, 1)
			if t < Items.COOK_T:
				Game.I.toast_to(from, "아직 덜 익었다 (%d/%d초)" % [int(t), int(Items.COOK_T)])
			_sync_data.rpc(id, d)
		["float_log", "tie"]:
			var group := log_group(id)
			var need := log_ropes_needed(group.size())
			if group.size() < 4:
				Game.I.give_to(from, "rope", 1)
				Game.I.toast_to(from, "통나무가 %d개뿐이다. 4개 이상 나란히 띄워야 뗏목이 된다" % group.size())
				return
			d.ropes = d.get("ropes", 0) + 1
			var have := log_ropes_have(group)
			Game.I.sfx_all("chop", pos)
			if have < need:
				_sync_data.rpc(id, d)
				Game.I.toast_to(from, "통나무를 묶는 중... 밧줄 %d/%d" % [have, need])
				return
			# 다 묶었다: 통나무들이 뗏목이 된다
			var c := Vector3.ZERO
			for lid in group:
				c += list[lid].pos
			c /= group.size()
			var yaw: float = s.rot
			for lid in group:
				_remove.rpc(lid)
			Game.I.ents.spawn_raft(Vector3(c.x, Terrain.WATER_Y, c.z), yaw)
			Game.I.broadcast_toast("%s 통나무를 묶어 뗏목을 만들었다!" % Items.josa(Net.player_name(from), "이", "가"), "levelup")
		["farm_plot", "fertilize"]:
			if d.crop == "" or d.grow >= 1.0:
				Game.I.give_to(from, "rotten_food", 1)
				return
			d.grow = minf(1.0, d.grow + 0.35)
			_sync_data.rpc(id, d)
			Game.I.sfx_all("leaves", pos)
		["door", "toggle"]:
			d.open = not d.get("open", false)
			_sync_data.rpc(id, d)
			Game.I.sfx_all("chest_open" if d.open else "chest_close", pos)
		["totem", "activate"]:
			Game.I.quests.try_adapt_ending(from)


func _refund_missing(from: int, action: String, arg: Variant) -> void:
	## 그새 부서진 설치물에 먼저 낸 아이템 돌려주기
	match action:
		"take", "plant", "fuel", "grill":
			if arg is String and arg != "":
				Game.I.give_to(from, arg, 1)
		"fertilize":
			Game.I.give_to(from, "rotten_food", 1)
		"tie":
			Game.I.give_to(from, "rope", 1)
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
	Game.I.sfx_all("craft", list[id].pos)
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
			if _ringer_near(list[other].pos):
				get_tree().create_timer(0.4).timeout.connect(func():
					_bell_fx.rpc(other)
					_bell_rung[list[other].data.get("bell", 0)] = Time.get_ticks_msec() / 1000.0
					_check_bells())
	_check_bells()


func _ringer_near(c: Vector3) -> bool:
	for id in list:
		if list[id].kind == "bell_ringer" and (list[id].pos as Vector3).distance_to(c) <= 2.6:
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
			Game.I.sfx_all("chest_open", list[id].pos)
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
