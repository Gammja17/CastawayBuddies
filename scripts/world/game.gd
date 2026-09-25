class_name Game
extends Node3D
## 게임 한 판. 접속 · 세계 만들기 · 스냅샷 · 저장 · 플레이어 · 공용 이펙트 · 엔딩.

static var I: Game

var PLAYER_SCENE: PackedScene = load("res://scenes/player.tscn")
const SAVE_DIR := "user://saves/"
const SAVE_VERSION := 2
const JOIN_TIMEOUT := 12.0
## 난이도: drain = 배고픔·목마름 줄어드는 속도, dmg = 받는 피해
const DIFFS := [
	{"name": "느긋하게 (캐주얼)", "drain": 0.6, "dmg": 0.6},
	{"name": "보통", "drain": 1.0, "dmg": 1.0},
	{"name": "빡빡하게 (고수)", "drain": 1.35, "dmg": 1.4},
]

@onready var terrain: Terrain = $Terrain
@onready var props: Props = $Props
@onready var structs: Structs = $Structs
@onready var ents: Ents = $Ents
@onready var players_root: Node3D = $Players
@onready var decor_root: Node3D = $Decor
@onready var fx_root: Node3D = $FX
@onready var clock: Clock = $Clock
@onready var quests: Quests = $Quests
@onready var hud: Hud = $HUD
@onready var ocean: MeshInstance3D = $Ocean

var gen: WorldGen
var world_seed := 0
var world_ready := false
var players := {}          # peer -> Player
var local_player: Player
var player_saves := {}     # 호스트: 이름 -> {"inv", "hp", "hunger", "thirst", "pos", "spawn"}
var stats := {}
var slot := "slot1"
var difficulty := 1
var ending_playing := false
var _host_lost := false
var _grass: Array = []     # [노드, 위치] 파거나 부으면 치운다
var _join_wait := -1.0
var _autosave_t := 180.0
var _upload_t := 5.0
var _shake := 0.0
var _shake_amp := 0.0


func _ready() -> void:
	I = self
	var req: Dictionary = Net.pending if not Net.pending.is_empty() else {"mode": "solo", "new": true, "slot": "slot1"}
	Net.pending = {}
	slot = req.get("slot", "slot1")
	Net.server_lost.connect(_on_server_lost)
	multiplayer.peer_disconnected.connect(_on_peer_left)
	terrain.changed.connect(_on_terrain_changed)
	clock.day_started.connect(_on_day_started)
	clock.night_started.connect(on_night)
	Audio.stop_all_ambience()
	Audio.ambience("ocean", true, -10.0)
	Settings.apply_graphics($Sun)
	match req.get("mode", "solo"):
		"solo":
			Net.start_solo()
			_host_begin(req)
		"host":
			var err := Net.start_host(req.get("port", Net.DEFAULT_PORT), req.get("upnp", true))
			if err != OK:
				hud.fatal("방을 만들 수 없어 (포트 %d 가 이미 쓰이는 중?)" % req.get("port", Net.DEFAULT_PORT))
				return
			_host_begin(req)
		"join":
			hud.show_loading("%s 에 접속하는 중..." % req.get("ip", "?"))
			Net.connected_ok.connect(_on_connected, CONNECT_ONE_SHOT)
			Net.connect_failed.connect(_on_connect_failed, CONNECT_ONE_SHOT)
			var err2 := Net.start_join(req.get("ip", "127.0.0.1"), req.get("port", Net.DEFAULT_PORT))
			if err2 != OK:
				hud.fatal("접속할 수 없어: 주소를 확인해 줘")
				return
			_join_wait = JOIN_TIMEOUT


func _exit_tree() -> void:
	if I == self:
		I = null


func _notification(what: int) -> void:
	# 창을 X 로 닫아도 저장
	if what == NOTIFICATION_WM_CLOSE_REQUEST and world_ready:
		if multiplayer.is_server():
			save_game()
		elif local_player:
			_upload_player.rpc_id(1, local_player.save_data())


# ═════════ 호스트 시작 ═════════

func _host_begin(req: Dictionary) -> void:
	var data := {}
	if not req.get("new", true):
		data = load_save(slot)
	if data.is_empty():
		world_seed = randi_range(1, 999999)
		difficulty = clampi(req.get("diff", 1), 0, DIFFS.size() - 1)
	else:
		world_seed = data.seed
		difficulty = clampi(data.get("difficulty", 1), 0, DIFFS.size() - 1)
	_build_world(data, true)
	stats = data.get("stats", {})
	player_saves = data.get("players", {})
	world_ready = true
	var my_name: String = Net.players[1].name
	var ps: Dictionary = player_saves.get(my_name, {})
	_spawn_player(1, ps.get("pos", gen.spawn), ps)
	hud.hide_loading()
	Audio.music("night" if clock.is_night() else "day")
	if data.is_empty():
		quests.flags["new_game"] = true
		if req.get("intro", true):
			_play_intro()
		else:
			hud.toast("눈을 떠 보니... 작은 섬이다. 떠밀려온 상자부터 열어 보자 (E)", Color("ffe08a"))
	else:
		hud.toast("%d일째. 다시 섬으로 돌아왔다." % clock.day, Color("ffe08a"))
	save_game()


func _build_world(data: Dictionary, host: bool) -> void:
	gen = WorldGen.new()
	gen.generate(world_seed)
	terrain.build(gen, data.get("terrain", {}))
	props.build(gen.props, data.get("props", []))
	structs.build(gen.structs, data.get("structs", {}))
	var es: Dictionary = data.get("ents", {})
	if es.is_empty():
		var pk: Array = []
		var i := 1
		for p in gen.pickups:
			pk.append({"id": i, "items": [[p.item, p.n, -1]], "pos": p.pos, "natural": true})
			i += 1
		es = {"next_id": i + 1, "pickups": pk}
	ents.load_snapshot(es, not host)
	clock.apply(data.get("clock", {}))
	quests.apply(data.get("quests", {}))
	structs.refresh_all("dig_spot")   # 보물 지도를 이미 읽었으면 보이게
	_build_decor()


func _build_decor() -> void:
	for c in decor_root.get_children():
		c.queue_free()
	_grass.clear()
	for d in gen.decor:
		if d.get("grass", false) and absf(terrain.height_at(d.pos.x, d.pos.z) - d.pos.y) > 0.05:
			continue   # 저장된 땅 변화로 자리가 없어진 풀
		var n := Vis.fit_model(d.model, d.h)
		decor_root.add_child(n)
		n.position = d.pos
		n.rotation = Vector3(deg_to_rad(d.get("tilt", 0.0)), deg_to_rad(d.rot), 0)
		if d.get("collide", false):
			_add_trimesh(n)
		if d.get("grass", false):
			_grass.append([n, d.pos])


func _add_trimesh(root: Node3D) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	root.add_child(body)
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if m.mesh == null:
			continue
		var cs := CollisionShape3D.new()
		cs.shape = m.mesh.create_trimesh_shape()
		cs.transform = Vis._rel_xform(root, m)
		body.add_child(cs)


func _on_terrain_changed(center: Vector3, radius: float) -> void:
	# 파거나 부은 자리의 풀 장식은 치운다
	var keep: Array = []
	for g in _grass:
		var gp: Vector3 = g[1]
		if Vector2(gp.x - center.x, gp.z - center.z).length() < radius + 0.4:
			if is_instance_valid(g[0]):
				g[0].queue_free()
		else:
			keep.append(g)
	_grass = keep
	props.follow_ground(center, radius)
	if hud:
		hud.map_dirty = true


# ═════════ 손님 접속 ═════════

func _on_connected() -> void:
	hud.show_loading("섬 정보를 받는 중...")
	_req_join.rpc_id(1)


func _on_connect_failed(reason: String) -> void:
	_join_wait = -1.0
	hud.fatal(reason)


func _on_server_lost() -> void:
	if ending_playing:
		_host_lost = true   # 엔딩 화면을 닫으면 알려 준다
		return
	hud.fatal("호스트와 연결이 끊어졌어")


func _on_peer_left(id: int) -> void:
	if multiplayer.is_server():
		if players.has(id):
			var p: Player = players[id]
			var pname := Net.player_name(id)
			_store_player_save(pname, p.remote_save_hint(player_saves.get(pname, {})))
			_despawn_player.rpc(id)
			broadcast_toast("%s 섬을 떠났다" % Items.josa(pname, "이", "가"), "")
		structs.sleepers.erase(id)
		for cid in structs.viewers:
			structs.viewers[cid].erase(id)
		ents.drop_rider(id)


@rpc("any_peer", "reliable")
func _req_join() -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if not world_ready:
		return
	var plist: Array = []
	for pid in players:
		plist.append([pid, players[pid].global_position])
	var snap := {
		"seed": world_seed, "terrain": terrain.diff_data(), "props": props.snapshot(), "structs": structs.snapshot(),
		"ents": ents.snapshot(), "clock": clock.snapshot(), "quests": quests.snapshot(), "stats": stats, "players": plist,
		"difficulty": difficulty,
	}
	_recv_snapshot.rpc_id(id, snap)
	var pname := Net.player_name(id)
	var ps: Dictionary = player_saves.get(pname, {})
	var pos: Vector3 = ps.get("pos", gen.spawn + Vector3(randf_range(-1, 1), 0.3, randf_range(-1, 1)))
	_spawn_player.rpc(id, pos, ps)
	broadcast_toast("%s 섬에 떠밀려 왔다!" % Items.josa(pname, "이", "가"), "jingle_found")


@rpc("authority", "reliable")
func _recv_snapshot(snap: Dictionary) -> void:
	_join_wait = -1.0
	world_seed = snap.seed
	difficulty = snap.get("difficulty", 1)
	_build_world(snap, false)
	stats = snap.get("stats", {})
	for p in snap.players:
		if not players.has(p[0]):
			_spawn_player(p[0], p[1], {})
	world_ready = true
	hud.hide_loading()
	Audio.music("night" if clock.is_night() else "day")


# ═════════ 플레이어 ═════════

@rpc("authority", "call_local", "reliable")
func _spawn_player(id: int, pos: Vector3, saved: Dictionary) -> void:
	if players.has(id):
		return
	var p: Player = PLAYER_SCENE.instantiate()
	p.name = "P%d" % id
	p.peer_id = id
	p.set_multiplayer_authority(id)
	p.position = pos   # _ready 전에 자리를 잡아야 남의 캐릭터가 원점에서 날아오지 않는다
	players_root.add_child(p)
	p.global_position = safe_spot(pos) if id == Net.my_id() else pos
	players[id] = p
	if id == Net.my_id():
		local_player = p
		p.make_local(saved)
		hud.bind_player(p)
	hud.on_players_changed()


@rpc("authority", "call_local", "reliable")
func _despawn_player(id: int) -> void:
	if players.has(id):
		players[id].queue_free()
		players.erase(id)
	hud.on_players_changed()


@rpc("any_peer", "call_remote", "unreliable_ordered")
func net_player_state(pos: Vector3, yaw: float, flags: int, held: String, rhp: float) -> void:
	var p: Player = players.get(multiplayer.get_remote_sender_id())
	if p and not p.is_local:
		p.apply_remote(pos, yaw, flags, held, rhp)


func safe_spot(pos: Vector3) -> Vector3:
	## 땅속에 박히지 않도록 지면 위로 올린다
	var gy := terrain.height_at(pos.x, pos.z)
	return Vector3(pos.x, maxf(pos.y, gy + 0.05), pos.z)


func player_node(id: int) -> Player:
	return players.get(id)


func nearest_player(pos: Vector3, radius: float) -> Player:
	var best: Player = null
	var bd := radius
	for id in players:
		var p: Player = players[id]
		if p.downed or p.sleeping:
			continue
		var d := p.global_position.distance_to(pos)
		if d < bd:
			bd = d
			best = p
	return best


func random_player() -> Player:
	if players.is_empty():
		return null
	var keys := players.keys()
	return players[keys[randi() % keys.size()]]


func player_on_spot(pos: Vector3, r: float) -> bool:
	## 누가 그 자리 위에 서 있나 (압력판, 설치 막기)
	for id in players:
		var p: Vector3 = players[id].global_position
		if Vector2(p.x - pos.x, p.z - pos.z).length() < r and absf(p.y - pos.y) < 0.9:
			return true
	return false


func player_standing_near(pos: Vector3, r: float, ground_h: float) -> bool:
	for id in players:
		var p: Vector3 = players[id].global_position
		if Vector2(p.x - pos.x, p.z - pos.z).length() < r and absf(p.y - ground_h) < 1.2:
			return true
	return false


func blocked_for_ground(pos: Vector3, r: float) -> bool:
	## 바로 위에 설치물이나 나무·바위가 있으면 땅을 못 판다 (둥둥 뜨니까)
	return structs.near_any(pos, r) >= 0 or props.near_alive(pos, r, true) >= 0


func near_fire(pos: Vector3, radius: float) -> bool:
	## 몸을 녹일 불 (불붙은 모닥불, 화덕)
	for id in structs.list:
		var k: String = structs.list[id].kind
		if (k == "campfire" and structs.is_lit(id)) or k == "furnace":
			if pos.distance_to(structs.list[id].pos) <= radius:
				return true
	return false


func near_light(pos: Vector3, radius: float) -> bool:
	for id in structs.list:
		var k: String = structs.list[id].kind
		if (k == "campfire" and structs.is_lit(id)) or k == "torch" or k == "furnace":
			if pos.distance_to(structs.list[id].pos) <= radius:
				return true
	for id in players:
		var p: Player = players[id]
		if p.held_id == "torch" and p.global_position.distance_to(pos) <= radius:
			return true
	return false


func hurt_player(p: Player, dmg: int, src: Vector3) -> void:
	if multiplayer.is_server() and is_instance_valid(p):
		p.net_hurt.rpc_id(p.peer_id, maxi(1, roundi(dmg * DIFFS[difficulty].dmg)), src)


func set_spawn_for(peer: int, pos: Vector3) -> void:
	var pname := Net.player_name(peer)
	var ps: Dictionary = player_saves.get(pname, {})
	ps.spawn = pos
	player_saves[pname] = ps
	_set_spawn.rpc_id(peer, pos)


@rpc("authority", "call_local", "reliable")
func _set_spawn(pos: Vector3) -> void:
	if local_player:
		local_player.spawn_point = pos
		hud.toast("여기서 다시 깨어난다 (침대)", Color("c8f7c5"))


func check_sleep() -> void:
	var alive := 0
	for id in players:
		if not players[id].downed:
			alive += 1
	var asleep := 0
	for id in structs.sleepers:
		if players.has(id):
			asleep += 1
	if asleep >= alive and alive > 0:
		structs.sleepers.clear()
		clock.skip_to_morning()
		_wake_all.rpc()
	else:
		broadcast_toast("%d/%d 명이 자는 중... 모두 누우면 아침이 된다" % [asleep, alive], "")


@rpc("authority", "call_local", "reliable")
func _wake_all() -> void:
	if local_player:
		local_player.wake_up()


@rpc("any_peer", "reliable")
func _upload_player(data: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	_store_player_save(Net.player_name(multiplayer.get_remote_sender_id()), data)


func _store_player_save(pname: String, data: Dictionary) -> void:
	var old: Dictionary = player_saves.get(pname, {})
	if old.has("spawn"):
		data.spawn = old.spawn
	player_saves[pname] = data


# ═════════ 호스트 → 손님 알림 ═════════

func give_to(peer: int, item: String, n: int, d: int = -1) -> void:
	if n > 0:
		_give.rpc_id(peer, item, n, d)


@rpc("authority", "call_local", "reliable")
func _give(item: String, n: int, d: int) -> void:
	if local_player:
		local_player.receive(item, n, d)


func toast_to(peer: int, text: String) -> void:
	_toast.rpc_id(peer, text)


@rpc("authority", "call_local", "reliable")
func _toast(text: String) -> void:
	hud.toast(text)


func broadcast_toast(text: String, sfx: String) -> void:
	_toast_all.rpc(text, sfx)


@rpc("authority", "call_local", "reliable")
func _toast_all(text: String, sfx: String) -> void:
	hud.toast(text, Color("ffe08a"))
	if sfx != "":
		Audio.play(sfx)


func unlock_hat_all(id: String) -> void:
	_unlock_hat.rpc(id)


@rpc("authority", "call_local", "reliable")
func _unlock_hat(id: String) -> void:
	if Settings.unlock_hat(id):
		hud.toast("새 모자 해금: %s! (타이틀 메뉴에서)" % Settings.HATS[id].name, Color("ffe08a"))


func announce_all(text: String) -> void:
	## 누구든 모두에게 알림 (기절 소식 등)
	_announce.rpc(text)


@rpc("any_peer", "call_local", "reliable")
func _announce(text: String) -> void:
	hud.toast(text, Color("ff9a8a"))


func sfx_all(name: String, pos: Vector3) -> void:
	_sfx.rpc(name, pos)


@rpc("authority", "call_local", "reliable")
func _sfx(name: String, pos: Vector3) -> void:
	Audio.play_at(name, pos)


func stat_add(key: String, n: int) -> void:
	if multiplayer.is_server():
		stats[key] = stats.get(key, 0) + n


@rpc("any_peer", "reliable")
func req_stat(key: String, n: int) -> void:
	if multiplayer.is_server():
		stat_add(key, n)


func add_stat(key: String, n: int) -> void:
	## 어느 쪽에서든 호출 가능
	if multiplayer.is_server():
		stat_add(key, n)
	else:
		req_stat.rpc_id(1, key, n)


func shake_all(amount: float) -> void:
	_shake_rpc.rpc(amount)


@rpc("authority", "call_local", "reliable")
func _shake_rpc(amount: float) -> void:
	shake_camera(amount, Vector3.INF)


# ═════════ 채팅 · 핑 ═════════

func send_chat(text: String) -> void:
	text = text.strip_edges().left(120)
	if text != "":
		_chat.rpc(text)


@rpc("any_peer", "call_local", "reliable")
func _chat(text: String) -> void:
	var from := multiplayer.get_remote_sender_id()
	hud.chat_line(Net.player_name(from), Net.player_color(from), text)
	var p := player_node(from)
	if p:
		p.say(text)


func send_ping(pos: Vector3) -> void:
	_ping.rpc(pos)


@rpc("any_peer", "call_local", "reliable")
func _ping(pos: Vector3) -> void:
	var from := multiplayer.get_remote_sender_id()
	var col := Net.player_color(from)
	var root := Node3D.new()
	fx_root.add_child(root)
	root.global_position = pos
	var beam := Vis.mesh_node(Vis._cyl(0.06, 6.0, 6), Vis.mat(Color(col, 0.55), true))
	beam.position.y = 3.0
	root.add_child(beam)
	var lb := Label3D.new()
	lb.text = "! %s" % Net.player_name(from)
	lb.font = Vis.font()
	lb.font_size = 56
	lb.outline_size = 12
	lb.modulate = col
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.no_depth_test = true
	lb.fixed_size = true
	lb.pixel_size = 0.0012
	lb.position.y = 1.2
	root.add_child(lb)
	Audio.play_at("select", pos, 4.0)
	hud.add_map_ping(pos, col)
	var tw := create_tween()
	tw.tween_interval(6.0)
	tw.tween_callback(root.queue_free)


# ═════════ 이펙트 ═════════

func fx_break(pos: Vector3, col: Color, amount: int = 10) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = amount
	p.lifetime = 0.7
	p.explosiveness = 0.95
	p.mesh = BoxMesh.new()
	(p.mesh as BoxMesh).size = Vector3(0.1, 0.1, 0.1)
	p.material_override = Vis.mat(col)
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.0
	p.gravity = Vector3(0, -14, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	fx_root.add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)


func fx_splash(pos: Vector3) -> void:
	fx_break(Vector3(pos.x, Terrain.WATER_Y, pos.z), Color(0.8, 0.93, 1.0, 0.9), 14)


func shake_camera(amount: float, src: Vector3) -> void:
	var a := amount
	if src != Vector3.INF and local_player:
		a *= clampf(1.0 - local_player.global_position.distance_to(src) / 25.0, 0.0, 1.0)
	_shake = maxf(_shake, 0.6)
	_shake_amp = maxf(_shake_amp, a)


func camera_shake_offset(delta: float) -> Vector3:
	if _shake <= 0.0:
		return Vector3.ZERO
	_shake -= delta
	var a := _shake_amp * clampf(_shake / 0.6, 0.0, 1.0)
	if _shake <= 0.0:
		_shake_amp = 0.0
	return Vector3(randf_range(-a, a), randf_range(-a, a), randf_range(-a, a)) * 0.35


# ═════════ 틱 ═════════

func _process(delta: float) -> void:
	if _join_wait > 0.0:
		_join_wait -= delta
		if _join_wait <= 0.0 and not world_ready:
			hud.fatal("응답이 없어. 호스트 주소와 방화벽을 확인해 줘")
	if not world_ready:
		return
	# 바다는 카메라를 따라다닌다 (끝없는 바다)
	var cam := get_viewport().get_camera_3d()
	if cam:
		ocean.global_position = Vector3(snappedf(cam.global_position.x, 8.0), Terrain.WATER_Y, snappedf(cam.global_position.z, 8.0))
	if local_player and not multiplayer.is_server():
		_upload_t -= delta
		if _upload_t <= 0.0:
			_upload_t = 5.0
			_upload_player.rpc_id(1, local_player.save_data())
	if multiplayer.is_server():
		_autosave_t -= delta
		if _autosave_t <= 0.0:
			_autosave_t = 180.0
			save_game()
	_music_t -= delta
	if _music_t <= 0.0 and not ending_playing:
		_music_t = 0.5
		Audio.music(_wanted_music())


var _music_t := 0.0


func _wanted_music() -> String:
	## 상어가 쫓아오거나 게 왕 근처면 긴장되는 음악
	if local_player:
		var me := local_player.global_position
		for id in ents.enemies:
			var e: Dictionary = ents.enemies[id]
			if not is_instance_valid(e.node):
				continue
			var d: float = (e.node as Node3D).global_position.distance_to(me)
			if e.kind == "king" and d < 16.0:
				return "danger"
			if e.kind == "shark" and e.state in ["chase", "hunt"] and d < 25.0:
				return "danger"
	return "night" if clock.is_night() else "day"


func _on_day_started(d: int) -> void:
	if multiplayer.is_server():
		save_game()
		hud.toast("자동 저장됨", Color("c8f7c5"))
	Audio.music("day")


func on_night() -> void:
	Audio.music("night")


# ═════════ 저장 ═════════

func save_game() -> void:
	if not multiplayer.is_server() or not world_ready:
		return
	if local_player:
		_store_player_save(Net.players.get(1, {}).get("name", "host"), local_player.save_data())
	for id in players:
		if id != 1:
			_store_player_save(Net.player_name(id), players[id].remote_save_hint(player_saves.get(Net.player_name(id), {})))
	var e := ents.snapshot()
	var rafts: Array = []
	for r in e.rafts:
		rafts.append({"id": r.id, "pos": r.pos, "yaw": r.yaw})   # 탄 사람(접속 id)은 저장하지 않는다
	e.rafts = rafts
	var names: Array = []
	for id in Net.players:
		names.append(Net.players[id].name)
	var data := {
		"version": SAVE_VERSION, "seed": world_seed, "terrain": terrain.diff_data(), "props": props.snapshot(),
		"structs": structs.snapshot(), "ents": {"next_id": e.next_id, "pickups": e.pickups, "rafts": e.rafts}, "clock": clock.snapshot(),
		"quests": quests.snapshot(), "stats": stats, "players": player_saves, "difficulty": difficulty,
		"meta": {"day": clock.day, "saved_at": Time.get_datetime_string_from_system(false, true), "names": names, "diff": difficulty},
	}
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var f := FileAccess.open(SAVE_DIR + slot + ".save", FileAccess.WRITE)
	if f:
		f.store_var(data)
		f.close()


static func load_save(s: String) -> Dictionary:
	var path := SAVE_DIR + s + ".save"
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var data = f.get_var()
	f.close()
	if data is Dictionary and data.get("version", 0) == SAVE_VERSION:
		return data
	return {}


static func save_meta(s: String) -> Dictionary:
	var d := load_save(s)
	return d.get("meta", {}) if not d.is_empty() else {}


func leave_to_title() -> void:
	if multiplayer.is_server():
		save_game()
	elif local_player:
		_upload_player.rpc_id(1, local_player.save_data())
	get_tree().paused = false
	await get_tree().create_timer(0.15).timeout
	Net.close()
	Audio.stop_all_ambience()
	get_tree().change_scene_to_file("res://scenes/ui/title.tscn")


# ═════════ 엔딩 ═════════

func try_depart(shipyard_id: int) -> void:
	var s: Dictionary = structs.list[shipyard_id]
	var at: Vector3 = s.pos
	var missing: Array = []
	for id in players:
		var p: Player = players[id]
		if p.global_position.distance_to(at) > 12.0:
			missing.append(Net.player_name(id))
	if missing.is_empty():
		start_ending("escape", shipyard_id)
	else:
		broadcast_toast("출항하려면 모두 모여야 해! 기다리는 중: " + ", ".join(missing), "error")


func start_ending(kind: String, where_id: int = -1) -> void:
	if not multiplayer.is_server() or ending_playing or quests.flag("ending_" + kind):
		return
	quests.set_flag("ending_" + kind)
	var s := stats.duplicate()
	s.day = clock.day
	var where := Vector3.ZERO
	if where_id >= 0 and structs.list.has(where_id):
		where = structs.list[where_id].pos
	elif kind == "adapt":
		var tid := structs.near("totem", Vector3.ZERO, 999.0)
		if tid >= 0:
			where = structs.list[tid].pos
	_ending.rpc(kind, s, where)
	save_game()


@rpc("authority", "call_local", "reliable")
func _ending(kind: String, s: Dictionary, where: Vector3) -> void:
	ending_playing = true
	if multiplayer.is_server():
		for r in ents.rafts.values():
			r.input.clear()   # 연출 중엔 뗏목이 혼자 떠내려가지 않게
	var cine := preload("res://scripts/world/ending_cine.gd").new()
	add_child(cine)
	cine.play(kind, s, where)


# ═════════ 오프닝 ═════════

var _intro_cam: Camera3D
var _intro_tw: Tween


func _play_intro() -> void:
	## 새 섬: 하늘에서 군도를 훑고 캐릭터 뒤로 내려온다. 아무 키나 누르면 건너뛴다
	if DisplayServer.get_name() == "headless" or local_player == null:
		hud.toast("눈을 떠 보니... 작은 섬이다. 떠밀려온 상자부터 열어 보자 (E)", Color("ffe08a"))
		return
	ending_playing = true
	hud.set_cinematic(true)
	_intro_cam = Camera3D.new()
	_intro_cam.fov = 60.0
	_intro_cam.far = 400.0
	add_child(_intro_cam)
	_intro_cam.current = true
	var center := Vector3(6, 0, 8)
	var end_pos := local_player.camera.global_position
	var end_look := local_player.global_position + Vector3.UP * 1.2
	_intro_tw = create_tween()
	_intro_tw.tween_method(func(t: float):
		var a := lerpf(-0.6, 1.9, t)
		var r := lerpf(55.0, 30.0, t)
		_intro_cam.global_position = center + Vector3(cos(a) * r, lerpf(34.0, 18.0, t), sin(a) * r)
		_intro_cam.look_at(center.lerp(end_look, t * t)), 0.0, 1.0, 5.0).set_trans(Tween.TRANS_SINE)
	_intro_tw.tween_method(func(t: float):
		var from := center + Vector3(cos(1.9) * 30.0, 18.0, sin(1.9) * 30.0)
		_intro_cam.global_position = from.lerp(end_pos, t)
		_intro_cam.look_at(end_look), 0.0, 1.0, 2.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_intro_tw.tween_callback(_end_intro)
	hud.toast("무인도 버디즈", Color("ffe08a"))


func _end_intro() -> void:
	if _intro_cam == null:
		return
	if _intro_tw and _intro_tw.is_valid():
		_intro_tw.kill()
	_intro_cam.queue_free()
	_intro_cam = null
	ending_playing = false
	hud.set_cinematic(false)
	if local_player:
		local_player.camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.toast("눈을 떠 보니... 작은 섬이다. 떠밀려온 상자부터 열어 보자 (E)", Color("ffe08a"))


func _unhandled_input(event: InputEvent) -> void:
	if _intro_cam and (event is InputEventKey or event is InputEventMouseButton) and event.is_pressed():
		_end_intro()
		get_viewport().set_input_as_handled()


func end_cinematic_done() -> void:
	ending_playing = false
	if _host_lost:
		hud.fatal("호스트와 연결이 끊어졌어")
