extends SceneTree

func _initialize() -> void:
	call_deferred("verify")

func verify() -> void:
	var pack := "res://dist/ASHFALL-LAN-Windows64/ASHFALL-LAN.pck" if "--lan-pack" in OS.get_cmdline_user_args() else "res://dist/ASHFALL-Windows64/ASHFALL.pck"
	assert(ProjectSettings.load_resource_pack(pack), "Exported PCK must mount")
	assert(not FileAccess.get_file_as_bytes("res://project.binary").hex_encode().contains("/etc/ssl/cert.pem".to_utf8_buffer().hex_encode()), "Exported settings must not retain the local certificate workaround")
	assert(ClassDB.class_exists("LanSession"), "Rust LAN class must register")
	print("PACK VERIFIED: mounted Windows release resources")
	var extension := FileAccess.get_file_as_string("res://native/ashfall.gdextension")
	print("PACKED EXTENSION CONFIG:\n", extension)
	assert("ashfall_core.dll" in extension)
	var models := ["res://assets/models/city_zombie.glb", "res://assets/models/horror_mutant.glb"]
	if "--lan-pack" in OS.get_cmdline_user_args(): models.append("res://assets/models/survivor_soldier.glb")
	for path in models:
		var scene: PackedScene = load(path)
		assert(scene != null, "Packed character scene must load")
		var model := scene.instantiate()
		root.add_child(model)
		var players := model.find_children("*", "AnimationPlayer", true, false)
		assert(not players.is_empty())
		var player: AnimationPlayer = players[0]
		assert(player.has_animation("walk") and player.has_animation("run"))
		assert(player.has_animation("idle" if "survivor_soldier" in path else "attack"))
		print("PACK VERIFIED: textured rig + animations / ", path)
		model.queue_free()
	var main: PackedScene = load("res://main.tscn")
	assert(main != null)
	var game := main.instantiate()
	root.add_child(game)
	game.start_run()
	game.state = "testing"
	await physics_frame
	await physics_frame
	assert(game.player.WEAPONS.size() == 6 and game.level.stage == 0)
	game._change_stage(1)
	game._change_stage(2)
	await process_frame
	assert(game.stage_index == 2)
	print("PACK VERIFIED: compiled release scripts + all three sectors load")
	if "--lan-pack" in OS.get_cmdline_user_args():
		game.test_mode = true
		game.lan.create_room("导出射击检查", "房主", 42672)
		assert(game.hud.menu.find_child("LobbyMapChoice", true, false).item_count == 3)
		game.lan.set_start_stage(1)
		game.lan.start_battle()
		assert(game.stage_index == 1 and game.wave == 4)
		game.state = "testing"
		game.set_process(false)
		game.lan.spawn_player(2, "队友")
		var pawn = game.lan.players[2]
		pawn.aim_pitch = -0.2
		pawn._process(0)
		assert(pawn.rig.visible and pawn.arm_chains.size() == 2)
		assert(absf(pawn.camera.rotation.x + 0.2) < 0.001)
		game.lan.show_shot({"owner": 2, "weapon": 4, "pos": [0, 5, 0], "traces": [[0, 5, -10]], "hit": false, "head": false, "killed": false})
		pawn._process(0.1)
		assert(pawn.weapon_index == 4 and pawn.flash.visible and pawn.gun_kick > 0)
		assert(game.fx.items.size() >= 2)
		print("PACK VERIFIED: teammate weapon, grip pose, pitch, slow-frame flash and tracer")
		game.fx.tracer(Vector3.ZERO, Vector3(0, 0, -110))
		assert(game.fx.items.back().node.scale.z < 1.201)
		print("PACK VERIFIED: selected starting map and short ordinary bullet tracer")
		game.lan.leave()
		game.return_to_menu()
		game.lan.create_room("导出 PvP 检查", "房主", 42672, "pvp")
		assert(game.hud.menu.find_child("LobbyFillBots", true, false).button_pressed)
		game.lan.start_battle()
		assert(game.state == "playing" and game.stage_index == 3)
		assert(game.lan.fighters.size() == 2 and game.battle.props.size() == 20)
		assert(game.level.pipe_routes.size() == 4 and game.level.roof_routes.size() == 2)
		game.core.coop_switch(1, 5)
		game.lan.sync_stats()
		assert(game.player.weapon_index == 5 and game.player.magazines.size() == 6)
		game.battle.make_mark(Vector3(0, 0, 20), Vector3.UP, 3, 4, 100)
		assert(game.battle.marks.size() == 1)
		print("PACK VERIFIED: warehouse, optional bot, scoped sniper, physical props and impact shader")
		game.return_to_menu()
	print("PACK VALIDATION COMPLETE (macOS host / Windows PCK; Windows DLL checked separately)")
	quit()
