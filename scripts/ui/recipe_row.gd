extends Button
## 조합법 목록 한 줄

var recipe_index := -1

@onready var icon_rect: TextureRect = $HBox/Icon
@onready var name_label: Label = $HBox/Name
@onready var info_label: Label = $HBox/Info


func setup(idx: int, r: Dictionary, can: bool, station_ok: bool) -> void:
	recipe_index = idx
	icon_rect.texture = Items.icon(r.out)
	name_label.text = Items.name_of(r.out) + ("" if r.n <= 1 else " x%d" % r.n)
	if not station_ok:
		info_label.text = Items.STATION_NAMES.get(r.at, r.at) + " 필요"
		modulate = Color(1, 1, 1, 0.45)
	elif can:
		info_label.text = "만들 수 있음"
		modulate = Color(1, 1, 1, 1)
	else:
		info_label.text = ""
		modulate = Color(1, 1, 1, 0.7)
