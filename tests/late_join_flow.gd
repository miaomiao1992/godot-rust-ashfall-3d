extends SceneTree
var game
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, text: String) -> void:
	print("LATE_JOIN ", "PASS " if ok else "FAIL ", text)
	if not ok: failures += 1

func wait_until(predicate: Callable, seconds: float = 15) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline: await process_frame
	return predicate.call()

func run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	if "--late-host" in OS.get_cmdline_user_args():
		game.lan.create_room("Late join selection", "Host", 42701, "pvp")
		game.lan.set_bot_difficulty(2)
		game.lan.start_battle()
		print("LATE_JOIN_HOST_READY")
		if await wait_until(func(): return game.lan.pending_team_peers.size() == 1, 30):
			var id: int = game.lan.pending_team_peers.keys()[0]
			check(await wait_until(func(): return game.lan.players[id].life == "spawning"), "late join waits safely without activation")
			check(await wait_until(func(): return not game.lan.pending_team_peers.has(id)), "host receives explicit team choice")
			check(game.lan.fighters.has(id) and int(game.lan.fighters[id].team) == 0, "chosen red team applied by host")
			check(game.lan.players[id].life == "alive", "player activated only after choosing")
			await create_timer(1.0).timeout
		else: check(false, "late peer arrived")
	else:
		game.lan.join_room("127.0.0.1", "Late player", 42701)
		if await wait_until(func(): return game.lan.choosing_team, 30):
			var red = game.hud.menu.find_child("JoinRedTeam", true, false)
			check(red != null and game.hud.menu.visible, "team-selection panel shown")
			var identity: int = red.get_instance_id() if red != null else 0
			await create_timer(1.0).timeout
			var still_red = game.hud.menu.find_child("JoinRedTeam", true, false)
			check(game.hud.menu.visible and still_red != null and still_red.get_instance_id() == identity, "snapshots do not hide or recreate selection panel")
			check(game.player.life == "spawning", "unselected client remains noncombatant")
			check(game.lan.bot_difficulty == 2, "host difficulty synchronized to late joiner")
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://tests/previews/47-midmatch-team-selection.png")
			game.lan.request("join_team", 0)
			check(await wait_until(func(): return not game.lan.choosing_team and game.player.life == "alive"), "team choice completes entry")
			check(game.player.team == 0 and not game.hud.menu.visible, "red selected and overlay hidden after confirmation")
			if DisplayServer.get_name() != "headless": check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "mouse captured only after confirmation")
			await create_timer(0.3).timeout
		else: check(false, "team-selection state received")
	print("LATE_JOIN RESULT: ", failures, " failures")
	game.return_to_menu()
	await process_frame
	quit(0 if failures == 0 else 1)
