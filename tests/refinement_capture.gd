extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.lan.create_room("机器人难度 / 普通 · 困难 · 地狱", "房主", 42703, "pvp")
	var choice = game.hud.menu.find_child("BotDifficultyChoice", true, false)
	choice.show_popup()
	for i in 3:
		await process_frame
		await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/previews/46-bot-difficulty.png")
	print("CAPTURED bot difficulty options")
	quit(0)
