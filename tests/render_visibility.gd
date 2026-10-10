extends SceneTree
## Compares frames with only the imported skinned body toggled. Helmets,
## labels and collision shapes cannot make this test pass on their own.
var passed := 0
var failed := 0

func _initialize() -> void:
	call_deferred("run")

func frame_image() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return get_root().get_texture().get_image()

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Visibility regression requires a real renderer")
		quit(1)
		return
	seed(88137)
	var scene: PackedScene = load("res://main.tscn")
	var game = scene.instantiate()
	root.add_child(game)
	current_scene = game
	game.test_mode = true
	await physics_frame
	await physics_frame
	var lan_mode := "--probe-lan" in OS.get_cmdline_user_args()
	if lan_mode:
		game.lan.create_room("渲染回归", "渲染房主", 42642)
		game.lan.start_battle()
	else: game.start_run()
	game.state = "testing"
	game.hud.root.visible = false
	game.player.rig.visible = false
	game.set_process(false)
	game.player.camera.position = Vector3(0, 1.65, 0)
	game.player.camera.rotation = Vector3.ZERO
	for kind in 6:
		var enemy = game._spawn_add(Vector3(0, 4, 34), kind)
		if enemy == null:
			failed += 1
			push_error("Failed to place visibility fixture")
			continue
		enemy.position = Vector3(0, 4.05, 34)
		enemy.rotation.y = PI
		enemy.animation.play("run" if kind == 1 else "walk")
		await create_timer(0.35).timeout
		var meshes: Array = []
		for mesh in enemy.actor.find_children("*", "MeshInstance3D", true, false):
			if mesh.skin != null: meshes.append(mesh)
		for mesh in meshes: mesh.visible = false
		var hidden: Image = await frame_image()
		for mesh in meshes: mesh.visible = true
		var visible: Image = await frame_image()
		var center: Vector2 = game.player.camera.unproject_position(enemy.position + Vector3.UP * 1.0 * enemy.size_factor)
		var size: Vector2i = visible.get_size()
		var changed := 0
		for x in range(maxi(int(center.x) - 130, 0), mini(int(center.x) + 130, size.x), 2):
			for y in range(maxi(int(center.y) - 190, 0), mini(int(center.y) + 190, size.y), 2):
				var a: Color = hidden.get_pixel(x, y)
				var b: Color = visible.get_pixel(x, y)
				if maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) > 0.08: changed += 1
		if changed >= 150:
			passed += 1
			print("PASS RENDER BODY: kind=", kind, " changed_samples=", changed, " LAN=", lan_mode)
		else:
			failed += 1
			push_error("Invisible skinned body: kind=%d samples=%d" % [kind, changed])
		visible.save_png("res://tests/previews/visible-%s-kind-%d.png" % ["lan" if lan_mode else "solo", kind])
		enemy.queue_free()
		await process_frame
	print("RENDER RESULT: ", passed, " passed, ", failed, " failed")
	quit(0 if failed == 0 else 1)
