extends SceneTree
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, text: String) -> void:
	print("CS16_CONTROLS ", "PASS " if ok else "FAIL ", text)
	if not ok: failures += 1

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.lan.create_room("Controls", "Host", 42685, "pvp")
	game.lan.start_battle()
	game.set_process(false)
	var p = game.player
	p.set_physics_process(false)
	game.core.coop_switch(1, 5)
	game.core.coop_tick(2.1)
	game.lan.sync_stats()
	await physics_frame
	var aim := InputEventAction.new()
	aim.action = "aim"
	aim.pressed = true
	p._unhandled_input(aim)
	aim.pressed = false
	p._unhandled_input(aim)
	for i in 30: p._physics_process(1.0 / 60)
	check(p.scope_latched and p.scope_active(), "right click locks scope after button release")
	check(p.camera.fov < 25, "locked scope uses actual perspective magnification")
	aim.pressed = true
	p._unhandled_input(aim)
	for i in 30: p._physics_process(1.0 / 60)
	check(not p.scope_latched and not p.scope_active(), "second right click exits scope")
	aim.pressed = false
	p._unhandled_input(aim)
	p.select_grenade(0)
	var fire := InputEventAction.new()
	fire.action = "shoot"
	fire.pressed = true
	p._unhandled_input(fire)
	fire.pressed = false
	p._unhandled_input(fire)
	check(p.grenade_release_pending and game.lan.ordnance.items.is_empty(), "quick click waits for pin-pull animation")
	p._process(0.51)
	check(game.lan.ordnance.items.size() == 1, "release throws after half-second preparation")
	var he: Dictionary = game.lan.ordnance.items.values()[0]
	check(is_equal_approx(float(he.life), 1.5), "HE has CS 1.6 1.5-second fuse")
	game.lan.ordnance.clear()
	game.lan.ordnance.throw_grenade(p, 2, 0, 0)
	var smoke: Dictionary = game.lan.ordnance.items.values()[0]
	smoke.pos = Vector3(0, 30, 0)
	smoke.life = 0
	game.lan.ordnance.process(0.001)
	check(not smoke.smoke, "moving smoke canister does not bloom in midair")
	smoke.life = 0
	smoke.vel = Vector3.ZERO
	smoke.pos = p.position + Vector3.UP * 0.08
	for i in 180:
		game.lan.ordnance.process(1.0 / 60)
		if smoke.smoke: break
	check(smoke.smoke and is_equal_approx(float(smoke.life), 25), "settled smoke lasts 25 seconds from bloom")
	game.lan.ordnance.process(21)
	check(game.lan.ordnance.items.size() == 1, "smoke still exists before fade-out completes")
	game.lan.ordnance.process(4.1)
	check(game.lan.ordnance.items.is_empty(), "smoke expires after 25 seconds")
	check(game.level.texture_surface("duct_flr01") == "metal", "vent hit sound is metal")
	check(game.level.texture_surface("c1a1_crate1") == "wood", "crate hit sound is wood")
	check(game.level.texture_surface("crete4_flr01") == "concrete", "wall hit sound is concrete")
	check(game.sound.bank.wood_hit.data != game.sound.bank.concrete_hit.data, "wood and concrete have distinct audio waveforms")
	print("CS16_CONTROLS RESULT: ", failures, " failures")
	game.return_to_menu()
	await process_frame
	quit(0 if failures == 0 else 1)
