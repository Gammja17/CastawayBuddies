extends PanelContainer
## 설정 창 (타이틀과 게임 안에서 같이 쓴다)

signal closed

@onready var master: HSlider = %Master
@onready var music: HSlider = %Music
@onready var sfx: HSlider = %Sfx
@onready var sens: HSlider = %Sens
@onready var fov: HSlider = %Fov
@onready var invert: CheckButton = %Invert
@onready var fullscreen: CheckButton = %Fullscreen
@onready var fps: CheckButton = %ShowFps
@onready var gfx: OptionButton = %Gfx


func _ready() -> void:
	for n in Settings.GFX_NAMES:
		gfx.add_item(n)
	visibility_changed.connect(_load)
	_load()
	master.value_changed.connect(func(v): Settings.master_vol = v; Settings.apply())
	music.value_changed.connect(func(v): Settings.music_vol = v; Settings.apply())
	sfx.value_changed.connect(func(v): Settings.sfx_vol = v; Settings.apply())
	sens.value_changed.connect(func(v): Settings.sensitivity = v)
	fov.value_changed.connect(_on_fov)
	invert.toggled.connect(func(v): Settings.invert_y = v)
	fullscreen.toggled.connect(func(v): Settings.fullscreen = v; Settings.apply())
	fps.toggled.connect(func(v): Settings.show_fps = v)
	gfx.item_selected.connect(func(i): Settings.gfx = i; Settings.apply())
	%Close.pressed.connect(_close)


func _load() -> void:
	if not visible:
		return
	master.set_value_no_signal(Settings.master_vol)
	music.set_value_no_signal(Settings.music_vol)
	sfx.set_value_no_signal(Settings.sfx_vol)
	sens.set_value_no_signal(Settings.sensitivity)
	fov.set_value_no_signal(Settings.fov)
	invert.set_pressed_no_signal(Settings.invert_y)
	fullscreen.set_pressed_no_signal(Settings.fullscreen)
	fps.set_pressed_no_signal(Settings.show_fps)
	gfx.select(Settings.gfx)


func _on_fov(v: float) -> void:
	Settings.fov = v
	var cam := get_viewport().get_camera_3d()
	if cam and Game.I and Game.I.local_player and cam == Game.I.local_player.camera:
		cam.fov = v


func _close() -> void:
	Settings.save_cfg()
	Audio.play("close", -8.0)
	closed.emit()
