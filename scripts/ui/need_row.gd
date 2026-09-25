extends HBoxContainer
## 조선소 재료 한 줄: "판자 12/40 [넣기]"

signal give_pressed(part: String, item: String)

var part := ""
var item := ""

@onready var label: Label = $Label
@onready var button: Button = $Give


func _ready() -> void:
	button.pressed.connect(func(): give_pressed.emit(part, item))


func setup(p: String, it: String, text: String, have: int, done: bool) -> void:
	part = p
	item = it
	label.text = text
	button.disabled = done or have <= 0
	button.text = "완료" if done else ("넣기 (%d)" % have)
