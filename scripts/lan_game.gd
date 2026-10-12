extends RefCounted
## Scene/UI adapter only. ENet, discovery, wire validation and player rules live in Rust.
var game
var net: Node
var enabled := false
var players: Dictionary = {}
var stats: Dictionary = {}
var inputs: Dictionary = {}
var replicas: Dictionary = {}
var zones: Dictionary = {}
var network_pickups: Dictionary = {}
var next_id := 1
var epoch := 0
var client_epoch := -1
var snapshot_tick := 0
var last_tick := -1
var snapshot_timer := 0.0
var input_sequence := 0
var action_sequence := 0
var input_timer := 0.0
var nickname := "幸存者"
var room_name := "余烬小队"
var members: Array = []
var ready_peers: Dictionary = {}
var target_frame := -1
var target_ids := PackedInt64Array()
var target_positions: Array[Vector3] = []
var start_stage := 0
var mode := "coop"
var pvp_state: Dictionary = {}
var fighters: Dictionary = {}
var generations: Dictionary = {}
var ordnance
var bots
var rules_clock_ms := 0

func _init(owner) -> void:
	game = owner
	net = ClassDB.instantiate("LanSession")
	net.name = "LanSession"
	game.add_child(net)
	ordnance = preload("res://scripts/ordnance.gd").new(game)
	bots = preload("res://scripts/pvp_bots.gd").new(game)

func host() -> bool:
	return enabled and net.role() == "host"

func local_id() -> int:
	return int(net.local_id()) if enabled else 1

func refresh_members() -> void:
	var data = JSON.parse_string(net.members_json())
	if data is Array:
		members = data

func create_room(name: String, nick: String, port: int = 42042, battle_mode: String = "coop") -> void:
	var error: String = net.host_room(name, nick, port)
	if not error.is_empty():
		game.hud.toast(error, Color(1, 0.4, 0.2), 5)
		return
	enabled = true
	mode = battle_mode
	game.core.reset_run()
	if mode == "pvp":
		net.configure_pvp_room()
		game.core.pvp_configure()
		game.core.coop_register(1, nick)
		refresh_pvp()
	start_stage = 0
	nickname = nick
	room_name = name
	refresh_members()
	game.state = "lobby"
	game.hud.show_lan_lobby()

func join_room(address: String, nick: String, port: int = 42042) -> void:
	var error: String = net.join_room(address, nick, port)
	if not error.is_empty():
		game.hud.toast(error, Color(1, 0.4, 0.2), 5)
		return
	enabled = true
	start_stage = 0
	nickname = nick
	client_epoch = -1
	last_tick = -1
	game.state = "connecting"
	game.hud.show_lan_connecting(address)

func leave() -> void:
	net.leave()
	enabled = false
	players.clear()
	stats.clear()
	inputs.clear()
	replicas.clear()
	zones.clear()
	network_pickups.clear()
	mode = "coop"
	pvp_state.clear()
	fighters.clear()
	generations.clear()
	ordnance.clear()
	bots.clear()

func world_ready(local_player) -> void:
	target_frame = -1
	players.clear()
	replicas.clear()
	zones.clear()
	network_pickups.clear()
	generations.clear()
	ordnance.clear()
	bots.clear()
	players[local_id()] = local_player
	local_player.peer_id = local_id()
	local_player.player_name = nickname
	refresh_members()
	for member in members:
		var id := int(member.id)
		if host():
			game.core.coop_register(id, member.name)
			if id != local_id(): game.core.coop_loading(id)
		if id != local_id():
			spawn_player(id, member.name)
	if host():
		sync_stats()
	if game.is_pvp():
		for f in fighters.values():
			if f.get("is_bot", false): spawn_player(int(f.id), str(f.name))
		if host(): sync_stats()
		for id in players: place_pvp_player(id)

func spawn_player(id: int, name: String) -> void:
	if players.has(id):
		return
	var p = game.PlayerScript.new()
	p.game = game
	p.peer_id = id
	p.is_local = id == local_id()
	p.player_name = name
	p.position = game.level.safe_ground(game.level.player_spawn + Vector3((id % 3 - 1) * 2.0, 0, -3)) + Vector3.UP * 0.15
	game.world.add_child(p)
	players[id] = p
	if game.is_pvp(): place_pvp_player(id)

func start_battle() -> void:
	if not host():
		return
	refresh_members()
	if mode == "pvp":
		game.core.pvp_fill_bots()
		refresh_pvp()
		var counts := [0, 0]
		for f in fighters.values(): counts[int(f.team)] += 1
		if counts[0] == 0 or counts[0] != counts[1]:
			game.hud.toast("双方人数需相等；可勾选「缺位补机器人」以单人开局", Color(1, 0.6, 0.2), 4)
			return
		epoch += 1
		ready_peers.clear()
		game.start_pvp()
	else:
		epoch += 1
		ready_peers.clear()
		game.start_run(start_stage)

func set_start_stage(index: int) -> void:
	if not host() or game.state != "lobby" or mode == "pvp": return
	start_stage = clampi(index, 0, game.STAGE_NAMES.size() - 1)
	net.send_event("lobby_map", JSON.stringify({"stage": start_stage}))
	net.update_room(start_stage, 0, false)

func process(delta: float) -> void:
	for event in net.drain_events():
		var data = JSON.parse_string(event.data) if event.kind not in ["error", "disconnected"] else {}
		match event.kind:
			"joined":
				refresh_members()
				if data is Dictionary:
					room_name = str(data.get("name", room_name))
					mode = str(data.get("mode", "coop"))
				if client_epoch < 0:
					game.state = "lobby"
					game.hud.show_lan_lobby()
				request("ready", 1 if client_epoch >= 0 else 0)
			"peer_join":
				refresh_members()
				if host():
					game.core.coop_register(int(event.peer), str(data.name))
					if mode == "pvp":
						refresh_pvp()
						net.send_event("lobby_pvp", JSON.stringify(pvp_state))
					if game.state in ["playing", "team_wipe", "victory", "pvp_finished"]:
						game.core.coop_loading(int(event.peer))
						spawn_player(int(event.peer), data.name)
						game.hud.toast(data.name + " 加入小队", Color(0.3, 0.9, 0.8), 3)
				if game.state == "lobby":
					game.hud.show_lan_lobby()
			"peer_left":
				var id := int(event.peer)
				game.core.coop_remove(id)
				if players.has(id):
					players[id].queue_free()
					players.erase(id)
				inputs.erase(id)
				stats.erase(id)
				refresh_members()
				if host() and mode == "pvp":
					refresh_pvp()
					net.send_event("lobby_pvp", JSON.stringify(pvp_state))
				if game.state == "lobby": game.hud.show_lan_lobby()
			"roster":
				refresh_members()
				if game.state == "lobby": game.hud.show_lan_lobby()
			"input":
				if host() and data is Dictionary:
					var old: Dictionary = inputs.get(int(event.peer), {})
					if int(data.seq) > int(old.get("seq", -1)):
						data["received"] = Time.get_ticks_msec()
						inputs[int(event.peer)] = data
			"action":
				if host() and data is Dictionary:
					apply_action(int(event.peer), data)
			"snapshot":
				if enabled and not host() and data is Dictionary:
					apply_snapshot(data)
			"shot":
				if not host() and data is Dictionary:
					show_shot(data)
			"lobby_map":
				if not host() and data is Dictionary and game.state in ["lobby", "connecting"]:
					start_stage = clampi(int(data.get("stage", 0)), 0, game.STAGE_NAMES.size() - 1)
					if game.state == "lobby": game.hud.show_lan_lobby()
			"hurt":
				if not host() and data is Dictionary and int(data.id) == local_id():
					game.hud.hurt = 1
					game.player.trauma = 1
					game.sound.play("hurt", -4)
			"lobby_pvp":
				if not host() and data is Dictionary:
					mode = "pvp"
					apply_pvp(data)
					if game.state == "lobby": game.hud.show_lan_lobby()
			"detonate":
				if not host() and data is Dictionary: ordnance.show_detonation(data)
			"assault_break":
				if not host() and data is Dictionary and game.level.has_method("apply_brushes"):
					game.level.apply_brushes([int(data.id)])
			"pvp_kill":
				if not host() and data is Dictionary: game.hud.add_pvp_kill(data)
			"room_closed", "disconnected", "error":
				var text: String = event.data if event.kind in ["error", "disconnected"] else "房主已关闭房间"
				leave()
				game.return_to_menu()
				game.hud.toast(text, Color(1, 0.5, 0.2), 6)
	if not enabled:
		return
	if host():
		if game.state == "playing":
			var rules_delta := delta
			if mode == "pvp":
				var now := Time.get_ticks_msec()
				if rules_clock_ms > 0: rules_delta = float(now - rules_clock_ms) / 1000.0
				rules_clock_ms = now
			game.core.coop_tick(rules_delta)
			if mode == "pvp":
				refresh_pvp()
				for id in players:
					var f: Dictionary = fighters.get(id, {})
					if not f.is_empty() and int(generations.get(id, -1)) != int(f.generation): place_pvp_player(id)
				bots.process(delta)
				ordnance.process(rules_delta)
				if int(pvp_state.get("winner", -1)) != -1:
					game.state = "pvp_finished"
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
					game.hud.show_pvp_result()
			else: update_revives(delta)
			if mode != "pvp" and game.core.coop_wipe():
				sync_stats()
				game.state = "team_wipe"
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				game.hud.show_death()
		if game.state in ["playing", "team_wipe", "victory", "pvp_finished"]:
			snapshot_timer -= delta
			if snapshot_timer <= 0:
				snapshot_timer = 0.05
				sync_stats()
				net.send_snapshot(JSON.stringify(make_snapshot()), 0)
		net.update_room(3 if mode == "pvp" else start_stage if game.state == "lobby" else game.stage_index, 0 if game.state == "lobby" else game.wave, game.state == "playing")
	else:
		if mode == "pvp": ordnance.process_visuals(delta)
		for id in players:
			if id != local_id():
				var p = players[id]
				p.position = p.position.lerp(p.network_position, minf(delta * 16, 1))
				p.rotation.y = lerp_angle(p.rotation.y, p.network_yaw, minf(delta * 16, 1))
		for enemy in replicas.values():
			enemy.position = enemy.position.lerp(enemy.network_position, minf(delta * 16, 1))
			enemy.rotation.y = lerp_angle(enemy.rotation.y, enemy.network_yaw, minf(delta * 16, 1))
		for h in zones.values():
			h.warning = maxf(h.warning - delta, 0)
			if h.warning == 0: h.life -= delta
			h.material.set_shader_parameter("progress", 1.0 - h.warning / maxf(h.warning_total, 0.01))
			h.material.set_shader_parameter("phase", 1.0 if h.warning == 0 else 0.0)
			h.material.set_shader_parameter("fade", clampf(1 + h.life / 0.55, 0, 1))

func sync_stats() -> void:
	if mode == "pvp": refresh_pvp()
	var list = JSON.parse_string(game.core.coop_players_json())
	if not list is Array:
		return
	stats.clear()
	for s in list:
		var id := int(s.id)
		stats[id] = s
		if players.has(id): players[id].apply_coop_stats(s)

func get_input(id: int) -> Dictionary:
	if mode == "pvp" and fighters.get(id, {}).get("is_bot", false): return bots.input_for(id)
	var data: Dictionary = inputs.get(id, {})
	if Time.get_ticks_msec() - int(data.get("received", 0)) > 400:
		return {"x": 0.0, "z": 0.0, "yaw": players[id].rotation.y if players.has(id) else 0.0, "pitch": 0.0, "buttons": 0}
	return data

func send_input(delta: float, x: float, z: float, yaw: float, pitch: float, buttons: int) -> void:
	input_timer -= delta
	if input_timer <= 0:
		input_timer = 1.0 / 30.0
		input_sequence += 1
		net.send_input(x, z, yaw, pitch, buttons, input_sequence)

func request(kind: String, arg: int = 0, yaw: float = 0.0, pitch: float = 0.0) -> void:
	action_sequence += 1
	if host():
		apply_action(local_id(), {"kind": kind, "arg": arg, "seq": action_sequence, "yaw": yaw, "pitch": pitch})
	else:
		net.send_action(kind, arg, action_sequence, yaw, pitch)

func apply_action(id: int, action: Dictionary) -> void:
	if action.kind == "team":
		if mode == "pvp" and game.state == "lobby" and game.core.pvp_team(id, int(action.arg)):
			refresh_pvp()
			net.send_event("lobby_pvp", JSON.stringify(pvp_state))
			game.hud.show_lan_lobby()
		return
	if action.kind == "ready":
		if game.state == "lobby":
			net.send_event("lobby_map", JSON.stringify({"stage": start_stage}))
			if mode == "pvp": net.send_event("lobby_pvp", JSON.stringify(pvp_state))
		if int(action.arg) == 1:
			ready_peers[id] = true
			game.core.coop_activate(id)
			sync_stats()
		if game.state in ["playing", "team_wipe", "victory", "pvp_finished"]:
			net.send_snapshot(JSON.stringify(make_snapshot()), id)
		return
	if action.kind == "restart":
		if id == local_id(): start_battle()
		return
	if not players.has(id) or game.state != "playing":
		return
	var p = players[id]
	match action.kind:
		"grenade":
			var grenade_arg := int(action.arg)
			var kind := grenade_arg % 3
			if mode == "pvp" and grenade_arg >= 0 and grenade_arg < 6 and game.core.pvp_throw(id, kind, int(action.seq)):
				ordnance.throw_grenade(p, kind, float(action.yaw), float(action.pitch), grenade_arg >= 3)
		"fire":
			var saved_sway: Vector2 = p.scope_sway
			p.scope_sway = Vector2.ZERO
			p.rotation.y = action.yaw
			p.camera.rotation.x = clampf(action.pitch, -1.5, 1.5)
			p.aim_pitch = p.camera.rotation.x + p.recoil
			p._update_weapon_pose()
			p.fire(int(action.seq))
			p.scope_sway = saved_sway
		"reload":
			game.core.coop_reload(id)
		"switch":
			game.core.coop_switch(id, int(action.arg))
		"interact":
			game.interact_for_player(p)
		"upgrade":
			game.core.coop_upgrade(id, int(action.arg))
	sync_stats()

func update_revives(delta: float) -> void:
	for actor_id in players:
		var actor = players[actor_id]
		var held: bool = Input.is_action_pressed("interact") and not game.hud.menu.visible if actor_id == local_id() else (int(get_input(actor_id).get("buttons", 0)) & 16) != 0
		for target_id in players:
			var target = players[target_id]
			if target.life == "downed":
				game.core.coop_revive(actor_id, target_id, actor.position.distance_to(target.position), held, delta)

func active_players() -> Array:
	var result: Array = []
	for p in players.values():
		if is_instance_valid(p) and not p.is_queued_for_deletion() and p.life == "alive": result.append(p)
	return result

func target_for_enemy(position: Vector3):
	var frame := Engine.get_physics_frames()
	if frame != target_frame:
		target_frame = frame
		target_ids.clear()
		target_positions.clear()
		for id in players:
			target_ids.append(id)
			target_positions.append(players[id].position)
	return players.get(game.core.coop_target(target_ids, target_positions, position), null)

func register_enemy(enemy) -> void:
	enemy.net_id = next_id
	next_id += 1

func make_snapshot() -> Dictionary:
	snapshot_tick += 1
	var pawn_states: Array = []
	for id in players:
		var p = players[id]
		pawn_states.append({"id": id, "name": p.player_name, "pos": vec(p.position), "yaw": p.rotation.y, "pitch": p.aim_pitch, "vel": vec(p.velocity), "crouch": p.crouching, "stats": stats.get(id, {})})
	var enemies: Array = []
	for enemy in game.get_tree().get_nodes_in_group("zombies"):
		if not enemy.dead and not enemy.is_queued_for_deletion():
			enemies.append({"id": enemy.net_id, "kind": enemy.kind, "variant": enemy.variant, "pos": vec(enemy.position), "yaw": enemy.rotation.y, "hp": enemy.hp, "max_hp": enemy.max_hp, "enraged": enemy.enraged})
	var hazards: Array = []
	for h in game.hazards:
		hazards.append({"id": h.nid, "pos": vec(h.node.position), "radius": h.radius, "kind": h.kind, "warning": h.warning, "total": h.warning_total, "life": h.life})
	var pickups: Array = []
	for item in game.pickups: pickups.append({"id": item.nid, "pos": vec(item.node.position), "kind": item.kind})
	var valves: Array = []
	for terminal in game.level.terminals: valves.append(terminal.activated)
	var broken_brushes: Array = game.level.snapshot_brushes() if game.level.has_method("snapshot_brushes") else []
	return {"epoch": epoch, "tick": snapshot_tick, "mode": mode, "pvp": pvp_state, "battle": game.battle.snapshot(), "ordnance": ordnance.snapshot(), "assault_broken": broken_brushes, "start_stage": start_stage, "stage": game.stage_index, "wave": game.wave, "state": game.state, "time": game.survival_time, "spawn_left": game.spawn_left, "alive": game.alive, "next_wave": game.next_wave, "level": game.level_number, "xp": game.xp, "xp_needed": game.xp_needed, "kills": game.kills, "headshots": game.headshots, "objective": game.objective_count, "valves": valves, "players": pawn_states, "enemies": enemies, "hazards": hazards, "pickups": pickups}

func apply_snapshot(s: Dictionary) -> void:
	if int(s.tick) <= last_tick and int(s.epoch) == client_epoch: return
	last_tick = int(s.tick)
	mode = str(s.get("mode", "coop"))
	if mode == "pvp": apply_pvp(s.get("pvp", {}))
	start_stage = clampi(int(s.get("start_stage", 0)), 0, game.STAGE_NAMES.size() - 1)
	var rebuild: bool = client_epoch != int(s.epoch) or game.stage_index != int(s.stage)
	if rebuild:
		client_epoch = int(s.epoch)
		game.stage_index = int(s.stage)
		game._build_run()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		game.hud.hide_overlay()
	if game.level.has_method("apply_brushes"): game.level.apply_brushes(s.get("assault_broken", []))
	game.wave = int(s.wave)
	game.survival_time = s.time
	game.spawn_left = int(s.spawn_left)
	game.alive = int(s.alive)
	game.next_wave = s.next_wave
	game.level_number = int(s.level)
	game.xp = int(s.xp)
	game.xp_needed = int(s.xp_needed)
	game.kills = int(s.kills)
	game.headshots = int(s.headshots)
	game.objective_count = int(s.objective)
	for i in game.level.terminals.size():
		if i < s.valves.size() and s.valves[i] and not game.level.terminals[i].activated: game.level.activate_terminal(i)
	var present: Dictionary = {}
	for data in s.players:
		var id := int(data.id)
		present[id] = true
		if not players.has(id): spawn_player(id, data.name)
		var p = players[id]
		var respawned: bool = mode == "pvp" and int(generations.get(id, -1)) != int(fighters.get(id, {}).get("generation", 0))
		if respawned: place_pvp_player(id)
		p.network_position = unvec(data.pos)
		p.network_yaw = data.yaw
		if id != local_id(): p.aim_pitch = float(data.pitch)
		if id != local_id(): p.set_crouching(bool(data.get("crouch", false)))
		p.velocity = unvec(data.vel)
		stats[id] = data.stats
		p.apply_coop_stats(data.stats)
		if id == local_id():
			if rebuild or respawned or p.position.distance_to(p.network_position) > 1.5: p.position = p.network_position
			else: p.position = p.position.lerp(p.network_position, 0.18)
	for id in players.keys():
		if not present.has(id): players[id].queue_free(); players.erase(id)
	present.clear()
	game.boss = null
	for data in s.enemies:
		var id := int(data.id)
		present[id] = true
		if not replicas.has(id):
			var enemy = game.ZombieScript.new()
			enemy.game = game
			enemy.kind = int(data.kind)
			enemy.forced_variant = int(data.variant)
			enemy.network_proxy = true
			enemy.net_id = id
			enemy.position = unvec(data.pos)
			game.world.add_child(enemy)
			replicas[id] = enemy
		var enemy = replicas[id]
		enemy.network_position = unvec(data.pos)
		enemy.network_yaw = data.yaw
		enemy.hp = data.hp
		enemy.max_hp = data.max_hp
		enemy.enraged = data.enraged
		if enemy.kind == 4: game.boss = enemy
	for id in replicas.keys():
		if not present.has(id):
			var enemy = replicas[id]
			game.fx.retain_corpse(enemy.model, enemy.animation, enemy.position)
			enemy.queue_free()
			replicas.erase(id)
	present.clear()
	for data in s.hazards:
		var id := int(data.id)
		present[id] = true
		if not zones.has(id):
			game.create_hazard(unvec(data.pos), data.radius, data.kind, maxf(data.total, 0.1))
			zones[id] = game.hazards.back()
		var h: Dictionary = zones[id]
		h.warning = data.warning
		h.warning_total = data.total
		h.life = data.life
	for id in zones.keys():
		if not present.has(id):
			var h: Dictionary = zones[id]
			h.node.queue_free()
			game.hazards.erase(h)
			zones.erase(id)
	present.clear()
	for data in s.pickups:
		var id := int(data.id)
		present[id] = true
		if not network_pickups.has(id):
			game._drop_pickup(unvec(data.pos), data.kind)
			network_pickups[id] = game.pickups.back()
	for id in network_pickups.keys():
		if not present.has(id):
			var item: Dictionary = network_pickups[id]
			item.node.queue_free()
			game.pickups.erase(item)
			network_pickups.erase(id)
	var old_state: String = game.state
	game.battle.apply_snapshot(s.get("battle", {}))
	if mode == "pvp": ordnance.apply_snapshot(s.get("ordnance", []))
	game.state = s.state
	if game.state != old_state:
		if game.state == "team_wipe": game.hud.show_death(); Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif game.state == "victory": game.hud.show_victory(); Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif game.state == "pvp_finished": game.hud.show_pvp_result(); Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif game.state == "playing": game.hud.hide_overlay(); Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if rebuild: request("ready", 1)

func shot_event(p, traces: Array, head: bool, killed: bool, hit: bool, impacts: Array = []) -> void:
	var data := {"owner": p.peer_id, "weapon": p.weapon_index, "pos": vec(p.muzzle.global_position), "traces": traces, "impacts": impacts, "head": head, "killed": killed, "hit": hit}
	net.send_event("shot", JSON.stringify(data))

func show_shot(data: Dictionary) -> void:
	for impact in data.get("impacts", []): game.battle.show_impact(impact)
	if int(data.owner) == local_id():
		if data.head or data.killed or not data.traces.is_empty():
			# traces include the authoritative per-shot hit flag as the final element.
			if data.get("hit", false) or data.head or data.killed:
				game.hud.confirm_hit(data.head, data.killed)
				game.sound.play("headshot" if data.head else "hit", -8)
		return
	var start := unvec(data.pos)
	if players.has(int(data.owner)):
		var p = players[int(data.owner)]
		var weapon := int(data.weapon)
		if p.weapon_index != weapon:
			p.weapon_index = weapon
			p._build_weapon()
		p.play_gun_feedback()
		start = p.muzzle.global_position
	else:
		game.sound.positional(game.player.WEAPONS[int(data.weapon)].sound, unvec(data.pos), -12)
	var color := Color(0.15, 0.85, 1) if int(data.weapon) == 4 else Color(1, 0.64, 0.24)
	for line in data.traces: game.fx.tracer(start, unvec(line), color, int(data.weapon) == 4)

static func vec(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]

static func unvec(v: Array) -> Vector3:
	return Vector3(v[0], v[1], v[2])

func refresh_pvp() -> void:
	var data = JSON.parse_string(game.core.pvp_json())
	if data is Dictionary: apply_pvp(data)
	if host() and game.state in ["playing", "pvp_finished"]:
		for id in players.keys():
			if id >= 4000000000 and not fighters.has(id):
				players[id].queue_free()
				players.erase(id)
				bots.brains.erase(id)
		for f in fighters.values():
			if f.get("is_bot", false) and not players.has(int(f.id)): spawn_player(int(f.id), str(f.name))

func set_fill_bots(value: bool) -> void:
	if not host() or game.state != "lobby": return
	game.core.pvp_set_fill_bots(value)
	refresh_pvp()
	net.send_event("lobby_pvp", JSON.stringify(pvp_state))

func apply_pvp(data: Dictionary) -> void:
	pvp_state = data
	fighters.clear()
	for key in data.get("fighters", {}):
		fighters[int(key)] = data.fighters[key]
	for id in players:
		players[id].set_team(int(fighters.get(id, {}).get("team", 0)))

func place_pvp_player(id: int) -> void:
	if not players.has(id) or not fighters.has(id): return
	var f: Dictionary = fighters[id]
	var ids: Array = []
	for key in fighters:
		if int(fighters[key].team) == int(f.team): ids.append(key)
	ids.sort()
	var p = players[id]
	p.position = game.level.spawn_for(int(f.team), ids.find(id))
	p.network_position = p.position
	p.velocity = Vector3.ZERO
	p.rotation.y = game.level.spawn_yaw(int(f.team), ids.find(id)) if game.level.has_method("spawn_yaw") else 0 if int(f.team) == 0 else PI
	p.network_yaw = p.rotation.y
	p.aim_pitch = 0
	p.crouching = false
	p.set_crouching(false)
	p.camera.position = Vector3(0, 1.65, 0)
	p.camera.rotation = Vector3.ZERO
	p.recoil = 0
	p.set_team(int(f.team))
	generations[id] = int(f.generation)

func hit_player(attacker: int, victim: int, damage: float, head: bool) -> Dictionary:
	var result: Dictionary = game.core.pvp_hit(attacker, victim, damage, head)
	if not result.hit: return result
	if players.has(victim) and players[victim].is_local:
		game.hud.hurt = 1
		players[victim].trauma = 1
		game.sound.play("hurt", -4)
	net.send_event("hurt", JSON.stringify({"id": victim}))
	if result.killed:
		var data := {"attacker": fighters.get(attacker, {}).get("name", "?"), "victim": fighters.get(victim, {}).get("name", "?"), "head": head}
		game.hud.add_pvp_kill(data)
		net.send_event("pvp_kill", JSON.stringify(data))
	sync_stats()
	return result
