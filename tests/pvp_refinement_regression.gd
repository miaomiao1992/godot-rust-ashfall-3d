extends SceneTree
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, text: String) -> void:
	print("PVP_REFINEMENT ", "PASS " if ok else "FAIL ", text)
	if not ok: failures += 1

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.lan.create_room("Refinements", "Tester", 42693, "pvp")
	var choice = game.hud.menu.find_child("BotDifficultyChoice", true, false)
	check(choice != null and choice.item_count == 3 and choice.selected == 0, "three difficulty choices default to normal")
	var normal: Dictionary = game.lan.bots.settings()
	game.lan.set_bot_difficulty(1)
	var hard: Dictionary = game.lan.bots.settings()
	game.lan.set_bot_difficulty(2)
	var hell: Dictionary = game.lan.bots.settings()
	check(normal.reaction > hard.reaction and hard.reaction > hell.reaction, "reaction time differs by difficulty")
	check(normal.error > hard.error and hard.error > hell.error, "normal accuracy reduced without damage buffs")
	check(normal.pause > hard.pause and hard.pause > hell.pause, "normal has longer pauses between short bursts")
	check(int(game.lan.pvp_state.bot_difficulty) == 2, "difficulty serialized for clients")
	game.lan.start_battle()
	game.set_process(false)
	for actor in game.lan.players.values(): actor.set_physics_process(false)
	var p = game.player
	p.position = Vector3(0, 30, 0)
	p.velocity = Vector3.ZERO
	game.lan.ordnance.throw_grenade(p, 0, 0, 0)
	var full: Dictionary = game.lan.ordnance.items.values()[0]
	var start: Vector3 = full.pos
	var peak: float = start.y
	for i in 45:
		game.lan.ordnance.process(1.0 / 60)
		peak = maxf(peak, full.pos.y)
	check(peak - start.y > 1.0, "level full throw has a clearly visible >1m arc")
	check(full.pos.z < start.z - 9, "arc preserves useful forward travel")
	check(full.node.scale.x > 1.0, "projectile remains readable in flight")
	game.lan.ordnance.clear()
	game.lan.ordnance.throw_grenade(p, 2, 0, 0)
	var smoke: Dictionary = game.lan.ordnance.items.values()[0]
	smoke.smoke = true
	smoke.pos = Vector3(0, 1, 0)
	smoke.life = 25.0
	check(game.lan.ordnance.smoke_blocks(Vector3(0, 1, 8), Vector3(0, 1, -8)), "bots cannot see through smoke across sightline")
	check(not game.lan.ordnance.smoke_blocks(Vector3(10, 1, 8), Vector3(10, 1, -8)), "smoke does not block unrelated sightlines")
	for actor in game.lan.players.values():
		if actor.is_local: continue
		check(actor.team_marker.position.y > 2 and actor.team_marker.mesh.radius < 0.06, "team marker is a tiny head indicator, not a body ring")
	print("PVP_REFINEMENT RESULT: ", failures, " failures")
	game.return_to_menu()
	await process_frame
	quit(0 if failures == 0 else 1)
