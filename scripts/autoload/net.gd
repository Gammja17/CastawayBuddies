extends Node
## 접속 관리. 호스트가 세계의 주인(서버)이고, 각자 자기 캐릭터와 가방의 주인이다.
## 게임 씬을 먼저 띄운 다음 접속한다 (RPC 가 도착할 노드가 먼저 있어야 해서).

signal players_changed
signal connected_ok
signal connect_failed(reason: String)
signal server_lost

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


func start_host(port: int, try_upnp: bool) -> Error:
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


func player_name(id: int) -> String:
	return players.get(id, _left.get(id, {})).get("name", "???")


func player_color(id: int) -> Color:
	var c: int = players.get(id, {}).get("color", 0)
	return Settings.COLORS[clampi(c, 0, Settings.COLORS.size() - 1)]


# ── 접속 이벤트 ──

func _on_peer_connected(_id: int) -> void:
	pass   # 손님이 register 를 보내면 그때 목록에 넣는다


func _on_peer_disconnected(id: int) -> void:
	if players.has(id):
		_left[id] = players[id]
	if players.erase(id):
		if multiplayer.is_server():
			_sync_players.rpc(players)
		players_changed.emit()


func _on_connected() -> void:
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
