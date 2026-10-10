extends SceneTree

var failed := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition: print("PASS ENVIRONMENT: ", message)
	else: failed += 1; push_error(message)

func capture(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.test_mode = true
	game.start_run()
	game.state = "testing"
	game.set_process(false)
	game.player.set_process(false)
	game.player.set_physics_process(false)
	game.player.rig.visible = false
	game.player.flashlight.visible = false
	game.hud.root.visible = false
	for stage in 2:
		game._change_stage(stage)
		var sky: Material = game.ambience.environment.sky.sky_material
		check(sky is PanoramaSkyMaterial and sky.panorama.get_width() == 2048, "full panorama for sector %d" % stage)
		var image := Image.new()
		image.load("res://assets/skies/highway_dusk.png" if stage == 0 else "res://assets/skies/harbor_overcast.png")
		var seamless := true
		for row in image.get_height():
			seamless = seamless and image.get_pixel(0, row).is_equal_approx(image.get_pixel(image.get_width() - 1, row))
		check(seamless, "longitude seam matches in sector %d" % stage)
		game.player.camera.global_position = game.level.player_spawn + Vector3(0, 1.65, 0)
		game.player.camera.rotation = Vector3(-0.04, 0, 0)
		if DisplayServer.get_name() != "headless":
			await capture("res://tests/previews/20-environment-%d.png" % stage)
			game.key_light.shadow_enabled = false
			await capture("res://tests/previews/21-shadow-diagnostic-%d.png" % stage)
			game.key_light.shadow_enabled = true
			print("ENVIRONMENT DRAW CALLS stage=", stage, " calls=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	print("ENVIRONMENT RESULT: ", failed, " failures")
	quit(0 if failed == 0 else 1)
