class_name Player
extends CharacterBody3D
## 캐릭터. 내 캐릭터는 직접 움직이고, 남의 캐릭터는 받은 위치를 따라간다.

const WALK := 4.3
const SPRINT := 6.8
const SWIM := 2.9
const WADE := 3.2
const JUMP := 7.4
const GRAVITY := 20.0
const REACH := 4.6
const MAX_STAT := 100.0
const BLEED_TIME := 30.0
const REVIVE_TIME := 2.2
const FISH_RANGE := 14.0

var peer_id := 1
var is_local := false
var inv := Inventory.new()
var hotbar_i := 0
var held_id := ""
var hp := MAX_STAT
var hunger := MAX_STAT
var thirst := MAX_STAT
var downed := false
var sleeping := false
var swimming := false
var deep_time := 0.0
var spawn_point := Vector3.ZERO
var first_person := false
var riding := -1              # 타고 있는 뗏목 id
var _ride_seat := 0
var _ride_send_t := 0.0
var _last_ride_input := Vector2.ZERO
var _ride_paddle := false
var _salt_confirm := -10.0
var _wave_t := 0.0

# 조준
var target := {}              # {"type": "block"/"prop"/"struct", ...}
var water_point := Vector3.INF
var _break_cell := Vector3i(999, 999, 999)
var _break_dmg := 0.0
var _struct_hits := {}
var _swing_cd := 0.0
var _use_cd := 0.0
var _swing_count := 0
var _yaw := 0.0
var _pitch := -0.2
var _bleed := 0.0
var _revive_t := 0.0
var _revive_target: Player = null
var _step_acc := 0.0
var _was_in_water := false
var _net_t := 0.0
var _jump_cd := 0.0
var _hurt_flash := 0.0
var _say_t := 0.0

# 원격
var _r_pos := Vector3.ZERO
var _r_yaw := 0.0
var _r_flags := 0
var _r_swing := 0
var _anim_t := 0.0
var _swing_anim := 0.0
var _last_pos := Vector3.ZERO

# 낚시
var _fish_state := ""      # "", "wait", "bite"
var _fish_t := 0.0
var _bobber: Node3D
var _line: MeshInstance3D

@onready var model: Node3D = $Model
@onready var arm_r: Node3D = $Model/ArmR
@onready var arm_l: Node3D = $Model/ArmL
@onready var leg_l: Node3D = $Model/LegL
@onready var leg_r: Node3D = $Model/LegR
@onready var hand: Node3D = $Model/ArmR/Hand
@onready var head: Node3D = $Model/Head
@onready var cam_yaw: Node3D = $CamYaw
@onready var cam_pitch: Node3D = $CamYaw/CamPitch
@onready var spring: SpringArm3D = $CamYaw/CamPitch/Arm
@onready var camera: Camera3D = $CamYaw/CamPitch/Arm/Camera
@onready var name_tag: Label3D = $NameTag
@onready var say_label: Label3D = $Say
@onready var torch_light: OmniLight3D = $TorchLight

var _highlight: MeshInstance3D
var _ghost: Node3D
var _ghost_key := ""
var _crack: MeshInstance3D


func _ready() -> void:
	var col := Net.player_color(peer_id)
	var shirt: StandardMaterial3D = $Model/Body.get_surface_override_material(0).duplicate()
	shirt.albedo_color = col
	$Model/Body.set_surface_override_material(0, shirt)
	name_tag.text = Net.player_name(peer_id)
	name_tag.modulate = col.lightened(0.3)
	# 모자 (엔딩 보상)
	var hat: String = Net.players.get(peer_id, {}).get("hat", "straw")
	if hat != "straw":
		$Model/Head/Brim.visible = false
		$Model/Head/Crown.visible = false
		if hat != "none":
			var hn := Vis.hat_node(hat)
			hn.position.y = 0.44
			head.add_child(hn)
	_r_pos = global_position
	_last_pos = global_position
	if peer_id != Net.my_id():
		$Shape.disabled = true   # 남의 몸은 충돌 안 함 (위치만 따라감)
		cam_yaw.queue_free()
	inv.changed.connect(_on_inv_changed)


func make_local(saved: Dictionary) -> void:
	is_local = true
	name_tag.visible = false
	camera.current = true
	camera.fov = Settings.fov
	spring.add_excluded_object(get_rid())
	spawn_point = saved.get("spawn", Game.I.gen.spawn)
	if saved.has("inv"):
		inv.from_array(saved.inv)
	hp = saved.get("hp", MAX_STAT)
	hunger = saved.get("hunger", MAX_STAT)
	thirst = saved.get("thirst", MAX_STAT)
	hotbar_i = saved.get("hot", 0)
	if hp <= 0:
		hp = 50
	_highlight = _make_highlight()
	Game.I.fx_root.add_child(_highlight)
	_crack = Vis.mesh_node(_box_mesh(1.01), Vis.crack_material(0))
	_crack.visible = false
	Game.I.fx_root.add_child(_crack)
	_yaw = rotation.y
	if not saved.has("pos"):
		_yaw = PI * 0.5   # 처음엔 떠밀려온 상자 쪽(서쪽)을 본다
		model.rotation.y = _yaw
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_on_inv_changed()


func save_data() -> Dictionary:
	return {"inv": inv.to_array(), "hp": hp, "hunger": hunger, "thirst": thirst, "pos": world_pos(), "spawn": spawn_point, "hot": hotbar_i}


func remote_save_hint(old: Dictionary) -> Dictionary:
	## 남의 캐릭터: 그 사람이 마지막으로 알려 준 좌표 (엔딩 연출로 움직인 화면 좌표 말고)
	var d := old.duplicate()
	d.pos = _r_pos
	return d


func world_pos() -> Vector3:
	## 엔딩 연출로 세계가 통째로 움직여도 원래 좌표로 저장
	return global_position - get_parent().position if get_parent() is Node3D else global_position


func _box_mesh(s: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3.ONE * s
	return b


func _make_highlight() -> MeshInstance3D:
	var im := ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.material_override = Vis.mat(Color(0, 0, 0, 0.8), true)
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var s := 1.004
	var o := -0.002
	var c := [Vector3(o, o, o), Vector3(s, o, o), Vector3(s, o, s), Vector3(o, o, s), Vector3(o, s, o), Vector3(s, s, o), Vector3(s, s, s), Vector3(o, s, s)]
	for e in [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4], [0, 4], [1, 5], [2, 6], [3, 7]]:
		im.surface_add_vertex(c[e[0]])
		im.surface_add_vertex(c[e[1]])
	im.surface_end()
	mi.visible = false
	return mi


# ═════════ 입력 ═════════

func _unhandled_input(event: InputEvent) -> void:
	if not is_local or Game.I.ending_playing:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var s: float = Settings.sensitivity * 0.01
		_yaw -= event.relative.x * s
		_pitch -= event.relative.y * s * (-1.0 if Settings.invert_y else 1.0)
		_pitch = clampf(_pitch, -1.45, 1.35)
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_select_slot((hotbar_i + 8) % 9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_select_slot((hotbar_i + 1) % 9)
	for i in 9:
		if event.is_action_pressed("slot_%d" % (i + 1)):
			_select_slot(i)
	if event.is_action_pressed("camera"):
		first_person = not first_person
	if event.is_action_pressed("drop"):
		_drop_held(Input.is_key_pressed(KEY_CTRL))
	if event.is_action_pressed("secondary"):
		_secondary()
	if event.is_action_pressed("interact"):
		_interact_press()
	if event.is_action_pressed("ping") or event.is_action_pressed("ping_mouse"):
		_ping()
	if event.is_action_pressed("wave"):
		_wave_t = 1.6


func _select_slot(i: int) -> void:
	if i == hotbar_i:
		return
	hotbar_i = i
	_cancel_fishing()
	_break_dmg = 0.0
	_on_inv_changed()
	Audio.play("click", -12.0)


func _on_inv_changed() -> void:
	var s = inv.slots[hotbar_i]
	var id: String = s.id if s != null else ""
	if id != held_id:
		held_id = id
		_update_held_visual()
		if _fish_state != "" and held_id != "fishing_rod":
			_cancel_fishing()
	if is_local and Game.I and Game.I.hud:
		Game.I.hud.refresh_inventory()


func _update_held_visual() -> void:
	for c in hand.get_children():
		c.queue_free()
	torch_light.visible = held_id == "torch"
	if held_id == "":
		return
	var tool := Items.tool_of(held_id)
	var size := 0.34
	if not tool.is_empty():
		size = 0.75 if tool.kind in ["spear", "rod", "hook"] else 0.55
	if Items.item(held_id).has("block"):
		size = 0.3
	var n := Vis.item_node(held_id, size)
	hand.add_child(n)
	if not tool.is_empty() and tool.kind != "torch":
		n.position = Vector3(0, size * 0.35, 0)


# ═════════ 물리 ═════════

func _physics_process(delta: float) -> void:
	if not is_local:
		_remote_update(delta)
		return
	if Game.I == null or not Game.I.world_ready or Game.I.ending_playing:
		return
	var t := Game.I.terrain
	var ui_block: bool = Game.I.hud.blocks_game_input()
	var input := Vector2.ZERO
	if not ui_block and not downed and not sleeping:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if riding >= 0:
		_ride_update(delta, input, ui_block)
		_update_stats(delta, false)
		_update_camera(delta)
		_update_target()
		_update_actions(delta)
		_animate(delta, 0.0, false, true)
		_send_state(delta)
		return
	var feet := global_position.y
	var ground := t.ground_at(global_position + Vector3.UP * 0.5)
	var in_water := feet < Terrain.WATER_Y - 0.1 and ground < Terrain.WATER_Y - 0.2
	swimming = feet < Terrain.WATER_Y - 0.55 and ground < Terrain.WATER_Y - 1.0
	if swimming and t.top_y(int(floor(global_position.x)), int(floor(global_position.z))) < -1:
		deep_time += delta
	else:
		deep_time = 0.0
	if in_water and not _was_in_water and velocity.y < -2.0:
		Audio.play_at("splash", global_position)
		Game.I.fx_splash(global_position)
	_was_in_water = in_water
	var sprint := Input.is_action_pressed("sprint") and hunger > 5.0 and not swimming and input.length() > 0.1
	var speed := WALK
	if swimming:
		speed = SWIM
	elif in_water:
		speed = WADE
	elif sprint:
		speed = SPRINT
	if downed:
		speed = 0.0
	var basis_y := Basis(Vector3.UP, _yaw)
	var dir := basis_y * Vector3(input.x, 0, input.y)
	var accel := 12.0 if is_on_floor() or swimming else 4.0
	velocity.x = move_toward(velocity.x, dir.x * speed, accel * speed * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, accel * speed * delta)
	_jump_cd = maxf(0.0, _jump_cd - delta)
	if swimming:
		var target_feet := Terrain.WATER_Y - 1.0
		velocity.y = move_toward(velocity.y, (target_feet - feet) * 3.0, 14.0 * delta)
		var hop := dir.length() > 0.1 and _ledge_ahead(dir, int(floor(Terrain.WATER_Y)))
		if (Input.is_action_pressed("jump") and not ui_block or hop) and _jump_cd <= 0.0 and not downed:
			velocity.y = JUMP * 0.95
			_jump_cd = 0.7
	else:
		velocity.y -= GRAVITY * delta * (0.6 if in_water else 1.0)
		if is_on_floor() and not downed and _jump_cd <= 0.0:
			if Input.is_action_pressed("jump") and not ui_block:
				velocity.y = JUMP
				_jump_cd = 0.25
			elif dir.length() > 0.1 and _ledge_ahead(dir, int(floor(feet + 0.2))):
				# 한 칸 턱은 알아서 폴짝
				velocity.y = JUMP
				_jump_cd = 0.35
	move_and_slide()
	if global_position.y < -25.0:
		global_position = spawn_point
		velocity = Vector3.ZERO
	# 발소리
	if is_on_floor() and Vector2(velocity.x, velocity.z).length() > 1.0 and not in_water:
		_step_acc += Vector2(velocity.x, velocity.z).length() * delta
		if _step_acc > 1.9:
			_step_acc = 0.0
			Audio.play_at(_step_sound(), global_position, -10.0)
	_update_stats(delta, sprint)
	_update_camera(delta)
	_update_target()
	_update_actions(delta)
	_animate(delta, Vector2(velocity.x, velocity.z).length(), swimming, is_on_floor())
	_send_state(delta)


# ═════════ 뗏목 ═════════

func start_ride(id: int, seat: int) -> void:
	var first := riding != id
	riding = id
	_ride_seat = seat
	velocity = Vector3.ZERO
	if first:
		_cancel_fishing()
		Game.I.hud.toast("뗏목에 탔다! W/S 노 젓기 / A/D 방향 / E 또는 Space 내리기\n같이 저으면 더 빠르다", Color("a8e4ff"))


func stop_ride() -> void:
	if riding < 0:
		return
	var sp := Game.I.ents.raft_seat_pos(riding, _ride_seat)
	riding = -1
	if sp != Vector3.INF:
		global_position = Game.I.safe_spot(sp + Vector3.UP * 0.5)
	velocity = Vector3.UP * 3.0


func _ride_update(delta: float, input: Vector2, ui_block: bool) -> void:
	var sp := Game.I.ents.raft_seat_pos(riding, _ride_seat)
	if sp == Vector3.INF:
		riding = -1
		return
	global_position = sp
	velocity = Vector3.ZERO
	swimming = false
	deep_time = 0.0
	if Input.is_action_just_pressed("jump") and not ui_block and not downed:
		Game.I.ents.req_raft_leave.rpc_id(1, riding)
	_ride_send_t -= delta
	if _ride_send_t <= 0.0 or input.distance_to(_last_ride_input) > 0.2:
		_ride_send_t = 0.1
		_last_ride_input = input
		_ride_paddle = input.length() > 0.1
		Game.I.ents.req_raft_input.rpc_id(1, riding, input)


func _ledge_ahead(dir: Vector3, base_y: int) -> bool:
	## 앞에 딱 한 칸짜리 턱이 있고 그 위 두 칸이 비었나
	var t := Game.I.terrain
	var ahead := global_position + dir.normalized() * 0.55
	var c := Vector3i(int(floor(ahead.x)), base_y, int(floor(ahead.z)))
	return t.is_solid(c) and not t.is_solid(c + Vector3i.UP) and not t.is_solid(c + Vector3i.UP * 2) \
			and not t.is_solid(t.cell_of(global_position) + Vector3i.UP * 2)


func _step_sound() -> String:
	var t := Game.I.terrain
	var below := t.get_block(t.cell_of(global_position + Vector3.DOWN * 0.1))
	var id: String = Items.block(below).get("id", "")
	match id:
		"grass", "dirt", "leaf_block", "thatch_block": return "step_grass"
		"plank_block", "log_block": return "step_wood"
		"stone", "stone_block", "brick_block", "ancient", "iron_ore", "sandstone": return "step_stone"
	return "step_sand"


func _update_stats(delta: float, sprint: bool) -> void:
	if downed:
		_bleed -= delta
		Game.I.hud.set_downed(true, _bleed)
		if _bleed <= 0.0:
			_faint()
		return
	var mult: float = (0.5 if sleeping else 1.0) * Game.DIFFS[Game.I.difficulty].drain
	hunger = maxf(0.0, hunger - delta * MAX_STAT / 900.0 * mult * (1.6 if sprint else 1.0))
	thirst = maxf(0.0, thirst - delta * MAX_STAT / 600.0 * mult * (1.4 if sprint else 1.0) * (1.15 if not Game.I.clock.is_night() else 0.9))
	if hunger <= 0.0:
		hp -= delta * 0.8
	if thirst <= 0.0:
		hp -= delta * 1.1
	if hunger > 45.0 and thirst > 45.0 and hp < MAX_STAT:
		hp = minf(MAX_STAT, hp + delta * 0.6)
	if hp <= 0.0:
		_go_down()


func _update_camera(delta: float) -> void:
	cam_yaw.rotation.y = _yaw
	cam_pitch.rotation.x = _pitch
	var target_len := 0.0 if first_person else 3.4
	spring.spring_length = lerpf(spring.spring_length, target_len, clampf(delta * 10.0, 0, 1))
	spring.position.x = lerpf(spring.position.x, 0.0 if first_person else 0.55, clampf(delta * 10.0, 0, 1))
	model.visible = spring.spring_length > 0.6 or sleeping or downed
	camera.h_offset = 0.0
	camera.position = Game.I.camera_shake_offset(delta)
	if not downed and not sleeping:
		model.rotation.y = lerp_angle(model.rotation.y, _yaw, clampf(delta * 12.0, 0, 1))
	Game.I.hud.set_underwater(camera.global_position.y < Terrain.WATER_Y - 0.05)


# ═════════ 조준 ═════════

func eye_pos() -> Vector3:
	return global_position + Vector3.UP * 1.55


func look_dir() -> Vector3:
	return -camera.global_basis.z


func _update_target() -> void:
	target = {}
	water_point = Vector3.INF
	var from := camera.global_position
	var dir := look_dir()
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * (REACH + spring.spring_length + 1.0), 1 | 2 | 32)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	var eye := eye_pos()
	if not hit.is_empty() and hit.position.distance_to(eye) <= REACH:
		var col: Object = hit.collider
		var n: Vector3 = hit.normal
		if col is GridMap:
			var cell: Vector3i = Game.I.terrain.cell_of(hit.position - n * 0.5)
			var place: Vector3i = Game.I.terrain.cell_of(hit.position + n * 0.5)
			target = {"type": "block", "cell": cell, "place": place, "normal": n, "pos": hit.position}
		elif col.has_meta("prop"):
			target = {"type": "prop", "id": col.get_meta("prop"), "pos": hit.position}
		elif col.has_meta("raft"):
			target = {"type": "raft", "id": col.get_meta("raft"), "pos": hit.position}
		elif col.has_meta("struct"):
			var sid: int = col.get_meta("struct")
			var sc: Vector3i = Game.I.structs.list.get(sid, {}).get("cell", Vector3i.ZERO)
			target = {"type": "struct", "id": sid, "pos": hit.position, "normal": n, "cell": sc, "place": sc + Vector3i(roundi(n.x), 0 if n.y < 0.5 else 1, roundi(n.z))}
	# 물 표면
	if dir.y < -0.01:
		var tt := (Terrain.WATER_Y - from.y) / dir.y
		if tt > 0.0:
			var wp := from + dir * tt
			var hit_d: float = from.distance_to(hit.position) if not hit.is_empty() else INF
			if tt < hit_d:
				water_point = wp
	_update_highlight()


func _update_highlight() -> void:
	var show_cell := Vector3i(999, 999, 999)
	if target.get("type", "") == "block":
		show_cell = target.cell
	if show_cell.x != 999:
		_highlight.visible = true
		_highlight.global_position = Vector3(show_cell)
	else:
		_highlight.visible = false
	if _break_cell != show_cell:
		_break_dmg = 0.0
		_crack.visible = false
	# 설치 미리보기
	var key := ""
	var place := _placement()
	if not place.is_empty():
		key = held_id
	if key != _ghost_key:
		_ghost_key = key
		if _ghost:
			_ghost.queue_free()
			_ghost = null
		if key != "":
			if Items.item(key).has("block"):
				_ghost = Vis.block_node(Items.block_id(key), 1.0)
				_ghost.transparency = 0.6
			else:
				var sk := Items.struct_of(key)
				var def: Dictionary = Items.STRUCTS.get(sk, {})
				if def.has("model"):
					_ghost = Vis.fit_model(def.model, Structs.MODEL_H.get(sk, 1.0))
				else:
					_ghost = Vis.make(def.get("vis", {}))
				for mi in _ghost.find_children("*", "MeshInstance3D", true, false):
					(mi as MeshInstance3D).transparency = 0.55
			Game.I.fx_root.add_child(_ghost)
	if _ghost:
		if place.is_empty():
			_ghost.visible = false
		else:
			_ghost.visible = true
			var c: Vector3i = place.cell
			if place.kind == "block":
				_ghost.global_position = Vector3(c) + Vector3(0.5, 0.5, 0.5)
			else:
				_ghost.global_position = Vector3(c.x + 0.5, c.y, c.z + 0.5)
				_ghost.rotation.y = _rot_index() * PI * 0.5


func _rot_index() -> int:
	return int(round(fposmod(_yaw + PI, TAU) / (PI * 0.5))) % 4


func _placement() -> Dictionary:
	## 지금 우클릭하면 어디에 놓이는지
	if held_id == "":
		return {}
	var item := Items.item(held_id)
	var t := Game.I.terrain
	if item.has("block"):
		var c := Vector3i(999, 999, 999)
		var tkind: String = Game.I.structs.kind_of(target.id) if target.get("type", "") == "struct" else ""
		if tkind == "plate":
			c = target.cell   # 압력판 위에 블록을 올리면 그 칸에 들어간다 (눌림)
		elif target.get("type", "") == "block" or (tkind != "" and target.normal.y > 0.5):
			c = target.place
		elif water_point != Vector3.INF and water_point.distance_to(eye_pos()) <= REACH + 0.5:
			c = Vector3i(int(floor(water_point.x)), 0, int(floor(water_point.z)))
			while c.y > WorldGen.BOTTOM and not t.is_solid(c + Vector3i.DOWN) and not _has_side_neighbor(c):
				c.y -= 1
			if not _has_side_neighbor(c) and not t.is_solid(c + Vector3i.DOWN):
				return {}
		if c.x == 999 or t.is_solid(c):
			return {}
		if Game.I.player_in_cell(c) or Game.I.occupied(c) != "":
			return {}
		return {"kind": "block", "cell": c}
	var sk: String = item.get("struct", "")
	if sk != "" and target.get("type", "") == "block" and target.normal.y > 0.5:
		var c2: Vector3i = target.place
		if t.is_solid(c2) or Game.I.occupied(c2) != "":
			return {}
		return {"kind": "struct", "cell": c2, "struct": sk}
	return {}


func _has_side_neighbor(c: Vector3i) -> bool:
	var t := Game.I.terrain
	for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		if t.is_solid(c + d):
			return true
	return false


# ═════════ 행동 ═════════

func _update_actions(delta: float) -> void:
	_swing_cd = maxf(0.0, _swing_cd - delta)
	_use_cd = maxf(0.0, _use_cd - delta)
	_hurt_flash = maxf(0.0, _hurt_flash - delta)
	if _say_t > 0.0:
		_say_t -= delta
		if _say_t <= 0.0:
			say_label.text = ""
	_update_fishing(delta)
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not Game.I.hud.blocks_game_input()
	if captured and not downed and not sleeping and Input.is_action_pressed("primary") and _swing_cd <= 0.0:
		_primary()
	# 되살리기 (E 꾹)
	if _revive_target:
		if captured and Input.is_action_pressed("interact") and is_instance_valid(_revive_target) and _revive_target.downed \
				and _revive_target.global_position.distance_to(global_position) < 2.8:
			_revive_t += delta
			Game.I.hud.set_progress("%s 살리는 중..." % Net.player_name(_revive_target.peer_id), _revive_t / REVIVE_TIME)
			if _revive_t >= REVIVE_TIME:
				_revive_target.net_revived.rpc_id(_revive_target.peer_id)
				Game.I.add_stat("revives", 1)
				_revive_target = null
				Game.I.hud.set_progress("", -1.0)
		else:
			_revive_target = null
			Game.I.hud.set_progress("", -1.0)
	Game.I.hud.set_prompt(_prompt_text())
	# 자동 줍기
	for id in Game.I.ents.pickups:
		var e: Dictionary = Game.I.ents.pickups[id]
		if e.get("asked", false) or not is_instance_valid(e.node):
			continue
		if e.node.global_position.distance_to(global_position + Vector3.UP * 0.4) < 1.5 and e.t > 0.6:
			e.asked = true
			Game.I.ents.req_pickup.rpc_id(1, id)
			get_tree().create_timer(1.0).timeout.connect(_unask.bind(id))


func _unask(id: int) -> void:
	if Game.I and Game.I.ents.pickups.has(id):
		Game.I.ents.pickups[id].erase("asked")


func _prompt_text() -> String:
	if downed or sleeping:
		return "[E] 일어나기" if sleeping else ""
	var dp := _downed_friend()
	if dp:
		return "[E 꾹] %s 살리기" % Net.player_name(dp.peer_id)
	if riding >= 0:
		var rr: Dictionary = Game.I.ents.rafts.get(riding, {})
		return "W/S 노 젓기 / A/D 방향 / [E] 내리기   (탄 사람 %d명, 같이 저으면 빨라진다)" % rr.get("riders", {}).size()
	var rid := _raft_target()
	if rid >= 0:
		var r: Dictionary = Game.I.ents.rafts[rid]
		return "[E] 뗏목 타기 (%d/4)   좌클릭 3번: 뗏목 걷기" % r.riders.size()
	if target.get("type", "") == "struct":
		var s: Dictionary = Game.I.structs.list.get(target.id, {})
		if not s.is_empty():
			return _struct_prompt(s)
	if target.get("type", "") == "prop":
		var def := Game.I.props.def_of(target.id)
		var e: Dictionary = Game.I.props.list[target.id]
		return "%s  %d/%d" % [def.name, e.hp, def.hp]
	var fid := _flotsam_target(3.2)
	if fid >= 0:
		return "[E] 떠다니는 잔해 건지기"
	if held_id == "hook" and _flotsam_target(11.0) >= 0:
		return "[좌클릭] 갈고리 던지기"
	if held_id == "fishing_rod" and _fish_state == "":
		return "[좌클릭] 낚싯대 던지기" if _fish_point() != Vector3.INF else ""
	if held_id == "bottle" and water_point != Vector3.INF and water_point.distance_to(eye_pos()) < REACH:
		return "[우클릭] 바닷물 뜨기"
	return ""


func _struct_prompt(s: Dictionary) -> String:
	var k: String = s.kind
	var d: Dictionary = s.data
	var nm: String = Items.STRUCTS[k].name
	match k:
		"workbench", "campfire", "furnace": return "[E] %s 사용" % nm
		"chest": return "[E] 상자 열기"
		"bed": return "[E] 잠자기 / 부활 장소 정하기"
		"rain_collector": return "[E] 물 받기 (빈 병 필요)  %d/3" % d.stored
		"trap": return "[E] 통발 걷기 (%d)" % d.stored
		"sand_trap": return "[E] 모래 줍기 (%d)" % d.stored
		"farm_plot":
			if d.crop == "": return "[E] 심기 (감자/산딸기)"
			if d.grow >= 1.0: return "[E] 수확!"
			return "자라는 중... %d%%" % int(d.grow * 100)
		"loot_crate", "loot_barrel": return "[E] 열어 보기" if not d.get("opened", false) else "빈 상자"
		"captain_chest": return "[E] 선장의 금고 (쇠지렛대 필요)" if not d.get("opened", false) else "빈 금고"
		"tablet": return "[E] 고대 석판 읽기"
		"note_sign": return "[E] 팻말 읽기"
		"bell": return "[E] 종 치기"
		"altar": return "[E] 거북 제단에 바치기"
		"shipyard": return "[E] 조선소"
		"totem": return "[E] 축제 시작!"
		"door": return "[E] 문 닫기" if d.get("open", false) else "[E] 문 열기"
		"big_rock": return "[E] 밀기 - 둘이 동시에! (혼자면 철곡괭이)"
		"dig_spot": return "[E] 삽으로 파기"
		"plate": return "압력판 (위에 올라서거나 블록을 올려 두자)"
	return nm


func _raft_target() -> int:
	if target.get("type", "") == "raft":
		return target.id
	return Game.I.ents.raft_near(global_position, 2.2)


func _downed_friend() -> Player:
	for id in Game.I.players:
		var p: Player = Game.I.players[id]
		if p != self and p.downed and p.global_position.distance_to(global_position) < 2.6:
			return p
	return null


func _flotsam_target(max_d: float) -> int:
	return Game.I.ents.flotsam_near(eye_pos(), look_dir(), max_d, 20.0)


func _swing() -> void:
	_swing_count = (_swing_count + 1) % 256
	_swing_anim = 0.25
	var tool := Items.tool_of(held_id)
	_swing_cd = 0.3 if tool.is_empty() else 0.38
	Audio.play_at("whoosh", global_position + Vector3.UP, -14.0)


func _use_tool_durability() -> void:
	var s = inv.slots[hotbar_i]
	if s == null or not s.has("d"):
		return
	var name := Items.name_of(s.id)
	if inv.use_durability(hotbar_i):
		Game.I.hud.toast("%s 부서졌다!" % Items.josa(name, "이", "가"), Color("ff9a8a"))
		Audio.play("break")


func _primary() -> void:
	if held_id == "fishing_rod":
		_swing_cd = 0.35
		_fish_click()
		return
	if held_id == "hook":
		var fid := _flotsam_target(11.0)
		if fid >= 0:
			_swing()
			Game.I.ents.req_grab_flotsam.rpc_id(1, fid)
			_use_tool_durability()
			return
	var tool := Items.tool_of(held_id)
	var kind: String = tool.get("kind", "")
	_swing()
	# 1) 적
	var reach := 3.2 if kind == "spear" else 2.4
	var eid := Game.I.ents.enemy_near(eye_pos() - Vector3.UP * 0.6, look_dir(), reach)
	if eid >= 0:
		var dmg: int = tool.get("dmg", 1)
		Game.I.ents.req_hit_enemy.rpc_id(1, eid, dmg, global_position)
		_use_tool_durability()
		return
	# 1.5) 친구 뿅망치 (데미지 없음, 날아가기만)
	var friend := _friend_in_front(2.2)
	if friend and not target.is_empty() and target.pos.distance_to(global_position) < friend.global_position.distance_to(global_position) + 0.3:
		friend = null   # 친구보다 가까운 걸 보고 있으면 그걸 친다
	if friend:
		friend.net_bonk.rpc_id(friend.peer_id, global_position)
		return
	var tt: String = target.get("type", "")
	# 뗏목 걷기 (세 번 치면 아이템으로)
	if tt == "raft":
		_struct_hits[-100 - target.id] = _struct_hits.get(-100 - target.id, 0) + 1
		Audio.play_at("chop", target.pos, -4.0)
		if _struct_hits[-100 - target.id] >= 3:
			_struct_hits.erase(-100 - target.id)
			Game.I.ents.req_raft_pickup.rpc_id(1, target.id)
		return
	# 2) 채집물
	if tt == "prop":
		Game.I.props.req_hit.rpc_id(1, target.id, held_id)
		var def := Game.I.props.def_of(target.id)
		if kind != "" and kind == def.get("tool", "x"):
			_use_tool_durability()
		return
	# 3) 설치물
	if tt == "struct":
		var s: Dictionary = Game.I.structs.list.get(target.id, {})
		if s.is_empty():
			return
		if s.kind == "bell":
			Game.I.structs.req_interact.rpc_id(1, target.id, "ring", null)
			return
		if Items.STRUCTS[s.kind].get("world", false):
			return
		# 실수로 부수지 않게: 3초 안에 6번 때려야 걷힌다
		var now := Time.get_ticks_msec() / 1000.0
		var h: Array = _struct_hits.get(target.id, [0, now])
		if now - h[1] > 3.0:
			h = [0, now]
		h[0] += 1
		h[1] = now
		_struct_hits[target.id] = h
		Audio.play_at("punch", target.pos, -4.0)
		Game.I.fx_break(target.pos, Color("a0764a"), 3)
		if h[0] == 1:
			Game.I.hud.toast("%s: 계속 때리면 걷어서 가방에 넣는다" % Items.STRUCTS[s.kind].name)
		if h[0] >= 6:
			_struct_hits.erase(target.id)
			Game.I.structs.req_remove.rpc_id(1, target.id)
		return
	# 4) 블록
	if tt == "block":
		var cell: Vector3i = target.cell
		var bt := Game.I.terrain.get_block(cell)
		if bt < 0:
			return
		var b := Items.block(bt)
		if b.hard < 0:
			Game.I.hud.toast("단단한 고대 벽돌이다. 부술 수 없다")
			Audio.play_at("mine", target.pos, 0.0, 1.5)
			return
		if b.has("need") and kind != b.need:
			Game.I.hud.toast("%s 필요해!" % Items.josa(Props.NEED_NAMES.get(b.need, b.need), "이", "가"))
			Audio.play_at("mine", target.pos, 0.0, 1.5)
			return
		var power: float = tool.get("power", 1) if (kind != "" and kind == b.tool) else 1.0
		if cell != _break_cell:
			_break_cell = cell
			_break_dmg = 0.0
		_break_dmg += power
		var snd := "dig"
		if b.tool == "pick":
			snd = "mine"
		elif b.tool == "axe":
			snd = "chop"
		Audio.play_at(snd, target.pos, -6.0, 1.2)
		Game.I.fx_break(target.pos, b.color, 3)
		if kind != "" and kind == b.tool:
			_use_tool_durability()
		if _break_dmg >= b.hard:
			_break_dmg = 0.0
			_crack.visible = false
			Game.I.terrain.req_break.rpc_id(1, cell)
		else:
			_crack.visible = true
			_crack.global_position = Vector3(cell) + Vector3(0.5, 0.5, 0.5)
			_crack.material_override = Vis.crack_material(_break_dmg / b.hard)


func _secondary() -> void:
	if downed or sleeping or _use_cd > 0.0 or held_id == "":
		return
	var item := Items.item(held_id)
	_use_cd = 0.25
	# 뗏목 띄우기
	if held_id == "raft":
		if water_point == Vector3.INF or water_point.distance_to(eye_pos()) > REACH + 3.0:
			Game.I.hud.toast("바다를 보고 우클릭해서 띄우자")
			return
		inv.remove("raft", 1)
		Game.I.ents.req_raft_spawn.rpc_id(1, water_point, _yaw)
		return
	# 설치
	var place := _placement()
	if not place.is_empty():
		var id := held_id
		inv.remove(id, 1)
		if place.kind == "block":
			Game.I.terrain.req_place.rpc_id(1, place.cell, Items.block_id(id), id)
		else:
			Game.I.structs.req_place.rpc_id(1, place.struct, place.cell, _rot_index(), id)
		_swing()
		return
	# 바닷물 뜨기
	if held_id == "bottle" and water_point != Vector3.INF and water_point.distance_to(eye_pos()) < REACH:
		inv.remove("bottle", 1)
		receive("salt_water", 1, -1)
		Audio.play_at("splash", water_point, -6.0, 1.4)
		return
	# 먹기
	if item.has("food"):
		_eat(held_id)
		return


func _eat(id: String) -> void:
	var f := Items.food_of(id)
	if f.is_empty():
		return
	if id == "salt_water" and Time.get_ticks_msec() / 1000.0 - _salt_confirm > 2.5:
		_salt_confirm = Time.get_ticks_msec() / 1000.0
		Game.I.hud.toast("정말 바닷물을 마실 거야? 더 목마르다... (한 번 더 우클릭) 모닥불에 끓이면 깨끗한 물")
		return
	var full: bool = hunger >= MAX_STAT - 1 and f.get("thirst", 0) <= 0 and f.get("hp", 0) <= 0
	if full:
		Game.I.hud.toast("배불러!")
		return
	inv.remove(id, 1)
	hunger = clampf(hunger + f.get("hunger", 0), 0, MAX_STAT)
	thirst = clampf(thirst + f.get("thirst", 0), 0, MAX_STAT)
	hp = clampf(hp + f.get("hp", 0), 1, MAX_STAT)
	_use_cd = 0.6
	var drink: bool = f.get("thirst", 0) > f.get("hunger", 0)
	Audio.play_at("drink" if drink else "eat", global_position + Vector3.UP)
	if f.has("ret"):
		receive(f.ret, 1, -1)
	if id == "salt_water":
		Game.I.hud.toast("퉤퉤! 짜다! 목이 더 마르다...", Color("ff9a8a"))
	elif id in ["raw_fish", "big_fish", "crab_meat"]:
		Game.I.hud.toast("으... 비려. 구워 먹을걸", Color("ffcf8a"))


func _interact_press() -> void:
	if sleeping:
		wake_up()
		return
	if downed:
		return
	# 살리기가 제일 먼저 (뗏목 위에서도)
	var dp := _downed_friend()
	if dp:
		_revive_target = dp
		_revive_t = 0.0
		return
	if riding >= 0:
		Game.I.ents.req_raft_leave.rpc_id(1, riding)
		return
	if target.get("type", "") == "struct":
		_interact_struct(target.id)
		return
	var rid := _raft_target()
	if rid >= 0:
		Game.I.ents.req_raft_board.rpc_id(1, rid)
		return
	var fid := _flotsam_target(3.2)
	if fid >= 0:
		Game.I.ents.req_grab_flotsam.rpc_id(1, fid)
		return


func _interact_struct(id: int) -> void:
	var st := Game.I.structs
	var s: Dictionary = st.list.get(id, {})
	if s.is_empty():
		return
	var d: Dictionary = s.data
	match s.kind:
		"workbench", "campfire", "furnace":
			Game.I.hud.open_inventory(s.kind)
		"chest":
			Game.I.hud.open_chest(id)
		"bed":
			# 눕고 나서 알린다 (혼자면 알리자마자 아침이 될 수 있어서)
			if Game.I.clock.is_night():
				_lie_down(Vector3(s.cell.x + 0.5, s.cell.y + 0.2, s.cell.z + 0.5))
			st.req_interact.rpc_id(1, id, "sleep", null)
		"rain_collector":
			if d.stored <= 0:
				Game.I.hud.toast("아직 물이 안 고였어")
			elif inv.count("bottle") <= 0:
				Game.I.hud.toast("빈 병이 필요해")
			else:
				inv.remove("bottle", 1)
				st.req_interact.rpc_id(1, id, "take", "bottle")
		"trap", "sand_trap":
			st.req_interact.rpc_id(1, id, "take", null)
		"farm_plot":
			if d.crop == "":
				var seed := ""
				if held_id in ["potato", "berries"]:
					seed = held_id
				elif inv.count("potato") > 0:
					seed = "potato"
				elif inv.count("berries") > 0:
					seed = "berries"
				if seed == "":
					Game.I.hud.toast("심을 게 없어 (감자나 산딸기)")
				else:
					inv.remove(seed, 1)
					st.req_interact.rpc_id(1, id, "plant", seed)
			elif d.grow >= 1.0:
				st.req_interact.rpc_id(1, id, "harvest", null)
			else:
				Game.I.hud.toast("아직 자라는 중 (%d%%)" % int(d.grow * 100))
		"loot_crate", "loot_barrel":
			st.req_interact.rpc_id(1, id, "open", null)
		"captain_chest":
			if d.get("opened", false):
				Game.I.hud.toast("이미 비었다")
			elif inv.count("crowbar") <= 0:
				Game.I.hud.toast("꽉 잠겨 있다. 쇠지렛대가 있으면 비틀어 열 수 있을 텐데...")
				Audio.play_at("metal", global_position)
			else:
				st.req_interact.rpc_id(1, id, "open", null)
		"dig_spot":
			if inv.count("shovel") <= 0:
				Game.I.hud.toast("삽이 필요해")
			else:
				st.req_interact.rpc_id(1, id, "dig", null)
				_swing()
		"tablet", "note_sign":
			st.req_interact.rpc_id(1, id, "read", null)
		"bell":
			st.req_interact.rpc_id(1, id, "ring", null)
			_swing()
		"altar":
			if not d.feast and inv.count("seaweed_feast") > 0:
				inv.remove("seaweed_feast", 1)
				st.req_interact.rpc_id(1, id, "feast", null)
			elif d.shells < 3 and inv.count("golden_shell") > 0:
				inv.remove("golden_shell", 1)
				st.req_interact.rpc_id(1, id, "shell", null)
			else:
				Game.I.hud.toast("거북 제단: 잔치상 %s / 황금 조개 %d/3" % ["O" if d.feast else "X", d.shells])
		"shipyard":
			Game.I.hud.open_shipyard(id)
		"totem":
			st.req_interact.rpc_id(1, id, "activate", null)
		"door":
			st.req_interact.rpc_id(1, id, "toggle", null)
		"big_rock":
			st.req_interact.rpc_id(1, id, "push", "iron_pick" if inv.count("iron_pick") > 0 else "")
			_swing()
		"plate":
			Game.I.hud.toast("압력판이다. 위에 뭔가 올려 두면...")
		_:
			Game.I.hud.toast(Items.STRUCTS[s.kind].name)


func _drop_held(all: bool) -> void:
	if held_id == "" or downed:
		return
	var s: Dictionary = inv.take_slot(hotbar_i, -1 if all else 1)
	if s.is_empty():
		return
	var dir := look_dir()
	Game.I.ents.req_drop.rpc_id(1, [[s.id, s.n, s.get("d", -1)]], eye_pos() + dir * 0.6, dir * 5.0 + Vector3.UP * 2.0)
	Audio.play("whoosh", -8.0)


func _ping() -> void:
	var p: Vector3 = target.get("pos", Vector3.INF)
	if p == Vector3.INF and water_point != Vector3.INF:
		p = water_point
	if p == Vector3.INF:
		var from := camera.global_position
		var q := PhysicsRayQueryParameters3D.create(from, from + look_dir() * 60.0, 1 | 2)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			p = hit.position
	if p != Vector3.INF:
		Game.I.send_ping(p)


# ═════════ 받기 · 조합 ═════════

func receive(id: String, n: int, d: int) -> void:
	var left := inv.add(id, n, d)
	if n - left > 0:
		Game.I.hud.pickup_note(id, n - left)
	if left > 0:
		Game.I.ents.req_drop.rpc_id(1, [[id, left, d]], global_position + Vector3.UP, Vector3(0, 2, 0))
		Game.I.hud.toast("가방이 꽉 찼어!", Color("ff9a8a"))


func station_near(st: String) -> bool:
	if st == "":
		return true
	return Game.I.structs.near(st, global_position + Vector3.UP * 0.5, 5.0) >= 0


func can_craft(r: Dictionary) -> bool:
	return station_near(r.at) and inv.has_all(r.in)


func craft(r: Dictionary, times: int = 1) -> int:
	var made := 0
	for i in times:
		if not can_craft(r):
			break
		inv.remove_all(r.in)
		receive(r.out, r.n, -1)
		made += 1
	if made > 0:
		Audio.play("craft")
		Game.I.add_stat("crafted", made)
		if r.out == "seaweed_feast" or r.out == "totem" or r.out == "shipyard":
			Audio.play("levelup")
	return made


# ═════════ 피해 · 기절 · 부활 ═════════

@rpc("any_peer", "call_local", "reliable")
func net_hurt(dmg: int, src: Vector3) -> void:
	if multiplayer.get_remote_sender_id() != 1 or not is_local or downed:
		return
	if sleeping:
		wake_up()
	hp -= dmg
	_hurt_flash = 0.3
	var push := global_position - src
	push.y = 0
	velocity += push.normalized() * 5.0 + Vector3.UP * 3.0
	Audio.play("hurt")
	Game.I.hud.hurt_flash()
	Game.I.shake_camera(0.25, Vector3.INF)
	if hp <= 0:
		_go_down()


func _friend_in_front(reach: float) -> Player:
	var dir := look_dir()
	dir.y = 0
	for id in Game.I.players:
		var p: Player = Game.I.players[id]
		if p == self or p.downed:
			continue
		var to := p.global_position - global_position
		if absf(to.y) > 1.5:
			continue
		to.y = 0
		if to.length() < reach and to.length() > 0.05 and rad_to_deg(dir.angle_to(to)) < 35.0:
			return p
	return null


@rpc("any_peer", "call_local", "reliable")
func net_bonk(from_pos: Vector3) -> void:
	if not is_local:
		return
	var push := global_position - from_pos
	push.y = 0
	velocity += push.normalized() * 9.0 + Vector3.UP * 5.5
	if sleeping:
		wake_up()
	Audio.play("hurt", -2.0, 1.6)
	var who := Net.player_name(multiplayer.get_remote_sender_id())
	var who_ig := Items.josa(who, "이", "가")
	var lines := ["%s 때렸다! (안 아프다)" % who_ig, "%s의 뿅망치!" % who, "%s 장난친다" % who_ig, "%s: 퍽!" % who]
	Game.I.hud.toast(lines[randi() % lines.size()], Color("ffd0f0"))


@rpc("any_peer", "call_local", "reliable")
func net_stolen(item: String, gull_id: int) -> void:
	if multiplayer.get_remote_sender_id() != 1 or not is_local:
		return
	var s = inv.slots[hotbar_i]
	if s != null and s.id == item:
		inv.take_slot(hotbar_i, 1)
	elif inv.remove(item, 1) <= 0:
		return   # 이미 먹어 버렸다. 갈매기 헛걸음
	Game.I.ents.req_gull_got.rpc_id(1, gull_id, item)
	Game.I.hud.toast("갈매기가 %s 채 갔다!! 때려서 되찾자!" % Items.josa(Items.name_of(item), "을", "를"), Color("ffcf8a"))
	Audio.play("gull", 2.0)
	Game.I.shake_camera(0.2, Vector3.INF)


func _go_down() -> void:
	if downed:
		return
	hp = 0
	downed = true
	_cancel_fishing()
	var alone := Game.I.players.size() <= 1
	_bleed = 3.0 if alone else BLEED_TIME
	Game.I.hud.toast("기절했다!" + ("" if alone else " 친구가 E 를 꾹 눌러 살려줄 수 있다"), Color("ff7a6a"))
	if not alone:
		Game.I.announce_all("%s 기절했다! 30초 안에 가서 E 를 꾹 눌러 살려 주자 (지도 M)" % Items.josa(Net.player_name(peer_id), "이", "가"))
	Game.I.add_stat("downs", 1)


@rpc("any_peer", "call_local", "reliable")
func net_revived() -> void:
	if not is_local or not downed:
		return
	downed = false
	hp = 35.0
	Game.I.hud.set_downed(false, 0)
	Game.I.hud.toast("%s 살려줬다!" % Items.josa(Net.player_name(multiplayer.get_remote_sender_id()), "이", "가"), Color("c8f7c5"))
	Audio.play("revive")


func _faint() -> void:
	if riding >= 0:
		Game.I.ents.req_raft_leave.rpc_id(1, riding)
		riding = -1
	# 가방(단축바 제외)을 그 자리에 떨군다
	var bag: Array = []
	for i in range(Inventory.HOTBAR, Inventory.SIZE):
		var s = inv.slots[i]
		if s != null:
			bag.append([s.id, s.n, s.get("d", -1)])
			inv.slots[i] = null
	inv.changed.emit()
	if not bag.is_empty():
		Game.I.ents.req_drop.rpc_id(1, bag, global_position + Vector3.UP * 0.5, Vector3.ZERO, true)
	downed = false
	hp = 60.0
	hunger = maxf(hunger, 40.0)
	thirst = maxf(thirst, 40.0)
	global_position = Game.I.safe_spot(spawn_point + Vector3.UP * 0.3)
	velocity = Vector3.ZERO
	Game.I.hud.set_downed(false, 0)
	Game.I.hud.toast("정신을 차려 보니 다른 곳이다... 가방은 쓰러진 곳에 떨어져 있다" if not bag.is_empty() else "정신을 차려 보니 다른 곳이다...", Color("ffcf8a"))
	Game.I.add_stat("deaths", 1)
	Audio.play("jingle_bad")


func _lie_down(pos: Vector3) -> void:
	sleeping = true
	global_position = pos
	velocity = Vector3.ZERO
	Game.I.hud.set_sleeping(true)


func wake_up() -> void:
	if not sleeping:
		return
	sleeping = false
	Game.I.hud.set_sleeping(false)
	Game.I.structs.req_interact.rpc_id(1, Game.I.structs.near("bed", global_position, 3.0), "wake", null)


func say(text: String) -> void:
	say_label.text = text
	_say_t = 5.0


# ═════════ 낚시 ═════════

func _fish_point() -> Vector3:
	var from := camera.global_position
	var dir := look_dir()
	if dir.y > -0.02:
		return Vector3.INF
	var tt := (Terrain.WATER_Y - from.y) / dir.y
	var wp := from + dir * tt
	if wp.distance_to(global_position) > FISH_RANGE:
		return Vector3.INF
	if Game.I.terrain.top_y(int(floor(wp.x)), int(floor(wp.z))) >= 0:
		return Vector3.INF
	return wp


func _fish_click() -> void:
	match _fish_state:
		"":
			var p := _fish_point()
			if p == Vector3.INF:
				Game.I.hud.toast("물을 보고 던져야 해")
				return
			_cast_bobber(p)
		"wait":
			_cancel_fishing()
		"bite":
			var rng := RandomNumberGenerator.new()
			rng.randomize()
			for l in Items.roll_loot("fish", rng):
				receive(l[0], l[1], -1)
				if l[0] == "golden_shell":
					Game.I.hud.toast("!!! 황금 조개가 낚였다 !!!", Color("ffd23f"))
			Audio.play("pickup")
			Game.I.add_stat("fish", 1)
			_use_tool_durability()
			_cancel_fishing()


func _cast_bobber(p: Vector3) -> void:
	_fish_state = "wait"
	_fish_t = randf_range(3.0, 8.0) * (0.7 if Game.I.clock.raining else 1.0)
	_bobber = Vis.make({"s": "sphere", "c": "ff4a3a", "sz": [0.16, 0.16, 0.16]})
	Game.I.fx_root.add_child(_bobber)
	_bobber.global_position = hand.global_position
	var tw := create_tween()
	tw.tween_property(_bobber, "global_position", p, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func(): Audio.play_at("fish_bite", p, -8.0, 1.4))
	_line = MeshInstance3D.new()
	_line.mesh = ImmediateMesh.new()
	_line.material_override = Vis.mat(Color(1, 1, 1, 0.8), true)
	Game.I.fx_root.add_child(_line)
	_swing()


func _update_fishing(delta: float) -> void:
	if _fish_state == "":
		return
	if not is_instance_valid(_bobber) or _bobber.global_position.distance_to(global_position) > FISH_RANGE + 3.0:
		_cancel_fishing()
		return
	var im: ImmediateMesh = _line.mesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_add_vertex(hand.global_position + hand.global_basis.y * 0.7)
	im.surface_add_vertex(_bobber.global_position)
	im.surface_end()
	_fish_t -= delta
	var now := Time.get_ticks_msec() / 1000.0
	if _fish_state == "wait":
		_bobber.position.y = Terrain.WATER_Y + sin(now * 3.0) * 0.03
		if _fish_t <= 0.0:
			_fish_state = "bite"
			_fish_t = 0.9
			Audio.play_at("fish_bite", _bobber.global_position, 2.0)
			Game.I.hud.fish_alert(true)
	elif _fish_state == "bite":
		_bobber.position.y = Terrain.WATER_Y - 0.12 + sin(now * 30.0) * 0.05
		if _fish_t <= 0.0:
			Game.I.hud.toast("놓쳤다!")
			Game.I.hud.fish_alert(false)
			_fish_state = "wait"
			_fish_t = randf_range(3.0, 7.0)


func _cancel_fishing() -> void:
	_fish_state = ""
	if is_instance_valid(_bobber):
		_bobber.queue_free()
	if is_instance_valid(_line):
		_line.queue_free()
	_bobber = null
	_line = null
	if Game.I and Game.I.hud:
		Game.I.hud.fish_alert(false)


# ═════════ 동기화 · 애니메이션 ═════════

func _flags() -> int:
	var f := 0
	if Vector2(velocity.x, velocity.z).length() > 0.5: f |= 1
	if riding >= 0: f |= 2
	if _ride_paddle and riding >= 0: f |= 32
	if _wave_t > 0.0: f |= 128
	if swimming: f |= 4
	if downed: f |= 8
	if sleeping: f |= 16
	if is_on_floor(): f |= 64
	return f | (_swing_count << 8)


func _send_state(delta: float) -> void:
	_net_t -= delta
	if _net_t > 0.0 or not Net.is_online():
		return
	_net_t = 0.05
	Game.I.net_player_state.rpc(global_position, model.rotation.y, _flags(), held_id, hp)


func apply_remote(pos: Vector3, yaw: float, flags: int, held: String, rhp: float) -> void:
	_r_pos = pos
	_r_yaw = yaw
	var sc := flags >> 8
	if sc != _r_swing:
		_r_swing = sc
		_swing_anim = 0.25
	_r_flags = flags & 0xff
	downed = (_r_flags & 8) != 0
	sleeping = (_r_flags & 16) != 0
	swimming = (_r_flags & 4) != 0
	hp = rhp
	if held != held_id:
		held_id = held
		_update_held_visual()


func _remote_update(delta: float) -> void:
	var before := global_position
	if global_position.distance_to(_r_pos) > 6.0:
		global_position = _r_pos
	else:
		global_position = global_position.lerp(_r_pos, clampf(delta * 12.0, 0, 1))
	if not downed and not sleeping:
		model.rotation.y = lerp_angle(model.rotation.y, _r_yaw, clampf(delta * 12.0, 0, 1))
	var spd := (global_position - before).length() / maxf(delta, 0.001)
	_animate(delta, spd, swimming, (_r_flags & 64) != 0)
	# 호스트의 상어가 손님도 노릴 수 있게 깊은 물 시간을 여기서도 센다
	if swimming and Game.I and Game.I.terrain.top_y(int(floor(global_position.x)), int(floor(global_position.z))) < -1:
		deep_time += delta
	else:
		deep_time = 0.0


func _animate(delta: float, speed: float, swim: bool, _on_floor: bool) -> void:
	var sit: bool = riding >= 0 if is_local else (_r_flags & 2) != 0
	if sit:
		# 뗏목 위: 앉아서 노 젓기
		var paddle: bool = _ride_paddle if is_local else (_r_flags & 32) != 0
		model.rotation.x = 0.0
		model.position.y = lerpf(model.position.y, -0.35, clampf(delta * 8.0, 0, 1))
		leg_l.rotation.x = -1.4
		leg_r.rotation.x = -1.4
		var pw := sin(Time.get_ticks_msec() / 160.0) * 0.8 if paddle else 0.0
		arm_l.rotation.x = -0.9 + pw
		arm_r.rotation.x = -0.9 + pw
		return
	if downed or sleeping:
		model.rotation.x = lerpf(model.rotation.x, -PI * 0.5, clampf(delta * 8.0, 0, 1))
		model.position.y = lerpf(model.position.y, 0.25, clampf(delta * 8.0, 0, 1))
		return
	model.rotation.x = lerpf(model.rotation.x, -0.9 if swim and speed > 0.5 else 0.0, clampf(delta * 6.0, 0, 1))
	model.position.y = lerpf(model.position.y, -0.35 if swim else 0.0, clampf(delta * 6.0, 0, 1))
	if speed > 0.3:
		_anim_t += delta * speed * 2.2
	else:
		_anim_t = lerpf(_anim_t, round(_anim_t / PI) * PI, clampf(delta * 8.0, 0, 1))
	var sw := sin(_anim_t) * clampf(speed / 5.0, 0.0, 1.0) * 0.9
	if swim:
		sw = sin(Time.get_ticks_msec() / 250.0) * 0.8
	leg_l.rotation.x = sw
	leg_r.rotation.x = -sw
	arm_l.rotation.x = -sw * 0.8
	var arm_base := -sw * 0.8
	if held_id != "":
		arm_base = -0.35
	if _swing_anim > 0.0:
		_swing_anim -= delta
		var k := 1.0 - _swing_anim / 0.25
		arm_base = -2.2 + k * 2.4
	arm_r.rotation.x = lerpf(arm_r.rotation.x, arm_base, clampf(delta * 25.0, 0, 1))
	# 손 흔들기 (G)
	_wave_t = maxf(0.0, _wave_t - delta)
	var waving: bool = _wave_t > 0.0 if is_local else (_r_flags & 128) != 0
	if waving:
		arm_l.rotation.x = -2.9
		arm_l.rotation.z = sin(Time.get_ticks_msec() / 90.0) * 0.45 - 0.2
	else:
		arm_l.rotation.z = lerpf(arm_l.rotation.z, 0.0, clampf(delta * 10.0, 0, 1))
	if is_local and _hurt_flash > 0.0:
		model.scale = Vector3.ONE * (1.0 + _hurt_flash * 0.3)
	else:
		model.scale = Vector3.ONE
