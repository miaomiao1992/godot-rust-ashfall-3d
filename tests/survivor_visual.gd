extends SceneTree
## Review actual teammate avatars alongside an enemy; validate rig and body pixels.
var failed := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition: print("PASS SURVIVOR: ", message)
	else:
		failed += 1
		push_error(message)

func frame_image() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func run() -> void:
	var scene: PackedScene = load("res://main.tscn")
	var game = scene.instantiate()
	root.add_child(game)
	current_scene = game
	game.test_mode = true
	game.lan.create_room("幸存者外观检查", "房主", 42652)
	game.lan.start_battle()
	game.state = "testing"
	game.set_process(false)
	game.player.set_physics_process(false)
	game.hud.root.visible = false
	game.player.rig.visible = false
	game.player.camera.global_position = Vector3(0, 5.65, 39)
	game.player.camera.look_at(Vector3(0, 5.0, 34))
	var avatars: Array = []
	var clips := ["idle", "walk", "run"]
	for i in 3:
		game.lan.spawn_player(i + 2, ["待机", "行走", "奔跑"][i])
		var pawn = game.lan.players[i + 2]
		pawn.position = Vector3(-2.5 + i * 1.7, 4.05, 34)
		pawn.rotation.y = PI
		pawn.set_process(false)
		pawn.set_physics_process(false)
		check(pawn.avatar.scene_file_path == "res://assets/models/survivor_soldier.glb", "dedicated survivor model " + clips[i])
		check(pawn.avatar_animation.has_animation(clips[i]), "clip exists: " + clips[i])
		pawn.avatar_animation.play(clips[i])
		pawn.avatar_animation.advance(0.3)
		var skeleton = pawn.avatar.find_child("Skeleton3D", true, false)
		check(skeleton != null and skeleton.get_bone_count() >= 20, "humanoid skeleton " + clips[i])
		if clips[i] != "idle":
			var bone: int = skeleton.find_bone("LeftLeg")
			var before: Quaternion = skeleton.get_bone_pose_rotation(bone)
			pawn.avatar_animation.advance(0.3)
			check(before.angle_to(skeleton.get_bone_pose_rotation(bone)) > 0.01, "leg animates: " + clips[i])
		avatars.append(pawn)
	var enemy = game._spawn_add(Vector3(2.7, 4.05, 34), 0)
	enemy.rotation.y = 0
	enemy.set_physics_process(false)
	await create_timer(0.5).timeout
	if DisplayServer.get_name() != "headless":
		var visible: Image = await frame_image()
		visible.save_png("res://tests/previews/12-survivor-vs-zombie.png")
		for pawn in avatars: pawn.avatar.visible = false
		var hidden: Image = await frame_image()
		var changed := 0
		for x in range(0, visible.get_width(), 2):
			for y in range(0, visible.get_height(), 2):
				var a: Color = hidden.get_pixel(x, y)
				var b: Color = visible.get_pixel(x, y)
				if maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) > 0.08: changed += 1
		check(changed > 800, "survivor bodies render: %d changed samples" % changed)
	print("SURVIVOR RESULT: ", failed, " failures")
	game.lan.leave()
	quit(0 if failed == 0 else 1)
