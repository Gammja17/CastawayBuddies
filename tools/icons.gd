extends Node
## 아이템 아이콘 굽기: godot --path . tools/icons.tscn
## 각 아이템의 3D 모양을 비스듬히 찍어서 assets/icons/<id>.png 로 저장한다.

const SIZE := 128


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/icons")
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.85, 0.85, 0.9)
	e.ambient_light_energy = 0.9
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 1.3
	vp.add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.35
	vp.add_child(cam)
	cam.position = Vector3(1.6, 1.3, 1.9)
	cam.look_at(Vector3.ZERO)
	for id in Items.ITEMS:
		var holder := Node3D.new()
		vp.add_child(holder)
		var n := Vis.item_node(id, 1.0)
		holder.add_child(n)
		var tool := Items.tool_of(id)
		if not tool.is_empty() and tool.kind != "torch":
			holder.rotation_degrees = Vector3(0, 0, -35)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.resize(64, 64, Image.INTERPOLATE_LANCZOS)
		img.save_png("res://assets/icons/%s.png" % id)
		holder.queue_free()
		await get_tree().process_frame
	print("아이콘 %d 개 완료" % Items.ITEMS.size())
	get_tree().quit()
