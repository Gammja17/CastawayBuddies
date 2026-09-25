extends Node
## 모양 공장. Kenney 모델을 불러오거나, 없는 건 상자·원기둥으로 허접하게 만든다.
## 블록 재질(16x16 노이즈 텍스처)도 여기서 만든다.

const MODEL_DIR := "res://assets/models/"

var _scene_cache := {}
var _mat_cache := {}
var _block_mats := {}
var _aabb_cache := {}
var _font: Font


func font() -> Font:
	if _font == null:
		_font = load("res://assets/fonts/Jua-Regular.ttf")
	return _font


func model(path: String) -> Node3D:
	## "survival/tree" -> 인스턴스. 없으면 분홍 상자.
	if not _scene_cache.has(path):
		var full := MODEL_DIR + path + ".glb"
		_scene_cache[path] = load(full) if ResourceLoader.exists(full) else null
	var ps: PackedScene = _scene_cache[path]
	if ps == null:
		push_warning("모델 없음: " + path)
		return box(Vector3(0.5, 0.5, 0.5), Color.HOT_PINK)
	return ps.instantiate()


func make(vis) -> Node3D:
	if vis is String:
		if vis.begins_with("m:"):
			return model(vis.substr(2))
		return box(Vector3(0.3, 0.3, 0.3), Color.MAGENTA)
	var d: Dictionary = vis
	var c := Color(d.get("c", "ffffff")) if d.get("c", "") is String else Color.WHITE
	var sz := Vector3.ONE * 0.3
	if d.has("sz"):
		sz = Vector3(d.sz[0], d.sz[1], d.sz[2])
	var n: Node3D
	match d.get("s", "box"):
		"box": n = box(sz, c)
		"cyl": n = mesh_node(_cyl(sz.x * 0.5, sz.y, 8), mat(c))
		"sphere": n = mesh_node(_sphere(sz), mat(c))
		"cone": n = mesh_node(_cone(sz.x * 0.5, sz.y), mat(c))
		"torus":
			var t := TorusMesh.new()
			t.inner_radius = sz.x * 0.25
			t.outer_radius = sz.x * 0.5
			t.rings = 10
			t.ring_segments = 6
			n = mesh_node(t, mat(c))
		"prism":
			var p := PrismMesh.new()
			p.size = sz
			n = mesh_node(p, mat(c))
		"block": n = block_node(Items.block_index.get(d.b, 0), 0.4)
		"spear": n = _spear(c, Color(d.get("tip", "3d3f46")))
		"rod": n = _rod(c)
		"hook": n = _hook(c)
		"torch": n = torch_node()
		"sapling": n = _sapling()
		"furnace": n = _furnace()
		"trap": n = _trap()
		"totem": n = _totem()
		"bell": n = _bell()
		"xmark": n = _xmark()
		"door": n = _door()
		"raft": n = raft_node()
		_: n = box(sz, c)
	if d.has("rot"):
		n.rotation_degrees = Vector3(d.rot[0], d.rot[1], d.rot[2])
	if d.get("glow", false):
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			var m: StandardMaterial3D = mat(c).duplicate()
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = 0.8
			mi.material_override = m
	var wrap := Node3D.new()
	wrap.add_child(n)
	return wrap


func item_node(id: String, size: float = 0.4) -> Node3D:
	## 손에 들거나 바닥에 떨어진 아이템 모양. 가장 긴 변이 size 가 되게 맞춘다.
	var vis = Items.item(id).get("vis", {"s": "box", "c": "ff00ff"})
	var n := make(vis)
	var ab := aabb_of(n)
	var longest := maxf(ab.size.x, maxf(ab.size.y, ab.size.z))
	var holder := Node3D.new()
	holder.add_child(n)
	if longest > 0.001:
		var s := size / longest
		n.scale *= s
		n.position = -ab.get_center() * s
	return holder


func aabb_of(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if m.mesh == null:
			continue
		var xf := _rel_xform(root, m)
		var ab: AABB = xf * m.mesh.get_aabb()
		if first:
			out = ab
			first = false
		else:
			out = out.merge(ab)
	return out


func _rel_xform(root: Node3D, n: Node3D) -> Transform3D:
	# root 자신의 변환은 빼고, root 좌표계 기준으로
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


func fit_model(path: String, height: float) -> Node3D:
	## 모델을 높이 height 에 맞춰 바닥 중앙 기준으로 놓는다.
	var n := model(path)
	var ab: AABB
	if _aabb_cache.has(path):
		ab = _aabb_cache[path]
	else:
		ab = aabb_of(n)
		_aabb_cache[path] = ab
	var holder := Node3D.new()
	holder.add_child(n)
	if ab.size.y > 0.001:
		var s := height / ab.size.y
		n.scale = Vector3.ONE * s
		n.position = Vector3(-ab.get_center().x * s, -ab.position.y * s, -ab.get_center().z * s)
	return holder


# ── 재질 ──

func mat(c: Color, unshaded: bool = false) -> StandardMaterial3D:
	var key := "%s|%s" % [c.to_html(), unshaded]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.95
	if c.a < 0.99:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_cache[key] = m
	return m


func block_material(idx: int) -> StandardMaterial3D:
	if _block_mats.has(idx):
		return _block_mats[idx]
	var b: Dictionary = Items.block(idx)
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(_block_image(b.id, b.color))
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.roughness = 1.0
	if b.color.a < 0.99:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# BoxMesh 는 3x2 로 UV 를 나누니, 한 면에 텍스처 한 장이 가득 차도록 uv1 을 맞춘다
	m.uv1_scale = Vector3(3, 2, 1)
	_block_mats[idx] = m
	return m


func _block_image(id: String, base: Color) -> Image:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	for y in 16:
		for x in 16:
			var c := base
			var j := rng.randf_range(-0.07, 0.07)
			c = Color(c.r + j, c.g + j, c.b + j, c.a)
			match id:
				"plank_block":
					if y % 4 == 0: c = base.darkened(0.3)
					elif (x + (y / 4) * 5) % 16 == 0: c = base.darkened(0.25)
				"stone_block", "brick_block":
					var row := y / 4
					var off := 4 if row % 2 == 1 else 0
					if y % 4 == 0 or (x + off) % 8 == 0:
						c = Color("d8cfc0") if id == "brick_block" else base.darkened(0.35)
				"grass":
					if rng.randf() < 0.18: c = base.lightened(0.18)
					if y < 1 and rng.randf() < 0.4: c = base.darkened(0.2)
				"sand":
					if rng.randf() < 0.1: c = base.darkened(0.12)
				"glass_block":
					if x == 0 or y == 0 or x == 15 or y == 15:
						c = Color(1, 1, 1, 0.85)
					elif x == y and x > 3 and x < 8:
						c = Color(1, 1, 1, 0.6)
				"thatch_block":
					if (x + y) % 3 == 0: c = base.darkened(0.25)
				"ancient":
					if x == 0 or y == 0 or x == 15 or y == 15: c = base.darkened(0.35)
					elif rng.randf() < 0.15: c = Color("4e7a44")
					if (x == 7 or x == 8) and y > 4 and y < 12: c = Color("c9e0a8")
					if (y == 7 or y == 8) and x > 4 and x < 12: c = Color("c9e0a8")
				"iron_ore":
					c = Color("8d8d93")
					c = Color(c.r + j, c.g + j, c.b + j)
					if rng.randf() < 0.16: c = Color("d08a4e")
				"stone":
					if rng.randf() < 0.12: c = base.darkened(0.2)
				"leaf_block":
					if rng.randf() < 0.25: c = base.darkened(0.25)
				"log_block":
					if x % 4 == 0: c = base.darkened(0.3)
					elif rng.randf() < 0.1: c = base.lightened(0.15)
				"sandstone":
					if y % 5 == 0: c = base.darkened(0.15)
					elif y % 5 == 1: c = base.lightened(0.08)
			img.set_pixel(x, y, c)
	return img


# ── 도형 ──

func mesh_node(m: Mesh, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = material
	return mi


func box(sz: Vector3, c: Color) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = sz
	return mesh_node(b, mat(c))


func block_node(idx: int, size: float = 1.0) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = Vector3.ONE * size
	return mesh_node(b, block_material(idx))


func _cyl(r: float, h: float, seg: int) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


func _cone(r: float, h: float) -> CylinderMesh:
	var c := _cyl(r, h, 8)
	c.top_radius = 0.0
	return c


func _sphere(sz: Vector3) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = sz.x * 0.5
	s.height = sz.y
	s.radial_segments = 8
	s.rings = 5
	return s


func _add(parent: Node3D, child: Node3D, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> Node3D:
	parent.add_child(child)
	child.position = pos
	child.rotation_degrees = rot
	return child


func _spear(shaft: Color, tip: Color) -> Node3D:
	var n := Node3D.new()
	_add(n, mesh_node(_cyl(0.025, 1.2, 6), mat(shaft)), Vector3(0, 0.6, 0))
	_add(n, mesh_node(_cone(0.06, 0.22), mat(tip)), Vector3(0, 1.31, 0))
	return n


func _rod(c: Color) -> Node3D:
	var n := Node3D.new()
	_add(n, mesh_node(_cyl(0.02, 1.3, 6), mat(c)), Vector3(0, 0.65, 0), Vector3(0, 0, -8))
	_add(n, box(Vector3(0.06, 0.06, 0.06), Color("dddddd")), Vector3(0.05, 0.25, 0.03))
	return n


func _hook(c: Color) -> Node3D:
	var n := Node3D.new()
	_add(n, mesh_node(_cyl(0.025, 0.9, 6), mat(c)), Vector3(0, 0.45, 0))
	_add(n, box(Vector3(0.22, 0.04, 0.04), Color("5a5a60")), Vector3(0.09, 0.9, 0))
	_add(n, box(Vector3(0.04, 0.14, 0.04), Color("5a5a60")), Vector3(0.19, 0.85, 0))
	return n


func torch_node() -> Node3D:
	var n := Node3D.new()
	_add(n, mesh_node(_cyl(0.035, 0.7, 6), mat(Color("7a5230"))), Vector3(0, 0.35, 0))
	_add(n, box(Vector3(0.1, 0.1, 0.1), Color("4caf3f")), Vector3(0, 0.72, 0))
	var flame := MeshInstance3D.new()
	flame.mesh = _cone(0.07, 0.2)
	flame.material_override = mat(Color("ffb13b"), true)
	_add(n, flame, Vector3(0, 0.86, 0))
	flame.name = "Flame"
	return n


func _sapling() -> Node3D:
	var n := Node3D.new()
	_add(n, mesh_node(_cyl(0.03, 0.35, 5), mat(Color("8a6a3a"))), Vector3(0, 0.17, 0))
	for i in 3:
		_add(n, box(Vector3(0.28, 0.03, 0.1), Color("5fbf4a")), Vector3(0, 0.36, 0), Vector3(0, i * 60, 20))
	_add(n, mesh_node(_sphere(Vector3(0.18, 0.18, 0.18)), mat(Color("6b4423"))), Vector3(0, 0.05, 0))
	return n


func _furnace() -> Node3D:
	var n := Node3D.new()
	_add(n, box(Vector3(0.9, 0.8, 0.9), Color("77777d")), Vector3(0, 0.4, 0))
	_add(n, box(Vector3(0.5, 0.3, 0.05), Color("ff8a2a")), Vector3(0, 0.3, 0.45))
	_add(n, box(Vector3(0.3, 0.4, 0.3), Color("5d5d63")), Vector3(0, 1.0, 0))
	(n.get_child(1) as MeshInstance3D).material_override = mat(Color("ff8a2a"), true)
	return n


func _trap() -> Node3D:
	var n := Node3D.new()
	for i in 4:
		_add(n, mesh_node(_cyl(0.02, 0.6, 4), mat(Color("9b6a3a"))), Vector3(0, 0.3, 0), Vector3(0, i * 45, 70))
	_add(n, mesh_node(_cyl(0.3, 0.05, 8), mat(Color("c7a86b"))), Vector3(0, 0.05, 0))
	return n


func _totem() -> Node3D:
	var n := Node3D.new()
	var cols := [Color("b5553c"), Color("ffcf4a"), Color("4fc3f7"), Color("7ddc6a")]
	for i in 4:
		_add(n, box(Vector3(0.7, 0.6, 0.7), cols[i]), Vector3(0, 0.3 + i * 0.62, 0))
		_add(n, box(Vector3(0.12, 0.12, 0.05), Color.BLACK), Vector3(-0.15, 0.4 + i * 0.62, 0.36))
		_add(n, box(Vector3(0.12, 0.12, 0.05), Color.BLACK), Vector3(0.15, 0.4 + i * 0.62, 0.36))
		_add(n, box(Vector3(0.35, 0.07, 0.05), Color("3a1a0a")), Vector3(0, 0.2 + i * 0.62, 0.36))
	_add(n, box(Vector3(1.6, 0.12, 0.2), Color("ffcf4a")), Vector3(0, 2.3, 0))
	_add(n, mesh_node(_cone(0.3, 0.4), mat(Color("ffd23f"))), Vector3(0, 2.8, 0))
	return n


func _bell() -> Node3D:
	var n := Node3D.new()
	var bronze := mat(Color("b8863b"))
	_add(n, mesh_node(_cyl(0.08, 2.4, 6), mat(Color("6f8f7a"))), Vector3(-0.8, 1.2, 0))
	_add(n, mesh_node(_cyl(0.08, 2.4, 6), mat(Color("6f8f7a"))), Vector3(0.8, 1.2, 0))
	_add(n, box(Vector3(1.9, 0.18, 0.25), Color("6f8f7a")), Vector3(0, 2.4, 0))
	var bell := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.22
	cm.bottom_radius = 0.5
	cm.height = 0.8
	cm.radial_segments = 10
	bell.mesh = cm
	bell.material_override = bronze
	bell.name = "Bell"
	_add(n, bell, Vector3(0, 1.85, 0))
	return n


func hat_node(id: String) -> Node3D:
	## 머리 위 (0,0) 기준 모자. 밀짚모자와 맨머리는 player.tscn 에 이미 있다
	var n := Node3D.new()
	match id:
		"captain":
			_add(n, mesh_node(_cyl(0.3, 0.05, 10), mat(Color("1d2233"))), Vector3(0, 0.03, -0.04))
			_add(n, mesh_node(_cyl(0.24, 0.2, 10), mat(Color("24304f"))), Vector3(0, 0.14, 0))
			_add(n, mesh_node(_cyl(0.245, 0.04, 10), mat(Color("f2f2f2"))), Vector3(0, 0.25, 0))
			_add(n, box(Vector3(0.1, 0.07, 0.02), Color("ffd23f")), Vector3(0, 0.15, -0.245))
		"flower":
			var cols := [Color("ff6b9a"), Color("ffe066"), Color("ffffff"), Color("8fd3ff"), Color("ff9f43")]
			for i in 10:
				var a := i * TAU / 10.0
				var f := mesh_node(_sphere(Vector3(0.1, 0.08, 0.1)), mat(cols[i % cols.size()]))
				_add(n, f, Vector3(cos(a) * 0.22, 0.03, sin(a) * 0.22))
			for i in 10:
				var a2 := (i + 0.5) * TAU / 10.0
				_add(n, box(Vector3(0.08, 0.02, 0.05), Color("4caf3f")), Vector3(cos(a2) * 0.22, 0.02, sin(a2) * 0.22), Vector3(0, -rad_to_deg(a2), 0))
		"turtle":
			var shell := mesh_node(_sphere(Vector3(0.56, 0.36, 0.56)), mat(Color("4f8f4a")))
			_add(n, shell, Vector3(0, 0.02, 0))
			for i in 6:
				var a3 := i * TAU / 6.0
				_add(n, box(Vector3(0.09, 0.03, 0.09), Color("c9b458")), Vector3(cos(a3) * 0.16, 0.14, sin(a3) * 0.16))
			_add(n, box(Vector3(0.1, 0.03, 0.1), Color("c9b458")), Vector3(0, 0.19, 0))
		"crab":
			var body := mesh_node(_sphere(Vector3(0.36, 0.18, 0.3)), mat(Color("e8603c")))
			_add(n, body, Vector3(0, 0.1, 0))
			for side in [-1, 1]:
				_add(n, box(Vector3(0.1, 0.08, 0.14), Color("f07050")), Vector3(side * 0.2, 0.12, -0.16))
				_add(n, mesh_node(_sphere(Vector3(0.06, 0.06, 0.06)), mat(Color.WHITE)), Vector3(side * 0.06, 0.22, -0.1))
			for i in 5:
				_add(n, mesh_node(_cone(0.03, 0.09), mat(Color("ffd23f"))), Vector3(cos(i * TAU / 5) * 0.08, 0.24, sin(i * TAU / 5) * 0.08))
	return n


func raft_node() -> Node3D:
	## 뗏목: 통나무 다섯 개 + 가로대 + 작은 돛
	var n := Node3D.new()
	var wood := Color("9b6a3a")
	for i in 5:
		var lg := mesh_node(_cyl(0.2, 2.6, 7), mat(wood.lightened(0.06 * (i % 2))))
		lg.rotation.x = PI * 0.5
		lg.position = Vector3(-0.84 + i * 0.42, 0.0, 0)
		n.add_child(lg)
	for z in [-0.9, 0.9]:
		_add(n, box(Vector3(2.2, 0.08, 0.16), Color("c7a86b")), Vector3(0, 0.2, z))
	_add(n, mesh_node(_cyl(0.05, 1.8, 6), mat(Color("7a5230"))), Vector3(0, 1.1, -0.6))
	var sail := box(Vector3(1.0, 0.9, 0.03), Color("efe8d8"))
	_add(n, sail, Vector3(0.0, 1.35, -0.62))
	return n


func _door() -> Node3D:
	var n := Node3D.new()
	var wood := Color("b0804a")
	_add(n, box(Vector3(0.9, 1.95, 0.1), wood), Vector3(0, 0.975, 0))
	for y in [0.35, 0.95, 1.55]:
		_add(n, box(Vector3(0.92, 0.08, 0.12), wood.darkened(0.25)), Vector3(0, y, 0))
	_add(n, box(Vector3(0.08, 0.08, 0.14), Color("3d3f46")), Vector3(0.32, 0.95, 0))
	return n


func _xmark() -> Node3D:
	var n := Node3D.new()
	_add(n, box(Vector3(0.9, 0.03, 0.14), Color("b3261e")), Vector3(0, 0.02, 0), Vector3(0, 45, 0))
	_add(n, box(Vector3(0.9, 0.03, 0.14), Color("b3261e")), Vector3(0, 0.02, 0), Vector3(0, -45, 0))
	return n


func crack_material(stage: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0, 0, 0, clampf(stage, 0.0, 1.0) * 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m
