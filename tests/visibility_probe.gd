extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene: PackedScene = load("res://main.tscn")
	var game = scene.instantiate()
	root.add_child(game)
	current_scene = game
	game.test_mode = true
	await physics_frame
	await physics_frame
	if "--probe-lan" in OS.get_cmdline_user_args():
		game.lan.create_room("显示诊断", "诊断房主", 42642)
		game.lan.start_battle()
	else:
		game.start_run()
	game.player.hp = 10000
	game.player.max_hp = 10000
	game.player.invulnerability = 999
	for frame in 720:
		await physics_frame
	print("VISIBILITY STATE: ", game.state, " alive=", game.alive, " pending=", game.spawn_left, " player=", game.player.position)
	var all = get_nodes_in_group("zombies")
	for i in mini(all.size(), 8):
		var enemy = all[i]
		var meshes: Array = []
		for mesh in enemy.actor.find_children("*", "MeshInstance3D", true, false):
			var info: Dictionary = {"name": str(mesh.name), "visible": mesh.is_visible_in_tree(), "position": str(mesh.global_position), "aabb": str(mesh.get_aabb()), "custom_aabb": str(mesh.custom_aabb), "scale": str(mesh.global_basis.get_scale()), "layers": mesh.layers}
			if i == 0 and mesh.skin != null:
				var arrays: Array = mesh.mesh.surface_get_arrays(0)
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
				var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
				var width: int = bones.size() / verts.size()
				var bound := AABB()
				var first := true
				for v in range(0, verts.size(), maxi(verts.size() / 1000, 1)):
					var point := Vector3.ZERO
					for w in width:
						var bind := int(bones[v * width + w])
						var bone: int = mesh.skin.get_bind_bone(bind)
						if bone < 0: bone = enemy.skeleton.find_bone(mesh.skin.get_bind_name(bind))
						if bone >= 0:
							point += (enemy.skeleton.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(bind) * verts[v]) * weights[v * width + w]
					point = mesh.global_transform * point
					if first: bound = AABB(point, Vector3.ZERO); first = false
					else: bound = bound.expand(point)
				info["deformed_world_bounds"] = str(bound)
				info["bind0"] = str(mesh.skin.get_bind_pose(0))
				var mat: StandardMaterial3D = mesh.get_active_material(0)
				info["material"] = {"alpha": mat.albedo_color.a, "transparency": mat.transparency, "cull": mat.cull_mode}
			meshes.append(info)
		print("VISIBILITY ENEMY ", JSON.stringify({"kind":enemy.kind,"position":str(enemy.position),"animation":str(enemy.animation.current_animation),"meshes":meshes}))
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png("res://tests/previews/visibility-lan.png" if game.is_lan() else "res://tests/previews/visibility-solo.png")
	quit()
