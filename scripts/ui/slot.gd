class_name Slot
extends Button
## 아이템 칸 하나. 좌/우클릭을 알려준다.

signal slot_clicked(index: int, button: int, shift: bool)
signal slot_hovered(index: int, inside: bool)

var index := -1
var item_id := ""
var fresh := -1.0   # 썩는 음식이면 남은 싱싱함 0~1

@onready var icon_rect: TextureRect = $Icon
@onready var count_label: Label = $Count
@onready var dur_bar: ProgressBar = $Dur
@onready var abbr: Label = $Abbr
@onready var key_label: Label = $Key
@onready var sel: Panel = $Sel


func _ready() -> void:
	gui_input.connect(_on_gui_input)
	mouse_entered.connect(func(): slot_hovered.emit(index, true))
	mouse_exited.connect(func(): slot_hovered.emit(index, false))


func _on_gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and (ev.button_index == MOUSE_BUTTON_LEFT or ev.button_index == MOUSE_BUTTON_RIGHT):
		slot_clicked.emit(index, ev.button_index, ev.shift_pressed)
		accept_event()


func set_item(s) -> void:
	if s == null or (s is Dictionary and s.is_empty()):
		item_id = ""
		fresh = -1.0
		icon_rect.texture = null
		count_label.text = ""
		dur_bar.visible = false
		abbr.text = ""
		tooltip_text = ""
		return
	item_id = s.id
	var tex := Items.icon(s.id)
	icon_rect.texture = tex
	abbr.text = "" if tex else Items.name_of(s.id).left(2)
	count_label.text = str(s.n) if s.n > 1 else ""
	fresh = -1.0
	if s.has("d"):
		var mx: int = Items.tool_of(s.id).get("dur", 100)
		dur_bar.visible = s.d < mx
		dur_bar.max_value = mx
		dur_bar.value = s.d
	elif s.has("a") and Items.SPOIL.has(s.id):
		fresh = clampf(1.0 - s.a / Items.SPOIL[s.id], 0.0, 1.0)
		dur_bar.visible = fresh < 0.999
		dur_bar.max_value = 1.0
		dur_bar.value = fresh
	else:
		dur_bar.visible = false


func set_selected(on: bool) -> void:
	sel.visible = on


func set_key(t: String) -> void:
	key_label.text = t
