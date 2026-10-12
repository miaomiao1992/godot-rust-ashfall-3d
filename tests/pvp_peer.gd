extends Node
## Actual host/client integration: real ray hits, snapshots, ordnance and restart.
var game
var failures := 0
var checks := 0
var required := 2
var client_kill := false
var client_dead := false
var client_respawn := false
var client_smoke := false
var client_flash := false
var client_finished := false
var client_roof := false
var client_pipe := false
var first_epoch := -1

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--players="): required = int(arg.get_slice("=", 1))
	call_deferred("_run")

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PVP_TEST ", "PASS " if ok else "FAIL ", text)

func wait_until(predicate: Callable, seconds: float = 20) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return predicate.call()

func pause(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func _run() -> void:
	if "--pvp-host" in OS.get_cmdline_user_args(): await _host()
	else: await _client()
	print("PVP_TEST RESULT ", "PASS" if failures == 0 else "FAIL", " checks=", checks)
	game.return_to_menu()
	await get_tree().process_frame
	get_tree().quit(0 if failures == 0 else 1)

func _host() -> void:
	game.lan.create_room("PvP regression", "RED-HOST", 42042, "pvp")
	game.lan.set_fill_bots(false)
	game.lan.start_battle()
	check(game.state == "lobby", "unbalanced lobby cannot start")
	print("PVP_TEST LOBBY")
	if not await wait_until(func(): return game.lan.members.size() == required, 40):
		check(false, "all clients connected")
		return
	check(game.lan.fighters.size() == required, "roster registered")
	game.lan.start_battle()
	if not await wait_until(func(): return game.lan.ready_peers.size() == required - 1):
		check(false, "clients ready")
		return
	check(game.level.spatial_type == "pvp_warehouse_three_lane", "warehouse loaded")
	check(game.get_tree().get_nodes_in_group("zombies").is_empty(), "no survival enemies")
	var victim := 0
	for id in game.lan.fighters:
		if int(game.lan.fighters[id].team) == 1: victim = id; break
	check(victim > 1, "opponent allocated")
	var p = game.player
	var target = game.lan.players[victim]
	p.position = Vector3(30, 11.1, 30)
	target.position = Vector3(28, 0.2, 8)
	await pause(1)
	for team in 2:
		for slot in 5:
			var spawn: Vector3 = game.level.spawn_for(team, slot)
			check(not game.level.grid.is_point_solid(game.level.world_cell(spawn)), "spawn navigable %d/%d" % [team, slot])
	var path: PackedVector2Array = game.level.grid.get_point_path(game.level.world_cell(game.level.spawn_for(0, 0)), game.level.world_cell(game.level.spawn_for(1, 0)))
	check(path.size() > 10, "cross-map route connected")
	await pause(2.2)
	p.position = Vector3(0, 0.05, 5)
	target.position = Vector3(0, 0.05, -5)
	p.rotation.y = 0
	p.aim_pitch = 0
	game.core.coop_switch(1, 4)
	game.lan.sync_stats()
	await pause(0.3)
	await get_tree().physics_frame
	p._update_weapon_pose()
	p.fire()
	game.lan.sync_stats()
	check(target.life == "dead", "real weapon ray kills opponent")
	check(int(game.lan.pvp_state.scores[0]) == 1, "kill scores exactly once")
	check(int(game.lan.fighters[victim].deaths) == 1, "death recorded")
	check(not game.core.pvp_hit(1, victim, 999, false).hit, "dead target cannot score twice")
	var old_generation := int(game.lan.fighters[victim].generation)
	check(await wait_until(func(): return int(game.lan.fighters[victim].generation) > old_generation, 8), "automatic five-second respawn")
	game.lan.sync_stats()
	check(target.hp == 100 and target.life == "alive", "respawn restores health")
	check(target.position.z < -40, "respawn returns to blue base")
	check(not game.core.pvp_hit(1, victim, 999, false).hit, "spawn immunity enforced")
	await pause(2.2)
	p.position = Vector3(0, 0.05, 5)
	target.position = Vector3(0, 0.05, -3)
	p.camera.rotation.x = 0
	p.trauma = 0
	game.lan.request("grenade", 1, 0, 0)
	check(game.lan.ordnance.items.size() == 1, "host throwable created")
	check(int(game.lan.fighters[1].grenades[1]) == 1, "grenade inventory consumed")
	game.lan.request("grenade", 0, 0, 0)
	check(game.lan.ordnance.items.size() == 1, "throw cooldown enforced")
	check(await wait_until(func(): return game.lan.ordnance.detonations >= 1, 5), "flash detonated")
	# A close, visible flash is also tested against the same authoritative exposure path.
	game.lan.ordnance._detonate({"kind": 1, "owner": 1, "pos": target.position + Vector3(0, 1.5, -1)})
	check(float(game.lan.fighters[victim].flash) > 0, "flash exposure applied")
	await pause(0.5)
	game.lan.request("grenade", 2, 0, 0)
	check(await wait_until(func():
		for item in game.lan.ordnance.items.values():
			if item.smoke: return true
		return false, 5), "smoke expands after fuse")
	await pause(1)
	var covered: bool = not game.lan.ordnance.exposed(Vector3(0, 1, 40), Vector3(0, 1, 30))
	check(covered, "spawn cover blocks explosion line of sight")
	game.lan.hit_player(1, victim, 999, false)
	check(int(game.lan.pvp_state.scores[0]) == 2, "second authoritative kill")
	await pause(0.5)
	# Complete through the score rule, then verify that clients receive the result.
	for n in 48:
		game.core.coop_tick(5.1)
		game.core.coop_tick(2.1)
		game.core.pvp_hit(1, victim, 999, false)
	game.lan.sync_stats()
	check(int(game.lan.pvp_state.winner) == 0, "50-kill victory")
	await pause(1)
	check(game.state == "pvp_finished", "host result screen")
	if "--pvp-photo" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		game.get_viewport().get_texture().get_image().save_png("res://tests/previews/25-pvp-result.png")
	game.lan.start_battle()
	check(game.lan.ordnance.items.is_empty(), "restart clears ordnance")
	check(await wait_until(func(): return game.lan.ready_peers.size() == required - 1), "restart clients ready")
	check(int(game.lan.pvp_state.scores[0]) == 0 and game.state == "playing", "restart resets score")
	await pause(2)

func _client() -> void:
	game.lan.join_room("127.0.0.1", "BLUE-CLIENT")
	if not await wait_until(func(): return game.state == "playing", 45):
		check(false, "joined battle")
		return
	first_epoch = game.lan.client_epoch
	check(game.is_pvp() and game.stage_index == 3, "mode and warehouse synchronized")
	check(game.level_number == 8 and game.player.weapon_index == 3, "initial full weapon loadout")
	check(await wait_until(func(): return game.lan.client_epoch > first_epoch, 90 if required == 10 else 45), "match restart synchronized")
	check(client_kill and client_dead, "score and death snapshots observed")
	check(client_respawn, "respawn generation observed")
	check(client_flash, "flash synchronized")
	check(client_smoke, "smoke synchronized")
	check(client_finished, "result screen synchronized")
	check(client_roof and client_pipe, "roof height and pipe positions synchronized")
	check(int(game.lan.pvp_state.scores[0]) == 0, "restart score cleared")
	game.lan.request("grenade", 0, game.player.rotation.y, 0)
	check(await wait_until(func(): return int(game.lan.fighters.get(game.lan.local_id(), {}).get("grenades", [2, 2, 1])[0]) == 1, 4), "client throw accepted by host")

func _process(_delta: float) -> void:
	if not game.is_pvp() or game.lan.host() or game.lan.client_epoch < 0: return
	var state: Dictionary = game.lan.pvp_state
	if int(state.get("scores", [0, 0])[0]) > 0: client_kill = true
	for f in game.lan.fighters.values():
		if float(f.respawn) > 0: client_dead = true
		if int(f.generation) > 1: client_respawn = true
		if float(f.flash) > 0: client_flash = true
	for item in game.lan.ordnance.items.values():
		if item.smoke: client_smoke = true
	if game.state == "pvp_finished": client_finished = true
	for p in game.lan.players.values():
		if p.network_position.y > 10: client_roof = true
		if absf(p.network_position.x - 28) < 0.5 and absf(p.network_position.z - 8) < 0.5: client_pipe = true
