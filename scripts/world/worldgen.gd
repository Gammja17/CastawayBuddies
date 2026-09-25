class_name WorldGen
extends RefCounted
## 씨앗(seed) 하나로 똑같은 섬들을 만든다 (v2: 매끈한 높이맵).
## 호스트와 손님이 각자 만들고, 바뀐 것(판 곳·부은 곳)만 주고받는다.

const HALF := 64                 # 좌표 -64..64
const SIZE := HALF * 2 + 1       # 한 변 꼭짓점 수
const WATER_Y := 0.7
const SEA_FLOOR := -5.5

enum M { SAND, GRASS, DIRT, ROCK, CLAY, SEABED, ANCIENT }

const ISLANDS := [
	{"key": "home", "name": "시작섬", "c": Vector2(0, 0), "r": 5.2, "peak": 0.9, "stretch": Vector2(1, 1)},
	{"key": "jungle", "name": "숲섬", "c": Vector2(21, -9), "r": 9.0, "peak": 2.6, "stretch": Vector2(1.1, 0.9)},
	{"key": "rocky", "name": "돌섬", "c": Vector2(-23, 9), "r": 8.0, "peak": 7.0, "stretch": Vector2(1, 1)},
	{"key": "wreck", "name": "난파선 모래톱", "c": Vector2(5, 27), "r": 6.8, "peak": 0.35, "stretch": Vector2(1.4, 0.8)},
	{"key": "ruins", "name": "고대 유적섬", "c": Vector2(31, 21), "r": 10.0, "peak": 1.3, "stretch": Vector2(1, 1), "flat": 0.72},
]

# 결과
var heights := PackedFloat32Array()   # SIZE*SIZE
var mats := PackedByteArray()         # SIZE*SIZE
var props: Array = []    # {"kind", "pos": Vector3}
var structs: Array = []  # {"kind", "pos": Vector3, "rot": float, "data": {}}
var pickups: Array = []  # {"item", "n", "pos"}
var decor: Array = []    # {"model", "pos", "rot", "h", "tilt", "collide"}
var spawn := Vector3(0.5, 2.0, 1.5)
var pois := {}           # 이름 -> Vector3 (지도 표시용)
var crab_king_home := Vector3.ZERO

var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
var _noise2 := FastNoiseLite.new()
var _biome := PackedByteArray()        # 꼭짓점별 섬 번호 (255 = 바다)


static func idx(x: int, z: int) -> int:
	return (clampi(x, -HALF, HALF) + HALF) * SIZE + (clampi(z, -HALF, HALF) + HALF)


func generate(world_seed: int) -> void:
	_rng.seed = world_seed
	_noise.seed = world_seed
	_noise.frequency = 0.11
	_noise2.seed = world_seed + 7
	_noise2.frequency = 0.23
	heights.resize(SIZE * SIZE)
	mats.resize(SIZE * SIZE)
	_biome.resize(SIZE * SIZE)
	_shape_islands()
	_sandbar(Vector2(4.5, 1.5), Vector2(14.0, -5.5))   # 시작섬 -> 숲섬 얕은 모래길 (튜토리얼 길)
	_paint()
	_ensure_clay(16)
	_home()
	_jungle()
	_rocky()
	_wreck()
	_ruins()
	_seaweed()
	_decorate()


# ── 높이 ──

func _shape_islands() -> void:
	for x in range(-HALF, HALF + 1):
		for z in range(-HALF, HALF + 1):
			var best := SEA_FLOOR + _noise.get_noise_2d(x * 0.5, z * 0.5) * 0.6
			var b := 255
			for i in ISLANDS.size():
				var hh := _island_h(ISLANDS[i], x, z)
				if hh > best:
					best = hh
					b = i
			heights[idx(x, z)] = best
			_biome[idx(x, z)] = b


func _island_h(isl: Dictionary, x: int, z: int) -> float:
	var p: Vector2 = Vector2(x, z) - isl.c
	p = Vector2(p.x / isl.stretch.x, p.y / isl.stretch.y)
	var d: float = p.length() / isl.r + _noise.get_noise_2d(x, z) * 0.16
	if d >= 1.0:
		# 물가에서 바다 밑으로 내려가는 비탈
		return lerpf(WATER_Y - 0.45, SEA_FLOOR, smoothstep(1.0, 1.75, d))
	var t := clampf((1.0 - d) / 0.85, 0.0, 1.0)
	if isl.has("flat") and d < isl.flat:
		t = 1.0
	var bump := _noise2.get_noise_2d(x * 2.0, z * 2.0) * 0.18 * t
	if isl.key == "rocky":
		bump *= 3.0
	return WATER_Y + 0.3 + isl.peak * pow(t, 1.35) + bump


func _sandbar(a: Vector2, b: Vector2) -> void:
	for x in range(int(minf(a.x, b.x)) - 2, int(maxf(a.x, b.x)) + 3):
		for z in range(int(minf(a.y, b.y)) - 2, int(maxf(a.y, b.y)) + 3):
			var p := Vector2(x, z)
			var ab := b - a
			var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
			var dist := p.distance_to(a + ab * t)
			if dist < 1.6:
				var i := idx(x, z)
				heights[i] = maxf(heights[i], WATER_Y - 0.3 - dist * 0.15)


# ── 색(재질) ──

func _paint() -> void:
	for x in range(-HALF, HALF + 1):
		for z in range(-HALF, HALF + 1):
			var i := idx(x, z)
			var h := heights[i]
			var b := _biome[i]
			var key: String = ISLANDS[b].key if b != 255 else ""
			var m := M.SEABED
			if h >= WATER_Y - 0.05:
				if h < WATER_Y + 0.55:
					m = M.SAND
					if key == "jungle" and _noise.get_noise_2d(x * 3.0, z * 3.0) > 0.25:
						m = M.CLAY
				else:
					match key:
						"rocky": m = M.ROCK
						"wreck": m = M.SAND
						_:
							m = M.GRASS
							if _noise2.get_noise_2d(x * 1.7, z * 1.7) > 0.45:
								m = M.DIRT
			mats[i] = m


func _ensure_clay(min_n: int) -> void:
	## 점토가 너무 적은 세계가 나오지 않게 숲섬 해변 모래를 점토로 바꿔 채운다
	var have := 0
	var cand: Array = []
	for x in range(-HALF, HALF + 1):
		for z in range(-HALF, HALF + 1):
			var i := idx(x, z)
			if _biome[i] == 1 and heights[i] >= WATER_Y - 0.05 and heights[i] < WATER_Y + 0.55:
				if mats[i] == M.CLAY:
					have += 1
				else:
					cand.append(Vector2i(x, z))
	while have < min_n and not cand.is_empty():
		var k: Vector2i = cand.pop_at(_rng.randi() % cand.size())
		mats[idx(k.x, k.y)] = M.CLAY
		have += 1


func height_at(x: float, z: float) -> float:
	## Terrain 과 같은 삼각형 나눔으로 보간
	var x0 := int(floor(x))
	var z0 := int(floor(z))
	var fx := x - x0
	var fz := z - z0
	var h00 := heights[idx(x0, z0)]
	var h10 := heights[idx(x0 + 1, z0)]
	var h01 := heights[idx(x0, z0 + 1)]
	var h11 := heights[idx(x0 + 1, z0 + 1)]
	if fx >= fz:
		return h00 + (h10 - h00) * fx + (h11 - h10) * fz
	return h00 + (h11 - h01) * fx + (h01 - h00) * fz


func surface(x: float, z: float) -> Vector3:
	return Vector3(x, height_at(x, z), z)


func _land(key: String, min_above: float = 0.25) -> Array:
	var bi := -1
	for i in ISLANDS.size():
		if ISLANDS[i].key == key:
			bi = i
	var out: Array = []
	for x in range(-HALF, HALF):
		for z in range(-HALF, HALF):
			var i := idx(x, z)
			if _biome[i] == bi and heights[i] > WATER_Y + min_above:
				out.append(Vector2i(x, z))
	return out


func _prop(kind: String, x: float, z: float) -> void:
	props.append({"kind": kind, "pos": surface(x, z)})


func _struct(kind: String, x: float, z: float, rot: float = 0.0, data: Dictionary = {}) -> void:
	structs.append({"kind": kind, "pos": surface(x, z), "rot": rot, "data": data})


func _pickup(item: String, x: float, z: float) -> void:
	var p := surface(x + _rng.randf_range(-0.3, 0.3), z + _rng.randf_range(-0.3, 0.3))
	pickups.append({"item": item, "n": 1, "pos": p + Vector3.UP * 0.05})


func _scatter(key: String, kind: String, count: int, used: Array, min_above: float = 0.3, as_pickup := false, spacing := 2.2) -> void:
	var cells := _land(key, min_above)
	var tries := 0
	while count > 0 and tries < 500 and not cells.is_empty():
		tries += 1
		var k: Vector2i = cells[_rng.randi() % cells.size()]
		var p := Vector2(k.x + 0.5, k.y + 0.5)
		var ok := true
		for u: Vector2 in used:
			if u.distance_to(p) < spacing:
				ok = false
				break
		if not ok:
			continue
		used.append(p)
		if as_pickup:
			_pickup(kind, p.x, p.y)
		else:
			_prop(kind, p.x, p.y)
		count -= 1


# ── 섬별 배치 ──

func _home() -> void:
	# 작은 섬: 야자수 하나, 덤불 하나, 떠밀려온 상자
	spawn = surface(0.5, 1.8) + Vector3(0, 0.2, 0)
	pois["시작섬"] = surface(0, 0)
	_prop("palm", 1.5, -1.0)
	_prop("bush", -2.0, -1.2)
	_struct("loot_crate", -1.2, 1.6, PI * 0.5, {"loot": "start"})
	_struct("note_sign", 2.4, 1.4, PI * 1.5, {"note": "sign_home"})
	for p in [[-3, 0, "stick"], [0, -3, "stone"], [2, 2.6, "stick"], [-1, -2.5, "stone"], [3.2, -1, "stone"], [-2, 2.5, "stick"],
			[1, 3, "stone"], [-3.2, -1.5, "stone"], [3.2, 1, "stick"]]:
		_pickup(p[2], p[0], p[1])
	decor.append({"model": "pirate/boat-row-small", "pos": surface(-3.4, -2.6) + Vector3(0, -0.2, 0), "rot": 35.0, "h": 0.7, "tilt": 16.0})


func _jungle() -> void:
	var used: Array = []
	var c: Vector2 = ISLANDS[1].c
	pois["숲섬"] = surface(c.x, c.y)
	_scatter("jungle", "tree", 8, used, 0.9, false, 2.6)
	_scatter("jungle", "palm", 4, used, 0.3)
	_scatter("jungle", "bush", 5, used, 0.6)
	_scatter("jungle", "berry_bush", 3, used, 0.6)
	_scatter("jungle", "stick", 5, used, 0.2, true, 1.2)
	_scatter("jungle", "stone", 3, used, 0.2, true, 1.2)
	# 보물 자리: 숲섬 북쪽 해변 (보물 지도를 읽어야 보인다)
	var cells := _land("jungle", 0.05)
	var best: Vector2i = cells[0]
	for k: Vector2i in cells:
		if heights[idx(k.x, k.y)] < WATER_Y + 0.6 and k.y < best.y:
			best = k
	_struct("dig_spot", best.x + 0.5, best.y + 0.5, 0.0, {"loot": "treasure"})
	pois["보물?"] = surface(best.x + 0.5, best.y + 0.5)


func _rocky() -> void:
	var c: Vector2 = ISLANDS[2].c
	var cx := c.x
	var cz := c.y
	pois["돌섬"] = surface(cx, cz)
	# 동굴: 동쪽 해안에서 산 가운데로 파고 들어가는 좁은 틈 + 지붕 바위
	var floor_y := WATER_Y + 0.45
	for x in range(int(cx) - 3, int(cx) + 10):
		for z in range(int(cz) - 3, int(cz) + 4):
			var dz := absf(z - cz)
			var in_corr := x >= cx - 1 and dz <= 1.2
			var in_room := Vector2(x, z).distance_to(Vector2(cx - 0.5, cz)) <= 2.3
			if in_corr or in_room:
				var i := idx(x, z)
				heights[i] = minf(heights[i], floor_y)
				mats[i] = M.ROCK
	structs.append({"kind": "cave_roof", "pos": Vector3(cx + 3.0, floor_y, cz), "rot": 0.0, "data": {"len": 11.0}})
	structs.append({"kind": "tablet", "pos": Vector3(cx - 1.8, floor_y, cz), "rot": PI * 0.5, "data": {"note": "tablet_1"}})
	structs.append({"kind": "torch", "pos": Vector3(cx - 0.5, floor_y, cz - 1.6), "rot": 0.0, "data": {}})
	# 굴 입구를 막은 큰 바위 (둘이 같이 밀어야 한다)
	structs.append({"kind": "big_rock", "pos": Vector3(cx + 3.0, floor_y, cz), "rot": 0.0, "data": {}})
	var used: Array = [Vector2(cx, cz)]
	for x in range(int(cx) - 3, int(cx) + 10):
		used.append(Vector2(x, cz))
	_scatter("rocky", "boulder", 5, used, 0.4, false, 2.8)
	_scatter("rocky", "iron_rock", 3, used, 0.6, false, 2.8)
	_scatter("rocky", "palm", 2, used, 0.2)
	_scatter("rocky", "flint", 4, used, 0.1, true, 1.2)
	_scatter("rocky", "stone", 5, used, 0.1, true, 1.2)


func _wreck() -> void:
	var c: Vector2 = ISLANDS[3].c
	var cx := c.x
	var cz := c.y
	pois["난파선"] = surface(cx, cz)
	decor.append({"model": "pirate/ship-wreck", "pos": surface(cx - 1, cz) + Vector3(0, -0.6, 0), "rot": 80.0, "h": 6.5, "tilt": -8.0, "collide": true})
	_struct("note_sign", cx + 3.5, cz + 2.2, PI, {"note": "captain_log"})
	_struct("captain_chest", cx + 4.5, cz - 1.0, PI * 1.5, {})
	_struct("loot_barrel", cx - 5.5, cz + 2.2, 0.0, {"loot": "barrel"})
	_struct("loot_barrel", cx + 6.5, cz + 1.0, 0.0, {"loot": "barrel"})
	_struct("loot_crate", cx - 4.5, cz - 2.2, PI, {"loot": "barrel"})
	_struct("loot_crate", cx + 2.5, cz + 3.2, PI * 0.5, {"loot": "wreck_crate"})
	var used: Array = []
	for x in range(int(cx) - 5, int(cx) + 4):
		used.append(Vector2(x, cz))
	_scatter("wreck", "shell", 4, used, 0.05, true, 1.2)
	_scatter("wreck", "stick", 2, used, 0.05, true, 1.2)


func _ruins() -> void:
	var c: Vector2 = ISLANDS[4].c
	var cx := c.x
	var cz := c.y
	pois["고대 유적"] = surface(cx, cz)
	# 바닥을 판판하게 다지고 고대 돌바닥으로
	var gy := height_at(cx, cz)
	for x in range(int(cx) - 6, int(cx) + 7):
		for z in range(int(cz) - 9, int(cz) + 5):
			var i := idx(x, z)
			heights[i] = gy
			if absf(x - cx) <= 4 and z >= cz - 8 and z <= cz - 1:
				mats[i] = M.ANCIENT
	# 신전: 문은 압력판 두 개를 동시에 밟으면 열린다
	structs.append({"kind": "temple", "pos": Vector3(cx, gy, cz - 4.5), "rot": 0.0, "data": {}})
	for sx in [-4.0, 4.0]:
		structs.append({"kind": "plate", "pos": Vector3(cx + sx, gy, cz + 1.0), "rot": 0.0, "data": {}})
	structs.append({"kind": "tablet", "pos": Vector3(cx, gy, cz - 6.2), "rot": 0.0, "data": {"note": "tablet_3"}})
	structs.append({"kind": "loot_crate", "pos": Vector3(cx + 1.6, gy, cz - 6.2), "rot": 0.0, "data": {"loot": "temple"}})
	structs.append({"kind": "tablet", "pos": Vector3(cx + 2.5, gy, cz + 3.0), "rot": 0.0, "data": {"note": "tablet_2"}})
	structs.append({"kind": "altar", "pos": Vector3(cx, gy, cz + 2.0), "rot": 0.0, "data": {}})
	var bi := 0
	for sx in [-7.5, 7.5]:
		structs.append({"kind": "bell", "pos": surface(cx + sx, cz), "rot": 0.0, "data": {"bell": bi}})
		bi += 1
	crab_king_home = surface(cx + 5.5, cz + 6.5)
	pois["게 왕의 해변"] = crab_king_home
	for p in [[-5, 4], [5, 4], [-6, -4], [6, -4]]:
		decor.append({"model": "nature/statue_columnDamaged", "pos": surface(cx + p[0], cz + p[1]), "rot": _rng.randf() * 360.0, "h": 2.2, "collide": true})
	decor.append({"model": "nature/statue_head", "pos": surface(cx - 6.5, cz + 5.0), "rot": 200.0, "h": 2.4, "collide": true})
	var used: Array = []
	for x in range(int(cx) - 8, int(cx) + 9):
		for z in range(int(cz) - 9, int(cz) + 5):
			if (x + z) % 2 == 0:
				used.append(Vector2(x, z))
	_scatter("ruins", "palm", 4, used, 0.2)
	_scatter("ruins", "tree", 2, used, 0.8)
	_scatter("ruins", "bush", 3, used, 0.6)
	_scatter("ruins", "shell", 4, used, 0.05, true, 1.2)


func _seaweed() -> void:
	var cand: Array = []
	for x in range(-HALF, HALF):
		for z in range(-HALF, HALF):
			var h := heights[idx(x, z)]
			if h < WATER_Y - 0.5 and h > WATER_Y - 2.4:
				cand.append(Vector2i(x, z))
	var n := 0
	var tries := 0
	var used := {}
	while n < 28 and tries < 800 and not cand.is_empty():
		tries += 1
		var k: Vector2i = cand[_rng.randi() % cand.size()]
		if used.has(k):
			continue
		used[k] = true
		props.append({"kind": "seaweed", "pos": surface(k.x + 0.5, k.y + 0.5)})
		n += 1


func _decorate() -> void:
	var models := ["nature/grass_large", "nature/grass", "nature/flower_redA", "nature/flower_yellowA", "nature/flower_purpleA", "nature/mushroom_redGroup"]
	var taken: Array = []
	for p in props:
		taken.append(Vector2(p.pos.x, p.pos.z))
	for s in structs:
		taken.append(Vector2(s.pos.x, s.pos.z))
	for x in range(-HALF, HALF):
		for z in range(-HALF, HALF):
			var i := idx(x, z)
			if mats[i] != M.GRASS or _rng.randf() > 0.2:
				continue
			var p := Vector2(x + _rng.randf_range(0.2, 0.8), z + _rng.randf_range(0.2, 0.8))
			var near := false
			for t: Vector2 in taken:
				if t.distance_squared_to(p) < 1.0:
					near = true
					break
			if near:
				continue
			decor.append({"model": models[_rng.randi() % models.size()], "pos": surface(p.x, p.y), "rot": _rng.randf() * 360.0,
					"h": _rng.randf_range(0.25, 0.45), "grass": true})
