extends RefCounted
## 테스트 공용: 매끈한 지형에서 알맞은 자리 찾기


static func spot(g: Game, kind: String, near: Vector3, max_r: float = 16.0) -> Vector3:
	## near 근처에서 kind 설치물을 놓을 수 있는 자리 (없으면 INF)
	var r := 0.0
	while r <= max_r:
		var n := maxi(1, int(r * 4.0))
		for i in n:
			var a := i * TAU / n
			var p := Vector3(near.x + cos(a) * r, 0, near.z + sin(a) * r)
			p.y = g.terrain.height_at(p.x, p.z)
			if g.structs.placement_problem(kind, p) == "":
				return p
		r += 0.7
	return Vector3.INF


static func shallow(g: Game, near: Vector3, max_r: float = 30.0) -> Vector3:
	## near 에서 가까운 얕은 물 (메우기 시험용, 물 표면 좌표)
	var r := 0.0
	while r <= max_r:
		var n := maxi(1, int(r * 4.0))
		for i in n:
			var a := i * TAU / n
			var x := near.x + cos(a) * r
			var z := near.z + sin(a) * r
			var hh := g.terrain.height_at(x, z)
			if hh < Terrain.WATER_Y - 0.2 and hh > Terrain.WATER_Y - 1.0:
				return Vector3(x, Terrain.WATER_Y, z)
		r += 0.5
	return Vector3.INF


static func deck_spot(g: Game, near: Vector3, max_r: float = 30.0) -> Vector3:
	## near 근처에서 나무 기초를 깔 수 있는 자리 (기초 윗면 좌표)
	var r := 0.0
	while r <= max_r:
		var n := maxi(1, int(r * 3.0))
		for i in n:
			var a := i * TAU / n
			var q := Vector3(near.x + cos(a) * r, 0, near.z + sin(a) * r)
			var f := Build.free_spot("foundation", q, 0.0, g.terrain)
			if g.structs.parts_near(q, 3.0).is_empty() and g.structs.part_problem("foundation", f.pos, 0.0) == "":
				return f.pos
		r += 1.0
	return Vector3.INF


static func hut(g: Game, near: Vector3) -> Vector3:
	## 기초 한 장 + 기둥 넷 + 지붕 (오두막). 기초 윗면 좌표를 돌려준다
	var p0 := deck_spot(g, near)
	var st := g.structs
	st.req_place.rpc_id(1, "foundation", p0, 0.0, "foundation")
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			st.req_place.rpc_id(1, "pillar", p0 + Vector3(sx, 0, sz) * Build.G * 0.5, 0.0, "pillar")
	st.req_place.rpc_id(1, "roof", p0 + Vector3.UP * Build.H, 0.0, "roof")
	return p0


static func deep(g: Game, near: Vector3, max_r: float = 50.0) -> Vector3:
	## near 에서 가까운 깊은 물 (뗏목·상어 시험용, 물 표면 좌표)
	var r := 0.0
	while r <= max_r:
		var n := maxi(1, int(r * 4.0))
		for i in n:
			var a := i * TAU / n
			var x := near.x + cos(a) * r
			var z := near.z + sin(a) * r
			var ok := true
			for dx in [-1.5, 0.0, 1.5]:
				for dz in [-1.5, 0.0, 1.5]:
					if g.terrain.height_at(x + dx, z + dz) > Terrain.WATER_Y - 1.2:
						ok = false
			if ok:
				return Vector3(x, Terrain.WATER_Y, z)
		r += 1.0
	return Vector3.INF
