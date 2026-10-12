extends SceneTree

var failed := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition: print("PASS COMBAT_VISUAL: ", message)
	else:
		failed += 1
		push_error(message)

func frame_image() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func changed_pixels(a: Image, b: Image) -> int:
	var count := 0
	for x in a.get_width():
		for y in a.get_height():
			var difference := a.get_pixel(x, y) - b.get_pixel(x, y)
			if maxf(absf(difference.r), maxf(absf(difference.g), absf(difference.b))) > 0.08: count += 1
	return count

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.test_mode = true
	game.lan.create_room("射击表现回归", "房主", 42662)
	game.lan.start_battle()
	game.state = "testing"
	game.set_process(false)
	game.player.set_physics_process(false)
	game.hud.root.visible = false
	game.lan.spawn_player(2, "队友")
	var pawn = game.lan.players[2]
	pawn.set_physics_process(false)
	pawn.position = Vector3(0, 4.05, 34)
	pawn.rotation.y = PI
	pawn.aim_pitch = -0.2
	pawn._update_weapon_pose()
	var skeleton = pawn.avatar.find_child("Skeleton3D", true, false)
	check(pawn.arm_chains.size() == 2, "both weapon grip arm chains found")
	check(pawn.rig.visible and pawn.rig.is_visible_in_tree(), "remote weapon visible")
	check(not pawn.flashlight.visible, "remote flashlight starts disabled")
	check(absf(pawn.camera.rotation.x + 0.2) < 0.001, "remote aiming pitch applied")
	pawn.play_gun_feedback()
	pawn._process(0.001)
	check(pawn.flash.visible and pawn.flash_light.visible and pawn.gun_kick > 0, "remote muzzle flash and recoil")
	pawn._process(0.2)
	check(not pawn.flash.visible and not pawn.flash_light.visible, "flash expires on render clock")
	pawn.play_gun_feedback()
	pawn._process(0.1)
	check(pawn.flash.visible and pawn.gun_kick > 0, "slow frame still displays shot feedback")
	pawn._process(0.1)
	check(not pawn.flash.visible, "slow-frame flash expires next frame")
	pawn.life = "downed"
	pawn._process(0)
	check(not pawn.rig.visible, "downed teammate weapon hidden")
	pawn.life = "alive"
	pawn._process(0)
	check(pawn.rig.visible, "revived teammate weapon visible")
	for index in game.player.WEAPONS.size():
		pawn.weapon_index = index
		pawn._build_weapon()
		pawn._process(0)
		check(pawn.muzzle.is_inside_tree() and pawn.rig.is_visible_in_tree(), "remote weapon variant %d" % index)
	pawn.weapon_index = 3
	pawn._build_weapon()
	pawn._process(0)
	await process_frame
	for chain in pawn.arm_chains:
		var hand: Vector3 = skeleton.to_global(skeleton.get_bone_global_pose(chain.hand).origin)
		check(hand.distance_to(pawn.rig.global_position) < 0.65, "hand follows weapon grip")
	var count: int = game.fx.items.size()
	game.lan.show_shot({"owner": 2, "weapon": 4, "pos": [0, 5.3, 34], "traces": [[0, 5.3, 39]], "head": false, "killed": false, "hit": false})
	check(pawn.weapon_index == 4 and game.fx.items.size() >= count + 2, "shot event updates weapon and creates casing/tracer")
	var tracer: Dictionary = game.fx.items.back()
	check(tracer.node.material_override.albedo_color.b > 0.8, "railgun tracer keeps cyan color")
	game.player.predict_tracers()
	check(game.fx.items.size() > count + 2, "local client cosmetic tracer prediction")
	game.fx.tracer(Vector3(0, 5, 0), Vector3(0, 5, -110))
	var short_tracer: Dictionary = game.fx.items.back()
	check(short_tracer.node.scale.z <= 1.201, "ordinary 110 m shot renders only a short tracer")
	game.fx._process(0.001)
	var start_position: Vector3 = short_tracer.node.position
	game.fx._process(0.01)
	check(short_tracer.node.position.distance_to(start_position) > 1 and short_tracer.node.scale.z <= 1.201, "short tracer moves along its hit path")
	# Every same-height deck cell must have only one physical top surface.
	for stage in 3:
		game._change_stage(stage)
		var occupied: Dictionary = {}
		var overlap := false
		for region in game.level.deck_regions:
			for x in range(region.rect.position.x, region.rect.end.x):
				for y in range(region.rect.position.y, region.rect.end.y):
					var key := Vector3i(x, int(region.height * 100), y)
					if occupied.has(key): overlap = true
					occupied[key] = true
		check(not overlap, "no coplanar deck overlap in stage %d" % stage)
	check(Forge.material(Color(0.025, 0.13, 0.19), 0, 0, 0.48).metallic == 0, "water is dielectric")
	check(Forge.material(Color.GRAY, 0.5, 0, 0.8) != Forge.material(Color.GRAY, 0.5, 0, 0.4), "roughness variants use separate cached materials")
	# Stage changes reposition the party; restore the display teammate.
	game._change_stage(0)
	game.lan.spawn_player(2, "队友")
	pawn = game.lan.players[2]
	pawn.set_physics_process(false)
	pawn.position = Vector3(0, 4.05, 34)
	pawn.rotation.y = PI
	pawn.weapon_index = 3
	pawn._build_weapon()
	pawn._process(0)
	game.player.rig.visible = false
	game.player.camera.global_position = Vector3(2.5, 5.65, 38)
	game.player.camera.look_at(pawn.position + Vector3.UP * 1.3)
	if DisplayServer.get_name() != "headless":
		pawn.set_process(false)
		pawn.avatar_animation.pause()
		var visible: Image = await frame_image()
		visible.save_png("res://tests/previews/13-teammate-weapon.png")
		pawn.rig.visible = false
		var hidden: Image = await frame_image()
		check(changed_pixels(visible, hidden) > 20, "remote weapon changes actual rendered pixels")
		pawn.rig.visible = true
		pawn.play_gun_feedback()
		pawn._process(0)
		game.fx.tracer(pawn.muzzle.global_position, pawn.muzzle.global_position - pawn.camera.global_basis.z * 5)
		game.fx.set_process(false)
		var shooting: Image = await frame_image()
		shooting.save_png("res://tests/previews/14-teammate-shot.png")
		check(changed_pixels(visible, shooting) > 20, "remote shot changes actual rendered pixels")
		game._change_stage(1)
		game.player.camera.global_position = Vector3(-3, 3.5, 36)
		game.player.camera.look_at(Vector3(4, -0.5, 8))
		var docks: Image = await frame_image()
		docks.save_png("res://tests/previews/15-dock-surface.png")
	print("COMBAT_VISUAL RESULT: ", failed, " failures")
	game.lan.leave()
	quit(0 if failed == 0 else 1)
