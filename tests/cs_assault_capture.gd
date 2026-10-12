extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func capture(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("CAPTURED: ", path)

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.lan.mode = "pvp"
	game.stage_index = 3
	game.state = "testing"
	game._build_run()
	game.set_process(false)
	var pawn = game.player
	pawn.set_process(false)
	pawn.set_physics_process(false)
	game.hud.root.visible = false

	# 1. Day view matching the CS_ASSAULT screenshot perspective (looking down driveway towards ramp and bays)
	game.pvp_time_of_day = 11.5 # Midday sun
	game._update_pvp_celestial(0.0)
	pawn.camera.global_position = Vector3(-16.0, 5.5, 34.0)
	pawn.camera.look_at(Vector3(12.0, 2.5, -20.0))
	pawn.rig.visible = false
	await capture("res://tests/previews/32-assault-daytime.png")

	# 2. Night view with moonlight streaming through skylights and warm industrial luminaires
	game.pvp_time_of_day = 0.5 # Midnight moon
	game._update_pvp_celestial(0.0)
	await capture("res://tests/previews/33-assault-night-moonlight.png")

	# 3. Sunset / Dusk view
	game.pvp_time_of_day = 18.2 # Golden hour dusk
	game._update_pvp_celestial(0.0)
	await capture("res://tests/previews/34-assault-sunset.png")

	# 4. First-person grenades held in hand (HE, Flashbang, Smoke)
	game.pvp_time_of_day = 12.0
	game._update_pvp_celestial(0.0)
	pawn.position = Vector3(0.0, 0.1, 0.0)
	pawn.camera.position = Vector3(0.0, 1.65, 0.0)
	pawn.camera.rotation = Vector3.ZERO
	pawn.rig.visible = true

	# HE Grenade
	pawn.active_grenade = 0
	pawn._build_weapon()
	await capture("res://tests/previews/35-grenade-in-hand.png")
	await capture("res://tests/previews/35-grenade-he.png")

	# Flashbang
	pawn.active_grenade = 1
	pawn._build_weapon()
	await capture("res://tests/previews/36-grenade-flash.png")

	# Smoke Grenade
	pawn.active_grenade = 2
	pawn._build_weapon()
	await capture("res://tests/previews/37-grenade-smoke.png")

	quit(0)
