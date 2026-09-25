extends Control
## 화면 위 나침반 바: 동서남북 + 친구 방향(색 삼각형) + 최근 핑

const FOV_DEG := 160.0

var _pings: Array = []   # [pos, color, time]


func add_ping(pos: Vector3, col: Color) -> void:
	_pings.append([pos, col, Time.get_ticks_msec() / 1000.0])


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _bearing_x(from: Vector3, to: Vector3, yaw: float) -> float:
	## 화면 가로 위치 (-1..1 밖이면 안 보임)
	var d := to - from
	var ang := atan2(-d.x, -d.z)            # 북(-Z) = 0, 서쪽이 +
	var rel := wrapf(ang - yaw, -PI, PI)
	return -rel / deg_to_rad(FOV_DEG * 0.5)


func _draw() -> void:
	var g := Game.I
	if g == null or g.local_player == null:
		return
	var me := g.local_player
	var yaw: float = me._yaw
	var w := size.x
	var h := size.y
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.05, 0.03, 0.45))
	var font := Vis.font()
	# 방위
	var dirs := {"북": Vector3(0, 0, -1), "동": Vector3(1, 0, 0), "남": Vector3(0, 0, 1), "서": Vector3(-1, 0, 0)}
	for name in dirs:
		var x := _bearing_x(Vector3.ZERO, dirs[name], yaw)
		if absf(x) <= 1.0:
			var px := (x * 0.5 + 0.5) * w
			var col := Color("ff8a7a") if name == "북" else Color("fff4d8")
			draw_string(font, Vector2(px - 9, h * 0.72), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, col)
	for i in 24:
		var a := i * TAU / 24.0
		var x2 := _bearing_x(Vector3.ZERO, Vector3(-sin(a), 0, -cos(a)), yaw)
		if absf(x2) <= 1.0 and i % 6 != 0:
			var px2 := (x2 * 0.5 + 0.5) * w
			draw_line(Vector2(px2, h * 0.15), Vector2(px2, h * 0.35), Color(1, 1, 1, 0.35), 2.0)
	# 핑
	var now := Time.get_ticks_msec() / 1000.0
	var alive: Array = []
	for p in _pings:
		if now - p[2] < 10.0:
			alive.append(p)
			var xp := _bearing_x(me.global_position, p[0], yaw)
			var pxp := (clampf(xp, -1.0, 1.0) * 0.5 + 0.5) * w
			draw_circle(Vector2(pxp, h * 0.5), 6.0, p[1])
			draw_string(font, Vector2(pxp - 3, h * 0.62), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.BLACK)
	_pings = alive
	# 친구
	for id in g.players:
		var p2: Player = g.players[id]
		if p2 == me:
			continue
		var xf := _bearing_x(me.global_position, p2.global_position, yaw)
		var off := absf(xf) > 1.0
		var pxf := (clampf(xf, -1.0, 1.0) * 0.5 + 0.5) * w
		var col2 := Net.player_color(id)
		if p2.downed:
			col2 = Color("ff4a3a") if int(now * 4.0) % 2 == 0 else Color.WHITE
		var tri := PackedVector2Array([Vector2(pxf, h * 0.95), Vector2(pxf - 7, h * 0.62), Vector2(pxf + 7, h * 0.62)])
		draw_colored_polygon(tri, col2 if not off else Color(col2, 0.55))
		var dist := int(me.global_position.distance_to(p2.global_position))
		if not off:
			draw_string(font, Vector2(pxf + 9, h * 0.98), "%dm" % dist, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.8))
	# 가운데 표시
	draw_line(Vector2(w * 0.5, 0), Vector2(w * 0.5, h * 0.25), Color("ffe08a"), 2.0)
