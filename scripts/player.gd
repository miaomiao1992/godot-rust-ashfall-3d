extends CharacterBody3D

const GrenadeModel = preload("res://scripts/grenade_model.gd")

var WEAPONS: Array[Dictionary] = []

var game
var camera: Camera3D
var rig: Node3D
var muzzle: Node3D
var flash: MeshInstance3D
var flash_light: OmniLight3D
var flashlight: SpotLight3D
var weapon_index := 0
var magazines: Array[int] = []
var reserves: Array[int] = []
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
var flash_pending := false
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
var avatar_skeleton: Skeleton3D
var arm_chains: Array[Dictionary] = []
var team := -1
var name_label: Label3D
var team_marker: MeshInstance3D
const SNIPER := 5
var scope_zoom := 4.0
var scope_latched := false
var holding_breath := false
var breath := 4.0
var breath_exhausted := false
var scope_clock := 0.0
var scope_sway := Vector2.ZERO
var bolt_timer := 0.0
var bolt_sound_pending := false
var bolt_handle: Node3D
var active_grenade: int = -1
var grenade_throw_action := ""
var crouching := false
var capsule_collision: CollisionShape3D
var climbing := false
var grenade_ready_timer := 0.0
var grenade_release_pending := false
var grenade_soft_toss := false

func _ready() -> void:
	WEAPONS = game.core.weapons()
	for weapon in WEAPONS:
		magazines.append(int(weapon.mag))
		reserves.append(int(weapon.reserve))
	rng.randomize()
	collision_layer = 2
	collision_mask = 5
	floor_snap_length = 0.3
	var collision := CollisionShape3D.new()
	capsule_collision = collision
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.75
	collision.shape = capsule
	collision.position.y = 0.88
	add_child(collision)
	camera = Camera3D.new()
	camera.position.y = 1.65
	camera.near = 0.04
	camera.far = 240
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
	rig.visible = true
	flashlight.visible = is_local
	_update_weapon_pose()

func _unhandled_input(event: InputEvent) -> void:
	if not is_local or game.state != "playing" or (game.is_lan() and game.hud.menu.visible):
		grenade_throw_action = ""
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sensitivity: float = game.sensitivity / scope_zoom if scope_active() else game.sensitivity * (0.65 if aim > 0.5 else 1.0)
		rotate_y(-event.relative.x * sensitivity)
		aim_pitch = clampf(aim_pitch - event.relative.y * sensitivity, -1.43, 1.43)
	if event.is_action_pressed("reload"):
		begin_reload()
	if event.is_action_pressed("flashlight"):
		flashlight.visible = not flashlight.visible
	if active_grenade >= 0:
		if life == "alive":
			for action in ["shoot", "aim"]:
				if event.is_action_pressed(action):
					if grenade_throw_action.is_empty() and not grenade_release_pending:
						grenade_throw_action = action
						grenade_ready_timer = 0.5
						game.sound.play("pinpull", -12)
					return
				if event.is_action_released(action):
					if grenade_throw_action == action:
						grenade_throw_action = ""
						grenade_release_pending = true
						grenade_soft_toss = action == "aim"
						if grenade_ready_timer <= 0: throw_active_grenade(grenade_soft_toss)
					return
	if active_grenade < 0 and weapon_index == SNIPER and life == "alive" and event.is_action_pressed("aim"):
		scope_latched = not scope_latched
		return
	for i in WEAPONS.size():
		if event.is_action_pressed("weapon_%d" % (i + 1)):
			cancel_grenade()
			switch_weapon(i)
	if event.is_action_pressed("next_weapon"):
		if active_grenade >= 0: cancel_grenade()
		elif weapon_index == SNIPER and aim > 0.8: scope_zoom = 8 if scope_zoom == 4 else 4
		else: cycle_weapon(1)
	if event.is_action_pressed("previous_weapon"):
		if active_grenade >= 0: cancel_grenade()
		elif weapon_index == SNIPER and aim > 0.8: scope_zoom = 4 if scope_zoom == 8 else 8
		else: cycle_weapon(-1)
	if game.is_pvp() and life == "alive":
		if event.is_action_pressed("grenade"):
			select_grenade(0 if active_grenade != 0 else 1)
		elif event.is_action_pressed("flash_grenade"):
			select_grenade(1 if active_grenade != 1 else 2)
		elif event.is_action_pressed("smoke_grenade"):
			select_grenade(2 if active_grenade != 2 else 0)
		elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_4:
			select_grenade(0 if active_grenade != 0 else (active_grenade + 1) % 3)

func _physics_process(delta: float) -> void:
	if life != "alive" or game.state != "playing" or (game.is_lan() and game.hud.menu.visible):
		grenade_throw_action = ""
	if game.state != "playing":
		return
	if game.is_lan() and not is_local and not game.lan.host(): return
	shot_timer -= delta
	invulnerability -= delta
	empty_timer -= delta
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
	var aiming: bool = (int(remote.get("buttons", 0)) & 4) != 0 if not is_local else scope_latched if weapon_index == SNIPER and active_grenade < 0 else Input.is_action_pressed("aim")
	var wants_crouch: bool = (int(remote.get("buttons", 0)) & 8) != 0 if not is_local else Input.is_action_pressed("crouch")
	set_crouching(wants_crouch)
	if stamina <= 3:
		sprint_exhausted = true
	elif stamina >= 25:
		sprint_exhausted = false
	var sprint_input: bool = (int(remote.get("buttons", 0)) & 2) != 0 if not is_local else Input.is_action_pressed("sprint")
	sprinting = sprint_input and input.y < -0.3 and not sprint_exhausted and not aiming and reload_timer <= 0 and not crouching
	stamina = clampf(stamina + (-28.0 if sprinting else 19.0) * delta, 0, 100)
	var speed := (9.2 if sprinting else 3.7 if aiming else 6.0) + speed_bonus
	var desired := direction * speed
	if game.is_lan() and game.lan.host():
		desired = game.core.coop_velocity(peer_id, direction, sprint_input and input.y < -0.3, aiming, delta)
	if crouching: desired *= 0.45
	velocity.x = move_toward(velocity.x, desired.x, delta * 32)
	velocity.z = move_toward(velocity.z, desired.z, delta * 32)
	var ladder: AABB = game.level.ladder_at(position) if game.level.has_method("ladder_at") else AABB()
	climbing = ladder.size != Vector3.ZERO and absf(input.y) > 0.1 and life == "alive"
	if climbing:
		velocity.y = -input.y * 3.0
		velocity.x = direction.x * 1.8
		velocity.z = direction.z * 1.8
	elif not is_on_floor():
		velocity.y -= 24 * delta
	elif ((int(remote.get("buttons", 0)) & 1) != 0 if not is_local else Input.is_action_just_pressed("jump")) and life == "alive":
		velocity.y = 7.2
	move_and_slide()
	if not game.is_lan() or game.lan.host():
		for slide in get_slide_collision_count():
			var contact := get_slide_collision(slide)
			var body = contact.get_collider()
			if body.has_method("push"): body.push(direction)
	if game.is_lan() and is_local and not game.lan.host():
		var buttons := 0
		if life == "alive" and not game.hud.menu.visible:
			if Input.is_action_pressed("jump"): buttons |= 1
			if Input.is_action_pressed("sprint"): buttons |= 2
			if aiming: buttons |= 4
			if crouching: buttons |= 8
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
	if active_grenade < 0 and is_local and life == "alive" and not (game.is_lan() and game.hud.menu.visible) and wants_fire and shot_timer <= 0 and reload_timer <= 0 and not sprinting:
		if magazines[weapon_index] > 0:
			fire()
		elif empty_timer <= 0:
			game.sound.play("empty", -8)
			empty_timer = 0.3
			begin_reload()
	aim = move_toward(aim, 1.0 if aiming else 0.0, delta * 7)
	update_scope(delta, aiming, sprint_input)
	var target_fov := rad_to_deg(2 * atan(tan(deg_to_rad(82.0) * 0.5) / scope_zoom)) if scope_active() else 61.0 if aiming and weapon_index != SNIPER else 91.0 if sprinting else 82.0
	camera.fov = lerpf(camera.fov, target_fov, minf(delta * 12, 1))
	camera.position.y = (0.72 if crouching else 1.65) + sin(bob) * (0.028 if moving else 0.0)

func set_crouching(value: bool) -> void:
	if capsule_collision == null: return
	if not value and crouching:
		var shape := CapsuleShape3D.new()
		shape.radius = 0.32
		shape.height = 1.75
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform = Transform3D(Basis.IDENTITY, global_position + Vector3.UP * 0.88)
		query.collision_mask = 1
		query.exclude = [get_rid()]
		if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(): return
	crouching = value
	var capsule: CapsuleShape3D = capsule_collision.shape
	capsule.height = 0.85 if crouching else 1.75
	capsule_collision.position.y = 0.43 if crouching else 0.88
	camera.position.y = 0.72 if crouching else 1.65

func _update_weapon_pose() -> void:
	camera.rotation = Vector3(aim_pitch - recoil + scope_sway.y + rng.randf_range(-1, 1) * trauma * 0.022, scope_sway.x + rng.randf_range(-1, 1) * trauma * 0.018, rng.randf_range(-1, 1) * trauma * 0.011)
	var reload_pose := sin((1.0 - reload_timer / reload_total) * PI) if reload_timer > 0 else 0.0
	rig.position = Vector3(lerpf(0.27, 0.035, aim) if is_local else 0.18, lerpf(-0.25, -0.2, aim) - reload_pose * 0.25, (-0.42 if is_local else -0.32) + gun_kick * 0.85)
	rig.position.x += sin(bob * 0.5) * 0.012
	rig.rotation = Vector3(gun_kick * 0.8 + reload_pose * 0.55 + (0.35 if sprinting else 0.0), reload_pose * -0.35, reload_pose * -0.45 + sin(bob * 0.5) * 0.015)
	if is_instance_valid(bolt_handle):
		var progress := 1 - bolt_timer / 1.45
		bolt_handle.position.z = 0.02 + sin(clampf((progress - 0.17) / 0.6, 0, 1) * PI) * 0.10
		bolt_handle.rotation.z = -sin(clampf(progress / 0.6, 0, 1) * PI) * 0.6

func scope_active() -> bool:
	return weapon_index == SNIPER and aim > 0.85 and bolt_timer < 0.12 and reload_timer <= 0 and life == "alive"

func update_scope(delta: float, aiming: bool, steady: bool) -> void:
	scope_clock += delta
	var engaged := weapon_index == SNIPER and aiming and life == "alive" and reload_timer <= 0
	if breath < 0.1: breath_exhausted = true
	elif breath > 1.5: breath_exhausted = false
	holding_breath = engaged and steady and not breath_exhausted and velocity.length() < 0.5
	breath = clampf(breath + (-1 if holding_breath else 0.65) * delta, 0, 4)
	var amplitude := 0.00010 if holding_breath else 0.0012
	if velocity.length() > 0.5: amplitude *= 3
	scope_sway = Vector2(sin(scope_clock * 0.9), sin(scope_clock * 1.2)) * amplitude if engaged else Vector2.ZERO

func _build_weapon() -> void:
	bolt_handle = null
	for child in rig.get_children():
		child.free()
	if active_grenade >= 0:
		GrenadeModel.build_first_person_rig(rig, active_grenade)
		muzzle = Node3D.new()
		muzzle.position = Vector3(0, -0.05, -0.5)
		rig.add_child(muzzle)
		flash = Forge.sphere(muzzle, Vector3.ZERO, 0.01, Forge.material(Color.BLACK))
		flash.visible = false
		flash_light = OmniLight3D.new()
		flash_light.visible = false
		muzzle.add_child(flash_light)
		return
	var steel := Forge.material(Color(0.11, 0.15, 0.17), 0.8)
	var dark := Forge.material(Color(0.045, 0.055, 0.064), 0.35)
	var accent := Forge.material(Color(0.88, 0.4, 0.11), 0.55)
	var skin := Forge.material(Color(0.27, 0.19, 0.13))
	var glove := Forge.material(Color(0.075, 0.09, 0.095))
	var length: float = [0.35, 0.5, 0.76, 0.65, 0.87, 1.05][weapon_index]
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
		if is_local:
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
	if weapon_index == SNIPER:
		Forge.box(rig, Vector3(0, -0.04, 0.3), Vector3(0.13, 0.20, 0.4), dark)
		var optic := Forge.cylinder(rig, Vector3(0, 0.18, -0.25), 0.065, 0.40, dark)
		optic.mesh.radial_segments = 16
		optic.rotation.x = PI / 2
		for z in [-0.05, -0.44]:
			Forge.cylinder(rig, Vector3(0, 0.18, z), 0.081, 0.07, steel).rotation.x = PI / 2
		Forge.cylinder(rig, Vector3(0, 0.18, -0.016), 0.062, 0.008, Forge.material(Color(0.11, 0.38, 0.47), 0.4)).rotation.x = PI / 2
		bolt_handle = Node3D.new()
		rig.add_child(bolt_handle)
		Forge.box(bolt_handle, Vector3(0.12, 0.03, 0.02), Vector3(0.20, 0.025, 0.025), steel)
		Forge.sphere(bolt_handle, Vector3(0.22, 0.02, 0.02), 0.038, dark)
	if is_local:
		Forge.box(rig, Vector3(0.03, -0.17, 0.08), Vector3(0.14, 0.14, 0.18), glove)
		Forge.box(rig, Vector3(0.035, -0.29, 0.18), Vector3(0.14, 0.18, 0.15), skin).rotation.x = -0.35
	muzzle = Node3D.new()
	muzzle.position = Vector3(0, -0.005, -length * 0.98)
	rig.add_child(muzzle)
	flash = Forge.sphere(muzzle, Vector3(0, 0, -0.075), 0.075, Forge.material(Color(0.2, 0.95, 1) if weapon_index == 4 else Color(1, 0.63, 0.2), 0, 5))
	flash.scale = Vector3(1, 0.7, 2.4)
	flash.visible = false
	flash_pending = false
	flash_light = OmniLight3D.new()
	flash_light.light_color = Color(1, 0.58, 0.2) if weapon_index != 4 else Color(0.2, 0.8, 1)
	flash_light.light_energy = 4.0
	flash_light.omni_range = 7
	flash_light.shadow_enabled = false
	flash_light.visible = false
	muzzle.add_child(flash_light)
	for visual in rig.find_children("*", "MeshInstance3D", true, false):
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func select_grenade(kind: int) -> void:
	if not game.is_pvp(): return
	var f: Dictionary = game.lan.fighters.get(peer_id, {})
	var grenades: Array = f.get("grenades", [0, 0, 0])
	if kind < 0 or kind >= grenades.size() or int(grenades[kind]) <= 0:
		for next_kind in 3:
			var test_k := (kind + next_kind) % 3
			if int(grenades[test_k]) > 0:
				kind = test_k
				break
	if int(grenades[kind]) <= 0:
		game.hud.toast("投掷物耗尽", Color(1, 0.4, 0.4), 1.5)
		return
	active_grenade = kind
	scope_latched = false
	grenade_throw_action = ""
	grenade_release_pending = false
	grenade_ready_timer = 0
	game.hud.toast("按住鼠标准备 · 松开左键高抛 / 右键轻掷", Color(0.3, 0.9, 1.0), 1.8)
	_build_weapon()

func cancel_grenade() -> void:
	grenade_throw_action = ""
	grenade_release_pending = false
	grenade_ready_timer = 0
	if active_grenade >= 0:
		active_grenade = -1
		_build_weapon()

func throw_active_grenade(soft_toss: bool = false) -> void:
	grenade_throw_action = ""
	grenade_release_pending = false
	if active_grenade < 0: return
	var kind := active_grenade
	active_grenade = -1
	game.lan.request("grenade", kind + (3 if soft_toss else 0), rotation.y + camera.rotation.y, camera.rotation.x)
	shot_timer = 0.5
	gun_kick = 0.12
	recoil += 0.05
	if is_local: game.sound.play("melee", -4)
	_build_weapon()

func fire(sequence: int = 0) -> void:
	if active_grenade >= 0:
		return
	if game.is_lan():
		if life != "alive": return
		if not game.lan.host():
			game.lan.request("fire", weapon_index, rotation.y + camera.rotation.y, camera.rotation.x)
			play_gun_feedback()
			predict_tracers()
			magazines[weapon_index] = maxi(magazines[weapon_index] - 1, 0)
			return
		if sequence == 0:
			game.lan.action_sequence += 1
			sequence = game.lan.action_sequence
		if not game.core.coop_fire(peer_id, sequence): return
	var weapon: Dictionary = WEAPONS[weapon_index]
	if not game.is_lan(): magazines[weapon_index] -= 1
	shot_timer = weapon.rate
	if weapon_index == SNIPER:
		bolt_timer = weapon.rate
		bolt_sound_pending = true
	if is_local: recoil += weapon.kick * (0.65 if aim > 0.5 else 1.0)
	gun_kick = weapon.kick * 2.5
	if is_local: trauma = minf(trauma + weapon.kick * 2, 0.7)
	flash_timer = 0.045
	flash_pending = true
	flash.rotation.z = rng.randf() * TAU
	game.shots_fired += 1
	if is_local: game.sound.play(weapon.sound, -4 if weapon_index != 2 else -1)
	else: game.sound.positional(weapon.sound, global_position, -12)
	game.fx.casing(muzzle.global_position + Vector3.UP * 0.05, camera.global_basis.x)
	var any_hit := false
	var any_head := false
	var any_kill := false
	var traces: Array = []
	var impacts: Array = []
	for pellet in int(weapon.pellets):
		var spread: float = (0.00015 if weapon_index == SNIPER and aim > 0.85 else weapon.spread * (0.36 if aim > 0.5 else 1.0))
		var direction: Vector3 = (camera.global_basis * Vector3(rng.randf_range(-spread, spread), rng.randf_range(-spread, spread), -1)).normalized()
		var start := camera.global_position
		var remaining := 4 if weapon_index == 4 else 1
		var walls_left := 2 if weapon_index in [4, 5] else 1
		var damage_factor := 1.0
		var excluded: Array[RID] = [get_rid()]
		var range_m := 220.0 if weapon_index == SNIPER else 110.0
		var endpoint := start + direction * range_m
		while remaining > 0:
			var query := PhysicsRayQueryParameters3D.create(start, endpoint, 7 if game.is_pvp() else 5, excluded)
			var result := get_world_3d().direct_space_state.intersect_ray(query)
			if result.is_empty():
				break
			endpoint = result.position
			var collider = result.collider
			if game.is_pvp() and collider is CharacterBody3D and collider.has_method("set_team"):
				var head: bool = result.position.y - collider.global_position.y > 1.42
				var outcome: Dictionary = game.lan.hit_player(peer_id, collider.peer_id, weapon.damage * damage_factor, head)
				any_hit = any_hit or outcome.hit
				any_head = any_head or outcome.head
				any_kill = any_kill or outcome.killed
				excluded.append(collider.get_rid())
				remaining -= 1
				if remaining > 0:
					start = result.position + direction * 0.06
					endpoint = start + direction * range_m
			elif collider.has_method("take_hit"):
				var outcome: Dictionary = collider.take_hit(weapon.damage * damage_multiplier * damage_factor, result.position, direction, weapon.force)
				any_hit = true
				any_head = any_head or outcome.head
				any_kill = any_kill or outcome.killed
				excluded.append(collider.get_rid())
				remaining -= 1
				if remaining > 0:
					start = result.position + direction * 0.06
					endpoint = start + direction * range_m
			else:
				var exit: Dictionary = game.battle.bullet_exit(result, direction, weapon_index, excluded) if walls_left > 0 else {}
				impacts.append(game.battle.impact(result, direction, weapon.damage * damage_factor, weapon.force))
				if exit.is_empty(): break
				impacts.append(game.battle.make_mark(exit.pos, exit.normal, 1 if game.battle.surface_of(collider) == "metal" else 2 if game.battle.surface_of(collider) == "wood" else 0, 0.22, 100, collider))
				damage_factor *= float(exit.factor)
				walls_left -= 1
				start = exit.pos + direction * 0.025
				endpoint = start + direction * range_m
		if pellet < 3:
			game.fx.tracer(muzzle.global_position, endpoint, Color(0.15, 0.85, 1) if weapon_index == 4 else Color(1, 0.64, 0.24), weapon_index == 4)
			traces.append([endpoint.x, endpoint.y, endpoint.z])
	if any_hit:
		game.shots_hit += 1
		if is_local:
			game.hud.confirm_hit(any_head, any_kill)
			game.sound.play("headshot" if any_head else "hit", -8)
		if any_kill and (weapon_index == 2 or any_head or weapon_index == 4):
			game.hit_stop(0.045)
	if game.is_lan():
		game.lan.shot_event(self, traces, any_head, any_kill, any_hit, impacts)
		game.lan.sync_stats()
	if magazines[weapon_index] == 0 and is_local:
		game.hud.toast("弹匣已空  ·  R 换弹", Color(1, 0.57, 0.24), 1.8)

func begin_reload() -> void:
	scope_latched = false
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
	if index != weapon_index: scope_latched = false
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
	for i in range(1, WEAPONS.size() + 1):
		var index := posmod(weapon_index + step * i, WEAPONS.size())
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
	for i in range(1, WEAPONS.size()):
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
	if is_instance_valid(team_marker): team_marker.visible = life == "alive"
	if is_instance_valid(name_label): name_label.visible = life != "dead"
	if life != "alive": grenade_throw_action = ""
	if life != "alive": grenade_release_pending = false
	if life != "alive": scope_latched = false
	if old_weapon != weapon_index:
		scope_latched = false
		_build_weapon()
	if is_local and old_life != "alive" and life == "alive":
		camera.position = Vector3(0, 1.65, 0)
		camera.rotation = Vector3(aim_pitch, 0, 0)

func play_gun_feedback() -> void:
	var weapon: Dictionary = WEAPONS[weapon_index]
	if weapon_index == SNIPER:
		bolt_timer = weapon.rate
		bolt_sound_pending = true
	shot_timer = weapon.rate
	if is_local: recoil += weapon.kick * (0.65 if aim > 0.5 else 1.0)
	gun_kick = weapon.kick * 2.5
	if is_local: trauma = minf(trauma + weapon.kick * 2, 0.7)
	flash_timer = 0.05
	flash_pending = true
	flash.rotation.z = rng.randf() * TAU
	if is_local: game.sound.play(weapon.sound, -4)
	else: game.sound.positional(weapon.sound, muzzle.global_position, -12)
	game.fx.casing(muzzle.global_position, camera.global_basis.x)

func predict_tracers() -> void:
	# Cosmetic prediction only: damage and hit confirmation remain host-authoritative.
	var weapon: Dictionary = WEAPONS[weapon_index]
	for pellet in mini(int(weapon.pellets), 3):
		var spread: float = 0.00015 if weapon_index == SNIPER and aim > 0.85 else weapon.spread * (0.36 if aim > 0.5 else 1.0)
		var direction := (camera.global_basis * Vector3(rng.randf_range(-spread, spread), rng.randf_range(-spread, spread), -1)).normalized()
		var endpoint := camera.global_position + direction * (220 if weapon_index == SNIPER else 110)
		var query := PhysicsRayQueryParameters3D.create(camera.global_position, endpoint, 7 if game.is_pvp() else 5, [get_rid()])
		var result := get_world_3d().direct_space_state.intersect_ray(query)
		if not result.is_empty(): endpoint = result.position
		game.fx.tracer(muzzle.global_position, endpoint, Color(0.15, 0.85, 1) if weapon_index == 4 else Color(1, 0.64, 0.24), weapon_index == 4)

func _build_avatar() -> void:
	avatar = preload("res://assets/models/survivor_soldier.glb").instantiate()
	avatar.name = "SurvivorAvatar"
	add_child(avatar)
	avatar.rotation.y = PI
	avatar.scale = Vector3.ONE
	for mesh in avatar.find_children("*", "MeshInstance3D", true, false):
		mesh.custom_aabb = (mesh.global_transform.affine_inverse() * global_transform) * AABB(Vector3(-0.8, -0.2, -0.8), Vector3(1.6, 2.6, 1.6))
	avatar.visible = not is_local
	avatar_animation = avatar.find_child("AnimationPlayer", true, false)
	avatar_skeleton = avatar.find_child("Skeleton3D", true, false)
	if not is_local and avatar_skeleton:
		for side in ["Left", "Right"]:
			var upper := avatar_skeleton.find_bone(side + "Arm")
			var lower := avatar_skeleton.find_bone(side + "ForeArm")
			var hand := avatar_skeleton.find_bone(side + "Hand")
			if upper >= 0 and lower >= 0 and hand >= 0:
				arm_chains.append({"upper": upper, "lower": lower, "hand": hand, "left": side == "Left", "a": avatar_skeleton.get_bone_global_rest(upper), "b": avatar_skeleton.get_bone_global_rest(lower), "c": avatar_skeleton.get_bone_global_rest(hand)})
	if avatar_animation and avatar_animation.has_animation("idle"):
		avatar_animation.get_animation("idle").loop_mode = Animation.LOOP_LINEAR
		avatar_animation.play("idle")
	if not is_local:
		name_label = Forge.label(self, Vector3(0, 2.2, 0), player_name, Color(0.3, 0.92, 0.9), 32)
		name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		name_label.pixel_size = 0.009
		if game.is_pvp():
			team_marker = Forge.sphere(self, Vector3(0, 1.25, 0), 0.4, Forge.material(Color.WHITE))
			team_marker.scale = Vector3(1.15, 0.22, 0.95)

func _process(delta: float) -> void:
	grenade_ready_timer = maxf(0, grenade_ready_timer - delta)
	if grenade_release_pending:
		if game.state != "playing" or life != "alive" or game.hud.menu.visible:
			grenade_release_pending = false
		elif grenade_ready_timer <= 0:
			throw_active_grenade(grenade_soft_toss)
	bolt_timer = maxf(bolt_timer - delta, 0)
	if bolt_sound_pending and bolt_timer < 1.1:
		bolt_sound_pending = false
		if is_local: game.sound.play("bolt", -12)
		else: game.sound.positional("bolt", global_position, -17)
	if is_local: rig.visible = life == "alive" and not scope_active()
	flash_timer = maxf(flash_timer - delta, 0)
	# Always display a newly received shot for at least one rendered frame,
	# even when a slow frame is longer than the flash's nominal lifetime.
	if is_instance_valid(flash):
		flash.visible = flash_pending or flash_timer > 0
	if is_instance_valid(flash_light):
		flash_light.visible = is_instance_valid(flash) and flash.visible
	flash_pending = false
	recoil = move_toward(recoil, 0, delta * 0.22)
	trauma = move_toward(trauma, 0, delta * 1.8)
	gun_kick = lerpf(gun_kick, 0, 1.0 - exp(-delta * 15))
	if game.state == "playing" or not is_local: _update_weapon_pose()
	if not game.is_lan(): return
	if not is_local:
		rig.visible = life == "alive"
		if avatar_animation:
			var clip := "run" if velocity.length() > 7 else "walk" if velocity.length() > 0.7 else "idle"
			if avatar_animation.has_animation(clip) and avatar_animation.current_animation != clip:
				avatar_animation.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
				avatar_animation.play(clip, 0.15)
		avatar.rotation.x = 0 if life == "alive" else -1.15
		avatar.rotation.z = -gun_kick * 0.12 if life == "alive" else 0.0
		_pose_weapon_arms()
	elif life == "dead":
		var allies: Array = game.lan.active_players()
		if game.is_pvp(): allies = allies.filter(func(p): return p.team == team)
		if not allies.is_empty():
			camera.global_position = allies[0].global_position + Vector3(0, 2.7, 3.5)
			camera.look_at(allies[0].global_position + Vector3.UP)

func set_team(value: int) -> void:
	if team == value: return
	team = value
	var color := Color(0.95, 0.18, 0.12) if team == 0 else Color(0.12, 0.48, 1)
	if is_instance_valid(name_label) and game.is_pvp(): name_label.modulate = color
	if is_instance_valid(team_marker): team_marker.material_override = Forge.material(color, 0, 0.4)

func _pose_weapon_arms() -> void:
	if not avatar_skeleton: return
	avatar_skeleton.clear_bones_global_pose_override()
	if life != "alive": return
	# Keep locomotion on the legs, and solve both arms toward world-space gun grips.
	# Skeleton units are asset-defined (this soldier uses centimetres), so all
	# lengths and targets are computed in skeleton space rather than hardcoded.
	var length: float = [0.35, 0.5, 0.76, 0.65, 0.87, 1.05][weapon_index]
	for chain in arm_chains:
		var a: Transform3D = chain.a
		var b: Transform3D = chain.b
		var c: Transform3D = chain.c
		var shoulder: Vector3 = avatar_skeleton.get_bone_global_pose(chain.upper).origin
		var grip := Vector3(-0.055, -0.12, -length * 0.55) if chain.left and weapon_index > 0 else Vector3(-0.025 if chain.left else 0.03, -0.12, 0.025)
		var target := avatar_skeleton.to_local(rig.to_global(grip))
		var upper_length := a.origin.distance_to(b.origin)
		var lower_length := b.origin.distance_to(c.origin)
		var direction := (target - shoulder).normalized()
		var distance := clampf(shoulder.distance_to(target), absf(upper_length - lower_length) + 0.01, upper_length + lower_length - 0.01)
		target = shoulder + direction * distance
		var pole := avatar_skeleton.global_basis.inverse() * (global_basis * Vector3(-1 if chain.left else 1, -1, 0))
		var bend := (pole - direction * pole.dot(direction)).normalized()
		var along := (upper_length * upper_length + distance * distance - lower_length * lower_length) / (2 * distance)
		var elbow := shoulder + direction * along + bend * sqrt(maxf(upper_length * upper_length - along * along, 0))
		a.basis = Basis(Quaternion((b.origin - a.origin).normalized(), (elbow - shoulder).normalized())) * a.basis
		a.origin = shoulder
		b.basis = Basis(Quaternion((c.origin - b.origin).normalized(), (target - elbow).normalized())) * b.basis
		b.origin = elbow
		c.origin = target
		c.basis = b.basis * chain.b.basis.inverse() * c.basis
		avatar_skeleton.set_bone_global_pose_override(chain.upper, a, 1.0, true)
		avatar_skeleton.set_bone_global_pose_override(chain.lower, b, 1.0, true)
		avatar_skeleton.set_bone_global_pose_override(chain.hand, c, 1.0, true)
