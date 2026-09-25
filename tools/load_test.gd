extends Node
## 저장 → 다시 불러오기 왕복: godot --headless --path . tools/load_test.tscn

const T := preload("res://tools/tutil.gd")


func _ready() -> void:
	Net.pending = {"mode": "solo", "new": true, "slot": "loadtest"}
	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game)
	await _wait(1.0)
	var g: Game = Game.I
	var p: Player = g.local_player
	var seed1 := g.world_seed
	var w := T.shallow(g, p.global_position)
	for i in 4:
		g.terrain.req_fill.rpc_id(1, w, "dirt")
	var cp := T.spot(g, "chest", p.global_position + Vector3(2, 0, 1))
	g.structs.req_place.rpc_id(1, "chest", cp, 0.5, "chest")
	await _wait(0.2)
	var cid := g.structs.near("chest", cp, 1.0)
	g.structs.req_chest.rpc_id(1, cid, "put", {"id": "iron", "n": 5, "d": -1})
	var rp := T.deep(g, p.global_position)
	print("뗏목 자리: ", rp)
	g.ents.req_raft_spawn.rpc_id(1, rp, 1.0)
	p.inv.add("golden_shell", 2)
	p.hunger = 42.0
	g.quests.set_flag("escape_known")
	g.clock.day = 3
	await _wait(0.3)
	g.save_game()
	var before := {"ground": snappedf(g.terrain.height_at(w.x, w.z), 0.01), "land": g.terrain.land_gain(), "chest": g.structs.list[cid].data.items[0], "rafts": g.ents.rafts.size(),
		"shell": p.inv.count("golden_shell"), "hunger": p.hunger, "flag": g.quests.flag("escape_known"), "day": g.clock.day, "pos": p.global_position}
	print("저장 전: ", before)
	game.queue_free()
	await _wait(0.3)
	Net.pending = {"mode": "solo", "new": false, "slot": "loadtest"}
	var game2: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game2)
	await _wait(1.0)
	g = Game.I
	p = g.local_player
	var cid2 := g.structs.near("chest", cp, 1.0)
	var after := {"ground": snappedf(g.terrain.height_at(w.x, w.z), 0.01), "land": g.terrain.land_gain(), "chest": g.structs.list[cid2].data.items[0] if cid2 >= 0 else null, "rafts": g.ents.rafts.size(),
		"shell": p.inv.count("golden_shell"), "hunger": snappedf(p.hunger, 0.1), "flag": g.quests.flag("escape_known"), "day": g.clock.day, "pos": p.global_position}
	print("불러온 뒤: ", after, " 같은 씨앗? ", seed1 == g.world_seed)
	get_tree().quit()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout
