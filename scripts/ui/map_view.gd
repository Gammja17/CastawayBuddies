extends Control
## 지도 [M]: 블록 윗면 색으로 그린 섬 지도 + 친구 위치 + 핑.

const HALF := 64
const SCALE := 5.5

var _tex: ImageTexture
var _pings: Array = []   # [pos, color, time]


func rebuild_if_dirty() -> void:
	var hud: Hud = Game.I.hud if Game.I else null
	if hud == null:
		return
	if hud.map_dirty or _tex == null:
		hud.map_dirty = false
		_rebuild()
	queue_redraw()


func _rebuild() -> void:
	var t := Game.I.terrain
	var img := Image.create(HALF * 2, HALF * 2, false, Image.FORMAT_RGB8)
	for z in range(-HALF, HALF):
		for x in range(-HALF, HALF):
			var top := t.top_y(x, z)
			var c: Color
			if top < -50:
				c = Color("2a6f9e")
			elif top < 0:
				c = Color("3e9cc2") if top == -1 else Color("3486b0")
			else:
				var b := t.get_block(Vector3i(x, top, z))
				c = Items.block(b).get("color", Color.MAGENTA)
				c.a = 1.0
				c = c.lightened(clampf(top * 0.05, 0.0, 0.3))
			img.set_pixel(x + HALF, z + HALF, c)
	_tex = ImageTexture.create_from_image(img)


func add_ping(pos: Vector3, col: Color) -> void:
	_pings.append([pos, col, Time.get_ticks_msec() / 1000.0])


func _to_map(p: Vector3) -> Vector2:
	var origin := (size - Vector2.ONE * HALF * 2 * SCALE) * 0.5
	return origin + (Vector2(p.x, p.z) + Vector2.ONE * HALF) * SCALE


func _draw() -> void:
	if _tex == null or Game.I == null:
		return
	var origin := (size - Vector2.ONE * HALF * 2 * SCALE) * 0.5
	var r := Rect2(origin, Vector2.ONE * HALF * 2 * SCALE)
	draw_texture_rect(_tex, r, false)
	draw_rect(r, Color("5a3a1e"), false, 4.0)
	var font := Vis.font()
	var gen := Game.I.gen
	for poi in gen.pois:
		if poi == "보물?" and not Game.I.quests.flag("treasure_map"):
			continue
		var mp := _to_map(gen.pois[poi])
		if poi == "보물?":
			draw_line(mp + Vector2(-7, -7), mp + Vector2(7, 7), Color("d8201a"), 4.0)
			draw_line(mp + Vector2(-7, 7), mp + Vector2(7, -7), Color("d8201a"), 4.0)
		else:
			var w := font.get_string_size(poi, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
			draw_string_outline(font, mp + Vector2(-w * 0.5, -10), poi, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 6, Color(0, 0, 0, 0.8))
			draw_string(font, mp + Vector2(-w * 0.5, -10), poi, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("fff4d8"))
	# 설치물 중 중요한 것
	for id in Game.I.structs.list:
		var s: Dictionary = Game.I.structs.list[id]
		if s.kind in ["bed", "campfire", "shipyard", "totem", "chest"]:
			var mp2 := _to_map(Vector3(s.cell.x + 0.5, 0, s.cell.z + 0.5))
			draw_rect(Rect2(mp2 - Vector2(3, 3), Vector2(6, 6)), Color("ffcf4a") if s.kind != "bed" else Color("ff8ac8"))
	# 기절하며 떨군 가방
	for pid in Game.I.ents.pickups:
		var pk: Dictionary = Game.I.ents.pickups[pid]
		if pk.items.size() > 1 or pk.get("keep", false):
			var bp := _to_map(pk.pos)
			draw_circle(bp, 7.0, Color("5a3a1e"))
			draw_circle(bp, 4.5, Color("c7a86b"))
			draw_string_outline(font, bp + Vector2(9, 5), "가방", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 5, Color(0, 0, 0, 0.8))
			draw_string(font, bp + Vector2(9, 5), "가방", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("ffe08a"))
	var now := Time.get_ticks_msec() / 1000.0
	var alive: Array = []
	for p in _pings:
		if now - p[2] < 8.0:
			alive.append(p)
			var mp3 := _to_map(p[0])
			draw_circle(mp3, 6.0 + fmod(now * 8.0, 8.0), Color(p[1], 0.5))
			draw_circle(mp3, 4.0, p[1])
	_pings = alive
	for pid in Game.I.players:
		var pl: Player = Game.I.players[pid]
		var mp4 := _to_map(pl.global_position)
		var col := Net.player_color(pid)
		var fwd := Vector2(-sin(pl.model.rotation.y), -cos(pl.model.rotation.y))
		draw_colored_polygon(PackedVector2Array([mp4 + fwd * 11, mp4 + fwd.rotated(2.5) * 8, mp4 + fwd.rotated(-2.5) * 8]), col)
		draw_polyline(PackedVector2Array([mp4 + fwd * 11, mp4 + fwd.rotated(2.5) * 8, mp4 + fwd.rotated(-2.5) * 8, mp4 + fwd * 11]), Color.BLACK, 2.0)
		var nm := Net.player_name(pid)
		draw_string_outline(font, mp4 + Vector2(10, 4), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 5, Color(0, 0, 0, 0.8))
		draw_string(font, mp4 + Vector2(10, 4), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col)
