extends SceneTree

var failures := 0

func check(ok: bool, text: String) -> void:
	print("GRENADE_DAMAGE ", "PASS " if ok else "FAIL ", text)
	if not ok: failures += 1

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.lan.create_room("Grenade damage", "Host", 42679, "pvp")
	game.lan.start_battle()
	game.set_process(false)
	var p = game.player
	var enemy
	for id in game.lan.players:
		var actor = game.lan.players[id]
		actor.set_physics_process(false)
		if actor.team != p.team: enemy = actor
	check(enemy != null, "real PvP opponent registered")
	if enemy == null:
		quit(1)
		return
	p.position = Vector3(0, 30, 0)
	enemy.position = Vector3(4, 30, 0)
	await physics_frame
	var before_ammo: int = game.lan.fighters[p.peer_id].grenades[0]
	p.select_grenade(0)
	var event := InputEventAction.new()
	event.action = "shoot"
	event.pressed = true
	p._unhandled_input(event)
	check(game.lan.ordnance.items.is_empty(), "mouse press creates no projectile")
	check(int(game.lan.fighters[p.peer_id].grenades[0]) == before_ammo, "holding consumes no grenade")
	event.pressed = false
	p._unhandled_input(event)
	await create_timer(0.6).timeout
	check(game.lan.ordnance.items.size() == 1, "mouse release creates authoritative HE projectile")
	check(int(game.lan.fighters[p.peer_id].grenades[0]) == before_ammo - 1, "release consumes exactly one grenade")
	if game.lan.ordnance.items.is_empty():
		quit(1)
		return
	# Advance spawn protection, then place the thrown grenade in unobstructed
	# air at a known range. Expire its fuse to isolate real blast HP accounting.
	game.core.coop_tick(2.1)
	game.lan.sync_stats()
	var item: Dictionary = game.lan.ordnance.items.values()[0]
	item.pos = Vector3(0, 31.4, 0)
	item.vel = Vector3.ZERO
	item.life = 0.001
	var before_hp: float = enemy.hp
	game.lan.ordnance.process(0.002)
	check(enemy.hp < before_hp, "HE reduces enemy HP: %.2f -> %.2f" % [before_hp, enemy.hp])
	check(absf(enemy.hp - (before_hp - 150.0 * (1.0 - 4.0 / 9.0))) < 1.0, "four-metre blast applies expected ~83.33 damage")
	check(p.hp == 100, "current PvP rules exclude self damage")
	check(game.lan.ordnance.items.is_empty(), "detonated HE projectile removed")
	print("GRENADE_DAMAGE RESULT: ", failures, " failures")
	game.return_to_menu()
	await process_frame
	quit(0 if failures == 0 else 1)
