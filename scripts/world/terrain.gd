class_name Terrain
extends GridMap
## 블록 세계. 부수기/놓기는 호스트가 확인하고 모두에게 알린다.

signal block_changed(cell: Vector3i, t: int)

const WATER_Y := 0.7
const EMPTY := -1

var base := {}      # 생성기가 만든 원래 블록
var diff := {}      # 바뀐 것만: Vector3i -> int (EMPTY = 파냄)
var _tops := {}     # Vector2i -> int 캐시
var placed_count := 0


func setup_library() -> void:
	var lib := MeshLibrary.new()
	for i in Items.BLOCKS.size():
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE
		bm.material = Vis.block_material(i)
		lib.create_item(i)
		lib.set_item_mesh(i, bm)
		lib.set_item_name(i, Items.BLOCKS[i].id)
		var sh := BoxShape3D.new()
		sh.size = Vector3.ONE
		lib.set_item_shapes(i, [sh, Transform3D.IDENTITY])
	mesh_library = lib
	cell_size = Vector3.ONE
	collision_layer = 1
	collision_mask = 0


func build(gen_blocks: Dictionary, diff_arr: PackedInt32Array) -> void:
	setup_library()
	clear()
	base = gen_blocks
	diff = {}
	_tops.clear()
	for c: Vector3i in base:
		set_cell_item(c, base[c])
	var i := 0
	while i + 3 < diff_arr.size():
		var c := Vector3i(diff_arr[i], diff_arr[i + 1], diff_arr[i + 2])
		_apply(c, diff_arr[i + 3])
		i += 4


func diff_array() -> PackedInt32Array:
	var out := PackedInt32Array()
	for c: Vector3i in diff:
		out.append_array([c.x, c.y, c.z, diff[c]])
	return out


func get_block(c: Vector3i) -> int:
	return get_cell_item(c)


func is_solid(c: Vector3i) -> bool:
	return get_cell_item(c) != EMPTY


func top_y(x: int, z: int) -> int:
	var k := Vector2i(x, z)
	if _tops.has(k):
		return _tops[k]
	var t := -99
	for y in range(16, WorldGen.BOTTOM - 2, -1):
		if get_cell_item(Vector3i(x, y, z)) != EMPTY:
			t = y
			break
	_tops[k] = t
	return t


func ground_at(pos: Vector3) -> float:
	## 해당 위치 발밑 땅 높이 (위에서부터 pos.y 아래 첫 블록). 없으면 -99
	var x := int(floor(pos.x))
	var z := int(floor(pos.z))
	for y in range(int(floor(pos.y)), WorldGen.BOTTOM - 2, -1):
		if get_cell_item(Vector3i(x, y, z)) != EMPTY:
			return y + 1.0
	return -99.0


func is_water_column(x: int, z: int) -> bool:
	return top_y(x, z) < 0


func cell_of(p: Vector3) -> Vector3i:
	return Vector3i(int(floor(p.x)), int(floor(p.y)), int(floor(p.z)))


func _apply(c: Vector3i, t: int) -> void:
	set_cell_item(c, t)
	_tops.erase(Vector2i(c.x, c.z))
	if base.get(c, EMPTY) == t:
		diff.erase(c)
	else:
		diff[c] = t
	block_changed.emit(c, t)


# ── 네트워크 ──

@rpc("any_peer", "call_local", "reliable")
func req_break(c: Vector3i) -> void:
	if not multiplayer.is_server():
		return
	var from := multiplayer.get_remote_sender_id()
	var t := get_cell_item(c)
	if t == EMPTY:
		return
	var b := Items.block(t)
	if b.hard < 0:
		return
	if Game.I.occupied_by_struct(c + Vector3i.UP) != "":
		Game.I.toast_to(from, "위에 뭔가 놓여 있어서 못 부숴!")
		return
	_set_block.rpc(c, EMPTY)
	if not base.has(c):
		Game.I.quests.on_block_removed()   # 사람이 놓은 블록을 부수면 "섬 넓히기" 에서 빠진다
	if b.drop != "":
		Game.I.give_to(from, b.drop, b.get("drop_n", 1))
	Game.I.stat_add("blocks_broken", 1)


@rpc("any_peer", "call_local", "reliable")
func req_place(c: Vector3i, t: int, item_id: String) -> void:
	if not multiplayer.is_server():
		return
	var from := multiplayer.get_remote_sender_id()
	var ok := get_cell_item(c) == EMPTY and c.y >= WorldGen.BOTTOM and c.y < 16
	ok = ok and Game.I.occupied(c) == "" and not Game.I.player_in_cell(c)
	if ok:
		_set_block.rpc(c, t)
		placed_count += 1
		Game.I.stat_add("blocks_placed", 1)
		Game.I.quests.on_block_placed()
	else:
		Game.I.give_to(from, item_id, 1)


@rpc("authority", "call_local", "reliable")
func _set_block(c: Vector3i, t: int) -> void:
	var old := get_cell_item(c)
	_apply(c, t)
	var pos := Vector3(c) + Vector3(0.5, 0.5, 0.5)
	if t == EMPTY and old != EMPTY:
		Game.I.fx_break(pos, Items.block(old).color)
		var snd := "dig"
		match Items.block(old).get("tool", ""):
			"pick": snd = "mine"
			"axe": snd = "chop"
		Audio.play_at(snd, pos)
	elif t != EMPTY:
		Audio.play_at("place", pos, -2.0)


func set_block_server(c: Vector3i, t: int) -> void:
	## 호스트 전용: 문 열기 같은 이벤트용
	if multiplayer.is_server():
		_set_block.rpc(c, t)
