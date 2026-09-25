class_name Build
extends RefCounted
## v2 부품 건축: 2m 격자에 기초·바닥·벽·창문벽·문틀벽·계단·지붕·기둥을 붙여 짓는다.
## 부품도 설치물(Structs)의 하나다. 여기선 모양 · 충돌 · 붙는 자리만 계산한다.

const G := 2.0            # 격자 한 칸
const H := 2.2            # 벽 높이
const T := 0.16           # 벽 두께
const ROOF_RISE := 1.15   # 지붕 한 칸이 올라가는 높이 (약 30도)
const LEG_MAX := 3.8      # 기초 다리 최대 길이
const SNAP_R := 1.6       # 이 거리 안의 자리에 착 붙는다
const WOOD := Color("a0764a")
const THATCH := Color("c9a85a")

# 자리 종류: cell(칸: 기초·바닥·지붕), edge(칸 가장자리: 벽들), corner(칸 꼭짓점: 기둥), inner(칸 안: 계단)
const PARTS := {
	"foundation": "cell", "floor": "cell", "roof": "cell",
	"wall": "edge", "window_wall": "edge", "doorway": "edge",
	"pillar": "corner", "stairs": "inner",
}
const WALLS := ["wall", "window_wall", "doorway"]
const DECKS := ["foundation", "floor"]   # 위에 서거나 물건을 놓을 수 있는 칸


static func is_part(kind: String) -> bool:
	return PARTS.has(kind)


# ── 모양 ──

static func visual(kind: String) -> Node3D:
	var n := Node3D.new()
	match kind:
		"foundation":
			_box(n, Vector3(G, 0.3, G), Vector3(0, -0.15, 0), WOOD.darkened(0.1))
			for i in 5:
				_box(n, Vector3(G, 0.02, 0.04), Vector3(0, 0.005, -G * 0.5 + 0.2 + i * 0.4), WOOD.darkened(0.4))
		"floor":
			_box(n, Vector3(G, 0.15, G), Vector3(0, -0.075, 0), WOOD)
			for i in 5:
				_box(n, Vector3(G, 0.02, 0.04), Vector3(0, 0.005, -G * 0.5 + 0.2 + i * 0.4), WOOD.darkened(0.35))
		"wall":
			_box(n, Vector3(G, H, T), Vector3(0, H * 0.5, 0), WOOD)
			for i in 4:
				_box(n, Vector3(G + 0.01, 0.04, T + 0.02), Vector3(0, 0.3 + i * 0.55, 0), WOOD.darkened(0.3))
		"window_wall":
			_box(n, Vector3(G, 0.9, T), Vector3(0, 0.45, 0), WOOD)
			_box(n, Vector3(G, H - 1.6, T), Vector3(0, (1.6 + H) * 0.5, 0), WOOD)
			_box(n, Vector3(0.55, 0.7, T), Vector3(-0.725, 1.25, 0), WOOD)
			_box(n, Vector3(0.55, 0.7, T), Vector3(0.725, 1.25, 0), WOOD)
			_box(n, Vector3(0.9, 0.7, 0.03), Vector3(0, 1.25, 0), Color(0.75, 0.9, 1.0, 0.35))
			_box(n, Vector3(0.04, 0.7, 0.05), Vector3(0, 1.25, 0), WOOD.darkened(0.3))
		"doorway":
			_box(n, Vector3(0.45, H, T), Vector3(-0.775, H * 0.5, 0), WOOD)
			_box(n, Vector3(0.45, H, T), Vector3(0.775, H * 0.5, 0), WOOD)
			_box(n, Vector3(1.1, H - 2.0, T), Vector3(0, 2.0 + (H - 2.0) * 0.5, 0), WOOD)
		"pillar":
			_box(n, Vector3(0.22, H, 0.22), Vector3(0, H * 0.5, 0), WOOD.darkened(0.15))
		"stairs":
			# 앞(-z)에서 뒤(+z)로 올라가는 여섯 칸
			for i in 6:
				var hh := H * (i + 1) / 6.0
				_box(n, Vector3(G * 0.9, hh, G / 6.0), Vector3(0, hh * 0.5, -G * 0.5 + (i + 0.5) * G / 6.0), WOOD.darkened(0.05 * (i % 2)))
		"roof":
			# 앞(-z)이 낮고 뒤(+z)가 높은 야자잎 지붕
			var slab := _box(n, Vector3(G + 0.2, 0.12, _roof_len() + 0.1), Vector3(0, ROOF_RISE * 0.5, 0), THATCH)
			slab.rotation.x = -atan2(ROOF_RISE, G)
			for i in 4:
				var line := _box(n, Vector3(G + 0.22, 0.03, 0.05), Vector3.ZERO, THATCH.darkened(0.3))
				var f := -0.4 + i * 0.27
				line.position = Vector3(0, ROOF_RISE * (0.5 + f) + 0.07, G * f)
				line.rotation.x = slab.rotation.x
	return n


static func legs(pos: Vector3, rot: float, t: Terrain) -> Node3D:
	## 기초 네 귀퉁이 다리 (땅/바다 밑까지)
	var n := Node3D.new()
	var b := Basis(Vector3.UP, rot)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var lo := Vector3(sx * (G * 0.5 - 0.15), 0, sz * (G * 0.5 - 0.15))
			var w := pos + b * lo
			var bottom := t.height_at(w.x, w.z) - 0.3
			var top := pos.y - 0.3
			if top - bottom < 0.05:
				continue
			var leg := _box(n, Vector3(0.18, top - bottom, 0.18), Vector3.ZERO, WOOD.darkened(0.3))
			leg.position = Vector3(lo.x, (top + bottom) * 0.5 - pos.y, lo.z)
	return n


static func shapes(kind: String) -> Array:
	## [[Shape3D, Transform3D], ...] (부품 기준 좌표)
	var out: Array = []
	match kind:
		"foundation":
			out.append(_bs(Vector3(G, 0.3, G), Vector3(0, -0.15, 0)))
		"floor":
			out.append(_bs(Vector3(G, 0.15, G), Vector3(0, -0.075, 0)))
		"wall", "window_wall":
			out.append(_bs(Vector3(G, H, T), Vector3(0, H * 0.5, 0)))
		"doorway":
			out.append(_bs(Vector3(0.45, H, T), Vector3(-0.775, H * 0.5, 0)))
			out.append(_bs(Vector3(0.45, H, T), Vector3(0.775, H * 0.5, 0)))
			out.append(_bs(Vector3(1.1, H - 2.0, T), Vector3(0, 2.0 + (H - 2.0) * 0.5, 0)))
		"pillar":
			out.append(_bs(Vector3(0.22, H, 0.22), Vector3(0, H * 0.5, 0)))
		"stairs":
			var cv := ConvexPolygonShape3D.new()
			var hx := G * 0.45
			cv.points = PackedVector3Array([Vector3(-hx, 0, -G * 0.5), Vector3(hx, 0, -G * 0.5), Vector3(-hx, 0, G * 0.5),
				Vector3(hx, 0, G * 0.5), Vector3(-hx, H, G * 0.5), Vector3(hx, H, G * 0.5)])
			out.append([cv, Transform3D.IDENTITY])
		"roof":
			var bx := BoxShape3D.new()
			bx.size = Vector3(G + 0.2, 0.12, _roof_len() + 0.1)
			out.append([bx, Transform3D(Basis(Vector3.RIGHT, -atan2(ROOF_RISE, G)), Vector3(0, ROOF_RISE * 0.5, 0))])
	return out


static func bounds(kind: String) -> AABB:
	## 사람이 끼는지 볼 때 쓰는 대략의 부피 (부품 기준 좌표)
	match kind:
		"foundation": return AABB(Vector3(-G * 0.5, -0.3, -G * 0.5), Vector3(G, 0.3, G))
		"floor": return AABB(Vector3(-G * 0.5, -0.15, -G * 0.5), Vector3(G, 0.15, G))
		"wall", "window_wall", "doorway": return AABB(Vector3(-G * 0.5, 0, -T * 0.5), Vector3(G, H, T))
		"pillar": return AABB(Vector3(-0.11, 0, -0.11), Vector3(0.22, H, 0.22))
		"stairs": return AABB(Vector3(-G * 0.45, 0, -G * 0.5), Vector3(G * 0.9, H, G))
	return AABB()


# ── 붙는 자리 ──

static func candidates(kind: String, parts: Array) -> Array:
	## 근처 부품들 [{kind, pos, rot}] → kind 가 붙을 수 있는 자리 [{pos, rot, fixed}]
	## fixed: 방향이 정해진 자리 (아니면 내가 보는 쪽으로 90도 단위로 돌린다)
	var out: Array = []
	var slot: String = PARTS.get(kind, "door" if kind == "door" else "")
	for p in parts:
		var pk: String = p.kind
		var pp: Vector3 = p.pos
		var r: float = p.rot
		var b := Basis(Vector3.UP, r)
		if pk in DECKS:
			match slot:
				"cell":
					if kind != "roof":
						for d in [Vector3(G, 0, 0), Vector3(-G, 0, 0), Vector3(0, 0, G), Vector3(0, 0, -G)]:
							out.append({"pos": pp + b * d, "rot": r, "fixed": true})
				"edge":
					out.append({"pos": pp + b * Vector3(G * 0.5, 0, 0), "rot": r + PI * 0.5, "fixed": true})
					out.append({"pos": pp + b * Vector3(-G * 0.5, 0, 0), "rot": r + PI * 0.5, "fixed": true})
					out.append({"pos": pp + b * Vector3(0, 0, G * 0.5), "rot": r, "fixed": true})
					out.append({"pos": pp + b * Vector3(0, 0, -G * 0.5), "rot": r, "fixed": true})
				"corner":
					for sx in [-1.0, 1.0]:
						for sz in [-1.0, 1.0]:
							out.append({"pos": pp + b * Vector3(sx * G * 0.5, 0, sz * G * 0.5), "rot": r, "fixed": true})
				"inner":
					out.append({"pos": pp, "rot": r, "fixed": false})
		elif pk in WALLS:
			var top := pp + Vector3.UP * H
			match slot:
				"edge":
					out.append({"pos": top, "rot": r, "fixed": true})
				"cell":
					if kind == "floor":
						out.append({"pos": top + b * Vector3(0, 0, G * 0.5), "rot": r, "fixed": true})
						out.append({"pos": top + b * Vector3(0, 0, -G * 0.5), "rot": r, "fixed": true})
					elif kind == "roof":
						# 벽에서 안쪽으로 올라가게
						out.append({"pos": top + b * Vector3(0, 0, G * 0.5), "rot": r, "fixed": true})
						out.append({"pos": top + b * Vector3(0, 0, -G * 0.5), "rot": r + PI, "fixed": true})
				"door":
					if pk == "doorway":
						out.append({"pos": pp, "rot": r, "fixed": true})
		elif pk == "pillar":
			var top2 := pp + Vector3.UP * H
			match slot:
				"corner":
					out.append({"pos": top2, "rot": r, "fixed": true})
				"cell":
					if kind != "foundation":
						for sx in [-1.0, 1.0]:
							for sz in [-1.0, 1.0]:
								out.append({"pos": top2 + b * Vector3(sx * G * 0.5, 0, sz * G * 0.5), "rot": r, "fixed": kind != "roof"})
		elif pk == "roof" and kind == "roof":
			out.append({"pos": pp + b * Vector3(G, 0, 0), "rot": r, "fixed": true})
			out.append({"pos": pp + b * Vector3(-G, 0, 0), "rot": r, "fixed": true})
			out.append({"pos": pp + b * Vector3(0, 0, G), "rot": r + PI, "fixed": true})   # 맞은편 (용마루)
	return out


static func find_snap(kind: String, aim: Vector3, want_rot: float, parts: Array) -> Dictionary:
	## 조준점에 가장 가까운 붙는 자리 (없으면 {})
	var best := {}
	var bd := SNAP_R
	for c in candidates(kind, parts):
		var d: float = anchor(kind, c.pos).distance_to(aim)
		if d < bd:
			bd = d
			best = c
	if best.is_empty():
		return {}
	var rot: float = best.rot
	if not best.fixed:
		rot += roundi(angle_difference(rot, want_rot) / (PI * 0.5)) * PI * 0.5
	return {"pos": best.pos, "rot": fposmod(rot, TAU)}


static func anchor(kind: String, pos: Vector3) -> Vector3:
	## 조준점과 비교할 부품의 한가운데
	match PARTS.get(kind, ""):
		"edge", "corner", "inner":
			return pos + Vector3.UP * H * 0.5
	if kind == "door":
		return pos + Vector3.UP * 1.0
	return pos


static func free_spot(kind: String, hit: Vector3, want_rot: float, t: Terrain) -> Dictionary:
	## 붙일 데가 없을 때 땅(또는 물)에 바로 세우기. 기초·기둥·계단만 된다
	match kind:
		"foundation":
			var p := Vector3(hit.x, 0, hit.z)
			p.y = foundation_top(p, want_rot, t)
			return {"pos": p, "rot": want_rot}
		"pillar", "stairs":
			return {"pos": Vector3(hit.x, t.height_at(hit.x, hit.z), hit.z), "rot": want_rot}
	return {}


static func ground_range(pos: Vector3, rot: float, t: Terrain) -> Vector2:
	## 기초 발자국 아래 땅 높이 (최저, 최고)
	var b := Basis(Vector3.UP, rot)
	var lo := 99.0
	var hi := -99.0
	for o in [Vector3.ZERO, Vector3(0.45, 0, 0.45), Vector3(-0.45, 0, 0.45), Vector3(0.45, 0, -0.45), Vector3(-0.45, 0, -0.45)]:
		var q: Vector3 = pos + b * (o * G)
		var hh := t.height_at(q.x, q.z)
		lo = minf(lo, hh)
		hi = maxf(hi, hh)
	return Vector2(lo, hi)


static func foundation_top(pos: Vector3, rot: float, t: Terrain) -> float:
	## 땅 위면 가장 높은 곳 + 두께, 물 위면 수면보다 조금 위
	return maxf(ground_range(pos, rot, t).y + 0.3, Terrain.WATER_Y + 0.5)


static func _roof_len() -> float:
	return sqrt(G * G + ROOF_RISE * ROOF_RISE)


static func _box(parent: Node3D, size: Vector3, pos: Vector3, c: Color) -> MeshInstance3D:
	var b := Vis.box(size, c)
	b.position = pos
	parent.add_child(b)
	return b


static func _bs(size: Vector3, pos: Vector3) -> Array:
	var bx := BoxShape3D.new()
	bx.size = size
	return [bx, Transform3D(Basis.IDENTITY, pos)]
