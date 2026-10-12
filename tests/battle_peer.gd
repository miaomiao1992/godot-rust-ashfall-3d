extends Node
## Real ENet hot-join replaces a bot, then replicates new combat features.
var game
var failed := 0

func _ready() -> void:
	call_deferred("run")

func check(ok: bool, text: String) -> void:
	print("BATTLE_NET ", "PASS " if ok else "FAIL ", text)
	if not ok: failed += 1

func wait_until(test: Callable, seconds: float = 20) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not test.call() and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	return test.call()

func run() -> void:
	if "--battle-host" in OS.get_cmdline_user_args(): await host()
	else: await client()
	print("BATTLE_NET RESULT ", "PASS" if failed == 0 else "FAIL")
	game.return_to_menu()
	await get_tree().process_frame
	get_tree().quit(0 if failed == 0 else 1)

func host() -> void:
	game.lan.create_room("Battle feature regression", "Human host", 42046, "pvp")
	game.lan.start_battle()
	check(game.state == "playing" and game.lan.fighters.size() == 2, "solo match starts with opposing bot")
	print("BATTLE_NET READY")
	if not await wait_until(func(): return game.lan.members.size() == 2 and game.lan.ready_peers.size() == 1):
		check(false, "hot client ready")
		return
	check(game.lan.fighters.values().all(func(f): return not f.is_bot), "actual ENet join replaces bot")
	var id := 0
	for member in game.lan.members:
		if int(member.id) != 1: id = int(member.id)
	var p = game.player
	var target = game.lan.players[id]
	p.position = Vector3(0, 0.05, 5)
	target.position = Vector3(0, 0.05, -5)
	var wall := Forge.box(game.world, Vector3(0, 1.5, 0), Vector3(6, 3, 0.22), Forge.material(Color(0.2, 0.3, 0.35), 0.8), true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	game.core.coop_tick(2.1)
	game.core.coop_switch(1, 5)
	game.core.coop_tick(0.3)
	game.lan.sync_stats()
	p.rotation.y = 0
	p.aim = 1
	p.recoil = 0
	p.trauma = 0
	p.scope_sway = Vector2.ZERO
	p.camera.look_at(target.global_position + Vector3.UP * 1.05)
	p.aim_pitch = p.camera.rotation.x
	p._update_weapon_pose()
	p.fire()
	game.lan.sync_stats()
	print("BATTLE_NET sniper target HP=", target.hp, " marks=", game.battle.marks.size())
	check(target.hp > 0 and target.hp < 100, "sniper shot penetrates actual metal collider")
	var cone = game.battle.spawn_prop("cone", Vector3(4, 0.35, 12))
	var drum = game.battle.spawn_prop("drum", Vector3(5.5, 0.55, 12))
	await get_tree().create_timer(0.3).timeout
	game.battle.impact({"collider": cone, "position": cone.global_position + Vector3.BACK * 0.22, "normal": Vector3.BACK}, Vector3.RIGHT, 5, 4)
	game.lan.ordnance._detonate({"kind": 0, "owner": 1, "pos": Vector3(4.5, 0.4, 12)})
	check(drum.broken, "blast ruptures physical drum")
	check(await wait_until(func(): return game.lan.members.size() == 1, 25), "client completed feature checks and left")
	check(game.lan.fighters.values().any(func(f): return f.is_bot), "real disconnect refills bot")
	wall.queue_free()

func client() -> void:
	game.lan.join_room("127.0.0.1", "Human client", 42046)
	if not await wait_until(func(): return game.state == "playing", 35):
		check(false, "hot-joined match")
		return
	check(bool(game.lan.pvp_state.fill_bots), "host fill-bots setting synchronized")
	check(game.lan.fighters.values().all(func(f): return not f.is_bot), "client sees human replacement, not ghost bot")
	check(game.player.WEAPONS.size() == 6, "six-weapon loadout available on client")
	var flags := {"sniper": false, "damage": false, "hole": false, "scorch": false, "spill": false, "debris": false, "prop_mark": false}
	var deadline := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline and flags.values().has(false):
		await get_tree().process_frame
		if game.lan.players.has(1) and game.lan.players[1].weapon_index == 5: flags.sniper = true
		if game.player.hp < 100: flags.damage = true
		for item in game.battle.marks.values():
			if int(item.data.kind) == 1: flags.hole = true
			if int(item.data.kind) == 3: flags.scorch = true
			if int(item.data.kind) == 4: flags.spill = true
			if int(item.data.target) > 0: flags.prop_mark = true
		for prop in game.battle.props.values():
			if prop.kind == "scrap" and prop.freeze: flags.debris = true
	for key in flags: check(flags[key], "client observed " + key)
	check(game.battle.props.values().all(func(prop): return prop.freeze), "client props are authority-controlled replicas")
