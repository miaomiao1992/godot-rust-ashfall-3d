extends SceneTree
var game
var pawn
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, text: String) -> void:
	print("ASSAULT_MOVE ", "PASS " if ok else "FAIL ", text)
	if not ok: failures += 1

func advance(frames: int, input: String = "forward", stop_height: float = -1) -> void:
	Input.action_press(input)
	for i in frames:
		await physics_frame
		pawn._physics_process(1.0 / 60)
		if stop_height > 0 and pawn.position.y >= stop_height and not pawn.climbing: break
	Input.action_release(input)

func run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.lan.create_room("Movement regression", "Tester", 42691, "pvp")
	game.lan.start_battle()
	game.set_process(false)
	pawn = game.player
	for actor in game.lan.players.values(): actor.set_physics_process(false)
	await physics_frame
	pawn.position = game.level.goldsrc(Vector3(752, 1760, 40))
	pawn.rotation.y = PI / 2
	pawn.velocity = Vector3.ZERO
	await advance(250)
	print("CONTAINER TOP ", pawn.position, " climbing=", pawn.climbing)
	check(pawn.position.y >= 9.5, "front-container ladder reaches top")
	var start: Vector3 = pawn.position
	await advance(60)
	check(Vector2(pawn.position.x - start.x, pawn.position.z - start.z).length() > 2.8, "container top restores normal walking speed")
	pawn.position = game.level.goldsrc(Vector3(-672, 1536, 8))
	pawn.rotation.y = PI / 2
	pawn.velocity = Vector3.ZERO
	await advance(280, "forward", 9.3)
	print("BACK LADDER TOP ", pawn.position, " climbing=", pawn.climbing)
	check(pawn.position.y >= 9.3, "back-door ladder reaches roof ledge")
	pawn.position = game.level.goldsrc(Vector3(736, 416, 400))
	pawn.rotation.y = PI / 2
	pawn.velocity = Vector3(0, 5, 0)
	pawn.climbing = false
	pawn.ladder_detach_timer = 0.65
	var latched := false
	Input.action_press("forward")
	for i in 25:
		await physics_frame
		pawn._physics_process(1.0 / 60)
		latched = latched or pawn.climbing
	Input.action_release("forward")
	check(not latched, "jump across bridge ladder area does not latch or slow into climbing")
	print("ASSAULT_MOVE RESULT: ", failures, " failures")
	game.return_to_menu()
	await process_frame
	quit(0 if failures == 0 else 1)
