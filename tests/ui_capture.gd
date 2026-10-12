extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func image(path: String) -> void:
	for i in 3:
		await process_frame
		await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("UI_CAPTURE ", path)

func run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await image("res://tests/previews/00-menu.png")
	game.lan.create_room("地图选择 / v1.0.0", "房主", 42689, "coop")
	await image("res://tests/previews/19-lobby-map-choice.png")
	quit(0)
