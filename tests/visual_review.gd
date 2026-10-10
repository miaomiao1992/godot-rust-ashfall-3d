extends Node

var game

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("review")

func capture(name: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tests/previews/" + name + ".png")
	print("VISUAL: ", name)

func review() -> void:
	await get_tree().create_timer(1.5).timeout
	await capture("00-menu")
	game.start_run()
	game.set_process(false)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for stage in 3:
		for enemy in get_tree().get_nodes_in_group("zombies"):
			enemy.queue_free()
		await get_tree().process_frame
		game.alive = 0
		game._change_stage(stage)
		game.wave = stage * 3 + 3
		game.spawn_left = 0
		game.level_number = 7
		game.player.weapon_index = 3
		game.player._build_weapon()
		game.player.rig.position = Vector3(0.27, -0.25, -0.42)
		game.player.rig.visible = true
		game.player.camera.position = Vector3(0, 1.65, 0)
		game.player.camera.rotation = Vector3.ZERO
		var showcases := [
			[Vector3(-3, 0, 30), Vector3(-10, 0, 21), Vector3(1, 0, 18), Vector3(-12, 0, 10), Vector3(-25, 0, 0), Vector3(-7, 0, 6)],
			[Vector3(-10, 0, 33), Vector3(-15, 0, 30), Vector3(-16, 0, 22), Vector3(12, 0, 27), Vector3(-12, 0, 10), Vector3(-16, 0, 14)],
			[Vector3(-7, 0, 23), Vector3(7, 0, 24), Vector3(-15, 0, 18), Vector3(18, 0, 15), Vector3(0, 0, 16), Vector3(-25, 0, 12)]
		]
		var positions: Array = showcases[stage]
		for kind in 6:
			var enemy = game._spawn_add(positions[kind], kind)
			enemy.position = game.level.ground_point(positions[kind]) + Vector3.UP * 0.05
			enemy.rotation.y = PI
			if kind == 4:
				game.boss = enemy
		game.hud.banner_timer = 0
		game.hud.toast_timer = 0
		await get_tree().create_timer(0.4).timeout
		await capture("0%d-sector" % (stage + 1))
		var camera: Camera3D = game.player.camera
		var previous := camera.global_transform
		game.hud.root.visible = false
		game.player.rig.visible = false
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 122
		camera.global_position = Vector3(0, 105, 0)
		camera.look_at(Vector3.ZERO, Vector3.FORWARD)
		await capture("0%d-layout" % (stage + 1))
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.global_transform = previous
		game.hud.root.visible = true
		game.player.rig.visible = true
		if stage == 1:
			game.create_hazard(game.player.position + Vector3(0, 0, -7), 2.2, "acid", 1.6)
			game.hazards[0].material.set_shader_parameter("progress", 0.6)
			await capture("05-acid-warning")
			game.state = "testing"
			game._update_hazards(1.7)
			await capture("06-acid-active")
			game._clear_hazards()
			game.state = "playing"
	game._open_upgrade()
	await capture("04-upgrade")
	print("VISUAL REVIEW COMPLETE")
	get_tree().quit()
