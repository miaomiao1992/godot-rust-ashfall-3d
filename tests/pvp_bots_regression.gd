extends SceneTree
var failed := 0
var game

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, text: String) -> void:
	print("PVP_BOTS ", "PASS " if ok else "FAIL ", text)
	if not ok: failed += 1

func wait_until(test: Callable, seconds: float = 8) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not test.call() and Time.get_ticks_msec() < deadline: await process_frame
	return test.call()

func run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.lan.create_room("Solo bots", "Human", 42045, "pvp")
	var checkbox = game.hud.menu.find_child("LobbyFillBots", true, false)
	check(checkbox != null and checkbox.button_pressed, "host has default-on fill-bots checkbox")
	checkbox.set_pressed(false)
	check(not bool(game.lan.pvp_state.fill_bots), "checkbox updates native match setting")
	game.lan.start_battle()
	check(game.state == "lobby", "unchecking bots requires a human opponent")
	checkbox.set_pressed(true)
	game.lan.start_battle()
	check(game.state == "playing", "solo host starts immediately with bots enabled")
	check(game.lan.fighters.size() == 2 and game.lan.players.size() == 2, "solo match gets one opposing bot")
	var bot_id := 0
	for id in game.lan.fighters:
		if game.lan.fighters[id].is_bot: bot_id = id
	check(bot_id > 0 and int(game.lan.fighters[bot_id].team) != game.player.team, "bot assigned to opposing team")
	var bot = game.lan.players[bot_id]
	var before: Vector3 = bot.position
	await create_timer(3).timeout
	check(bot.position.distance_to(before) > 1, "bot navigates using actual player physics")
	game.player.position = game.level.goldsrc(Vector3(200, 1800, 130))
	bot.position = game.level.goldsrc(Vector3(200, 2200, 130))
	bot.velocity = Vector3.ZERO
	check(await wait_until(func(): return game.player.hp < 100), "bot fires real weapons and deals authoritative damage")
	game.core.pvp_hit(1, bot_id, 999, false)
	game.lan.sync_stats()
	check(bot.life == "dead", "bot can be killed with ordinary combat rules")
	check(not bot.team_marker.visible and not bot.name_label.visible, "death hides floating team disk and name")
	var generation := int(game.lan.fighters[bot_id].generation)
	check(await wait_until(func(): return int(game.lan.fighters[bot_id].generation) > generation), "bot uses five-second respawn")
	check(bot.team_marker.visible and bot.name_label.visible, "respawn restores living team indicators")
	game.core.coop_register(2, "Late human")
	game.lan.refresh_pvp()
	check(game.lan.fighters.size() == 2 and game.lan.fighters.has(2), "joining human keeps balanced population")
	check(game.lan.fighters.values().all(func(f): return not f.is_bot), "human replaces opposing bot")
	check(not game.lan.players.has(bot_id), "replaced bot scene removed")
	game.core.coop_remove(2)
	game.lan.refresh_pvp()
	check(game.lan.fighters.values().any(func(f): return f.is_bot), "human departure refills opposing bot")
	if DisplayServer.get_name() != "headless":
		game.return_to_menu()
		game.lan.create_room("可选机器人 / 单人开局", "Human", 42045, "pvp")
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/previews/30-pvp-bot-choice.png")
	print("PVP_BOTS RESULT: ", failed, " failures")
	game.return_to_menu()
	await process_frame
	quit(0 if failed == 0 else 1)
