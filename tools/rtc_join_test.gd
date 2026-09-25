extends Node
## 웹판 방 코드 접속 실패 흐름 (없는 방): godot --headless --path . tools/rtc_join_test.tscn -- --rtc


func _ready() -> void:
	Net.pending = {"mode": "join", "ip": "ZZZZ9", "port": 0}
	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game)
	for i in 30:
		await get_tree().create_timer(1.0).timeout
		var g: Game = Game.I
		if g and g.hud and g.hud.fatal_rect.visible:
			print("%d초: 오류 화면 '%s'" % [i + 1, g.hud.fatal_label.text])
			get_tree().quit()
			return
	print("30초 동안 오류 화면 없음")
	get_tree().quit()
