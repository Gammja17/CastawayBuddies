class_name Terrain
extends Node3D
## v2 지형: 높이맵으로 만든 매끈한 로우폴리 섬.
## 삽으로 파면 낮아지고(재료가 나온다), 모래/흙을 부으면 높아진다 (물을 메워 섬을 넓힌다).
## 판 것·부은 것은 호스트가 확인하고, 모두에게 같은 계산을 시킨다.

signal changed(center: Vector3, radius: float)

const WATER_Y := WorldGen.WATER_Y
const HALF := WorldGen.HALF
const SIZE := WorldGen.SIZE
const CHUNK := 16
const MIN_H := -6.0
const MAX_H := 12.0
const EDIT_R := 1.3
const DIG_AMOUNT := 0.22
const FILL_AMOUNT := 0.26

# WorldGen.M 순서: SAND, GRASS, DIRT, ROCK, CLAY, SEABED, ANCIENT
const MAT_COLORS := [Color("e3cf94"), Color("6aa34a"), Color("7d5b3a"), Color("8b8a85"), Color("b3785a"), Color("c7b27f"), Color("7d8f80")]
const MAT_ITEMS := ["sand", "dirt", "dirt", "stone", "clay", "sand", ""]
const MAT_KEYS := ["sand", "grass", "dirt", "rock", "clay", "seabed", "ancient"]
const MAT_NAMES := ["모래", "풀밭", "흙", "바위", "점토", "바닷모래", "고대 돌바닥"]
const MAT_HARD := [2, 3, 3, 5, 3, 2, -1]       # 파는 데 필요한 힘 (-1 못 팜)
const MAT_TOOL := ["shovel", "shovel", "shovel", "pick", "shovel", "shovel", ""]

var h := PackedFloat32Array()
var mat := PackedByteArray()
var _base_h := PackedFloat32Array()
var _base_mat := PackedByteArray()
var _base_land := 0    # 처음 섬의 땅 칸 수
var _land := 0         # 지금 땅 칸 수
var _chunks := {}      # Vector2i -> {"mi", "body", "cs"}
var _dirty := {}
var _material: StandardMaterial3D
var _seabed: MeshInstance3D


static func idx(x: int, z: int) -> int:
	return WorldGen.idx(x, z)


func build(gen: WorldGen, diff: Dictionary) -> void:
	h = gen.heights.duplicate()
	mat = gen.mats.duplicate()
	_base_h = gen.heights
	_base_mat = gen.mats
	_base_land = _count_land(_base_h)
	apply_diff(diff)
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 1.0
	if _seabed == null:
		# 지도 밖 먼 바다 밑바닥
		_seabed = MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(700, 700)
		_seabed.mesh = pm
		_seabed.material_override = Vis.mat(MAT_COLORS[WorldGen.M.SEABED])
		_seabed.position.y = WorldGen.SEA_FLOOR - 1.0
		_seabed.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_seabed)
	for k in _chunks:
		_free_chunk(k)
	_chunks.clear()
	_dirty.clear()
	var n := SIZE / CHUNK
	for i in n:
		for j in n:
			_rebuild_chunk(Vector2i(i, j))


func apply_diff(diff: Dictionary) -> void:
	var ii: PackedInt32Array = diff.get("i", PackedInt32Array())
	var hh: PackedFloat32Array = diff.get("h", PackedFloat32Array())
	var mm: PackedByteArray = diff.get("m", PackedByteArray())
	for k in ii.size():
		h[ii[k]] = hh[k]
		mat[ii[k]] = mm[k]
	_land = _count_land(h)


func _count_land(hs: PackedFloat32Array) -> int:
	var n := 0
	for v in hs:
		if v >= WATER_Y - 0.1:
			n += 1
	return n


func land_gain() -> int:
	## 처음보다 늘어난 땅 (1칸 = 1m x 1m). 파내서 물이 되면 줄어든다
	return _land - _base_land


func diff_data() -> Dictionary:
	var ii := PackedInt32Array()
	var hh := PackedFloat32Array()
	var mm := PackedByteArray()
	for i in h.size():
		if absf(h[i] - _base_h[i]) > 0.0005 or mat[i] != _base_mat[i]:
			ii.append(i)
			hh.append(h[i])
			mm.append(mat[i])
	return {"i": ii, "h": hh, "m": mm}


# ── 높이 물어보기 ──

func height_at(x: float, z: float) -> float:
	if x < -HALF or z < -HALF or x > HALF or z > HALF:
		return WorldGen.SEA_FLOOR
	var x0 := int(floor(x))
	var z0 := int(floor(z))
	var fx := x - x0
	var fz := z - z0
	var h00 := h[idx(x0, z0)]
	var h10 := h[idx(x0 + 1, z0)]
	var h01 := h[idx(x0, z0 + 1)]
	var h11 := h[idx(x0 + 1, z0 + 1)]
	if fx >= fz:
		return h00 + (h10 - h00) * fx + (h11 - h10) * fz
	return h00 + (h11 - h01) * fx + (h01 - h00) * fz


func ground_at(pos: Vector3) -> float:
	return height_at(pos.x, pos.z)


func is_water(x: float, z: float) -> bool:
	return height_at(x, z) < WATER_Y - 0.12


func is_deep(x: float, z: float) -> bool:
	## 발이 안 닿는 깊은 물 (상어 구역)
	return height_at(x, z) < WATER_Y - 1.6


func material_at(x: float, z: float) -> int:
	return mat[idx(int(round(x)), int(round(z)))]


func slope_at(x: float, z: float) -> float:
	## 0 = 평지, 1 = 수직
	var dx := height_at(x + 0.3, z) - height_at(x - 0.3, z)
	var dz := height_at(x, z + 0.3) - height_at(x, z - 0.3)
	var n := Vector3(-dx, 0.6, -dz).normalized()
	return 1.0 - n.y


# ── 메쉬 ──

func _process(_delta: float) -> void:
	# 바뀐 조각은 프레임당 몇 개씩만 다시 만든다
	var n := 0
	for k in _dirty.keys():
		_rebuild_chunk(k)
		_dirty.erase(k)
		n += 1
		if n >= 4:
			break


func _free_chunk(k: Vector2i) -> void:
	var c: Dictionary = _chunks.get(k, {})
	for key in ["mi", "body"]:
		if c.has(key) and is_instance_valid(c[key]):
			c[key].queue_free()
	_chunks.erase(k)


func _rebuild_chunk(k: Vector2i) -> void:
	var x0 := -HALF + k.x * CHUNK
	var z0 := -HALF + k.y * CHUNK
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	for x in range(x0, x0 + CHUNK):
		for z in range(z0, z0 + CHUNK):
			var i00 := idx(x, z)
			var i10 := idx(x + 1, z)
			var i01 := idx(x, z + 1)
			var i11 := idx(x + 1, z + 1)
			var p00 := Vector3(x, h[i00], z)
			var p10 := Vector3(x + 1, h[i10], z)
			var p01 := Vector3(x, h[i01], z + 1)
			var p11 := Vector3(x + 1, h[i11], z + 1)
			_tri(st, faces, p00, p10, p11, [i00, i10, i11], x * 131 + z * 7)
			_tri(st, faces, p00, p11, p01, [i00, i11, i01], x * 131 + z * 7 + 3)
	var mesh := st.commit()
	var c: Dictionary = _chunks.get(k, {})
	if c.is_empty():
		var mi := MeshInstance3D.new()
		mi.material_override = _material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # 땅은 그림자를 받기만 (드리우면 조각마다 몇 번씩 더 그린다)
		add_child(mi)
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.set_meta("terrain", true)
		var cs := CollisionShape3D.new()
		body.add_child(cs)
		add_child(body)
		c = {"mi": mi, "body": body, "cs": cs}
		_chunks[k] = c
	(c.mi as MeshInstance3D).mesh = mesh
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	(c.cs as CollisionShape3D).shape = shape


func _tri(st: SurfaceTool, faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, ids: Array, seed_i: int) -> void:
	var cr := (b - a).cross(c - a)
	if cr.y > 0.0:
		var t := b
		b = c
		c = t
		cr = -cr
	var n := -cr.normalized()   # 위를 보는 면
	var col: Color = (MAT_COLORS[mat[ids[0]]] + MAT_COLORS[mat[ids[1]]] + MAT_COLORS[mat[ids[2]]]) / 3.0
	# 가파른 면은 바위색으로
	if n.y < 0.72 and mat[ids[0]] != WorldGen.M.ANCIENT:
		col = col.lerp(MAT_COLORS[WorldGen.M.ROCK], clampf((0.72 - n.y) * 2.5, 0.0, 0.85))
	# 면마다 살짝 다른 밝기 (로우폴리 느낌)
	var v := (float(hash(seed_i) % 1000) / 1000.0 - 0.5) * 0.08
	col = Color(col.r + v, col.g + v, col.b + v)
	for p in [a, b, c]:
		st.set_color(col)
		st.set_normal(n)
		st.add_vertex(p)
		faces.append(p)


# ── 파기 · 붓기 (네트워크) ──

@rpc("any_peer", "call_local", "reliable")
func req_dig(pos: Vector3, tool_kind: String) -> void:
	if not multiplayer.is_server():
		return
	var from := multiplayer.get_remote_sender_id()
	var m := material_at(pos.x, pos.z)
	if MAT_HARD[m] < 0:
		Game.I.toast_to(from, "단단한 고대 돌바닥이다. 팔 수 없다")
		return
	if m == WorldGen.M.ROCK and tool_kind != "pick":
		Game.I.toast_to(from, "바위는 곡괭이가 필요해!")
		return
	if height_at(pos.x, pos.z) <= MIN_H + 0.4:
		return
	if Game.I.blocked_for_ground(pos, 1.0):
		Game.I.toast_to(from, "바로 위에 뭔가 있어서 못 판다")
		return
	var good: bool = tool_kind == MAT_TOOL[m]
	_edit.rpc(pos.x, pos.z, -DIG_AMOUNT * (1.4 if good else 1.0), EDIT_R, -1, MAX_H)
	var item: String = MAT_ITEMS[m]
	if item != "":
		Game.I.give_to(from, item, 2 if good and m != WorldGen.M.ROCK else 1)
	Game.I.stat_add("dug", 1)


@rpc("any_peer", "call_local", "reliable")
func req_fill(pos: Vector3, item: String) -> void:
	if not multiplayer.is_server():
		return
	var from := multiplayer.get_remote_sender_id()
	var before := height_at(pos.x, pos.z)
	var ok := before < MAX_H - 0.5 and material_at(pos.x, pos.z) != WorldGen.M.ANCIENT
	ok = ok and not Game.I.player_standing_near(pos, 0.7, before) and not Game.I.blocked_for_ground(pos, 0.8)
	if not ok:
		Game.I.give_to(from, item, 1)
		Game.I.toast_to(from, "여기엔 못 붓는다")
		return
	var new_mat: int = WorldGen.M.SAND if item == "sand" else WorldGen.M.DIRT
	# 물에 부은 모래는 가라앉아 퍼진다: 수면 살짝 위까지만 쌓인다 (뾰족산 방지)
	var cap := WATER_Y + 0.2 if before < WATER_Y - 0.1 else MAX_H
	_edit.rpc(pos.x, pos.z, FILL_AMOUNT, EDIT_R, new_mat, cap)
	Game.I.quests.on_land_changed()


@rpc("authority", "call_local", "reliable")
func _edit(x: float, z: float, amount: float, radius: float, new_mat: int, cap: float) -> void:
	for vx in range(int(floor(x - radius)), int(ceil(x + radius)) + 1):
		for vz in range(int(floor(z - radius)), int(ceil(z + radius)) + 1):
			if vx < -HALF or vz < -HALF or vx > HALF or vz > HALF:
				continue
			var d := Vector2(vx - x, vz - z).length()
			if d > radius:
				continue
			var i := idx(vx, vz)
			if mat[i] == WorldGen.M.ANCIENT:
				continue
			var w := 1.0 - d / radius
			w = w * w * (3.0 - 2.0 * w)
			var was_land := h[i] >= WATER_Y - 0.1
			h[i] = clampf(minf(h[i] + amount * w, maxf(h[i], cap)), MIN_H, MAX_H)
			if (h[i] >= WATER_Y - 0.1) != was_land:
				_land += 1 if not was_land else -1
			if new_mat >= 0 and w > 0.25:
				mat[i] = new_mat if h[i] >= WATER_Y - 0.1 else WorldGen.M.SEABED
			elif amount < 0.0 and h[i] < WATER_Y - 0.1 and mat[i] != WorldGen.M.ROCK:
				mat[i] = WorldGen.M.SEABED
			elif amount < 0.0 and mat[i] == WorldGen.M.GRASS and w > 0.25:
				mat[i] = WorldGen.M.DIRT   # 풀을 걷어내면 흙이 드러난다
			# 이 꼭짓점을 쓰는 조각들을 다시 만들기
			for ox in [-1, 0]:
				for oz in [-1, 0]:
					var cx: int = (vx + ox + HALF) / CHUNK
					var cz: int = (vz + oz + HALF) / CHUNK
					if cx >= 0 and cz >= 0 and cx < SIZE / CHUNK and cz < SIZE / CHUNK:
						_dirty[Vector2i(cx, cz)] = true
	var p := Vector3(x, height_at(x, z), z)
	Game.I.fx_break(p + Vector3.UP * 0.2, MAT_COLORS[material_at(x, z)], 6)
	Audio.play_at("dig" if amount < 0 else "place", p, -3.0)
	changed.emit(p, radius)
