extends Node

var game
var passed := 0
var failures: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	if condition:
		passed += 1
		print("PASS: ", description)
	else:
		failures.append(description)
		push_error("FAIL: " + description)

func flush() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame

func clear_enemies() -> void:
	for enemy in get_tree().get_nodes_in_group("zombies"):
		enemy.queue_free()
	game.alive = 0
	game.boss = null

func run() -> void:
	await flush()
	check(ClassDB.class_exists("AshfallCore"), "Rust GDExtension registered")
	game.start_run()
	game.state = "testing"
	check(game.wave == 1 and game.spawn_left == 34, "campaign starts in sector 1")
	check(game.player.WEAPONS.size() == 6, "six weapons supplied by Rust")
	game.player.switch_weapon(4)
	check(game.player.weapon_index == 0, "growth-locked weapon cannot be equipped")
	# Verify the raycast really hits a 3D physics body.
	var target = game._spawn_add(Vector3(0, 4.1, 37), 0)
	target.position = Vector3(0, 4.05, 37)
	target.hp = 10000
	await flush()
	game.player.camera.look_at(target.global_position + Vector3.UP * 1.15)
	var before: float = target.hp
	game.player.fire()
	check(target.hp < before and game.shots_hit == 1, "hitscan damages actual 3D enemy")
	check(game.player.magazines[0] == 14, "firing consumes magazine")
	game.player.begin_reload()
	check(game.player.reload_timer > 0, "reload begins")
	game.player.reload_timer = 0.0001
	game.state = "playing"
	await flush()
	game.state = "testing"
	check(game.player.magazines[0] == 15, "reload completes and refills pistol")
	# Award legitimate enemy rewards through the native progression path.
	while game.level_number < 8:
		var victim = game._spawn_add(Vector3(8, 0.1, 8), 2)
		victim.take_hit(100000, victim.global_position + Vector3.UP * 3, Vector3.FORWARD, 1)
		await flush()
	game.levelup_pending = 0
	check(game.level_number >= 8, "kill XP unlocks the entire arsenal")
	for i in range(1, game.player.WEAPONS.size()):
		game.player.switch_weapon(i)
		game.player.camera.look_at(target.global_position + Vector3.UP * 1.15)
		before = target.hp
		game.player.fire()
		check(game.player.weapon_index == i and target.hp < before, "weapon %d equips and damages target" % (i + 1))
	game.state = "upgrade"
	game.choose_upgrade(1)
	game.state = "testing"
	check(game.player.max_hp == 120, "native upgrade updates player maximum HP")
	clear_enemies()
	await flush()
	var preserved_level: int = game.level_number
	var layouts: Array[Dictionary] = []
	for stage in 3:
		game._change_stage(stage)
		await flush()
		check(game.level.stage == stage and game.player.max_hp == 120 and game.level_number == preserved_level, "sector %d preserves growth" % (stage + 1))
		var navigable := true
		for point in game.level.spawn_points:
			var cells = game.level.grid.get_id_path(game.level.nearest_open(game.level.world_cell(point)), game.level.world_cell(game.level.player_spawn))
			if cells.is_empty():
				navigable = false
		check(navigable, "sector %d spawn routes reach the player" % (stage + 1))
		var shape: Dictionary = {}
		for x in 29:
			for z in 29:
				var cell := Vector2i(x, z)
				if not game.level.grid.is_point_solid(cell):
					shape[cell] = true
		layouts.append(shape)
		var height_continuous := true
		for cell in shape:
			for direction in [Vector2i.RIGHT, Vector2i.DOWN]:
				if shape.has(cell + direction) and absf(game.level.cell_world(cell).y - game.level.cell_world(cell + direction).y) > 1.1:
					height_continuous = false
		check(height_continuous, "sector %d navigation has no false links across vertical walls" % (stage + 1))
		var sample: Vector3 = [Vector3(-28, 0, -18), Vector3(16, 0, -4), Vector3(16, 0, 0)][stage]
		var query := PhysicsRayQueryParameters3D.create(sample + Vector3.UP * 30, sample - Vector3.UP * 5, 1)
		var floor_hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(query)
		check(not floor_hit.is_empty() and absf(floor_hit.position.y - game.level.surface_height(sample)) < 0.06, "sector %d physical floor matches navigation height" % (stage + 1))
		if stage == 0:
			check(not game.level.is_walkable_point(Vector3(30, 0, 16)) and game.level.surface_height(Vector3(-28, 0, -40)) > game.level.surface_height(game.player.position), "highway has real void and uphill elevation")
		elif stage == 1:
			check(not game.level.is_walkable_point(Vector3(0, 0, -20)) and game.level.is_walkable_point(Vector3(0, 0, 6)), "dock water channels are crossed only by authored bridges")
		else:
			check(not game.level.is_walkable_point(Vector3.ZERO) and game.level.terminals.size() == 3, "laboratory core blocks space and has three operable valves")
		# Test each stage's boss and ensure its skill dispatch creates gameplay objects.
		game.wave = (stage + 1) * 3
		var boss = game._spawn_add(Vector3(0, 0.1, -14), 4)
		game.boss = boss
		check(boss.size_factor > 2 and boss.hp > 1800, "sector %d has a durable distinct boss" % (stage + 1))
		boss.skill_timer = 0
		boss._boss_skills(0.016, game.player.position, 5)
		check(not game.hazards.is_empty(), "boss smash produces dodgeable warning")
		boss.hp = boss.max_hp * 0.4
		boss._boss_skills(0.016, game.player.position, 20)
		check(boss.enraged, "boss enters second phase")
		for kind in [0, 1, 2, 3, 5]:
			var enemy = game._spawn_add(Vector3(-8, 0.1, 8), kind)
			check(enemy.kind == kind and enemy.skeleton != null and enemy.animation != null, "monster tier %d loads textured rig and animations" % kind)
		clear_enemies()
		await flush()
	for a in 3:
		for b in range(a + 1, 3):
			var overlap := 0
			for cell in layouts[a]:
				if layouts[b].has(cell):
					overlap += 1
			var similarity := float(overlap) / (layouts[a].size() + layouts[b].size() - overlap)
			check(similarity < 0.65, "sector %d and %d differ structurally (floor Jaccard %.2f)" % [a + 1, b + 1, similarity])
	# Validate the actual warning / damage / harmless fade lifecycle in the game.
	game._change_stage(1)
	await flush()
	game._clear_hazards()
	game.acid_cast_cooldown = 0
	var caster = game._spawn_add(Vector3(-8, 0, -45), 5)
	var locked_position: Vector3 = game.player.position
	check(game.try_acid_attack(caster, locked_position, true) and game.hazards.size() == 1, "elite acid locks exactly one landing point")
	game.state = "playing"
	var prior_hp: float = game.player.hp
	game._update_hazards(0.8)
	check(game.player.hp == prior_hp and not game.hazards[0].activated, "amber warning causes no damage")
	game.player.invulnerability = 0
	game._update_hazards(0.81)
	check(game.hazards[0].activated and game.player.hp < prior_hp, "damage starts only after the warning expires")
	game.player.invulnerability = 0
	game._update_hazards(2.9)
	prior_hp = game.player.hp
	game._update_hazards(0.1)
	check(game.player.hp == prior_hp and game.hazards[0].life < 0, "fading corrosion no longer damages player")
	game._update_hazards(0.6)
	check(game.hazards.is_empty(), "corrosion expires instead of accumulating forever")
	game.state = "testing"
	game.acid_cast_cooldown = 0
	caster.acid_step = 0
	check(game.try_acid_attack(caster, locked_position, false) and game.hazards.size() == 3, "dock boss uses an ordered three-point line")
	var positions: Array[Vector3] = []
	for h in game.hazards:
		positions.append(h.node.position)
	game.player.position += Vector3(10, 0, 0)
	game._update_hazards(0.3)
	var unchanged := true
	for i in positions.size():
		unchanged = unchanged and positions[i] == game.hazards[i].node.position
	check(unchanged, "locked pattern does not chase subsequent player movement")
	check(not game.try_acid_attack(caster, locked_position, true), "shared cast interval prevents simultaneous spam")
	game.acid_cast_cooldown = 0
	check(not game.try_acid_attack(caster, locked_position, true), "overlapping corrosion stacks are rejected")
	game._clear_hazards()
	for i in 6:
		game.create_hazard(Vector3(40, 0, -40 + i * 6), 1.9, "acid", 1.6)
	check(not game.try_acid_attack(caster, locked_position, true), "global six-spot limit is enforced")
	game._clear_hazards()
	clear_enemies()
	game._change_stage(0)
	await flush()
	# Run a real CharacterBody3D uphill rather than trusting only nav metadata.
	var climber = game._spawn_add(Vector3(-28, 4.2, -11), 0)
	climber.position = game.level.ground_point(Vector3(-28, 0, -11)) + Vector3.UP * 0.05
	var initial_height: float = climber.position.y
	game.player.position = Vector3(-28, 8.1, -37)
	game.player.process_mode = Node.PROCESS_MODE_DISABLED
	game.set_process(false)
	game.state = "playing"
	for frame in 150:
		await get_tree().physics_frame
	check(climber.position.y > initial_height + 0.4, "zombie physics actually climbs the highway slope")
	game.state = "testing"
	game.set_process(true)
	game.player.process_mode = Node.PROCESS_MODE_INHERIT
	clear_enemies()
	await flush()
	game.state = "playing"
	game.player.invulnerability = 0
	game.player.take_damage(100000, Vector3.ZERO)
	check(game.state == "dead" and get_tree().paused, "lethal damage opens death screen and pauses")
	game.start_run()
	game.state = "testing"
	check(game.stage_index == 0 and game.wave == 1 and game.player.hp == 100 and game.level_number == 1, "restart resets campaign and growth")
	# Exercise the automatic nine-wave campaign transition, not just stage loading.
	for completed_wave in range(1, 10):
		clear_enemies()
		await flush()
		game.spawn_left = 0
		game.next_wave = 0
		game.state = "playing"
		game._process(0.01)
		if completed_wave >= 7:
			check(game.objective_waiting and game.next_wave == 0, "laboratory wave waits for coolant valve objective")
			var index := completed_wave - 7
			var terminal: Dictionary = game.level.terminals[index]
			game.player.position = terminal.position + Vector3(0, 0.1, 2.6)
			game.interact()
			check(game.objective_count == index + 1 and terminal.activated, "E interaction closes valve %d" % (index + 1))
			game._process(0.01)
		if completed_wave < 9:
			game._process(12.1)
			game.state = "testing"
			check(game.wave == completed_wave + 1 and game.stage_index == completed_wave / 3, "automatic transition after wave %d" % completed_wave)
			if game.wave % 3 == 0:
				check(is_instance_valid(game.boss), "boss automatically spawned on wave %d" % game.wave)
	check(game.state == "victory" and get_tree().paused, "victory opens completion screen")
	game.return_to_menu()
	check(game.state == "menu" and not get_tree().paused, "return to menu restores live scene")
	await flush()
	print("SMOKE RESULT: ", passed, " passed, ", failures.size(), " failed")
	get_tree().quit(0 if failures.is_empty() else 1)
