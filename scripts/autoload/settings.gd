extends Node
## 설정 저장/불러오기 + 입력 키 등록.

const PATH := "user://settings.cfg"

var player_name := ""
var player_color := 0
var last_ip := "127.0.0.1"
var master_vol := 0.8
var music_vol := 0.6
var sfx_vol := 0.8
var sensitivity := 0.25
var invert_y := false
var fov := 75.0
var fullscreen := false
var show_fps := false
var gfx := 1 if OS.has_feature("web") else 0      # 0 높음, 1 보통, 2 낮음 (웹은 느려서 처음엔 보통)
var gfx_chosen := false   # 설정에서 직접 골랐나 (안 골랐으면 기본값을 따라간다)
var hat := "straw"
var hats_unlocked: Array = ["straw", "none"]
const HATS := {
	"straw": {"name": "밀짚모자", "how": "처음부터"},
	"none": {"name": "맨머리", "how": "처음부터"},
	"captain": {"name": "선장 모자", "how": "탈출 엔딩"},
	"flower": {"name": "꽃 화관", "how": "적응 엔딩"},
	"turtle": {"name": "거북 등딱지 투구", "how": "??? 엔딩"},
	"crab": {"name": "게 왕관", "how": "게 왕 물리치기"},
}


func unlock_hat(id: String) -> bool:
	## 새로 풀렸으면 true
	if id in hats_unlocked or not HATS.has(id):
		return false
	hats_unlocked.append(id)
	save_cfg()
	return true
const GFX_NAMES := ["높음", "보통", "낮음 (느린 PC)"]

const COLORS := [Color("ffcf4a"), Color("ff6b6b"), Color("4fc3f7"), Color("7ddc6a"), Color("c792ea"), Color("ff9f43"), Color("f8f8f2"), Color("f06fb0")]
const COLOR_NAMES := ["노랑", "빨강", "파랑", "초록", "보라", "주황", "하양", "분홍"]

const KEYS := {
	"move_forward": [KEY_W], "move_back": [KEY_S], "move_left": [KEY_A], "move_right": [KEY_D],
	"jump": [KEY_SPACE], "sprint": [KEY_SHIFT], "interact": [KEY_E], "drop": [KEY_Q],
	"inventory": [KEY_TAB, KEY_I], "journal": [KEY_J], "camera": [KEY_V], "chat": [KEY_T, KEY_ENTER],
	"pause": [KEY_ESCAPE], "ping": [KEY_F], "map": [KEY_M], "wave": [KEY_G],
	"slot_1": [KEY_1], "slot_2": [KEY_2], "slot_3": [KEY_3], "slot_4": [KEY_4], "slot_5": [KEY_5],
	"slot_6": [KEY_6], "slot_7": [KEY_7], "slot_8": [KEY_8], "slot_9": [KEY_9],
}
const MOUSE := {"primary": MOUSE_BUTTON_LEFT, "secondary": MOUSE_BUTTON_RIGHT, "ping_mouse": MOUSE_BUTTON_MIDDLE}


func _ready() -> void:
	_setup_input()
	load_cfg()
	apply()
	if player_name == "":
		var names := ["코코넛덕후", "뗏목장인", "게공포증", "야자수킬러", "표류왕", "모래성주", "조개수집가", "갈매기친구"]
		player_name = names[randi() % names.size()]
		player_color = randi() % COLORS.size()


func _setup_input() -> void:
	for action in KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	for action in MOUSE:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE[action]
		InputMap.action_add_event(action, mb)


func load_cfg() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	player_name = cf.get_value("player", "name", player_name)
	player_color = cf.get_value("player", "color", player_color)
	last_ip = cf.get_value("net", "last_ip", last_ip)
	master_vol = cf.get_value("audio", "master", master_vol)
	music_vol = cf.get_value("audio", "music", music_vol)
	sfx_vol = cf.get_value("audio", "sfx", sfx_vol)
	sensitivity = cf.get_value("control", "sensitivity", sensitivity)
	invert_y = cf.get_value("control", "invert_y", invert_y)
	fov = cf.get_value("video", "fov", fov)
	fullscreen = cf.get_value("video", "fullscreen", fullscreen)
	show_fps = cf.get_value("video", "show_fps", show_fps)
	gfx_chosen = cf.get_value("video", "gfx_chosen", false)
	if gfx_chosen or not OS.has_feature("web"):
		gfx = cf.get_value("video", "gfx", gfx)   # 웹에서 직접 안 고른 사람은 새 기본값(보통)으로
	hat = cf.get_value("player", "hat", hat)
	hats_unlocked = cf.get_value("player", "hats", hats_unlocked)
	if not hat in hats_unlocked:
		hat = "straw"


func save_cfg() -> void:
	var cf := ConfigFile.new()
	cf.set_value("player", "name", player_name)
	cf.set_value("player", "color", player_color)
	cf.set_value("net", "last_ip", last_ip)
	cf.set_value("audio", "master", master_vol)
	cf.set_value("audio", "music", music_vol)
	cf.set_value("audio", "sfx", sfx_vol)
	cf.set_value("control", "sensitivity", sensitivity)
	cf.set_value("control", "invert_y", invert_y)
	cf.set_value("video", "fov", fov)
	cf.set_value("video", "fullscreen", fullscreen)
	cf.set_value("video", "show_fps", show_fps)
	cf.set_value("video", "gfx", gfx)
	cf.set_value("video", "gfx_chosen", gfx_chosen)
	cf.set_value("player", "hat", hat)
	cf.set_value("player", "hats", hats_unlocked)
	cf.save(PATH)


func apply() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)
	if has_node("/root/Audio"):
		get_node("/root/Audio").apply_volumes()
	apply_graphics(null)


func apply_graphics(sun: DirectionalLight3D) -> void:
	## 그래픽 품질: 안티에일리어싱, 3D 해상도, 그림자
	if DisplayServer.get_name() == "headless":
		return
	var q := clampi(gfx, 0, 2)
	var vp := get_tree().root
	vp.msaa_3d = [Viewport.MSAA_2X, Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED][q]
	vp.scaling_3d_scale = [1.0, 1.0, 0.7][q]
	RenderingServer.directional_shadow_atlas_set_size([4096, 2048, 1024][q], true)
	if sun == null and get_tree().current_scene:
		sun = get_tree().current_scene.get_node_or_null("Sun")
	if sun:
		sun.shadow_enabled = q < 2
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS   # 4단계는 그림자를 너무 많이 다시 그린다
		sun.directional_shadow_max_distance = [60.0, 45.0, 45.0][q]


func color() -> Color:
	return COLORS[clampi(player_color, 0, COLORS.size() - 1)]
