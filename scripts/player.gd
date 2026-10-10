extends CharacterBody3D

var WEAPONS: Array[Dictionary] = []

var game
var camera: Camera3D
var rig: Node3D
var muzzle: Node3D
var flash: MeshInstance3D
var flash_light: OmniLight3D
var flashlight: SpotLight3D
var weapon_index := 0
var magazines: Array[int] = [15, 36, 8, 30, 6]
var reserves: Array[int] = [999, 240, 56, 180, 36]
var hp := 100.0
var max_hp := 100.0
var stamina := 100.0
var damage_multiplier := 1.0
var reload_multiplier := 1.0
var speed_bonus := 0.0
var resistance := 0.0
var aim_pitch := 0.0
var recoil := 0.0
var trauma := 0.0
var shot_timer := 0.0
var reload_timer := 0.0
var reload_total := 1.0
var invulnerability := 0.0
var flash_timer := 0.0
var gun_kick := 0.0
var bob := 0.0
var step_timer := 0.0
var aim := 0.0
var sprinting := false
var empty_timer := 0.0
var hit_direction := 0.0
var sprint_exhausted := false
var rng := RandomNumberGenerator.new()
var peer_id := 1
var is_local := true
var player_name := "幸存者"
var life := "alive"
var bleed := 0.0
var revive_progress := 0.0
var upgrade_points := 0
var network_position := Vector3.ZERO
var network_yaw := 0.0
var avatar: Node3D
var avatar_animation: AnimationPlayer

func _ready() -> void:
	WEAPONS = game.core.weapons()
	rng.randomize()
	collision_layer = 2
	collision_mask = 5
	floor_snap_length = 0.3
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.75
	collision.shape = capsule
	collision.position.y = 0.88
	add_child(collision)
	camera = Camera3D.new()
	camera.position.y = 1.65
	camera.near = 0.04
	camera.far = 150
	camera.fov = 82
	camera.current = is_local
	add_child(camera)
	rig = Node3D.new()
	camera.add_child(rig)
	flashlight = SpotLight3D.new()
	flashlight.position = Vector3(0.2, -0.12, 0)
	flashlight.light_color = Color(0.73, 0.85, 0.87)
	flashlight.light_energy = 3.0
	flashlight.spot_range = 27
	flashlight.spot_angle = 34
	flashlight.spot_attenuation = 0.7
	flashlight.shadow_enabled = false
	camera.add_child(flashlight)
	_build_weapon()
	if game.is_lan(): _build_avatar()
	rig.visible = is_local

func _unhandled_input(event: InputEvent) -> void:
	if not is_local or game.state != "playing" or (game.is_lan() and game.hud.menu.visible):
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sensitivity: float = game.sensitivity * (0.65 if aim > 0.5 else 1.0)
		rotate_y(-event.relative.x * sensitivity)
		aim_pitch = clampf(aim_pitch - event.relative.y * sensitivity, -1.43, 1.43)
	if event.is_action_pressed("reload"):
		begin_reload()
	if event.is_action_pressed("flashlight"):
		flashlight.visible = not flashlight.visible
	for i in 5:
		if event.is_action_pressed("weapon_%d" % (i + 1)):
			switch_weapon(i)
	if event.is_action_pressed("next_weapon"):
		cycle_weapon(1)
	if event.is_action_pressed("previous_weapon"):
		cycle_weapon(-1)

func _physics_process(delta: float) -> void:
	if game.state != "playing":
		return
	if game.is_lan() and not is_local and not game.lan.host(): return
	shot_timer -= delta
	invulnerability -= delta
	empty_timer -= delta
	flash_timer -= delta
	flash.visible = flash_timer > 0
	flash_light.visible = flash_timer > 0
	if reload_timer > 0:
		reload_timer -= delta
		if reload_timer <= 0 and not game.is_lan():
			var needed: int = WEAPONS[weapon_index].mag - magazines[weapon_index]
			var amount := needed if weapon_index == 0 else mini(needed, reserves[weapon_index])
			magazines[weapon_index] += amount
			if weapon_index != 0:
				reserves[weapon_index] -= amount
	var input := Input.get_vector("left", "right", "forward", "back")
	var remote: Dictionary = {}
	if game.is_lan() and not is_local:
		remote = game.lan.get_input(peer_id)
		input = Vector2(remote.x, remote.z)
		rotation.y = remote.yaw
		aim_pitch = remote.pitch
	if game.is_lan() and (life != "alive" or (is_local and game.hud.menu.visible)): input = Vector2.ZERO
	var direction := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	var aiming: bool = (int(remote.get("buttons", 0)) & 4) != 0 if not is_local else Input.is_action_pressed("aim")
	if stamina <= 3:
		sprint_exhausted = true
	elif stamina >= 25:
		sprint_exhausted = false
	var sprint_input: bool = (int(remote.get("buttons", 0)) & 2) != 0 if not is_local else Input.is_action_pressed("sprint")
	sprinting = sprint_input and input.y < -0.3 and not sprint_exhausted and not aiming and reload_timer <= 0
	stamina = clampf(stamina + (-28.0 if sprinting else 19.0) * delta, 0, 100)
	var speed := (9.2 if sprinting else 3.7 if aiming else 6.0) + speed_bonus
	var desired := direction * speed
	if game.is_lan() and game.lan.host():
		desired = game.core.coop_velocity(peer_id, direction, sprint_input and input.y < -0.3, aiming, delta)
	velocity.x = move_toward(velocity.x, desired.x, delta * 32)
	velocity.z = move_toward(velocity.z, desired.z, delta * 32)
	if not is_on_floor():
		velocity.y -= 24 * delta
	elif ((int(remote.get("buttons", 0)) & 1) != 0 if not is_local else Input.is_action_just_pressed("jump")) and life == "alive":
		velocity.y = 7.2
	move_and_slide()
	if game.is_lan() and is_local and not game.lan.host():
		var buttons := 0
		if life == "alive" and not game.hud.menu.visible:
			if Input.is_action_pressed("jump"): buttons |= 1
			if Input.is_action_pressed("sprint"): buttons |= 2
			if aiming: buttons |= 4
			if Input.is_action_pressed("interact"): buttons |= 16
		game.lan.send_input(delta, input.x, input.y, rotation.y, aim_pitch, buttons)
	var moving := Vector2(velocity.x, velocity.z).length() > 0.7 and is_on_floor()
	if moving:
		bob += delta * (14 if sprinting else 10)
		step_timer -= delta
		if step_timer <= 0:
			game.sound.play("step", -22, 1.1 if sprinting else 0.85)
			step_timer = 0.28 if sprinting else 0.43
	else:
		bob = lerpf(bob, 0, delta * 5)
	var weapon: Dictionary = WEAPONS[weapon_index]
	var wants_fire := Input.is_action_pressed("shoot") if weapon.auto else Input.is_action_just_pressed("shoot")
	if is_local and life == "alive" and not (game.is_lan() and game.hud.menu.visible) and wants_fire and shot_timer <= 0 and reload_timer <= 0 and not sprinting:
		if magazines[weapon_index] > 0:
			fire()
		elif empty_timer <= 0:
			game.sound.play("empty", -8)
			empty_timer = 0.3
			begin_reload()
	recoil = move_toward(recoil, 0, delta * 0.22)
	trauma = move_toward(trauma, 0, delta * 1.8)
	gun_kick = lerpf(gun_kick, 0, minf(delta * 15, 1))
	aim = move_toward(aim, 1.0 if aiming else 0.0, delta * 7)
	camera.fov = lerpf(camera.fov, 61.0 if aiming else 91.0 if sprinting else 82.0, delta * 7)
	camera.position.y = 1.65 + sin(bob) * (0.028 if moving else 0.0)
	camera.rotation = Vector3(aim_pitch - recoil + rng.randf_range(-1, 1) * trauma * 0.022, rng.randf_range(-1, 1) * trauma * 0.018, rng.randf_range(-1, 1) * trauma * 0.011)
	var reload_pose := sin((1.0 - reload_timer / reload_total) * PI) if reload_timer > 0 else 0.0
	rig.position = Vector3(lerpf(0.27, 0.035, aim), lerpf(-0.25, -0.2, aim) - reload_pose * 0.25, -0.42 + gun_kick * 0.85)
	rig.position.x += sin(bob * 0.5) * 0.012
	rig.rotation = Vector3(gun_kick * 0.8 + reload_pose * 0.55 + (0.35 if sprinting else 0.0), reload_pose * -0.35, reload_pose * -0.45 + sin(bob * 0.5) * 0.015)

func _build_weapon() -> void:
	for child in rig.get_children():
		child.free()
	var steel := Forge.material(Color(0.11, 0.15, 0.17), 0.8)
	var dark := Forge.material(Color(0.045, 0.055, 0.064), 0.35)
	var accent := Forge.material(Color(0.88, 0.4, 0.11), 0.55)
	var skin := Forge.material(Color(0.27, 0.19, 0.13))
	var glove := Forge.material(Color(0.075, 0.09, 0.095))
	var length: float = [0.35, 0.5, 0.76, 0.65, 0.87][weapon_index]
	Forge.box(rig, Vector3(0, 0, -length * 0.35), Vector3(0.13, 0.13, length * 0.8), steel)
	Forge.box(rig, Vector3(0, -0.12, 0.025), Vector3(0.095, 0.24, 0.14), dark).rotation.x = -0.2
	Forge.box(rig, Vector3(0, 0.086, -0.08), Vector3(0.035, 0.034, 0.05), dark)
	Forge.box(rig, Vector3(0, 0.082, -length * 0.65), Vector3(0.028, 0.045, 0.03), accent)
	var barrel := Forge.cylinder(rig, Vector3(0, -0.005, -length * 0.77), 0.038 if weapon_index != 2 else 0.048, length * 0.37, dark)
	barrel.rotation.x = PI / 2
	if weapon_index > 0:
		Forge.box(rig, Vector3(0, -0.14, -0.2), Vector3(0.08, 0.24, 0.12), dark)
		Forge.box(rig, Vector3(0, -0.015, 0.19), Vector3(0.11, 0.15, 0.27), dark)
		Forge.box(rig, Vector3(0, -0.075, -length * 0.6), Vector3(0.16, 0.09, length * 0.33), accent if weapon_index == 2 else dark)
		Forge.box(rig, Vector3(-0.055, -0.16, -length * 0.55), Vector3(0.15, 0.1, 0.14), glove)
		Forge.box(rig, Vector3(-0.07, -0.26, -length * 0.4), Vector3(0.12, 0.22, 0.13), skin).rotation.x = 0.55
		for i in 5:
			Forge.box(rig, Vector3(0, 0.083, -0.13 - i * 0.055), Vector3(0.14, 0.02, 0.015), dark)
	if weapon_index == 4:
		var neon := Forge.material(Color(0.14, 0.8, 0.84), 0, 3)
		for side in [-1, 1]:
			Forge.box(rig, Vector3(side * 0.073, 0.02, -0.42), Vector3(0.02, 0.07, 0.4), neon)
		Forge.box(rig, Vector3(0, 0.15, -0.22), Vector3(0.09, 0.1, 0.2), steel)
		Forge.box(rig, Vector3(0, 0.15, -0.11), Vector3(0.07, 0.07, 0.015), neon)
	Forge.box(rig, Vector3(0.03, -0.17, 0.08), Vector3(0.14, 0.14, 0.18), glove)
	Forge.box(rig, Vector3(0.035, -0.29, 0.18), Vector3(0.14, 0.18, 0.15), skin).rotation.x = -0.35
	muzzle = Node3D.new()
	muzzle.position = Vector3(0, -0.005, -length * 0.98)
	rig.add_child(muzzle)
	flash = Forge.sphere(muzzle, Vector3(0, 0, -0.075), 0.075, Forge.material(Color(0.2, 0.95, 1) if weapon_index == 4 else Color(1, 0.63, 0.2), 0, 5))
	flash.scale = Vector3(1, 0.7, 2.4)
	flash.visible = false
	flash_light = OmniLight3D.new()
	flash_light.light_color = Color(1, 0.58, 0.2) if weapon_index != 4 else Color(0.2, 0.8, 1)
	flash_light.light_energy = 4.0
	flash_light.omni_range = 7
	flash_light.visible = false
	muzzle.add_child(flash_light)
	for visual in rig.find_children("*", "MeshInstance3D", true, false):
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func fire(sequence: int = 0) -> void:
	if game.is_lan():
		if life != "alive": return
		if not game.lan.host():
			game.lan.request("fire", weapon_index, rotation.y, camera.rotation.x)
			play_gun_feedback()
			magazines[weapon_index] = maxi(magazines[weapon_index] - 1, 0)
			return
		if sequence == 0:
			game.lan.action_sequence += 1
			sequence = game.lan.action_sequence
		if not game.core.coop_fire(peer_id, sequence): return
	var weapon: Dictionary = WEAPONS[weapon_index]
	if not game.is_lan(): magazines[weapon_index] -= 1
	shot_timer = weapon.rate
	recoil += weapon.kick * (0.65 if aim > 0.5 else 1.0)
	gun_kick = weapon.kick * 2.5
	trauma = minf(trauma + weapon.kick * 2, 0.7)
	flash_timer = 0.045
	flash.rotation.z = rng.randf() * TAU
	game.shots_fired += 1
	if is_local: game.sound.play(weapon.sound, -4 if weapon_index != 2 else -1)
	else: game.sound.positional(weapon.sound, global_position, -12)
	game.fx.casing(muzzle.global_position + Vector3.UP * 0.05, camera.global_basis.x)
	var any_hit := false
	var any_head := false
	var any_kill := false
	var traces: Array = []
	for pellet in int(weapon.pellets):
		var spread: float = weapon.spread * (0.36 if aim > 0.5 else 1.0)
		var direction: Vector3 = (camera.global_basis * Vector3(rng.randf_range(-spread, spread), rng.randf_range(-spread, spread), -1)).normalized()
		var start := camera.global_position
		var remaining := 4 if weapon_index == 4 else 1
		var excluded: Array[RID] = [get_rid()]
		var endpoint := start + direction * 110
		while remaining > 0:
			var query := PhysicsRayQueryParameters3D.create(start, endpoint, 5, excluded)
			var result := get_world_3d().direct_space_state.intersect_ray(query)
			if result.is_empty():
				break
			endpoint = result.position
			var collider = result.collider
			if collider.has_method("take_hit"):
				var outcome: Dictionary = collider.take_hit(weapon.damage * damage_multiplier, result.position, direction, weapon.force)
				any_hit = true
				any_head = any_head or outcome.head
				any_kill = any_kill or outcome.killed
				excluded.append(collider.get_rid())
				remaining -= 1
				if remaining > 0:
					start = result.position + direction * 0.06
					endpoint = start + direction * 110
			else:
				game.fx.burst(result.position, result.normal, Color(0.85, 0.6, 0.3), 3, 1.6)
				break
		if pellet < 3:
			game.fx.tracer(muzzle.global_position, endpoint, Color(0.15, 0.85, 1) if weapon_index == 4 else Color(1, 0.64, 0.24))
			traces.append([endpoint.x, endpoint.y, endpoint.z])
	if any_hit:
		game.shots_hit += 1
		if is_local:
			game.hud.confirm_hit(any_head, any_kill)
			game.sound.play("headshot" if any_head else "hit", -8)
		if any_kill and (weapon_index == 2 or any_head or weapon_index == 4):
			game.hit_stop(0.045)
	if game.is_lan():
		game.lan.shot_event(self, traces, any_head, any_kill, any_hit)
		game.lan.sync_stats()
	if magazines[weapon_index] == 0 and is_local:
		game.hud.toast("弹匣已空  ·  R 换弹", Color(1, 0.57, 0.24), 1.8)

func begin_reload() -> void:
	if game.is_lan():
		game.lan.request("reload")
		game.sound.play("reload", -7)
		return
	var weapon: Dictionary = WEAPONS[weapon_index]
	if reload_timer > 0 or magazines[weapon_index] >= int(weapon.mag) or (weapon_index != 0 and reserves[weapon_index] <= 0):
		return
	reload_total = weapon.reload * reload_multiplier
	reload_timer = reload_total
	game.sound.play("reload", -7)

func switch_weapon(index: int) -> void:
	if game.is_lan():
		game.lan.request("switch", index)
		return
	if game.level_number < int(WEAPONS[index].level):
		game.hud.toast("%s  ·  生存等级 %d 解锁" % [WEAPONS[index].short, WEAPONS[index].level], Color(0.66, 0.76, 0.77), 2.0)
		return
	if weapon_index == index:
		return
	weapon_index = index
	reload_timer = 0
	shot_timer = 0.23
	gun_kick = 0.25
	game.sound.play("reload", -13, 1.4)
	_build_weapon()

func cycle_weapon(step: int) -> void:
	for i in range(1, 6):
		var index := posmod(weapon_index + step * i, 5)
		if game.level_number >= int(WEAPONS[index].level):
			switch_weapon(index)
			return

func take_damage(amount: float, origin: Vector3) -> void:
	if game.is_lan():
		if not game.lan.host(): return
		if game.core.coop_damage(peer_id, amount):
			game.lan.sync_stats()
			if is_local:
				game.hud.hurt = 1
				trauma = 1
				game.sound.play("hurt", -4)
			game.lan.net.send_event("hurt", JSON.stringify({"id": peer_id}))
		return
	if invulnerability > 0 or game.state != "playing":
		return
	invulnerability = 0.38
	hp = game.core.player_damage(hp, amount, resistance)
	trauma = 1.0
	var relative := to_local(origin)
	hit_direction = atan2(relative.x, -relative.z)
	game.hud.hurt = 1.0
	game.sound.play("hurt", -4)
	if hp <= 0:
		hp = 0
		game.die()

func resupply(full: bool = false) -> void:
	if game.is_lan():
		if game.lan.host(): game.core.coop_resupply(peer_id, full)
		return
	for i in range(1, 5):
		reserves[i] = mini(reserves[i] + int(WEAPONS[i].reserve * (0.55 if full else 0.14)), int(WEAPONS[i].reserve))
	if full:
		hp = minf(hp + 18, max_hp)

func apply_coop_stats(data: Dictionary) -> void:
	if data.is_empty(): return
	var old_weapon := weapon_index
	var old_life := life
	life = data.life
	hp = data.hp
	max_hp = data.max_hp
	damage_multiplier = data.damage_multiplier
	resistance = data.resistance
	reload_multiplier = data.reload_multiplier
	speed_bonus = data.speed_bonus
	magazines.assign(data.magazines)
	reserves.assign(data.reserves)
	weapon_index = int(data.weapon)
	reload_timer = data.reload
	reload_total = data.reload_total
	bleed = data.bleed
	revive_progress = data.revive
	upgrade_points = int(data.points)
	stamina = data.stamina
	sprinting = data.sprinting
	collision_layer = 2 if life == "alive" else 0
	if old_weapon != weapon_index: _build_weapon()
	if is_local and old_life != "alive" and life == "alive":
		camera.position = Vector3(0, 1.65, 0)
		camera.rotation = Vector3(aim_pitch, 0, 0)

func play_gun_feedback() -> void:
	var weapon: Dictionary = WEAPONS[weapon_index]
	shot_timer = weapon.rate
	recoil += weapon.kick * (0.65 if aim > 0.5 else 1.0)
	gun_kick = weapon.kick * 2.5
	trauma = minf(trauma + weapon.kick * 2, 0.7)
	flash_timer = 0.05
	game.sound.play(weapon.sound, -4)
	game.fx.casing(muzzle.global_position, camera.global_basis.x)

func _build_avatar() -> void:
	avatar = preload("res://assets/models/city_zombie.glb").instantiate()
	add_child(avatar)
	avatar.rotation.y = PI
	avatar.scale = Vector3.ONE * 1.06
	for mesh in avatar.find_children("*", "MeshInstance3D", true, false):
		mesh.custom_aabb = (mesh.global_transform.affine_inverse() * global_transform) * AABB(Vector3(-0.8, -0.2, -0.8), Vector3(1.6, 2.6, 1.6))
	avatar.visible = not is_local
	avatar_animation = avatar.find_child("AnimationPlayer", true, false)
	var armor := Forge.material(Color(0.055, 0.22, 0.32), 0.5)
	Forge.box(avatar, Vector3(0, 1.3, 0.15), Vector3(0.52, 0.55, 0.18), armor)
	Forge.sphere(avatar, Vector3(0, 1.76, 0), 0.18, armor).scale.y = 0.7
	Forge.box(avatar, Vector3(0, 1.6, 0.18), Vector3(0.25, 0.21, 0.12), Forge.material(Color(0.04, 0.06, 0.07)))
	Forge.box(avatar, Vector3(0.3, 1.12, 0.3), Vector3(0.1, 0.1, 0.6), Forge.material(Color(0.08, 0.1, 0.12), 0.7))
	if not is_local:
		var label := Forge.label(self, Vector3(0, 2.2, 0), player_name, Color(0.3, 0.92, 0.9), 32)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.pixel_size = 0.009

func _process(delta: float) -> void:
	if not game.is_lan(): return
	if not is_local:
		flash_timer -= delta
		flash.visible = flash_timer > 0
		flash_light.visible = flash_timer > 0
		if avatar_animation:
			var clip := "run" if velocity.length() > 7 else "walk" if velocity.length() > 0.7 else "idle"
			if avatar_animation.has_animation(clip) and avatar_animation.current_animation != clip:
				avatar_animation.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
				avatar_animation.play(clip, 0.15)
		avatar.rotation.x = 0 if life == "alive" else -1.15
	elif life == "dead":
		var allies: Array = game.lan.active_players()
		if not allies.is_empty():
			camera.global_position = allies[0].global_position + Vector3(0, 2.7, 3.5)
			camera.look_at(allies[0].global_position + Vector3.UP)
