extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start_run(1) # Start at sector 2 (docks)
	game.set_process(false)
	game.player.set_process(false)
	game.player.set_physics_process(false)
	game.hud.root.visible = false
	# Open elevated vantage point looking across piers and open ocean
	game.player.camera.global_position = Vector3(22, 12, 38)
	game.player.camera.look_at(Vector3(-15, 0, -10))
	for frame in 5:
		await process_frame
		await RenderingServer.frame_post_draw
	var img = root.get_texture().get_image()
	img.save_png("res://tests/previews/31-ocean-water.png")
	print("SAVED OCEAN PREVIEW")
	quit(0)
