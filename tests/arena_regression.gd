extends Node

var game
var passed := 0
var failures: Array[String] = []

func check(condition: bool, description: String) -> void:
	if condition:
		passed += 1
		print("PASS ARENA: ", description)
	else:
		failures.append(description)
		push_error("FAIL ARENA: " + description)

func flush() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run")

func clear_enemies() -> void:
	for enemy in get_tree().get_nodes_in_group("zombies"):
		enemy.queue_free()
	game.alive = 0
	game.boss = null

func run() -> void:
	seed(73017)
	game.start_run()
	game.state = "testing"
	for i in 6:
		clear_enemies()
		await get_tree().physics_frame
		await get_tree().physics_frame
		game._begin_wave()
	clear_enemies()
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert(game.wave == 7 and game.stage_index == 2)
	game.set_process(false)
	game.player.process_mode = Node.PROCESS_MODE_DISABLED
	game.player.position = Vector3(0, 0.1, 28)
	game.player.invulnerability = 999
	game.spawn_left = 0
	check(game.wave == 7 and game.stage_index == 2, "test enters the actual third-sector first wave")
	var enemy = game._spawn_add(Vector3(0, 0.1, 42), 2)
	enemy.position = Vector3(0, 0.1, 42)
	enemy.hp = 10000
	# Ten shotgun pellets produce 40 units of impulse before brute mass scaling.
	enemy.take_hit(1, enemy.position + Vector3.UP, Vector3.BACK, 40)
	game.state = "playing"
	for frame in 240:
		await get_tree().physics_frame
	print("ARENA REPRO: enemy position=", enemy.position, " alive=", game.alive, " wave=", game.wave)
	var accessible: bool = enemy.position.y > -1 and game.level.is_walkable_point(enemy.position)
	check(accessible, "shotgun impulse cannot strand the last elite below the arena")
	var hp: float = enemy.hp
	enemy.position = Vector3(0, -30, 55)
	await flush()
	check(enemy.position.y > -1 and game.level.is_walkable_point(enemy.position), "forced fallen enemy is recovered onto reachable ground")
	check(enemy.hp == hp and game.alive == 1 and game.kills == 0, "recovery preserves HP and does not award a fake kill")
	game.state = "testing"
	for entrance in game.level.spawn_points:
		var clear := true
		for kind in 6:
			var actor = game._spawn_add(entrance, kind)
			if actor == null or not game.level.is_walkable_point(actor.position):
				clear = false
			if actor:
				actor.queue_free()
		check(clear, "all six monster types have valid placement at gate " + str(entrance))
	await flush()
	game.crowd_timer = 0
	game.state = "playing"
	game._process(0.01)
	check(game.alive == 1, "freed test actors are excluded from the real live roster")
	game.state = "testing"
	enemy.queue_free()
	await flush()
	game.alive = 99
	game.crowd_timer = 0
	game.state = "playing"
	game._process(0.01)
	check(game.alive == 0, "stale live counter is reconciled with actual scene actors")
	game.state = "testing"
	# A rejected spawn must leave its ticket pending, not create a phantom enemy.
	var open_cells: Array[Vector2i] = []
	for x in 29:
		for z in 29:
			var cell := Vector2i(x, z)
			if not game.level.grid.is_point_solid(cell):
				open_cells.append(cell)
	game.level.grid.fill_solid_region(game.level.grid.region)
	game.spawn_left = 1
	game._spawn_zombie()
	check(game.spawn_left == 1 and game.alive == 0, "failed placement keeps the spawn ticket without increasing alive")
	for cell in open_cells:
		game.level.grid.set_point_solid(cell, false)
	game._spawn_zombie()
	check(game.spawn_left == 0 and game.alive == 1, "spawn ticket succeeds after a valid location is available")
	clear_enemies()
	await flush()
	# Exhaust the real 106-enemy budget by spawning and killing real actors.
	game.spawn_left = 106
	game.spawn_cursor = 0
	var spawned := 0
	while game.spawn_left > 0 and spawned < 110:
		game._spawn_zombie()
		var actor = null
		for candidate in get_tree().get_nodes_in_group("zombies"):
			if not candidate.dead and not candidate.is_queued_for_deletion():
				actor = candidate
				break
		if actor == null:
			break
		actor.take_hit(100000, actor.position + Vector3.UP * 3, Vector3.FORWARD, 1)
		game.levelup_pending = 0
		spawned += 1
		await flush()
	check(spawned == 106 and game.spawn_left == 0 and game.alive == 0, "all 106 first-wave enemies spawn and clear without a ghost ticket")
	game.state = "playing"
	game.player.position = game.level.terminals[0].position + Vector3(0, 0.1, 2.6)
	game.interact()
	game.crowd_timer = 0
	game._process(0.11)
	check(game.objective_count == 1 and game.next_wave > 0, "cleared first wave plus one valve starts the intermission")
	game._process(12.1)
	check(game.wave == 8 and game.stage_index == 2 and game.spawn_left == 118, "third sector advances into its second wave")
	print("ARENA RESULT: ", passed, " passed, ", failures.size(), " failed")
	get_tree().quit(0 if failures.is_empty() else 1)
