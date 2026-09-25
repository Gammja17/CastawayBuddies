extends Node
## 20배속으로 며칠 돌려 보며 오류를 찾는다: godot --headless --path . tools/soak.tscn


func _ready() -> void:
	Net.pending = {"mode": "solo", "new": true, "slot": "soak"}
	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game)
	await get_tree().create_timer(1.0).timeout
	var g: Game = Game.I
	var p: Player = g.local_player
	p.inv.add("cooked_fish", 50)
	p.inv.add("fresh_water", 50)
	Engine.time_scale = 20.0
	Engine.physics_ticks_per_second = 60
	var last_day := 0
	var t := 0.0
	while t < 110.0:
		await get_tree().create_timer(5.0 * 20.0, true, false, false).timeout
		t += 5.0
		# 살려 두기
		p.hunger = 100.0
		p.thirst = 100.0
		p.hp = 100.0
		if p.downed:
			p.net_revived.rpc_id(1)
		if g.clock.day != last_day:
			last_day = g.clock.day
		print("t=%d 일=%d 시=%.1f 비=%s 적=%d 잔해=%d 줍기=%d 깃발=%s" % [t, g.clock.day, g.clock.hour, g.clock.raining, g.ents.enemies.size(), g.ents.flotsam.size(), g.ents.pickups.size(), g.quests.flags.keys()])
	Engine.time_scale = 1.0
	print("soak 끝")
	get_tree().quit()
