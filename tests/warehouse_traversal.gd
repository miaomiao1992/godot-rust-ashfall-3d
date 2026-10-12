extends SceneTree
## Walk the actual player capsule through each duct and up both roof ramps.
var failures := 0
var game
var pawn

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, text: String) -> void:
	print("WAREHOUSE ", "PASS " if ok else "FAIL ", text)
	if not ok: failures += 1

func walk_to(target: Vector3, max_frames: int = 500) -> bool:
	for frame in max_frames:
		await physics_frame
		var flat := Vector3(target.x - pawn.position.x, 0, target.z - pawn.position.z)
		if flat.length() < 0.35: return true
		var direction := flat.normalized()
		pawn.velocity.x = direction.x * 9.2
		pawn.velocity.z = direction.z * 9.2
		pawn.velocity.y = -1 if pawn.is_on_floor() else pawn.velocity.y - 24.0 / 60
		pawn.move_and_slide()
	print("WAREHOUSE blocked at ", pawn.position, " heading to ", target)
	return false

func image(path: String, pos: Vector3, focus: Vector3) -> void:
	pawn.camera.global_position = pos
	pawn.camera.look_at(focus)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.lan.create_room("Warehouse traversal", "Tester", 42044, "pvp")
	game.start_pvp()
	game.set_process(false)
	game.state = "testing"
	pawn = game.player
	pawn.set_process(false)
	pawn.set_physics_process(false)
	pawn.rig.visible = false
	game.hud.root.visible = false
	await physics_frame
	for route in game.level.pipe_routes:
		pawn.position = route.entry
		pawn.velocity = Vector3.ZERO
		check(await walk_to(route.exit), "player enters and crosses hollow pipe " + str(route.entry))
		check(pawn.position.y > -0.1 and pawn.position.y < 0.6, "pipe walkway supports feet")
		check(await walk_to(route.entry), "pipe also traversable in reverse")
	for route in game.level.roof_routes:
		pawn.position = route.entry
		pawn.velocity = Vector3.ZERO
		check(await walk_to(route.exit), "player ascends roof ramp " + str(route.entry))
		check(absf(pawn.position.y - game.level.ROOF_HEIGHT) < 0.4, "player stands on roof collider")
		check(await walk_to(Vector3(0, game.level.ROOF_HEIGHT, route.exit.z)), "landing connects to roof combat area")
		check(await walk_to(route.exit), "roof route returns to landing")
		check(await walk_to(route.entry), "player can descend to ground")
	if DisplayServer.get_name() != "headless":
		await image("res://tests/previews/22-pvp-warehouse.png", Vector3(1, 2, 30), Vector3(15, 2, 8))
		await image("res://tests/previews/23-pvp-pipe.png", Vector3(37, 1.85, 8), Vector3(16, 1.85, 8))
		await image("res://tests/previews/24-pvp-roof.png", Vector3(30, 13, 40), Vector3(0, 12, 0))
		await image("res://tests/previews/26-pvp-roof-access.png", Vector3(34, 2.0, 44), Vector3(40, 8, 24))
	print("WAREHOUSE RESULT: ", failures, " failures")
	game.return_to_menu()
	game.lan = null
	await process_frame
	quit(0 if failures == 0 else 1)
