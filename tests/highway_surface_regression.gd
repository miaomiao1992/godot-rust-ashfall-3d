extends SceneTree

var failed := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition: print("PASS HIGHWAY_SURFACE: ", message)
	else:
		failed += 1
		push_error(message)

func frame_image() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.test_mode = true
	game.start_run()
	game.state = "testing"
	game.set_process(false)
	game.player.set_process(false)
	game.player.set_physics_process(false)
	game.player.rig.visible = false
	game.hud.root.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await process_frame
	# Inspect the actual committed batch vertices, not authored height metadata.
	var concrete := Forge.material(Color(0.33, 0.34, 0.32))
	var supports := [Vector3(-8, 0, 28), Vector3(-8, 0, 12), Vector3(-28, 0, -2), Vector3(-28, 0, -36), Vector3(8, 0, -40)]
	for pos in supports:
		var surface: float = game.level.surface_height(pos)
		var found := false
		var highest := -INF
		for visual in game.level.find_children("*", "MeshInstance3D", true, false):
			for s in visual.mesh.get_surface_count():
				if visual.mesh.surface_get_material(s) != concrete: continue
				var arrays: Array = visual.mesh.surface_get_arrays(s)
				for vertex in arrays[Mesh.ARRAY_VERTEX]:
					var world_vertex: Vector3 = visual.to_global(vertex)
					if absf(world_vertex.x - pos.x) < 1.36 and absf(world_vertex.z - pos.z) < 1.61:
						found = true
						highest = maxf(highest, world_vertex.y)
		check(found and highest < surface - 0.6, "bridge support stays below slab at " + str(pos))
	if DisplayServer.get_name() != "headless":
		var camera: Camera3D = game.player.camera
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 122
		camera.global_position = Vector3(0, 105, 0)
		camera.look_at(Vector3.ZERO, Vector3.FORWARD)
		var layout: Image = await frame_image()
		layout.save_png("res://tests/previews/16-highway-surface-layout.png")
		layout.save_png("res://tests/previews/01-layout.png")
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.global_position = Vector3(-8, 5.65, 34)
		camera.look_at(Vector3(-8, 4, 27))
		game.player.flashlight.visible = false
		var before: Image = await frame_image()
		before.save_png("res://tests/previews/17-highway-surface-close.png")
		await create_timer(0.25).timeout
		var after: Image = await frame_image()
		var changed := 0
		for x in range(before.get_width() / 4, before.get_width() * 3 / 4):
			for y in range(before.get_height() / 2, before.get_height()):
				var diff := before.get_pixel(x, y) - after.get_pixel(x, y)
				if maxf(absf(diff.r), maxf(absf(diff.g), absf(diff.b))) > 0.08: changed += 1
		check(changed == 0, "stationary bridge surface has no temporal bright-line flicker (%d pixels)" % changed)
	print("HIGHWAY_SURFACE RESULT: ", failed, " failures")
	quit(0 if failed == 0 else 1)
