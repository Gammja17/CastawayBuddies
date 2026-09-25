extends PanelContainer
## 잠깐 떴다 사라지는 알림

@onready var label: Label = $Label


func show_text(text: String, col: Color, life: float = 4.0) -> void:
	label.text = text
	label.modulate = col
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.15)
	tw.tween_interval(life)
	tw.tween_property(self, "modulate:a", 0.0, 0.6)
	tw.tween_callback(queue_free)
