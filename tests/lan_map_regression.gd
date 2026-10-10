extends SceneTree

var failed := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition: print("PASS LAN_MAP: ", message)
	else:
		failed += 1
		push_error(message)

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.test_mode = true
	game.lan.create_room("地图选择检查", "房主", 42682)
	check(game.lan.start_stage == 0, "new room defaults to first map")
	var choice = game.hud.menu.find_child("LobbyMapChoice", true, false)
	check(choice != null and choice.item_count == 3 and choice.selected == 0 and not choice.disabled, "host can choose all three maps")
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/previews/19-lobby-map-choice.png")
	for stage in 3:
		game.state = "lobby"
		game.lan.set_start_stage(stage)
		game.lan.start_battle()
		game.state = "testing"
		game.set_process(false)
		game.player.set_physics_process(false)
		check(game.stage_index == stage and game.level.stage == stage and game.wave == stage * 3 + 1, "selected map %d starts at its first wave" % stage)
		check(game.level_number == 1 and game.xp == 0 and game.kills == 0, "map selection awards no skipped-map rewards")
		check(game.lan.players.has(1) and game.player.life == "alive", "local survivor registered on selected map")
	game.lan.start_battle()
	check(game.stage_index == 2 and game.wave == 7, "restart preserves room map selection")
	game.lan.leave()
	game.lan.create_room("新房间", "房主", 42682)
	check(game.lan.start_stage == 0, "next room resets selection to first map")
	game.lan.leave()
	print("LAN_MAP RESULT: ", failed, " failures")
	quit(0 if failed == 0 else 1)
