extends Node
## 걷기/점프/헤엄 확인: godot --headless --path . tools/move_test.tscn

const T := preload("res://tools/tutil.gd")


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
	var home := g.gen.spawn
	p.global_position = T.deep(g, home) + Vector3.UP * 2.0
	await _wait(2.0)
	print("바다 한가운데: ", p.global_position, " 헤엄? ", p.swimming, " 깊은물 시간 ", p.deep_time)
	Input.action_press("jump")
	await _wait(0.3)
	Input.action_release("jump")
	print("점프 뒤 ", p.global_position)
	# 헤엄쳐서 물가로 올라오기
	var to := Vector3(home.x - p.global_position.x, 0, home.z - p.global_position.z)
	p._yaw = atan2(-to.x, -to.z)
	Input.action_press("move_forward")
	var tt := 0.0
	while p.swimming or tt < 1.0:
		await _wait(0.25)
		tt += 0.25
		if tt > 12.0:
			break
	await _wait(1.0)
	Input.action_release("move_forward")
	print("물가로 헤엄 %.1f초: 위치 %s 헤엄? %s 땅높이 %.2f" % [tt, p.global_position, p.swimming, g.terrain.height_at(p.global_position.x, p.global_position.z)])
	get_tree().quit()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout
