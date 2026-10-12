extends SceneTree
## Real capsule collision through original 1.6 roof entry and duct branches.
var failures := 0
var game
var pawn

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, text: String) -> void:
	print("ASSAULT16 ", "PASS " if ok else "FAIL ", text)
	if not ok: failures += 1

func gold(point: Vector3) -> Vector3:
	return game.level.goldsrc(point)

func walk_to(target: Vector3, max_frames: int = 360) -> bool:
	for frame in max_frames:
		await physics_frame
		var flat := Vector3(target.x - pawn.position.x, 0, target.z - pawn.position.z)
		if flat.length() < 0.15: return true
		var direction := flat.normalized()
		pawn.velocity.x = direction.x * 3.0
		pawn.velocity.z = direction.z * 3.0
		pawn.velocity.y = -1 if pawn.is_on_floor() else pawn.velocity.y - 24.0 / 60
		pawn.move_and_slide()
	print("BLOCKED ", pawn.position, " target ", target)
	return false

func run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.lan.create_room("Original Assault", "Tester", 42683, "pvp")
	game.lan.start_battle()
	game.set_process(false)
	game.state = "testing"
	pawn = game.player
	for actor in game.lan.players.values():
		actor.set_process(false)
		actor.set_physics_process(false)
	await physics_frame
	await physics_frame
	check(game.level.spatial_type == "cs_assault_16", "original map loaded")
	check(game.level.ladders.size() == 8, "all eight original ladder volumes exist")
	check(game.level.team_spawns[0].size() == 10 and game.level.team_spawns[1].size() == 10, "original CT/T spawn positions")
	pawn.position = gold(Vector3(0, 2208, 516))
	pawn.set_crouching(true)
	for frame in 50:
		await physics_frame
		pawn.velocity = Vector3.DOWN * 3.0
		pawn.move_and_slide()
	check(absf(pawn.position.y - 10.9) < 0.1, "roof opening drops into original lower vent")
	check(await walk_to(gold(Vector3(0, 2700, 436))), "crawl along lower duct from roof hatch")
	pawn.set_crouching(false)
	check(pawn.crouching, "cannot stand into duct ceiling")
	check(await walk_to(gold(Vector3(0, 2464, 436))), "crawl back to duct junction")
	# Test upward traversal using actual player input/ladder logic at junction.
	game.state = "playing"
	pawn.position = gold(Vector3(0, 2464, 440))
	pawn.set_crouching(true)
	Input.action_press("forward")
	Input.action_press("crouch")
	for frame in 60:
		await physics_frame
		pawn._physics_process(1.0 / 60)
	Input.action_release("forward")
	Input.action_release("crouch")
	game.state = "testing"
	check(pawn.position.y > 13.1, "junction ladder climbs from lower to upper duct")
	pawn.position = gold(Vector3(-60, 2464, 530))
	pawn.set_crouching(true)
	check(await walk_to(gold(Vector3(-520, 2464, 528))), "upper branch leads towards monitor-room grille")
	var grille = game.level.brush_nodes[77]
	grille.receive_damage(10)
	check(grille.broken and grille.collision_layer == 0, "original grille can be shot open")
	check(await walk_to(gold(Vector3(-576, 2464, 528))), "crawl onto opened monitor-room exit")
	for frame in 80:
		await physics_frame
		pawn.velocity = Vector3.DOWN * 4.0
		pawn.move_and_slide()
	check(pawn.position.y < 12.0, "opened grille permits descent into interior")
	check(game.level.snapshot_brushes().has(77), "broken grille included in late-join snapshot")
	print("ASSAULT16 RESULT: ", failures, " failures")
	game.return_to_menu()
	await process_frame
	quit(0 if failures == 0 else 1)
