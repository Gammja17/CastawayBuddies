class_name WorldGen
extends RefCounted
## 씨앗(seed) 하나로 똑같은 섬들을 만든다. 호스트와 손님이 각자 만들고, 바뀐 것만 주고받는다.

const SAND := 0
const DIRT := 1
const GRASS := 2
const STONE := 3
const CLAY := 4
const IRON := 5
const PLANK := 6
const STONEB := 7
const ANCIENT := 11

const BOTTOM := -3

const ISLANDS := [
	{"key": "home", "name": "시작섬", "c": Vector2(0, 0), "r": 4.6, "peak": 1, "stretch": Vector2(1, 1)},
	{"key": "jungle", "name": "숲섬", "c": Vector2(21, -9), "r": 8.5, "peak": 3, "stretch": Vector2(1.1, 0.9)},
	{"key": "rocky", "name": "돌섬", "c": Vector2(-23, 9), "r": 7.5, "peak": 6, "stretch": Vector2(1, 1)},
	{"key": "wreck", "name": "난파선 모래톱", "c": Vector2(5, 27), "r": 6.5, "peak": 0, "stretch": Vector2(1.4, 0.8)},
	{"key": "ruins", "name": "고대 유적섬", "c": Vector2(31, 21), "r": 9.5, "peak": 1, "stretch": Vector2(1, 1), "flat": 0.75},
]

# 결과
var blocks := {}        # Vector3i -> int
var props: Array = []   # {"kind", "pos": Vector3}
var structs: Array = [] # {"kind", "cell": Vector3i, "rot": int, "data": {}}
var pickups: Array = [] # {"item", "n", "pos"}
var decor: Array = []   # {"model", "pos", "rot", "h"}
var spawn := Vector3(0.5, 2.0, 0.5)
var pois := {}          # 이름 -> Vector3 (지도 표시용)
var door_cells: Array = []
var plate_cells: Array = []
var bell_cells: Array = []
var crab_king_home := Vector3.ZERO
var tops := {}          # Vector2i -> int (기둥 맨 윗칸)

var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
var _biome := {}        # Vector2i -> 섬 key


func generate(world_seed: int) -> void:
	_rng.seed = world_seed
	_noise.seed = world_seed
	_noise.frequency = 0.12
	for isl in ISLANDS:
		_island(isl)
	_fill_columns()
	_ensure_clay(16)
	_sandbar(Vector2(4.5, 1.5), Vector2(13.5, -5.5))   # 시작섬->숲섬 얕은 모래길 (튜토리얼 길)
	_home()
	_jungle()
	_rocky()
	_wreck()
	_ruins()
	_seaweed()
	_decorate()


func _island(isl: Dictionary) -> void:
	var c: Vector2 = isl.c
	var r: float = isl.r
	var st: Vector2 = isl.stretch
	var ext := int(ceil(r * 1.6 * maxf(st.x, st.y)))
	for x in range(int(c.x) - ext, int(c.x) + ext + 1):
		for z in range(int(c.y) - ext, int(c.y) + ext + 1):
			var p := Vector2(x + 0.5, z + 0.5) - c
			p = Vector2(p.x / st.x, p.y / st.y)
			var d := p.length() / r + _noise.get_noise_2d(x, z) * 0.18
			var h := -99
			if d <= 1.0:
				var t := clampf((1.0 - d) / 0.75, 0.0, 1.0)
				if isl.has("flat") and d < isl.flat:
					t = 1.0
				h = int(floor(isl.peak * t + 0.001))
			elif d <= 1.3:
				h = -1
			elif d <= 1.55:
				h = -2
			var k := Vector2i(x, z)
			if h > tops.get(k, -99):
				tops[k] = h
				_biome[k] = isl.key


func _fill_columns() -> void:
	for k: Vector2i in tops:
		var h: int = tops[k]
		var biome: String = _biome[k]
		for y in range(BOTTOM, h + 1):
			var depth := h - y
			var t := SAND
			if h <= 0:
				t = SAND if depth < 2 else STONE
			else:
				match biome:
					"rocky":
						t = STONE
						if h <= 1 and depth == 0:
							t = SAND
						elif depth > 0 and y >= 1 and _rng.randf() < 0.1:
							t = IRON
					_:
						if depth == 0: t = GRASS
						elif depth <= 2: t = DIRT
						else: t = STONE
			blocks[Vector3i(k.x, y, k.y)] = t
		# 숲섬 물가 점토
		if biome == "jungle" and h == 0 and _noise.get_noise_2d(k.x * 3.0, k.y * 3.0) > 0.25:
			blocks[Vector3i(k.x, 0, k.y)] = CLAY


func _ensure_clay(min_cells: int) -> void:
	## 점토가 너무 적은 세계가 나오지 않게 숲섬 해변 모래를 점토로 바꿔 채운다
	var have := 0
	var cand: Array = []
	for k: Vector2i in tops:
		if _biome[k] == "jungle" and tops[k] == 0:
			if blocks.get(Vector3i(k.x, 0, k.y), -1) == CLAY:
				have += 1
			else:
				cand.append(k)
	cand.sort()
	while have < min_cells and not cand.is_empty():
		var k: Vector2i = cand.pop_at(_rng.randi() % cand.size())
		blocks[Vector3i(k.x, 0, k.y)] = CLAY
		have += 1


func _sandbar(a: Vector2, b: Vector2) -> void:
	var n := int(a.distance_to(b))
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		for dx in [0, 1]:
			var k := Vector2i(int(floor(p.x)) + dx, int(floor(p.y)))
			if tops.get(k, -99) < -1:
				tops[k] = -1
				_biome[k] = "bar"
				for y in range(BOTTOM, 0):
					blocks[Vector3i(k.x, y, k.y)] = SAND


func top(x: int, z: int) -> int:
	for y in range(12, BOTTOM - 1, -1):
		if blocks.has(Vector3i(x, y, z)):
			return y
	return -99


func surface(x: int, z: int) -> Vector3:
	return Vector3(x + 0.5, top(x, z) + 1, z + 0.5)


func _prop(kind: String, x: int, z: int) -> void:
	props.append({"kind": kind, "pos": surface(x, z)})


func _struct(kind: String, x: int, z: int, rot: int = 0, data: Dictionary = {}) -> Vector3i:
	var cell := Vector3i(x, top(x, z) + 1, z)
	structs.append({"kind": kind, "cell": cell, "rot": rot, "data": data})
	return cell


func _pickup(item: String, x: int, z: int) -> void:
	pickups.append({"item": item, "n": 1, "pos": surface(x, z) + Vector3(_rng.randf_range(-0.3, 0.3), 0.1, _rng.randf_range(-0.3, 0.3))})


func _land_cells(key: String, min_h: int = 0) -> Array:
	var out: Array = []
	for k: Vector2i in tops:
		if _biome[k] == key and tops[k] >= min_h:
			out.append(k)
	out.sort()
	return out


func _free(k: Vector2i, used: Dictionary) -> bool:
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			if used.has(k + Vector2i(dx, dz)):
				return false
	return true


func _scatter(key: String, kind: String, count: int, used: Dictionary, min_h: int = 0, as_pickup := false) -> void:
	var cells := _land_cells(key, min_h)
	var tries := 0
	while count > 0 and tries < 400 and not cells.is_empty():
		tries += 1
		var k: Vector2i = cells[_rng.randi() % cells.size()]
		if not _free(k, used):
			continue
		used[k] = true
		if as_pickup:
			_pickup(kind, k.x, k.y)
		else:
			_prop(kind, k.x, k.y)
		count -= 1


# ── 섬별 배치 ──

func _home() -> void:
	# 스카이블록처럼 작은 섬: 야자수 하나, 덤불 하나, 떠밀려온 상자
	spawn = surface(0, 1) + Vector3(0, 0.2, 0)
	pois["시작섬"] = surface(0, 0)
	_prop("palm", 1, -1)
	_prop("bush", -2, -1)
	_struct("loot_crate", -1, 1, 1, {"loot": "start"})
	_struct("note_sign", 2, 1, 3, {"note": "sign_home"})
	for p in [[-3, 0, "stick"], [0, -3, "stone"], [2, 2, "stick"], [-1, -2, "stone"], [3, -1, "stone"], [-2, 2, "stick"],
			[1, 3, "stone"], [-3, -1, "stone"], [3, 1, "stick"]]:
		_pickup(p[2], p[0], p[1])
	decor.append({"model": "pirate/boat-row-small", "pos": surface(-3, -2) + Vector3(0, -0.25, 0), "rot": 35.0, "h": 0.7, "tilt": 18.0})


func _jungle() -> void:
	var used := {}
	var c: Vector2 = ISLANDS[1].c
	pois["숲섬"] = surface(int(c.x), int(c.y))
	_scatter("jungle", "tree", 7, used, 1)
	_scatter("jungle", "palm", 4, used, 0)
	_scatter("jungle", "bush", 4, used, 1)
	_scatter("jungle", "berry_bush", 3, used, 1)
	_scatter("jungle", "stick", 5, used, 0, true)
	_scatter("jungle", "stone", 3, used, 0, true)
	# 보물 자리 (보물 지도를 읽어야 보인다)
	var cells := _land_cells("jungle", 0)
	var best: Vector2i = cells[0]
	for k: Vector2i in cells:
		if tops[k] == 0 and k.y < best.y:
			best = k
	_struct("dig_spot", best.x, best.y, 0, {"loot": "treasure"})
	pois["보물?"] = surface(best.x, best.y)


func _rocky() -> void:
	var c: Vector2 = ISLANDS[2].c
	var cx := int(c.x)
	var cz := int(c.y)
	pois["돌섬"] = surface(cx, cz)
	# 동굴: 동쪽 해안에서 가운데로 파고 들어간다
	for x in range(cx - 1, cx + 9):
		for z in range(cz, cz + 2):
			for y in range(1, 3):
				blocks.erase(Vector3i(x, y, z))
			if blocks.has(Vector3i(x, 0, z)):
				blocks[Vector3i(x, 0, z)] = STONE
	# 안쪽 방 3x3
	for x in range(cx - 2, cx + 1):
		for z in range(cz - 1, cz + 3):
			for y in range(1, 4):
				blocks.erase(Vector3i(x, y, z))
			blocks[Vector3i(x, 0, z)] = STONE
	# 방 벽에 철광석 박기
	for x in range(cx - 3, cx + 2):
		for z in range(cz - 2, cz + 4):
			for y in range(1, 4):
				var cell := Vector3i(x, y, z)
				if blocks.has(cell) and _rng.randf() < 0.35:
					blocks[cell] = IRON
	structs.append({"kind": "tablet", "cell": Vector3i(cx - 2, 1, cz + 1), "rot": 1, "data": {"note": "tablet_1"}})
	structs.append({"kind": "torch", "cell": Vector3i(cx, 1, cz - 1), "rot": 0, "data": {}})
	# 굴 입구를 막은 큰 바위 (둘이 같이 밀어야 한다)
	structs.append({"kind": "big_rock", "cell": Vector3i(cx + 2, 1, cz), "rot": 0, "data": {}})
	var used := {Vector2i(cx, cz): true}
	for x in range(cx - 2, cx + 9):
		used[Vector2i(x, cz)] = true
		used[Vector2i(x, cz + 1)] = true
	_scatter("rocky", "boulder", 5, used, 0)
	_scatter("rocky", "iron_rock", 2, used, 1)
	_scatter("rocky", "palm", 2, used, 0)
	_scatter("rocky", "flint", 4, used, 0, true)
	_scatter("rocky", "stone", 4, used, 0, true)


func _wreck() -> void:
	var c: Vector2 = ISLANDS[3].c
	var cx := int(c.x)
	var cz := int(c.y)
	pois["난파선"] = surface(cx, cz)
	decor.append({"model": "pirate/ship-wreck", "pos": surface(cx - 1, cz) + Vector3(0, -0.6, 0), "rot": 80.0, "h": 6.5, "tilt": -8.0, "collide": true})
	_struct("note_sign", cx + 3, cz + 2, 2, {"note": "captain_log"})
	_struct("captain_chest", cx + 4, cz - 1, 3, {})
	_struct("loot_barrel", cx - 5, cz + 2, 0, {"loot": "barrel"})
	_struct("loot_barrel", cx + 6, cz + 1, 0, {"loot": "barrel"})
	_struct("loot_crate", cx - 4, cz - 2, 2, {"loot": "barrel"})
	_struct("loot_crate", cx + 2, cz + 3, 1, {"loot": "wreck_crate"})
	var used := {}
	for x in range(cx - 4, cx + 3):
		for z in range(cz - 2, cz + 3):
			used[Vector2i(x, z)] = true
	_scatter("wreck", "shell", 4, used, 0, true)
	_scatter("wreck", "stick", 2, used, 0, true)


func _ruins() -> void:
	var c: Vector2 = ISLANDS[4].c
	var cx := int(c.x)
	var cz := int(c.y)
	pois["고대 유적"] = surface(cx, cz)
	var gy := top(cx, cz) + 1   # 땅 위 첫 칸
	# 신전: 5x5, 벽 높이 3, 지붕
	for x in range(cx - 2, cx + 3):
		for z in range(cz - 6, cz - 1):
			for y in range(gy, gy + 4):
				var edge := x == cx - 2 or x == cx + 2 or z == cz - 6 or z == cz - 2 or y == gy + 3
				if edge:
					blocks[Vector3i(x, y, z)] = ANCIENT
				else:
					blocks.erase(Vector3i(x, y, z))
			blocks[Vector3i(x, gy - 1, z)] = ANCIENT
	# 문 (압력판 두 개를 동시에 밟으면 열린다)
	for y in range(gy, gy + 2):
		door_cells.append(Vector3i(cx, y, cz - 2))
	# 지붕 장식 기둥
	for p in [[-3, -7], [3, -7], [-3, -1], [3, -1]]:
		for y in range(gy, gy + 3):
			blocks[Vector3i(cx + p[0], y, cz + p[1])] = ANCIENT
	plate_cells.append(Vector3i(cx - 4, gy, cz + 1))
	plate_cells.append(Vector3i(cx + 4, gy, cz + 1))
	for pc in plate_cells:
		structs.append({"kind": "plate", "cell": pc, "rot": 0, "data": {}})
	structs.append({"kind": "tablet", "cell": Vector3i(cx, gy, cz - 4), "rot": 0, "data": {"note": "tablet_3"}})
	structs.append({"kind": "loot_crate", "cell": Vector3i(cx + 1, gy, cz - 5), "rot": 0, "data": {"loot": "temple"}})
	structs.append({"kind": "tablet", "cell": Vector3i(cx + 2, gy, cz + 3), "rot": 0, "data": {"note": "tablet_2"}})
	structs.append({"kind": "altar", "cell": Vector3i(cx, gy, cz + 2), "rot": 0, "data": {}})
	bell_cells.append(Vector3i(cx - 7, gy, cz))
	bell_cells.append(Vector3i(cx + 7, gy, cz))
	for i in bell_cells.size():
		var bc: Vector3i = bell_cells[i]
		bc.y = top(bc.x, bc.z) + 1
		bell_cells[i] = bc
		structs.append({"kind": "bell", "cell": bc, "rot": 0, "data": {"bell": i}})
	crab_king_home = surface(cx + 5, cz + 6)
	pois["게 왕의 해변"] = crab_king_home
	# 유적 기둥 장식
	for p in [[-5, 4], [5, 4], [-6, -4], [6, -4]]:
		decor.append({"model": "nature/statue_columnDamaged", "pos": surface(cx + p[0], cz + p[1]), "rot": _rng.randf() * 360.0, "h": 2.2, "collide": true})
	decor.append({"model": "nature/statue_head", "pos": surface(cx - 6, cz + 5), "rot": 200.0, "h": 2.4, "collide": true})
	var used := {}
	for x in range(cx - 8, cx + 9):
		for z in range(cz - 8, cz + 4):
			used[Vector2i(x, z)] = true
	_scatter("ruins", "palm", 4, used, 0)
	_scatter("ruins", "tree", 2, used, 1)
	_scatter("ruins", "bush", 3, used, 1)
	_scatter("ruins", "shell", 4, used, 0, true)


func _seaweed() -> void:
	var shallow: Array = []
	for k: Vector2i in tops:
		if tops[k] == -1 or tops[k] == -2:
			shallow.append(k)
	shallow.sort()
	var used := {}
	var n := 0
	var tries := 0
	while n < 26 and tries < 600:
		tries += 1
		var k: Vector2i = shallow[_rng.randi() % shallow.size()]
		if used.has(k) or _biome.get(k, "") == "bar":
			continue
		used[k] = true
		props.append({"kind": "seaweed", "pos": Vector3(k.x + 0.5, tops[k] + 1, k.y + 0.5)})
		n += 1


func _decorate() -> void:
	var models := ["nature/grass_large", "nature/grass", "nature/flower_redA", "nature/flower_yellowA", "nature/flower_purpleA", "nature/mushroom_redGroup"]
	var taken := {}
	for p in props:
		taken[Vector2i(int(floor(p.pos.x)), int(floor(p.pos.z)))] = true
	for s in structs:
		taken[Vector2i(s.cell.x, s.cell.z)] = true
	var keys := tops.keys()
	keys.sort()
	for k: Vector2i in keys:
		if taken.has(k):
			continue
		var cell := Vector3i(k.x, top(k.x, k.y), k.y)
		if blocks.get(cell, -1) != GRASS:
			continue
		if _rng.randf() < 0.22:
			var m: String = models[_rng.randi() % models.size()]
			decor.append({"model": m, "pos": Vector3(k.x + _rng.randf_range(0.2, 0.8), cell.y + 1, k.y + _rng.randf_range(0.2, 0.8)),
					"rot": _rng.randf() * 360.0, "h": _rng.randf_range(0.25, 0.45), "cell": cell + Vector3i.UP})
