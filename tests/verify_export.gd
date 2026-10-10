extends SceneTree

func _initialize() -> void:
	call_deferred("verify")

func verify() -> void:
	var pack := "res://dist/ASHFALL-LAN-Windows64/ASHFALL-LAN.pck" if "--lan-pack" in OS.get_cmdline_user_args() else "res://dist/ASHFALL-Windows64/ASHFALL.pck"
	assert(ProjectSettings.load_resource_pack(pack), "Exported PCK must mount")
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
	assert(game.player.WEAPONS.size() == 5 and game.level.stage == 0)
	game._change_stage(1)
	game._change_stage(2)
	await process_frame
	assert(game.stage_index == 2)
	print("PACK VERIFIED: compiled release scripts + all three sectors load")
	print("PACK VALIDATION COMPLETE (macOS host / Windows PCK; Windows DLL checked separately)")
	quit()
