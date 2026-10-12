extends SceneTree
var game
var pawn

func _initialize() -> void:
	call_deferred("run")

func capture(path: String, source: Vector3, target: Vector3) -> void:
	pawn.camera.global_position = game.level.goldsrc(source)
	pawn.camera.look_at(game.level.goldsrc(target))
	for i in 4:
		await process_frame
		await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("CAPTURED: ", path)

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Scene screenshots require a real renderer, not --headless")
		quit(1)
		return
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.lan.create_room("CS 1.6 visual review", "Reviewer", 42681, "pvp")
	game.lan.start_battle()
	assert(game.level.spatial_type == "cs_assault_16")
	game.set_process(false)
	game.state = "testing"
	pawn = game.player
	for actor in game.lan.players.values():
		actor.set_process(false)
		actor.set_physics_process(false)
		actor.visible = false
	game.hud.root.visible = false
	pawn.rig.visible = false
	game.pvp_time_of_day = 11.5
	game._update_pvp_celestial(0)
	await capture("res://tests/previews/38-assault16-exterior.png", Vector3(300, 700, 140), Vector3(0, 2000, 240))
	await capture("res://tests/previews/43-assault16-overview.png", Vector3(1900, 400, 1800), Vector3(0, 1500, 120))
	await capture("res://tests/previews/39-assault16-interior.png", Vector3(480, 1800, 110), Vector3(-200, 2600, 280))
	await capture("res://tests/previews/40-assault16-roof.png", Vector3(180, 2100, 580), Vector3(0, 2208, 500))
	await capture("res://tests/previews/41-assault16-vent.png", Vector3(0, 2480, 466), Vector3(0, 2700, 460))
	game.pvp_time_of_day = 0.5
	game._update_pvp_celestial(0)
	await capture("res://tests/previews/42-assault16-night.png", Vector3(300, 700, 140), Vector3(0, 2000, 240))
	var sky: ShaderMaterial = game.ambience.environment.sky.sky_material
	var moon: Vector3 = sky.get_shader_parameter("moon_direction")
	var eye: Vector3 = game.level.goldsrc(Vector3(180, 2100, 580))
	pawn.camera.global_position = eye
	pawn.camera.look_at(eye + moon * 100)
	for i in 4:
		await process_frame
		await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/previews/44-assault16-moon.png")
	game.pvp_time_of_day = 11.5
	game._update_pvp_celestial(0)
	var sun: Vector3 = sky.get_shader_parameter("sun_direction")
	pawn.camera.global_position = eye
	pawn.camera.look_at(eye + sun * 100)
	for i in 4:
		await process_frame
		await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/previews/45-assault16-sun.png")
	# UI snapshots include ordinary and hover states, not a fabricated preview.
	game.return_to_menu()
	game.set_process(false)
	game.hud.root.visible = true
	for i in 4:
		await process_frame
		await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/previews/00-menu.png")
	game.lan.create_room("地图选择 / 高对比", "房主", 42681, "coop")
	for i in 4:
		await process_frame
		await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/previews/19-lobby-map-choice.png")
	game.return_to_menu()
	await process_frame
	quit(0)
