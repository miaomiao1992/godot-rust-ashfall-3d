extends SceneTree

func _initialize() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.lan.mode = "pvp"
	game.lan.enabled = true
	game.stage_index = 3
	game.state = "playing"
	game._build_run()
	game.hud.hide_overlay()
	for f in 3:
		await physics_frame
	var p = game.player
	game.lan.fighters[p.peer_id] = {"grenades": [2, 2, 1], "team": 0}
	print("Testing G key / grenade selection...")
	var ev_g := InputEventKey.new()
	ev_g.keycode = KEY_G
	ev_g.physical_keycode = KEY_G
	ev_g.pressed = true
	p._unhandled_input(ev_g)
	assert(p.active_grenade == 0, "G key should select HE grenade")
	for f in 5:
		await process_frame
		await physics_frame
	print("HE grenade selected via G key without crash! Testing Q key...")
	var ev_q := InputEventAction.new()
	ev_q.action = "flash_grenade"
	ev_q.pressed = true
	p._unhandled_input(ev_q)
	assert(p.active_grenade == 1, "Q key should select Flashbang")
	for f in 5:
		await process_frame
		await physics_frame
	print("Flashbang selected via Q key without crash! Testing C key...")
	var ev_c := InputEventAction.new()
	ev_c.action = "smoke_grenade"
	ev_c.pressed = true
	p._unhandled_input(ev_c)
	assert(p.active_grenade == 2, "C key should select Smoke")
	for f in 5:
		await process_frame
		await physics_frame
	print("Smoke selected via C key without crash! Testing left click throw...")
	var ev_shoot := InputEventAction.new()
	ev_shoot.action = "shoot"
	ev_shoot.pressed = true
	p._unhandled_input(ev_shoot)
	for f in 5:
		await process_frame
		await physics_frame
	assert(p.active_grenade == -1, "Throwing should switch back to gun")
	print("Grenade thrown via left click and weapon restored without crash!")
	print("ALL GRENADE INPUT/SELECTION TESTS PASSED")
	quit(0)
