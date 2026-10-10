extends SceneTree

var failed := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition: print("PASS CORPSE_GROUND: ", message)
	else:
		failed += 1
		push_error(message)

func actual_clearance(model: Node3D, ground: Dictionary) -> float:
	var lowest := INF
	for visual in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = visual.bake_mesh_from_current_skeleton_pose() if visual.skin else visual.mesh
		if mesh == null:
			failed += 1
			return INF
		for s in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(s)
			for vertex in arrays[Mesh.ARRAY_VERTEX]:
				var world_vertex: Vector3 = visual.to_global(vertex)
				lowest = minf(lowest, (world_vertex - ground.position).dot(ground.normal))
	return lowest

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
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for test_case in 4:
		var stage := test_case if test_case < 3 else 0
		game._change_stage(stage)
		await physics_frame
		var center: Vector3 = [Vector3(-7, 0, 32), Vector3(-12, 0, 33), Vector3(0, 0, 28), Vector3(-29, 0, -18)][test_case]
		var longest := 0.5
		for kind in 6:
			var enemy = game.ZombieScript.new()
			enemy.game = game
			enemy.kind = kind
			enemy.forced_variant = 1
			enemy.position = game.level.ground_point(center + Vector3((kind % 3 - 1) * 3, 0, -floori(kind / 3.0) * 4)) + Vector3.UP * (2.0 if kind == 5 else 0.12)
			game.world.add_child(enemy)
			enemy.set_physics_process(false)
			if enemy.animation.has_animation("death"):
				longest = maxf(longest, enemy.animation.get_animation("death").length + 0.1)
			enemy.take_hit(100000, enemy.global_position + Vector3.UP, Vector3.FORWARD, 1)
		await create_timer(longest + 0.3).timeout
		var corpses := 0
		var blood_on_floor := true
		for item in game.fx.items:
			if item.get("corpse", false):
				if DisplayServer.get_name() != "headless":
					var clearance := actual_clearance(item.model, item.ground)
					check(item.settled and clearance >= -0.01 and clearance < 0.07, "case %d corpse %d lies on rendered ground (%.3f m)" % [test_case, corpses, clearance])
				else:
					check(item.settled and item.node.global_position.is_finite(), "server corpse settled in case %d" % test_case)
				corpses += 1
			elif item.node is MeshInstance3D and item.node.mesh is CylinderMesh:
				var ground: Vector3 = game.level.ground_point(item.node.global_position)
				blood_on_floor = blood_on_floor and absf(item.node.global_position.y - ground.y) < 0.04
		check(corpses == 6, "six corpse models retained in case %d" % test_case)
		check(blood_on_floor, "blood stains follow floor height in case %d" % test_case)
		if DisplayServer.get_name() != "headless":
			game.player.camera.global_position = game.level.ground_point(center) + Vector3(7, 7, 8)
			game.player.camera.look_at(game.level.ground_point(center) + Vector3(0, 0.5, -1))
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://tests/previews/18-corpse-ground-%d.png" % test_case)
	print("CORPSE_GROUND RESULT: ", failed, " failures")
	quit(0 if failed == 0 else 1)
