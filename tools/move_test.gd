extends Node
## 걷기/점프/헤엄 확인: godot --headless --path . tools/move_test.tscn


func _ready() -> void:
	Net.pending = {"mode": "solo", "new": true, "slot": "movetest"}
	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game)
	await _wait(1.0)
	var g: Game = Game.I
	var p: Player = g.local_player
	print("시작 ", p.global_position, " 막힘? ", g.hud.blocks_game_input(), " 로딩 ", g.hud.loading.visible, " 열린창 '", g.hud._open, "'")
	Input.action_press("move_forward")
	await _wait(0.2)
	print("입력 ", Input.get_vector("move_left", "move_right", "move_forward", "move_back"), " 속도 ", p.velocity)
	await _wait(1.0)
	Input.action_release("move_forward")
	print("1.2초 앞으로 ", p.global_position)
	# 물로 던져 넣기
	p.global_position = Vector3(-12.5, 3.0, 0.5)
	await _wait(2.0)
	print("바다 한가운데: ", p.global_position, " 헤엄? ", p.swimming, " 깊은물 시간 ", p.deep_time)
	Input.action_press("jump")
	await _wait(0.3)
	Input.action_release("jump")
	print("점프 뒤 ", p.global_position)
	get_tree().quit()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout
