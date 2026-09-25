extends Node
## 접속 관리. 호스트가 세계의 주인(서버)이고, 각자 자기 캐릭터와 가방의 주인이다.
## 게임 씬을 먼저 띄운 다음 접속한다 (RPC 가 도착할 노드가 먼저 있어야 해서).

signal players_changed
signal connected_ok
signal connect_failed(reason: String)
signal server_lost
signal room_ready(code: String)   # 웹판: 방 코드가 생겼다

const DEFAULT_PORT := 24680
const MAX_PLAYERS := 4

## 타이틀에서 게임 씬으로 넘길 요청: {"mode": "solo"|"host"|"join", "ip", "port", "slot", "new": bool}
var pending: Dictionary = {}
## peer_id -> {"name", "color"}
var players: Dictionary = {}
var _left: Dictionary = {}     # 나간 사람 이름 (나간 직후 저장할 때 쓴다)
var host_port := DEFAULT_PORT
var upnp_status := ""
var public_ip := ""
var _upnp: UPNP
var _upnp_port := DEFAULT_PORT
var _upnp_thread: Thread

# ── 웹판: 브라우저끼리 WebRTC 로 직접 연결. 처음 서로 찾는 것만 공개 중개 서버(PeerJS)에 맡긴다 ──
# 중개 서버는 PeerJS 모양의 메시지만 전달해 줘서, 우리 말은 CANDIDATE 의 candidate 글자 안에 JSON 으로 넣어 보낸다.
const RTC_SIGNAL := "wss://0.peerjs.com/peerjs?key=peerjs&id=%s&token=%s"
const RTC_PREFIX := "castawaybuddies-v2-"
const RTC_ICE := {"iceServers": [{"urls": ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"]}]}
const CODE_CHARS := "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
const JOIN_TIMEOUT := 25.0

var room_code := ""       # 웹판 방 코드 (호스트가 만들고, 손님은 입력한다)
var rtc_status := ""
var _ws: WebSocketPeer
var _ws_id := ""
var _ws_token := ""
var _ws_open := false
var _ws_retry := -1.0
var _hb_t := 0.0
var _rtc: WebRTCMultiplayerPeer
var _links := {}          # 상대 중개 id -> {"peer": int, "conn": WebRTCPeerConnection}
var _host_sid := ""
var _next_peer := 2
var _join_t := -1.0
var _hosting := false      # 웹판 방장인가 (접속 전엔 multiplayer.is_server() 가 늘 참이라 따로 둔다)


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_failed)
	multiplayer.server_disconnected.connect(_on_server_lost)


func is_online() -> bool:
	return multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)


func my_id() -> int:
	return multiplayer.get_unique_id()


func start_solo() -> void:
	close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players = {1: _me()}
	players_changed.emit()


func _me() -> Dictionary:
	return {"name": Settings.player_name, "color": Settings.player_color, "hat": Settings.hat}


static func use_rtc() -> bool:
	## 브라우저에선 포트를 못 여니 방 코드(WebRTC)로. 개발용: -- --rtc (데스크톱은 중개 서버까지만 된다)
	return OS.has_feature("web") or "--rtc" in OS.get_cmdline_user_args()


func start_host(port: int, try_upnp: bool) -> Error:
	if use_rtc():
		return _rtc_host()
	close()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	host_port = port
	players = {1: _me()}
	players_changed.emit()
	if try_upnp:
		_upnp_thread = Thread.new()
		_upnp_thread.start(_upnp_open.bind(port))
	return OK


func start_join(ip: String, port: int) -> Error:
	if use_rtc():
		return _rtc_join(ip)
	close()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	players = {}
	return OK


func close() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players = {}
	_upnp_close()
	_ws_close()
	_rtc = null
	_links.clear()
	room_code = ""
	rtc_status = ""
	_join_t = -1.0
	_hosting = false


func player_name(id: int) -> String:
	return players.get(id, _left.get(id, {})).get("name", "???")


func player_color(id: int) -> Color:
	var c: int = players.get(id, {}).get("color", 0)
	return Settings.COLORS[clampi(c, 0, Settings.COLORS.size() - 1)]


# ── 접속 이벤트 ──

func _on_peer_connected(_id: int) -> void:
	pass   # 손님이 register 를 보내면 그때 목록에 넣는다


func _on_peer_disconnected(id: int) -> void:
	for sid in _links.keys():
		if _links[sid].peer == id:
			_links.erase(sid)
	if players.has(id):
		_left[id] = players[id]
	if players.erase(id):
		if multiplayer.is_server():
			_sync_players.rpc(players)
		players_changed.emit()


func _on_connected() -> void:
	if use_rtc():
		_join_t = -1.0
		_ws_close()   # 손님은 연결되면 중개 서버가 더는 필요 없다
	print("[호스트와 연결됨] 내 번호 ", my_id())
	_register.rpc_id(1, Settings.player_name, Settings.player_color, Settings.hat)
	connected_ok.emit()


func _on_failed() -> void:
	connect_failed.emit("접속 실패: 주소나 포트를 확인해 줘")


func _on_server_lost() -> void:
	server_lost.emit()


@rpc("any_peer", "reliable")
func _register(pname: String, pcolor: int, phat: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	# 이름 겹치면 번호 붙이기 (저장이 이름 기준이라)
	var base := pname.strip_edges().left(12)
	if base == "":
		base = "무명"
	var n := base
	var k := 2
	while _name_taken(n, id):
		n = "%s%d" % [base, k]
		k += 1
	players[id] = {"name": n, "color": pcolor, "hat": phat if Settings.HATS.has(phat) else "straw"}
	print("[들어옴] ", n, " (", id, ")")
	_sync_players.rpc(players)
	players_changed.emit()


func _name_taken(n: String, except_id: int) -> bool:
	for pid in players:
		if pid != except_id and players[pid].name == n:
			return true
	return false


@rpc("authority", "reliable")
func _sync_players(list: Dictionary) -> void:
	players = list
	players_changed.emit()


# ── 웹판: 방 코드 ──

func _rtc_host() -> Error:
	close()
	_rtc = WebRTCMultiplayerPeer.new()
	var err := _rtc.create_server()
	if err != OK:
		return err
	multiplayer.multiplayer_peer = _rtc
	_hosting = true
	players = {1: _me()}
	players_changed.emit()
	_next_peer = 2
	_new_room()
	return OK


func _new_room() -> void:
	room_code = ""
	for i in 5:
		room_code += CODE_CHARS[randi() % CODE_CHARS.length()]
	rtc_status = "방 코드 받는 중..."
	_ws_connect(RTC_PREFIX + room_code.to_lower())


func _rtc_join(code: String) -> Error:
	close()
	room_code = code.strip_edges().to_upper().replace(" ", "")
	if room_code.length() < 4:
		return ERR_INVALID_PARAMETER
	_rtc = WebRTCMultiplayerPeer.new()
	_host_sid = RTC_PREFIX + room_code.to_lower()
	_join_t = JOIN_TIMEOUT
	_ws_connect(RTC_PREFIX + "c%d" % randi())
	return OK


func invite_link() -> String:
	## 웹판 초대 링크 (누르면 바로 이 방에 들어온다)
	if room_code == "" or not OS.has_feature("web"):
		return ""
	var here: String = str(JavaScriptBridge.eval("location.origin + location.pathname", true))
	return "%s?join=%s" % [here, room_code]


func _ws_connect(id: String, token: String = "") -> void:
	_ws_close()
	_ws = WebSocketPeer.new()
	_ws_id = id
	_ws_token = token if token != "" else str(randi())
	_ws_open = false
	_ws_retry = -1.0
	_hb_t = 5.0
	if _ws.connect_to_url(RTC_SIGNAL % [id, _ws_token]) != OK:
		_on_ws_lost()


func _ws_close() -> void:
	if _ws:
		_ws.close()
	_ws = null
	_ws_open = false


func _ws_send(dst: String, obj: Dictionary) -> void:
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var payload := {"type": "data", "connectionId": "dc_castaway", "candidate": {"candidate": JSON.stringify(obj), "sdpMid": "0", "sdpMLineIndex": 0}}
	_ws.send_text(JSON.stringify({"type": "CANDIDATE", "dst": dst, "payload": payload}))


func _process(delta: float) -> void:
	if _join_t > 0.0:
		_join_t -= delta
		if _join_t <= 0.0:
			var reason := "방에 들어가지 못했어 (방 코드를 확인하거나, 공유기 사정으로 연결이 막혔을 수도)"
			close()
			connect_failed.emit(reason)
			return
	if _ws_retry > 0.0:
		_ws_retry -= delta
		if _ws_retry <= 0.0 and _hosting:
			rtc_status = "중개 서버에 다시 붙는 중..."
			_ws_connect(_ws_id, _ws_token)   # 같은 방 코드 그대로
	if _hosting:
		_prune_links()
	if _ws == null:
		return
	_ws.poll()
	var st := _ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		while _ws and _ws.get_available_packet_count() > 0:   # 처리하다 연결을 닫을 수도 있다
			var msg = JSON.parse_string(_ws.get_packet().get_string_from_utf8())
			if msg is Dictionary:
				_on_signal(msg)
		_hb_t -= delta
		if _hb_t <= 0.0 and _ws:
			_hb_t = 5.0
			_ws.send_text(JSON.stringify({"type": "HEARTBEAT"}))
	elif st == WebSocketPeer.STATE_CLOSED:
		_on_ws_lost()


func _on_ws_lost() -> void:
	_ws = null
	_ws_open = false
	if _hosting:
		rtc_status = "중개 서버와 끊겼다 - 새 친구는 잠깐 못 들어온다"
		_ws_retry = 5.0
	elif _join_t > 0.0:
		var reason := "중개 서버에 연결하지 못했어 (인터넷 연결 확인)"
		close()
		connect_failed.emit(reason)


func _on_signal(msg: Dictionary) -> void:
	match msg.get("type", ""):
		"OPEN":
			_ws_open = true
			print("[중개 서버 연결] ", "방장" if _hosting else "손님")
			if _hosting:
				rtc_status = "방 코드: %s" % room_code
				print("[방 코드] ", room_code)
				room_ready.emit(room_code)
			else:
				_ws_send(_host_sid, {"k": "join"})
		"ID-TAKEN":
			if _hosting:
				_new_room()   # 드물게 코드가 겹쳤다
			else:
				_ws_connect(RTC_PREFIX + "c%d" % randi())
		"ERROR":
			rtc_status = "중개 서버 오류"
		"EXPIRE":
			print("[중개 서버] 상대 없음: ", msg.get("src", ""))
			if not _hosting and msg.get("src", "") == _host_sid:
				var reason := "방 %s 을(를) 찾을 수 없어. 방 코드를 확인해 줘" % room_code
				close()
				connect_failed.emit(reason)
		"CANDIDATE":
			var inner = msg.get("payload", {}).get("candidate", {}).get("candidate", "")
			var obj = JSON.parse_string(inner) if inner is String else null
			if obj is Dictionary:
				_on_rtc_msg(str(msg.get("src", "")), obj)


func _on_rtc_msg(src: String, m: Dictionary) -> void:
	match m.get("k", ""):
		"join":   # 호스트: 누가 들어오고 싶어 한다
			if not _hosting or _rtc == null or _links.has(src):
				return
			if _links.size() + 1 >= MAX_PLAYERS:
				_ws_send(src, {"k": "full"})
				return
			var pid := _next_peer
			_next_peer += 1
			var conn := _new_conn(src)
			_links[src] = {"peer": pid, "conn": conn, "t": Time.get_ticks_msec()}
			_rtc.add_peer(conn, pid)
			conn.create_offer()
		"offer":  # 손님: 호스트가 번호와 연결 정보를 보냈다
			if _hosting or src != _host_sid or _links.has(src):
				return
			_rtc.create_client(int(m.get("id", 0)))
			multiplayer.multiplayer_peer = _rtc
			var conn2 := _new_conn(src)
			_links[src] = {"peer": 1, "conn": conn2}
			_rtc.add_peer(conn2, 1)
			conn2.set_remote_description("offer", str(m.get("sdp", "")))
		"answer":
			if _links.has(src):
				(_links[src].conn as WebRTCPeerConnection).set_remote_description("answer", str(m.get("sdp", "")))
		"ice":
			if _links.has(src):
				(_links[src].conn as WebRTCPeerConnection).add_ice_candidate(str(m.get("mid", "")), int(m.get("idx", 0)), str(m.get("cand", "")))
		"full":
			if src == _host_sid:
				close()
				connect_failed.emit("방이 꽉 찼어 (%d명)" % MAX_PLAYERS)


func _prune_links() -> void:
	## 30초 안에 못 들어온 손님 자리는 비운다
	var now := Time.get_ticks_msec()
	for sid in _links.keys():
		var l: Dictionary = _links[sid]
		if not players.has(l.peer) and now - int(l.get("t", now)) > 30000:
			if _rtc and _rtc.has_peer(l.peer):
				_rtc.remove_peer(l.peer)
			_links.erase(sid)


func _new_conn(sid: String) -> WebRTCPeerConnection:
	var conn := WebRTCPeerConnection.new()
	conn.initialize(RTC_ICE)
	conn.session_description_created.connect(func(type: String, sdp: String):
		conn.set_local_description(type, sdp)
		if type == "offer":
			_ws_send(sid, {"k": "offer", "id": _links[sid].peer, "sdp": sdp})
		else:
			_ws_send(sid, {"k": "answer", "sdp": sdp}))
	conn.ice_candidate_created.connect(func(mid: String, idx: int, cand: String):
		_ws_send(sid, {"k": "ice", "mid": mid, "idx": idx, "cand": cand}))
	return conn


# ── UPnP (공유기 포트 자동 열기) ──

func _upnp_open(port: int) -> void:
	_upnp_port = port
	_upnp = UPNP.new()
	var err := _upnp.discover(2000, 2)
	if err != OK or _upnp.get_gateway() == null or not _upnp.get_gateway().is_valid_gateway():
		upnp_status = "UPnP 실패 (공유기가 지원 안 함) - 같은 와이파이/VPN 으로 접속하세요"
		return
	var r1 := _upnp.add_port_mapping(port, port, "CastawayBuddies", "UDP")
	if r1 == UPNP.UPNP_RESULT_SUCCESS:
		public_ip = _upnp.query_external_address()
		upnp_status = "포트 열림! 친구는 %s 로 접속" % public_ip
	else:
		upnp_status = "UPnP 포트 열기 실패 - 같은 와이파이/VPN 으로 접속하세요"


func _upnp_close() -> void:
	if _upnp_thread:
		_upnp_thread.wait_to_finish()
		_upnp_thread = null
	if _upnp and public_ip != "":
		_upnp.delete_port_mapping(_upnp_port, "UDP")
	_upnp = null
	public_ip = ""
	upnp_status = ""


func _exit_tree() -> void:
	_upnp_close()


static func local_ips() -> Array:
	var out: Array = []
	for ip in IP.get_local_addresses():
		if ip.count(".") == 3 and not ip.begins_with("127.") and not ip.begins_with("169.254"):
			out.append(ip)
	return out
