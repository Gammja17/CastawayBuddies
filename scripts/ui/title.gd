extends Node3D
## 타이틀: 뒤에 섬이 빙글빙글, 앞에 메뉴.

const SLOTS := ["slot1", "slot2", "slot3"]

@onready var terrain: Terrain = $Terrain
@onready var props: Props = $Props
@onready var decor: Node3D = $Decor
@onready var cam: Camera3D = $Cam
@onready var ocean: MeshInstance3D = $Ocean
@onready var main_box: Control = %Main
@onready var slot_panel: Control = %SlotPanel
@onready var join_panel: Control = %JoinPanel
@onready var credits_panel: Control = %CreditsPanel
@onready var settings: Control = %Settings
@onready var name_edit: LineEdit = %NameEdit
@onready var color_btn: OptionButton = %ColorBtn
@onready var slot_title: Label = %SlotTitle
@onready var host_opts: Control = %HostOpts
@onready var port_spin: SpinBox = %PortSpin
@onready var upnp_check: CheckBox = %UpnpCheck
@onready var ip_edit: LineEdit = %IpEdit
@onready var join_port: SpinBox = %JoinPort
@onready var version: Label = %Version
@onready var diff_btn: OptionButton = %DiffBtn

var _mode := "solo"
var _t := 0.0
var _confirm := {}


func _ready() -> void:
	Net.close()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Settings.apply_graphics($Sun)
	var gen := WorldGen.new()
	gen.generate(4242)
	terrain.build(gen.blocks, PackedInt32Array())
	props.build(gen.props, [])
	for d in gen.decor:
		var n := Vis.fit_model(d.model, d.h)
		decor.add_child(n)
		n.position = d.pos
		n.rotation = Vector3(deg_to_rad(d.get("tilt", 0.0)), deg_to_rad(d.rot), 0)
	Audio.music("title")
	Audio.stop_all_ambience()
	Audio.ambience("ocean", true, -12.0)
	name_edit.text = Settings.player_name
	color_btn.clear()
	for i in Settings.COLORS.size():
		var img := Image.create(20, 20, false, Image.FORMAT_RGB8)
		img.fill(Settings.COLORS[i])
		color_btn.add_icon_item(ImageTexture.create_from_image(img), Settings.COLOR_NAMES[i], i)
	color_btn.select(Settings.player_color)
	_fill_hats()
	name_edit.text_changed.connect(func(t): Settings.player_name = t.strip_edges().left(12))
	color_btn.item_selected.connect(func(i): Settings.player_color = i)
	%SoloBtn.pressed.connect(_open_slots.bind("solo"))
	%HostBtn.pressed.connect(_open_slots.bind("host"))
	%JoinBtn.pressed.connect(_open_join)
	%SettingsBtn.pressed.connect(func(): _show(settings))
	%CreditsBtn.pressed.connect(func(): _show(credits_panel))
	%QuitBtn.pressed.connect(func(): get_tree().quit())
	%SlotBack.pressed.connect(func(): _show(main_box))
	%JoinBack.pressed.connect(func(): _show(main_box))
	%CreditsBack.pressed.connect(func(): _show(main_box))
	%JoinGo.pressed.connect(_join)
	settings.closed.connect(func(): _show(main_box))
	for i in SLOTS.size():
		get_node("%%Continue%d" % (i + 1)).pressed.connect(_start.bind(SLOTS[i], false))
		get_node("%%New%d" % (i + 1)).pressed.connect(_new_pressed.bind(i))
	for d in Game.DIFFS:
		diff_btn.add_item(d.name)
	diff_btn.select(1)
	ip_edit.text = Settings.last_ip
	port_spin.value = Net.DEFAULT_PORT
	join_port.value = Net.DEFAULT_PORT
	version.text = "v%s" % ProjectSettings.get_setting("application/config/version", "1.0")
	%CreditsText.text = _credits()
	if OS.has_feature("web"):
		# 브라우저는 방을 열거나 들어갈 수 없다 (같이 하려면 PC판)
		%HostBtn.visible = false
		%JoinBtn.visible = false
		%QuitBtn.visible = false
		%SoloBtn.text = "혼자 하기"
		main_box.offset_bottom = main_box.offset_top + 340.0   # 버튼 셋이 빠진 만큼 줄인다
		version.text = "웹판 v%s / 혼자 하기 전용 / 친구랑은 PC판(exe)" % ProjectSettings.get_setting("application/config/version", "1.0")
	_show(main_box)
	# 개발용: godot --path . -- --autostart  (바로 혼자 하기 새 게임)
	if "--autostart" in OS.get_cmdline_user_args():
		_mode = "solo"
		_start.call_deferred("slot3", true)


func _fill_hats() -> void:
	## 풀린 모자는 고를 수 있고, 잠긴 모자는 얻는 법을 보여 준다
	var hb: OptionButton = %HatBtn
	hb.clear()
	var i := 0
	for id in Settings.HATS:
		var h: Dictionary = Settings.HATS[id]
		var open: bool = id in Settings.hats_unlocked
		hb.add_item(h.name if open else "%s - 잠김 (%s)" % [h.name, h.how])
		hb.set_item_metadata(i, id)
		hb.set_item_disabled(i, not open)
		if id == Settings.hat:
			hb.select(i)
		i += 1
	if not hb.item_selected.is_connected(_on_hat):
		hb.item_selected.connect(_on_hat)


func _on_hat(i: int) -> void:
	Settings.hat = (%HatBtn as OptionButton).get_item_metadata(i)
	Settings.save_cfg()


func _show(c: Control) -> void:
	for p in [main_box, slot_panel, join_panel, credits_panel, settings]:
		p.visible = p == c
	Audio.play("click", -8.0)


func _open_slots(mode: String) -> void:
	_mode = mode
	slot_title.text = "혼자 하기 - 섬 고르기" if mode == "solo" else "방 만들기 - 섬 고르기"
	host_opts.visible = mode == "host"
	_confirm.clear()
	for i in SLOTS.size():
		var meta := Game.save_meta(SLOTS[i])
		var info: Label = get_node("%%Info%d" % (i + 1))
		var cont: Button = get_node("%%Continue%d" % (i + 1))
		var nw: Button = get_node("%%New%d" % (i + 1))
		nw.text = "새로 시작"
		if meta.is_empty():
			info.text = "섬 %d  -  비어 있음" % (i + 1)
			cont.disabled = true
		else:
			var dname: String = Game.DIFFS[clampi(meta.get("diff", 1), 0, 2)].name
			info.text = "섬 %d  -  %d일째 / %s / %s\n%s" % [i + 1, meta.get("day", 1), dname, ", ".join(meta.get("names", [])), meta.get("saved_at", "")]
			cont.disabled = false
	_show(slot_panel)


func _new_pressed(i: int) -> void:
	var nw: Button = get_node("%%New%d" % (i + 1))
	if not Game.save_meta(SLOTS[i]).is_empty() and not _confirm.get(i, false):
		_confirm[i] = true
		nw.text = "정말? 덮어쓴다"
		Audio.play("error", -6.0)
		return
	_start(SLOTS[i], true)


func _start(slot: String, is_new: bool) -> void:
	_save_name()
	Net.pending = {"mode": _mode, "slot": slot, "new": is_new, "port": int(port_spin.value), "upnp": upnp_check.button_pressed,
		"diff": diff_btn.selected}
	_go()


func _open_join() -> void:
	_show(join_panel)


func _join() -> void:
	_save_name()
	var ip := ip_edit.text.strip_edges()
	if ip == "":
		ip = "127.0.0.1"
	Settings.last_ip = ip
	Settings.save_cfg()
	Net.pending = {"mode": "join", "ip": ip, "port": int(join_port.value)}
	_go()


func _save_name() -> void:
	if Settings.player_name.strip_edges() == "":
		Settings.player_name = "무명씨"
	Settings.save_cfg()


func _go() -> void:
	Audio.play("select")
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _process(delta: float) -> void:
	_t += delta
	var center := Vector3(6, 1, 8)
	var a := _t * 0.06
	cam.global_position = center + Vector3(cos(a) * 34.0, 13.0 + sin(_t * 0.2) * 1.5, sin(a) * 34.0)
	cam.look_at(center)
	ocean.global_position = Vector3(snappedf(cam.global_position.x, 8.0), Terrain.WATER_Y, snappedf(cam.global_position.z, 8.0))


func _credits() -> String:
	return """[center][font_size=30][color=#ffe08a]무인도 버디즈[/color][/font_size]
친구랑 같이 무인도에서 살아남는 허접 로우폴리 협동 생존 게임

[color=#ffe08a]기획 / 개발[/color]
무인도 버디즈 팀 (Claude 와 함께)

[color=#ffe08a]3D 모델 / 효과음[/color]
Kenney - Survival Kit, Nature Kit, Pirate Kit,
Impact Sounds, RPG Audio, Interface Sounds, Music Jingles (CC0)
kenney.nl

[color=#ffe08a]음악 / 환경음[/color]
직접 합성 (tools/gen_audio.py)

[color=#ffe08a]글꼴[/color]
Jua - 우아한형제들 (SIL Open Font License)

[color=#ffe08a]엔진[/color]
Godot Engine 4.7

[color=#8a8070]게에게 물린 모든 표류자에게 바칩니다[/color][/center]"""
