extends Node
## 번거로운 생존 확인 (불·석쇠·썩음·배탈·젖음·추위·피·수리·코코넛 컵): godot --headless --path . tools/survival_test.tscn

const T := preload("res://tools/tutil.gd")


func _ready() -> void:
	Net.pending = {"mode": "solo", "new": true, "slot": "survivaltest"}
	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game)
	await _wait(1.0)
	var g: Game = Game.I
	var p: Player = g.local_player
	var st := g.structs
	g.hud._set_open("")
	g.clock.raining = false
	var home := p.global_position
	# 1) 모닥불: 처음엔 꺼져 있고, 불 없으면 물을 못 끓인다
	var fp := T.spot(g, "campfire", home + Vector3(1.5, 0, 0))
	st.req_place.rpc_id(1, "campfire", fp, 0.0, "campfire")
	await _wait(0.2)
	var fid := st.near("campfire", fp + Vector3.UP * 0.5, 1.0)
	p.global_position = g.safe_spot(fp + Vector3(1.2, 0.2, 0))
	await _wait(0.2)
	print("모닥불 켜짐? ", st.is_lit(fid), " / 물 끓이기 가능? ", p.station_near("campfire"))
	# 장작 없이 활비비 → 거절, 장작 넣고 비비기
	p.inv.slots[0] = {"id": "bow_drill", "n": 1, "d": 25}
	p.inv.slots[1] = {"id": "wood", "n": 2}
	p.hotbar_i = 1
	p._on_inv_changed()
	p.target = {"type": "struct", "id": fid, "pos": fp, "normal": Vector3.UP}
	p._interact_struct(fid)
	await _wait(0.2)
	print("장작 넣음: ", st.list[fid].data.fuel, "초, 가방 나무 ", p.inv.count("wood"))
	p.hotbar_i = 0
	p._on_inv_changed()
	var tries := 0
	while not st.is_lit(fid) and tries < 80:
		p.target = {"type": "struct", "id": fid, "pos": fp, "normal": Vector3.UP}   # 조준은 매 프레임 바뀐다
		p._drill()
		await get_tree().process_frame
		tries += 1
	await _wait(0.2)
	print("활비비 %d번 비벼서 불? %s  활비비 내구도 %d" % [tries, st.is_lit(fid), p.inv.slots[0].d if p.inv.slots[0] != null else -1])
	print("불 붙은 뒤 물 끓이기 가능? ", p.station_near("campfire"), " / 몸 따뜻? ", g.near_fire(p.global_position, 3.5))
	# 2) 석쇠: 올리고 → 익고 → 타고
	p.inv.slots[2] = {"id": "raw_fish", "n": 2, "a": 0.0}
	p.hotbar_i = 2
	p._on_inv_changed()
	p._interact_struct(fid)
	p._interact_struct(fid)
	await _wait(0.2)
	var d: Dictionary = st.list[fid].data
	print("석쇠 ", d.grill.size(), "개")
	d.grill[0][1] = 25.0   # 익은 것
	d.grill[1][1] = 60.0   # 탄 것
	p.hotbar_i = 5
	p._on_inv_changed()
	p._interact_struct(fid)
	p._interact_struct(fid)
	await _wait(0.2)
	print("꺼낸 것: 구운 생선 %d / 탄 음식 %d" % [p.inv.count("cooked_fish"), p.inv.count("burnt_food")])
	# 3) 장작이 다 타면 꺼진다
	st.list[fid].data.fuel = 0.3
	await _wait(0.8)
	print("장작 다 타고 꺼짐? ", not st.is_lit(fid))
	# 4) 썩음 → 거름, 배탈
	p.inv.slots[3] = {"id": "raw_fish", "n": 3, "a": 0.0}
	p.inv.age_food(310.0)
	print("310초 뒤: 날생선 ", p.inv.count("raw_fish"), " 썩은 음식 ", p.inv.count("rotten_food"), " 구운 생선 여전? ", p.inv.count("cooked_fish"))
	p.hunger = 50.0
	p._use_cd = 0.0
	p._eat("rotten_food")
	print("썩은 거 먹음 → 배탈 %d초" % int(p.cond.sick))
	var h0 := p.hunger
	for i in 10:
		p.cond.tick(p, 3.5)   # 35초 흐름 → 한 번은 토한다
	print("배탈 중 토함? 배고픔 %.0f → %.0f" % [h0, p.hunger])
	# 5) 젖음 / 추위: 물에 빠진 채 밤
	p.cond.sick = 0.0
	g.clock.hour = 23.0
	p.cond.wet = 1.0
	for i in 60:
		p.cond.tick(p, 1.0)
	print("젖은 채 밤 1분: 추위 %.2f 체력 손해/초 %.2f  상태 '%s'" % [p.cond.cold, p.cond.hp_loss(), p.cond.status_bbcode()])
	# 불 붙이고 옆에 있으면 녹는다
	st.list[fid].data.fuel = 100.0
	st.list[fid].data.lit = true
	for i in 30:
		p.cond.tick(p, 1.0)
	print("불 옆 30초: 추위 %.2f 젖음 %.2f" % [p.cond.cold, p.cond.wet])
	# 야자잎 우산
	g.clock.hour = 12.0
	g.clock.raining = true
	p.global_position = g.safe_spot(home + Vector3(-1.5, 0.2, -1.0))
	p.cond.wet = 0.0
	p.inv.slots[4] = {"id": "palm_leaf", "n": 1}
	p.hotbar_i = 4
	p._on_inv_changed()
	for i in 20:
		p.cond.tick(p, 1.0)
	var wet_umbrella := p.cond.wet
	p.hotbar_i = 7
	p._on_inv_changed()
	for i in 20:
		p.cond.tick(p, 1.0)
	print("비 20초: 야자잎 우산 젖음 %.2f / 맨몸 젖음 %.2f" % [wet_umbrella, p.cond.wet])
	g.clock.raining = false
	# 6) 피 흘림 → 붕대
	p.cond.start_bleed()
	var hp0 := p.hp
	for i in 10:
		p.cond.tick(p, 1.0)
	print("피 흘림: 체력 손해/초 %.2f" % p.cond.hp_loss())
	p.inv.add("bandage", 1)
	p._use_cd = 0.0
	p._eat("bandage")
	print("붕대 뒤 피 흘림? ", p.cond.bleed > 0.0)
	# 7) 도구 수리 (작업대에 대고 우클릭)
	var wb := T.spot(g, "workbench", home + Vector3(-2, 0, 1))
	st.req_place.rpc_id(1, "workbench", wb, 0.0, "workbench")
	await _wait(0.2)
	var wid := st.near("workbench", wb + Vector3.UP * 0.5, 1.0)
	p.inv.slots[5] = {"id": "stone_axe", "n": 1, "d": 10}
	p.inv.add("stone", 2)
	p.inv.add("rope", 1)
	p.hotbar_i = 5
	p._on_inv_changed()
	p.target = {"type": "struct", "id": wid, "pos": wb, "normal": Vector3.UP}
	p._use_cd = 0.0
	p._secondary()
	print("돌도끼 수리: 내구도 10 → %d" % p.inv.slots[5].d)
	# 8) 코코넛 → 껍데기 → 바닷물 뜨기
	p.inv.slots[6] = {"id": "coconut", "n": 1}
	p.hotbar_i = 6
	p._on_inv_changed()
	p.hunger = 50.0
	p._use_cd = 0.0
	p._eat("coconut")
	print("코코넛 먹고 껍데기 ", p.inv.count("coconut_shell"))
	var shell_i := -1
	for i in 9:
		if p.inv.slots[i] != null and p.inv.slots[i].id == "coconut_shell":
			shell_i = i
	p.hotbar_i = shell_i
	p._on_inv_changed()
	p.water_point = p.eye_pos() + Vector3(1.5, -1.2, 0)
	p.target = {}
	p._use_cd = 0.0
	p._secondary()
	print("껍데기로 바닷물: ", p.inv.count("shell_salt"))
	# 9) 저장에 몸 상태
	p.cond.wet = 0.7
	g.save_game()
	var data := Game.load_save("survivaltest")
	print("저장된 몸 상태: ", data.players.values()[0].get("cond", {}))
	print("생존 테스트 끝")
	get_tree().quit()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout
