extends Node

var game
var elapsed := 0.0
var duration := 14.0
var port := 42442
var is_host := false
var last_report := -1
var battle_started := false
var joined_battle := false
var bot_sequence := 100000
var shot_timer := 0.0
var expect_reject := false
var discovery_seen := false
var scenario := false
var battle_at := 0.0
var downed_test := false
var revive_test := false
var upgrade_test := false
var stage_test := false
var wipe_test := false
var restart_test := false
var scenario_target := 0
var upgrade_requested := false
var saw_downed := false
var saw_revived := false
var saw_upgrade := false
var saw_stage := false
var saw_wipe := false
var saw_restart := false
var scenario_report := -1
var downed_at := 0.0
var photographed := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	is_host = "--lan-host" in args
	expect_reject = "--expect-full" in args
	scenario = "--scenario" in args
	for arg in args:
		if arg.begins_with("--duration="): duration = float(arg.trim_prefix("--duration="))
		if arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
	game.test_mode = true
	game.lan.net.set_discovery_port(port + 1)
	game.lan.net.start_discovery()
	if is_host:
		game.lan.create_room("LAN 自动测试", "房主", port)
	else:
		game.lan.join_room("127.0.0.1", "队友-%d" % OS.get_process_id(), port)

func _process(delta: float) -> void:
	elapsed += delta
	var rooms = JSON.parse_string(game.lan.net.rooms_json())
	if rooms is Array and not rooms.is_empty(): discovery_seen = true
	if is_host and not battle_started and game.lan.members.size() >= 2:
		battle_started = true
		battle_at = elapsed
		game.lan.start_battle()
		print("LAN_TEST BATTLE_STARTED members=", game.lan.members.size())
	if scenario and game.lan.enabled:
		_run_scenario(delta)
	if not is_host and game.state == "playing" and game.lan.players.size() >= 2:
		joined_battle = true
		bot_sequence += 1
		game.lan.net.send_input(0.25 if elapsed < 3.0 else 0.0, 0.0, 0.0, 0.0, 0, bot_sequence)
		shot_timer -= delta
		if shot_timer <= 0:
			shot_timer = 0.35
			game.lan.request("fire", 0, 0, 0)
	var second := int(elapsed)
	if second % 2 == 0 and second != last_report:
		last_report = second
		print("LAN_TEST STATE ", JSON.stringify({"host": is_host, "role": game.lan.net.role(), "enabled": game.lan.enabled, "tick": game.lan.last_tick, "epoch": game.lan.client_epoch, "state": game.state, "members": game.lan.members.size(), "players": game.lan.players.size(), "enemies": game.alive, "stage": game.stage_index, "wave": game.wave, "discovery": discovery_seen}))
	if elapsed > duration:
		var passed: bool = battle_started if is_host else (game.lan.net.role() == "offline" if expect_reject else joined_battle)
		if scenario:
			passed = passed and (revive_test and upgrade_test and stage_test and wipe_test and restart_test if is_host else saw_downed and saw_revived and saw_upgrade and saw_stage and saw_wipe and saw_restart)
		print("LAN_TEST RESULT ", "PASS" if passed else "FAIL", " host=", is_host, " discovery=", discovery_seen)
		game.lan.leave()
		game.get_tree().quit(0 if passed else 1)
	if "--lan-photo" in OS.get_cmdline_user_args() and game.state == "playing" and game.player.life == "alive" and game.survival_time > 2 and elapsed > 5 and not photographed:
		photographed = true
		call_deferred("take_photo")

func take_photo() -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tests/previews/10-lan-host-squad.png" if is_host else "res://tests/previews/11-lan-client-squad.png")

func _run_scenario(_delta: float) -> void:
	if is_host and battle_started:
		var t := elapsed - battle_at
		for id in game.lan.players: game.core.coop_heal(id, 200)
		if t > 3 and not downed_test and game.lan.players.size() > 1:
			for id in game.lan.players:
				if id != 1: scenario_target = id; break
			if game.core.coop_damage(scenario_target, 10000):
				game.lan.sync_stats()
				game.player.position = game.lan.players[scenario_target].position + Vector3(1.5, 0, 0)
				Input.action_press("interact")
				downed_test = game.lan.players[scenario_target].life == "downed"
				downed_at = t
				print("LAN_SCENARIO HOST_DOWNED ", downed_test)
		if downed_test and not revive_test and t > downed_at + 2.9 and game.lan.players[scenario_target].life == "alive":
			revive_test = true
			Input.action_release("interact")
			print("LAN_SCENARIO HOST_REVIVED ", revive_test)
			# Earn real kill rewards until team level 2.
			while game.level_number < 2:
				var enemy = game._spawn_add(game.level.spawn_points[0], 0)
				enemy.take_hit(10000, enemy.position + Vector3.UP * 1.7, Vector3.FORWARD, 1)
		if t > 8 and not upgrade_test:
			upgrade_test = game.lan.players[scenario_target].max_hp > game.player.max_hp
			if upgrade_test: print("LAN_SCENARIO PERSONAL_UPGRADE PASS")
		if t > 12 and revive_test and upgrade_test and not stage_test:
			for _i in 3:
				for enemy in game.get_tree().get_nodes_in_group("zombies"):
					if not enemy.dead: enemy.take_hit(100000, enemy.position + Vector3.UP * 3, Vector3.FORWARD, 1)
				game._begin_wave()
			stage_test = game.stage_index == 1 and game.wave == 4
			print("LAN_SCENARIO STAGE_CHANGED ", stage_test)
		if t > 18 and not wipe_test:
			for id in game.lan.players: game.core.coop_damage(id, 100000)
			game.lan.sync_stats()
			wipe_test = game.core.coop_wipe()
			print("LAN_SCENARIO TEAM_WIPE ", wipe_test)
		if t > 22 and wipe_test and not restart_test:
			game.lan.start_battle()
			restart_test = game.stage_index == 0 and game.wave == 1 and game.lan.players.size() == 2
			print("LAN_SCENARIO RESTART ", restart_test)
	elif not is_host and joined_battle:
		if game.player.life == "downed" and game.state == "playing" and not saw_stage: saw_downed = true
		if saw_downed and game.player.life == "alive" and not saw_stage and not saw_wipe: saw_revived = true
		if game.player.upgrade_points > 0 and not upgrade_requested:
			game.lan.request("upgrade", 1)
			upgrade_requested = true
		if game.player.max_hp >= 120: saw_upgrade = true
		if game.stage_index == 1 and game.wave == 4: saw_stage = true
		if game.state == "team_wipe": saw_wipe = true
		if saw_stage and game.stage_index == 0 and game.wave == 1: saw_restart = true
		if int(elapsed) % 4 == 0 and scenario_report != int(elapsed):
			scenario_report = int(elapsed)
			print("LAN_SCENARIO CLIENT ", JSON.stringify({"downed": saw_downed,"revived": saw_revived,"upgrade": saw_upgrade,"stage": saw_stage,"wipe": saw_wipe,"restart": saw_restart}))
