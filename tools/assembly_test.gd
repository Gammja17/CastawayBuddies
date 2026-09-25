extends Node
## 직접 조립 확인 (도구 조립 · 통나무 뗏목): godot --headless --path . tools/assembly_test.tscn

const T := preload("res://tools/tutil.gd")


func _ready() -> void:
	Net.pending = {"mode": "solo", "new": true, "slot": "asmtest"}
	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game)
	await _wait(1.0)
	var g: Game = Game.I
	var p: Player = g.local_player
	var st := g.structs
	g.hud._set_open("")
	var home := p.global_position
	for it in [["flint", 3], ["stone", 6], ["rope", 8], ["fiber", 6], ["stick", 8], ["plank", 4], ["iron", 4], ["shark_tooth", 2], ["cloth", 2], ["coconut_shell", 1]]:
		p.inv.add(it[0], it[1])
	# 1) 여러 조합
	for c in [["axe", "flint", "rope", "stick"], ["pick", "stone", "fiber", "stick"], ["spear", "shark_tooth", "cloth", "stick"],
			["shovel", "coconut_shell", "rope", "plank"]]:
		var id := p.assemble(c[0], c[1], c[2], c[3])
		var tl := Items.tool_of(id)
		print("조립 %s → '%s' 힘 %d 공격 %d 내구 %d 느림 %s / 가방에 %d" % [c, Items.name_of(id), tl.get("power", -1), tl.get("dmg", -1), tl.get("dur", -1), tl.get("slow", false), p.inv.count(id)])
	# 2) 쇠 도끼는 작업대 없이는 안 된다
	print("작업대 없이 쇠 도끼: '", p.assemble("axe", "iron", "rope", "stick"), "'")
	var wb := T.spot(g, "workbench", home + Vector3(1.5, 0, 1))
	st.req_place.rpc_id(1, "workbench", wb, 0.0, "workbench")
	await _wait(0.2)
	p.global_position = g.safe_spot(wb + Vector3(1.0, 0.1, 0))
	await _wait(0.2)
	var iron_axe := p.assemble("axe", "iron", "rope", "stick")
	print("작업대 옆 쇠 도끼: '", Items.name_of(iron_axe), "' 힘 ", Items.tool_of(iron_axe).get("power", -1))
	# 3) 조립한 도끼로 야자수 패기 (호스트가 id 만 보고 힘을 안다)
	var palm := -1
	for i in g.props.list.size():
		if g.props.list[i].kind == "palm" and g.props.list[i].alive:
			palm = i
			break
	var hp0: int = g.props.list[palm].hp
	g.props.req_hit.rpc_id(1, palm, iron_axe)
	await _wait(0.1)
	print("쇠 도끼 한 방: 야자수 체력 %d → %d" % [hp0, g.props.list[palm].hp if g.props.list[palm].alive else 0])
	# 4) 떨어뜨렸다 줍기 / 저장해도 그대로
	var flint_axe := Items.tool_id("axe", "flint", "rope", "stick")
	var n0 := p.inv.count(flint_axe)
	p.inv.remove(flint_axe, 1)
	g.ents.req_drop.rpc_id(1, [[flint_axe, 1, 30]], p.global_position + Vector3.UP, Vector3.ZERO)
	await _wait(1.6)
	var got_d := -1
	for s in p.inv.slots:
		if s != null and s.id == flint_axe:
			got_d = s.get("d", -1)
	print("떨어뜨린 부싯돌 도끼 다시 주움: %d → %d (내구 %d)" % [n0, p.inv.count(flint_axe), got_d])
	g.save_game()
	var data := Game.load_save("asmtest")
	var saved_tools: Array = []
	for s in data.players.values()[0].inv:
		if s != null and String(s.id).begins_with("tool:"):
			saved_tools.append(s.id)
	print("저장된 조립 도구: ", saved_tools)
	# 5) 가방 창에서 조립 (UI 경로)
	g.hud.open_inventory("")
	g.hud.assemble_toggle.button_pressed = true
	await _wait(0.2)
	g.hud._asm = {"shape": "spear", "mat": "flint", "bind": "fiber", "handle": "stick"}
	g.hud._rebuild_assembly()
	print("조립 창: 버튼 켜짐? ", not g.hud.assemble_btn.disabled, " 미리보기 줄 수 ", g.hud.assemble_preview.text.count("\n"))
	g.hud._do_assemble()
	print("창에서 조립한 창: ", p.inv.count(Items.tool_id("spear", "flint", "fiber", "stick")))
	g.hud._set_open("")
	# 6) 통나무 뗏목
	var deep := T.deep(g, home)
	var first := st.log_snap(deep, 0.3)
	var logs: Array = [first]
	for i in 2:
		var last: Dictionary = logs.back()
		logs.append(st.log_snap(last.pos + Basis(Vector3.UP, last.rot) * Vector3(Structs.LOG_GAP, 0, 0), 0.0))
	for l in logs:
		print("  통나무 문제 '", st.placement_problem("float_log", l.pos), "'")
		st.req_place.rpc_id(1, "float_log", l.pos, l.rot, "wood")
	await _wait(0.2)
	var lid := -1
	for id in st.list:
		if st.list[id].kind == "float_log":
			lid = id
	print("통나무 3개 묶음 크기 ", st.log_group(lid).size())
	var rope0 := p.inv.count("rope")
	p.inv.remove("rope", 1)
	st.req_interact.rpc_id(1, lid, "tie", "rope")
	await _wait(0.1)
	print("3개일 때 묶기 → 밧줄 돌려받음? ", p.inv.count("rope") == rope0)
	var last2: Dictionary = logs.back()
	var l4 := st.log_snap(last2.pos + Basis(Vector3.UP, last2.rot) * Vector3(Structs.LOG_GAP, 0, 0), 0.0)
	st.req_place.rpc_id(1, "float_log", l4.pos, l4.rot, "wood")
	await _wait(0.2)
	print("통나무 4개 묶음 크기 ", st.log_group(lid).size(), " 필요한 밧줄 ", st.log_ropes_needed(4))
	var rafts0 := g.ents.rafts.size()
	for i in 2:
		p.inv.remove("rope", 1)
		st.req_interact.rpc_id(1, lid if st.list.has(lid) else -1, "tie", "rope")
		await _wait(0.1)
	var logs_left := 0
	for id in st.list:
		if st.list[id].kind == "float_log":
			logs_left += 1
	print("밧줄 2개로 묶음 → 뗏목 %d → %d, 남은 통나무 %d" % [rafts0, g.ents.rafts.size(), logs_left])
	print("조립 테스트 끝")
	get_tree().quit()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout
