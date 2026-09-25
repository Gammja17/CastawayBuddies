extends Node
## 장면에 그려지는 것 세기: godot --headless --path . tools/perf_count.tscn


func _ready() -> void:
	Net.pending = {"mode": "solo", "new": true, "slot": "perfcount"}
	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game)
	await get_tree().create_timer(2.0).timeout
	var g: Game = Game.I
	var total := 0
	for part in ["Decor", "Props", "Structs", "Ents", "Terrain", "Players", "FX", "AmbienceFX"]:
		var n: Node = g.get_node_or_null(part)
		if n == null:
			continue
		var surf := 0
		var shadow := 0
		var count := 0
		for m: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
			if m.mesh == null or not m.is_visible_in_tree():
				continue
			count += 1
			surf += m.mesh.get_surface_count()
			if m.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				shadow += m.mesh.get_surface_count()
		total += surf
		print("%s: 보이는 메쉬 %d개, 그리기 %d, 그림자 드리움 %d" % [part, count, surf, shadow])
	print("합계 그리기 %d / 장식 개수 %d / 그림자 모드 %d" % [total, g.gen.decor.size(), g.get_node("Sun").directional_shadow_mode])
	get_tree().quit()
