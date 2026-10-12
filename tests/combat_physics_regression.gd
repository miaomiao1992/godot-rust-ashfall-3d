extends SceneTree
var game
var p
var victim
var wall: Node3D
var failed := 0
var passed := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, text: String) -> void:
	print("COMBAT_PHYSICS ", "PASS " if ok else "FAIL ", text)
	if ok: passed += 1
	else: failed += 1

func frames(count: int = 2) -> void:
	for i in count: await physics_frame

func barrier(thickness: float, surface: String) -> void:
	if is_instance_valid(wall): wall.free()
	wall = Forge.box(game.world, Vector3(0, 1.5, -2), Vector3(6, 3, thickness), Forge.material(Color(0.4, 0.4, 0.4)), true)
	wall.get_child(0).set_meta("surface", surface)
	await frames()

func reset_fighters() -> void:
	game.core.pvp_start()
	game.core.coop_tick(2.1)
	game.lan.sync_stats()
	p.position = Vector3(0, 0.05, 6)
	victim.position = Vector3(0, 0.05, -6)
	p.velocity = Vector3.ZERO
	victim.velocity = Vector3.ZERO
	p.recoil = 0
	p.trauma = 0
	p.scope_sway = Vector2.ZERO
	p.aim = 1
	p.rotation.y = 0
	p.camera.position = Vector3(0, 1.65, 0)
	p.camera.look_at(victim.global_position + Vector3.UP * 1.05)
	p.aim_pitch = p.camera.rotation.x
	p._update_weapon_pose()
	await frames()

func shoot(index: int) -> void:
	game.core.coop_switch(1, index)
	game.core.coop_tick(0.3)
	game.lan.sync_stats()
	p.fire()
	game.lan.sync_stats()
	await frames()

func photo(path: String, pos: Vector3, focus: Vector3) -> void:
	p.camera.global_position = pos
	p.camera.look_at(focus)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func red_width(image: Image) -> int:
	var left := image.get_width()
	var right := 0
	for y in range(image.get_height() / 2 - 20, image.get_height() / 2 + 20):
		for x in range(image.get_width() / 4, image.get_width() * 3 / 4):
			var c := image.get_pixel(x, y)
			if c.r > 0.65 and c.g < 0.25 and c.b > 0.45: left = mini(left, x); right = maxi(right, x)
	return maxi(0, right - left)

func run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.lan.create_room("Combat physics", "RED", 42044, "pvp")
	game.core.coop_register(2, "BLUE")
	game.start_pvp()
	game.lan.spawn_player(2, "BLUE")
	game.set_process(false)
	p = game.player
	victim = game.lan.players[2]
	p.set_physics_process(false)
	victim.set_physics_process(false)
	p.set_process(false)
	victim.set_process(false)
	game.hud.root.visible = false
	# Isolate synthetic barriers from the new original-map walls. This test
	# exercises penetration physics; real map collision has its own traversal test.
	game.level.navigation.visible = false
	for brush in game.level.brush_nodes.values():
		brush.collision_layer = 0
		for child in brush.get_children():
			if child is StaticBody3D: child.collision_layer = 0
	Forge.box(game.world, Vector3(0, -0.5, 0), Vector3(70, 1, 70), Forge.material(Color(0.1, 0.1, 0.1)), true)
	await reset_fighters()
	await barrier(0.22, "wood")
	await shoot(0)
	check(victim.hp == 100, "pistol stopped by 22cm wood")
	await reset_fighters()
	await shoot(3)
	check(victim.hp > 0 and victim.hp < 100, "rifle penetrates real thin wood with reduced damage")
	var entry_exit := 0
	for item in game.battle.marks.values():
		if int(item.data.kind) == 2: entry_exit += 1
	check(entry_exit >= 3, "wood has entry and exit bullet marks")
	await barrier(0.20, "metal")
	await reset_fighters()
	await shoot(3)
	check(victim.hp == 100, "rifle stopped by 20cm steel")
	await reset_fighters()
	await shoot(5)
	check(victim.hp < 100, "sniper penetrates steel within its own depth limit")
	await barrier(0.8, "concrete")
	await reset_fighters()
	await shoot(5)
	check(victim.hp == 100, "sniper cannot penetrate thick concrete")
	await reset_fighters()
	await shoot(4)
	check(victim.hp < 100, "electromagnetic gun penetrates deeper concrete")
	await barrier(0.18, "wood")
	var origin := Vector3(0, 0.5, 0)
	var target := Vector3(0, 1.3, -4)
	var one_wall: float = game.battle.blast_transmission(origin, target)
	check(one_wall > 0.5 and one_wall < 1, "thin wood transmits attenuated blast")
	var extra := Forge.box(game.world, Vector3(0, 1.5, -3), Vector3(6, 3, 0.18), Forge.material(Color.GRAY), true)
	extra.get_child(0).set_meta("surface", "wood")
	await frames()
	var two_walls: float = game.battle.blast_transmission(origin, target)
	check(two_walls > 0 and two_walls < one_wall, "two walls compound blast attenuation")
	extra.free()
	await reset_fighters()
	victim.position = Vector3(0, 0.05, -4)
	await frames()
	game.lan.ordnance._detonate({"kind": 0, "owner": 1, "pos": origin})
	check(victim.hp < 100 and victim.hp > 0, "real grenade damages enemy behind thin wall")
	var soot := false
	for item in game.battle.marks.values():
		if int(item.data.kind) == 3: soot = true
	check(soot, "grenade leaves persistent projected scorch")
	await barrier(1.5, "concrete")
	await reset_fighters()
	victim.position = Vector3(0, 0.05, -4)
	await frames()
	game.lan.ordnance._detonate({"kind": 0, "owner": 1, "pos": origin})
	check(victim.hp == 100, "heavy concrete blocks grenade blast")
	wall.free()
	await frames()
	var drum = game.battle.spawn_prop("drum", Vector3(4, 0.55, 16))
	await frames(20)
	var before: Vector3 = drum.position
	drum.shot(10, drum.position + Vector3.UP * 0.3, Vector3.RIGHT, 4)
	await frames(30)
	check(drum.position.distance_to(before) > 0.025, "bullet impulse moves real rigid-body drum")
	var local_mark: Dictionary = game.battle.make_mark(drum.global_position + drum.global_basis.z * 0.38, drum.global_basis.z, 1, 0.16, 100, drum)
	check(game.battle.marks[int(local_mark.id)].node.get_parent() == drum, "bullet hole follows moving prop")
	var cone = game.battle.spawn_prop("cone", Vector3(5, 0.35, 24))
	await frames(20)
	before = cone.position
	game.battle.explosion(Vector3(4, 0.3, 24))
	await frames(25)
	check(cone.position.distance_to(before) > 0.5, "blast throws lightweight props")
	var crate = game.battle.spawn_prop("crate", Vector3(-4, 0.46, 24))
	await frames()
	crate.shot(100, crate.position, Vector3.RIGHT, 5)
	check(crate.broken and crate.collision_layer == 0, "destroyed crate releases its original collider")
	check(game.battle.props.values().any(func(prop): return prop.kind == "plank"), "crate creates physical plank fragments")
	drum.hurt(1000)
	await frames()
	check(game.battle.marks.values().any(func(item): return int(item.data.kind) == 4), "ruptured drum leaves chemical pollution")
	if DisplayServer.get_name() != "headless":
		await photo("res://tests/previews/27-blast-pollution.png", Vector3(4, 4, 19), Vector3(3, 0, 17))
		var board := Forge.box(game.world, Vector3(0, 1.5, 21), Vector3(4, 3, 0.2), Forge.material(Color(0.5, 0.5, 0.47)), true)
		for point in [Vector3(-0.6, 1.6, 21.105), Vector3(0, 1.3, 21.105), Vector3(0.55, 1.9, 21.105)]:
			game.battle.make_mark(point, Vector3.BACK, 0, 0.26, 100)
		await photo("res://tests/previews/28-bullet-holes.png", Vector3(0, 1.8, 24), Vector3(0, 1.5, 21))
		board.free()
	# Marks and fragments have independent caps and lifetimes.
	for i in 240: game.battle.make_mark(Vector3(0, 0, 22), Vector3.UP, 0, 0.1, 100)
	check(game.battle.marks.size() == game.battle.MAX_MARKS, "persistent surface history is bounded")
	for i in 10:
		var doomed = game.battle.spawn_prop("crate", Vector3(10, 0.46, 25))
		doomed.hurt(999)
	check(game.battle.props.values().filter(func(prop): return prop.lifetime > 0).size() <= game.battle.MAX_FRAGMENTS, "physical debris is capped independently")
	game.battle._process(200)
	check(game.battle.marks.is_empty(), "old combat traces expire")
	check(game.battle.props.values().all(func(prop): return prop.lifetime < 0), "temporary physical debris expires")
	# Actual magnification changes Camera3D projection, not just a UI texture.
	await reset_fighters()
	victim.position.x = 8
	game.core.coop_switch(1, 5)
	game.lan.sync_stats()
	p.position = Vector3(0, 0.05, 12)
	p.aim_pitch = 0
	p.scope_sway = Vector2.ZERO
	p._update_weapon_pose()
	p.bolt_timer = 0
	p.camera.fov = 82
	p.set_process(true)
	var calibration := Forge.box(game.world, Vector3(0, 1.70, -24), Vector3(1.4, 1.8, 0.2), Forge.material(Color(1, 0, 0.8), 0, 4))
	var baseline := 0
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		baseline = red_width(root.get_texture().get_image())
	game.hud.hide_overlay()
	var aim_click := InputEventAction.new()
	aim_click.action = "aim"
	aim_click.pressed = true
	p._unhandled_input(aim_click)
	p.set_physics_process(true)
	await frames(65)
	check(p.scope_active(), "right mouse engages sniper scope")
	var expected := rad_to_deg(2 * atan(tan(deg_to_rad(82.0) * 0.5) / 4))
	check(absf(p.camera.fov - expected) < 0.1, "4x scope uses true perspective magnification")
	var first := 0
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		first = red_width(root.get_texture().get_image())
		print("COMBAT_PHYSICS rendered widths baseline=", baseline, " 4x=", first)
		check(baseline > 0 and first > baseline * 3.5, "rendered target is enlarged fourfold")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	p._unhandled_input(wheel)
	await frames(35)
	check(p.scope_zoom == 8 and p.camera.fov < 13, "mouse wheel switches to genuine 8x zoom")
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		var second := red_width(root.get_texture().get_image())
		print("COMBAT_PHYSICS rendered width 8x=", second)
		check(first > 0 and second > first * 1.75, "8x doubles rendered target size over 4x")
	Input.action_press("sprint")
	await frames(15)
	check(p.holding_breath and p.scope_sway.length() < 0.0002, "shift holds breath and steadies the reticle")
	Input.action_release("sprint")
	if DisplayServer.get_name() != "headless":
		calibration.visible = false
		var line: Vector3 = victim.global_position + Vector3.UP * 1.15 - p.camera.global_position
		p.rotation.y = atan2(-line.x, -line.z)
		p.aim_pitch = atan2(line.y, Vector2(line.x, line.z).length())
		p._update_weapon_pose()
		game.hud.root.visible = true
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/previews/29-sniper-8x.png")
	p.set_physics_process(false)
	p.set_process(true)
	game.core.coop_tick(3)
	p.fire()
	check(p.bolt_timer > 1 and p.magazines[5] == 4, "sniper shot consumes independent round and cycles bolt")
	check(not p.scope_active(), "scope opens during bolt cycle")
	Input.action_release("aim")
	calibration.free()
	print("COMBAT_PHYSICS RESULT: ", passed, " passed, ", failed, " failed")
	game.return_to_menu()
	await process_frame
	quit(0 if failed == 0 else 1)
