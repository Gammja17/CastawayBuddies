class_name Quests
extends Node
## 세 갈래 루트(탈출 / 적응 / 거북이)와 쪽지. 모두가 같은 일지를 공유한다.

signal updated

const NOTES := {
	"note_start": {"title": "전 표류자 김씨의 쪽지", "text": "이 쪽지를 읽는 불쌍한 친구에게. 나는 김씨. 여기서 3주 버텼다.\n\n1) 야자수를 맨손으로 때려라. 손은 아프지만 통나무가 나온다. 가끔 코코넛도 떨어진다.\n2) 바닥에 굴러다니는 막대기와 돌멩이를 주워라. (근처로 걸어가면 알아서 주워진다)\n3) 통나무 4 + 돌멩이 2 로 [작업대]를 만들어라. 그 옆에서 더 많은 걸 만들 수 있다.\n4) 목이 마르면 코코넛. 바닷물은 빈 병에 떠서 모닥불에 끓여 마셔라.\n5) 밤에는 게가 사나워진다. 불 근처로 가라.\n\n동쪽 얕은 모래길을 따라가면 숲섬이 있다. 행운을 빈다.\n- 김씨"},
	"sign_home": {"title": "김씨의 팻말", "text": "[여기 코코넛 있음]\n\n모래길은 동쪽.\n상어는 깊은 바다에서 오래 헤엄치는 놈을 노린다.\n다리를 놓아라! 판자 블록은 물 위에도 놓인다.\n\n나는 먼저 간다. 어디로 갔는지는 비밀.\n- 김씨"},
	"captain_log": {"title": "선장 일지", "text": "...폭풍에 배가 두 동강 났다. 선원들은 모두 헤엄쳐 도망쳤고 나는 금고를 지킨다.\n\n이 섬을 떠나려면 제대로 된 배가 필요하다:\n  / 선체 - 판자 40, 밧줄 6\n  / 돛과 돛대 - 통나무 12, 천 8, 밧줄 6\n  / 나침반 - 내 금고 안에 있다. 쇠지렛대로 비틀어 열 것 (열쇠는 게가 먹었다)\n  / 항해 식량 - 익힌 음식 10, 깨끗한 물 8\n\n물가에 [조선소]를 지어라 (작업대에서 만든다).\n고철은 화덕에서 녹이면 철이 된다. 화덕은 돌과 점토로.\n점토는 숲섬 물가의 붉은 흙이다. 삽으로 파면 된다.\n\n추신: 이 섬, 가끔 움직이는 것 같다."},
	"treasure_map": {"title": "낡은 보물 지도", "text": "금고 안에서 나온 꼬깃꼬깃한 지도.\n\n숲섬 북쪽 해변에 커다란 X 표시가 있다.\n'삽으로 파시오. 진짜임.' 이라고 적혀 있다.\n\n(지도[M]에 표시가 생겼다)"},
	"treasure_note": {"title": "보물 상자 속 쪽지", "text": "축하합니다!\n당신은 이 보물의 999번째 발견자입니다.\n경품은 황금 조개입니다.\n\n...잠깐, 그럼 앞의 998명은?"},
	"tablet_1": {"title": "고대 석판 I", "text": "벽화가 새겨져 있다.\n\n거대한 거북이가 잠들어 있다. 그 등 위에는 야자수와 작은 사람들이 있다.\n그 아래, 해초를 산처럼 쌓아 올린 잔칫상.\n\n'잠든 섬을 깨우려면, 먼저 배불리 먹여라.'\n\n(해초 20 + 구운 생선 5 + 코코넛 5 = 해초 잔치상 / 모닥불에서)"},
	"tablet_2": {"title": "고대 석판 II", "text": "황금빛 조개 세 개가 거북 제단 위에 놓여 있다.\n옆에서는 왕관을 쓴 게가 조개를 끌어안고 있다.\n\n'빛나는 조개 셋을 바쳐라. 게들의 왕은 욕심이 많다.'\n\n신전 문 양옆에는 발자국 두 쌍이 새겨져 있다.\n...두 발판을 동시에 눌러야 하나 보다. 무거운 것을 올려 두어도 될까?"},
	"tablet_3": {"title": "고대 석판 III", "text": "두 사람이 멀리 떨어진 두 종을 동시에 치고 있다.\n거북이가 눈을 뜬다.\n\n'두 종이 한 목소리로 울릴 때, 섬이 일어나리라.'\n\n구석에 작은 글씨로:\n'친구가 없는 자는 태엽의 힘을 빌려라.' (태엽 뭉치 -> 태엽 종치기)"},
}

const BOTTLE_NOTES := [
	"모래 포집기를 얕은 물가에 두면 파도가 모래를 쌓아 준다. 섬을 넓혀라!\n- 김씨",
	"게들은 불빛을 싫어한다. 횃불 하나면 밤이 덜 무섭다.",
	"화덕 = 돌멩이 12 + 점토 6. 점토는 숲섬 물가의 붉은 흙이다. 삽으로 파라.",
	"7일을 버티고, 섬을 넓히고, 밭을 가꾸고, 모두의 침대를 놓은 자들은 섬의 주인이 된다고 한다.\n마을 토템을 세워라.",
	"게 왕은 유적섬 해변에 산다. 혼자 가지 마라. 진짜로.",
	"난파선 선장의 금고... 쇠지렛대가 필요하다. 철은 고철을 녹여서.",
	"섬이 가끔 흔들리는 거 느꼈어? 나만 그래?",
	"낚싯대로 아주 가끔 황금 조개가 낚인다는 소문이 있다. 소문이다.",
	"도와주세요. 저는 병 속 쪽지를 쓰는 사람입니다. 벌써 400장째입니다.",
	"신전 문 앞 두 발판... 무거운 걸 올려놔도 된다더라. 블록 같은 거.",
	"갈고리가 있으면 떠다니는 잔해를 멀리서 낚아챌 수 있다. 막대기 2 + 밧줄 2 + 부싯돌 1.",
	"비가 오면 빗물받이가 빨리 찬다. 빈 병은 버리지 마라.",
]

const BLOCK_GOAL := 120

const ROUTES := {
	"escape": {"name": "탈출 루트", "sub": "이 섬을 떠나 집으로!", "steps": [
		{"flag": "escape_known", "text": "난파선을 조사하자", "hint": "남쪽 모래톱에 부서진 배가 있다. 선장 일지가 있을지도."},
		{"flag": "shipyard_built", "text": "물가에 조선소 짓기", "hint": "작업대: 판자 20, 통나무 10, 밧줄 8, 철 4 (철은 화덕에서 고철/철광석을 녹여서)"},
		{"flag": "ship_hull", "text": "선체 (판자 40, 밧줄 6)", "hint": "조선소에 E 로 재료를 넣는다. 다 같이 모으자."},
		{"flag": "ship_sail", "text": "돛과 돛대 (통나무 12, 천 8, 밧줄 6)", "hint": "천은 난파선과 떠다니는 잔해에서."},
		{"flag": "ship_compass", "text": "나침반", "hint": "선장의 금고 안. 쇠지렛대(철 3)로 연다."},
		{"flag": "ship_food", "text": "항해 식량 (익힌 음식 10, 깨끗한 물 8)", "hint": "모닥불에서 굽고 끓이자."},
		{"flag": "ending_escape", "text": "모두 조선소에 모여 출항!", "hint": "모든 생존자가 조선소 근처에 있어야 한다."},
	]},
	"adapt": {"name": "적응 루트", "sub": "여기가 우리 집이다", "steps": [
		{"count": "day", "need": 7, "text": "7일 버티기", "hint": "밤엔 불 근처에서."},
		{"count": "blocks_placed", "need": BLOCK_GOAL, "text": "섬 넓히기: 블록 120개 쌓기", "hint": "모래 포집기(물가), 판자 블록, 돌 블록... 부수면 줄어든다"},
		{"count": "harvests", "need": 10, "text": "밭에서 10번 수확", "hint": "감자는 난파선에서. 산딸기도 심을 수 있다."},
		{"count": "beds", "need": -1, "text": "모두의 침대 (인원수만큼)", "hint": "작업대: 판자 4, 야자잎 8"},
		{"flag": "ending_adapt", "text": "마을 토템을 세우고 축제 시작!", "hint": "작업대: 판자 20, 벽돌 10, 조개껍데기 8, 천 3 -> 설치 후 E"},
	]},
	"turtle": {"name": "???", "real_name": "거북이 루트", "sub": "이 섬... 뭔가 이상하다", "reveal": "turtle_seen", "steps": [
		{"flag": "turtle_seen", "text": "섬의 비밀을 눈치채기", "hint": "지진이 나거나, 고대 석판을 읽으면..."},
		{"count": "tablets", "need": 3, "text": "고대 석판 3개 읽기", "hint": "돌섬 동굴 안, 유적 앞, 그리고 신전 안."},
		{"flag": "feast_offered", "text": "거북 제단에 해초 잔치상 바치기", "hint": "모닥불: 해초 20, 구운 생선 5, 코코넛 5"},
		{"count": "shells_offered", "need": 3, "text": "황금 조개 3개 바치기", "hint": "신전 상자, 보물, 그리고 게 왕..."},
		{"flag": "ending_turtle", "text": "두 종을 동시에 울리기", "hint": "유적 양쪽 끝의 종. 둘이서 (또는 태엽 종치기)."},
	]},
}

var flags := {}
var counts := {}
var notes: Array = []
var bottle_i := 0


func snapshot() -> Dictionary:
	return {"flags": flags, "counts": counts, "notes": notes, "bottle_i": bottle_i}


func apply(s: Dictionary) -> void:
	flags = s.get("flags", {})
	counts = s.get("counts", {})
	notes = s.get("notes", [])
	bottle_i = s.get("bottle_i", 0)
	updated.emit()


func flag(f: String) -> bool:
	return flags.get(f, false)


func count(c: String) -> int:
	match c:
		"day":
			return Game.I.clock.day if Game.I else 0
		"beds":
			return Game.I.structs.count_kind("bed") if Game.I else 0
	return counts.get(c, 0)


func need_of(step: Dictionary) -> int:
	var n: int = step.get("need", 0)
	if n < 0:
		return maxi(1, Net.players.size())
	return n


func step_done(step: Dictionary) -> bool:
	if step.has("flag"):
		return flag(step.flag)
	return count(step.count) >= need_of(step)


func route_progress(key: String) -> Array:
	## [완료 수, 전체]
	var steps: Array = ROUTES[key].steps
	var done := 0
	for s in steps:
		if step_done(s):
			done += 1
	return [done, steps.size()]


# ── 호스트 쪽 변경 ──

func set_flag(f: String) -> void:
	if not multiplayer.is_server() or flag(f):
		return
	flags[f] = true
	_after_change()
	match f:
		"escape_known": Game.I.broadcast_toast("일지에 [탈출 루트]가 생겼다! (J)", "quest")
		"shipyard_built", "temple_open", "feast_offered": pass
		"treasure_map": Game.I.structs.refresh_all("dig_spot")


func add_count(c: String, n: int) -> void:
	if not multiplayer.is_server():
		return
	counts[c] = counts.get(c, 0) + n
	_after_change()


func set_count(c: String, n: int) -> void:
	if not multiplayer.is_server():
		return
	counts[c] = n
	_after_change()


func _after_change() -> void:
	_sync.rpc(snapshot())


@rpc("authority", "call_local", "reliable")
func _sync(s: Dictionary) -> void:
	var before_flags := flags.duplicate()
	apply(s)
	if not multiplayer.is_server():
		if flag("treasure_map") and not before_flags.get("treasure_map", false):
			Game.I.structs.refresh_all("dig_spot")


func on_block_placed() -> void:
	counts["blocks_placed"] = counts.get("blocks_placed", 0) + 1
	var n: int = counts.blocks_placed
	if n % 10 == 0 or n == BLOCK_GOAL:
		_after_change()
	if n == BLOCK_GOAL:
		Game.I.broadcast_toast("섬이 꽤 넓어졌다! (적응 루트)", "quest")


func on_block_removed() -> void:
	var n: int = maxi(0, counts.get("blocks_placed", 0) - 1)
	counts["blocks_placed"] = n
	if n % 10 == 9:
		_after_change()


func on_struct_placed(kind: String) -> void:
	match kind:
		"shipyard": set_flag("shipyard_built")
		"bed": _after_change()


func on_quake() -> void:
	if not flag("turtle_seen"):
		set_flag("turtle_seen")
		Game.I.broadcast_toast("일지에 알 수 없는 루트가 생겼다...? (J)", "quest")


func find_note(id: String, by: int) -> void:
	## 호스트: 누가 쪽지/석판을 읽었다
	if not multiplayer.is_server():
		return
	_show_note.rpc_id(by, id, "")
	if id in notes:
		return
	notes.append(id)
	match id:
		"captain_log": set_flag("escape_known")
		"treasure_map": set_flag("treasure_map")
		"tablet_1", "tablet_2", "tablet_3":
			counts["tablets"] = counts.get("tablets", 0) + 1
			if not flag("turtle_seen"):
				flags["turtle_seen"] = true
				Game.I.broadcast_toast("일지에 알 수 없는 루트가 생겼다...? (J)", "quest")
	_after_change()
	if by != 0:
		Game.I.broadcast_toast("%s [%s] 발견했다" % [Items.josa(Net.player_name(by), "이", "가"), NOTES.get(id, {}).get("title", id)], "book")


func find_bottle_note(by: int) -> void:
	if not multiplayer.is_server():
		return
	var text: String = BOTTLE_NOTES[bottle_i % BOTTLE_NOTES.size()]
	bottle_i += 1
	_show_note.rpc_id(by, "", text)
	_after_change()


@rpc("authority", "call_local", "reliable")
func _show_note(id: String, text: String) -> void:
	if Game.I and Game.I.hud:
		if id != "":
			Game.I.hud.show_note(NOTES[id].title, NOTES[id].text)
		else:
			Game.I.hud.show_note("병 속의 쪽지", text)


# ── 엔딩 판정 ──

func try_adapt_ending(from: int) -> void:
	var missing: Array = []
	for s in ROUTES.adapt.steps:
		if s.has("flag"):
			continue
		if not step_done(s):
			missing.append("%s (%d/%d)" % [s.text, count(s.count), need_of(s)])
	if missing.is_empty():
		Game.I.start_ending("adapt")
	else:
		Game.I.toast_to(from, "아직 축제를 열 수 없어: " + ", ".join(missing))


func on_bells_together() -> void:
	var altar_ok := flag("feast_offered") and count("shells_offered") >= 3
	if altar_ok and count("tablets") >= 3:
		Game.I.start_ending("turtle")
	elif altar_ok:
		Game.I.broadcast_toast("두 종소리가 겹쳐 울렸다! 섬이 크게 꿈틀... 하지만 석판의 가르침을 다 읽지 못했다.", "rumble")
	else:
		Game.I.broadcast_toast("두 종소리가 섬을 울렸다... 거북 제단이 허전해 보인다.", "rumble")
		Game.I.shake_all(0.6)
