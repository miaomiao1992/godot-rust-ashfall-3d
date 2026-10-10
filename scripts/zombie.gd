extends CharacterBody3D

const CITY_MODEL = preload("res://assets/models/city_zombie.glb")
const MUTANT_MODEL = preload("res://assets/models/horror_mutant.glb")
static var skin_material_cache: Dictionary = {}

var game
var kind := 0
var hp := 75.0
var max_hp := 75.0
var speed := 2.1
var damage := 10.0
var size_factor := 1.0
var dead := false
var model: Node3D
var animation: AnimationPlayer
var skeleton: Skeleton3D
var actor: Node3D
var walk_clip := "walk"
var animation_variation := 1.0
var route := PackedVector3Array()
var path_timer := 0.0
var attack_timer := 0.0
var flinch := 0.0
var knockback := Vector3.ZERO
var phase := 0.0
var voice_timer := 3.0
var clothes := Color(0.18, 0.26, 0.22)
var health_label: Label3D
var variant := 0
var skill_timer := 5.0
var skill_step := 0
var enraged := false
var charge_windup := 0.0
var charge_time := 0.0
var charge_direction := Vector3.ZERO
var weakpoint: MeshInstance3D
var monster_name := "感染者"
var crowd_force := Vector3.ZERO
var acid_step := 0
var last_safe_position := Vector3.ZERO
var network_proxy := false
var net_id := 0
var forced_variant := -1
var network_position := Vector3.ZERO
var network_yaw := 0.0

func _ready() -> void:
	add_to_group("zombies")
	collision_layer = 4
	collision_mask = 1
	phase = randf() * TAU
	path_timer = randf() * 0.7
	voice_timer = randf_range(2.0, 7.0)
	variant = forced_variant if forced_variant >= 0 else randi_range(0, 3)
	var stats: Dictionary = game.core.monster_stats(kind, game.wave)
	hp = stats.hp
	speed = stats.speed
	damage = stats.damage
	size_factor = stats.scale
	monster_name = stats.name
	match kind:
		0:
			clothes = [Color(0.18, 0.26, 0.22), Color(0.3, 0.19, 0.15), Color(0.21, 0.27, 0.34), Color(0.4, 0.35, 0.18)][variant]
		1:
			clothes = Color(0.43, 0.23, 0.1)
		2:
			clothes = Color(0.29, 0.18, 0.25)
		3:
			clothes = Color(0.11, 0.2, 0.27)
		4:
			clothes = [Color(0.34, 0.17, 0.1), Color(0.11, 0.29, 0.23), Color(0.33, 0.1, 0.14)][game.stage_index]
			monster_name = game.BOSS_NAMES[game.stage_index]
			skill_timer = 3.0
		5:
			clothes = Color(0.23, 0.32, 0.085)
			skill_timer = randf_range(2.0, 5.0)
	max_hp = hp
	last_safe_position = global_position
	var shape := CapsuleShape3D.new()
	shape.radius = 0.32 * size_factor
	shape.height = 1.9 * size_factor
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = 0.95 * size_factor
	add_child(collider)
	_build_model()

func _build_model() -> void:
	model = Node3D.new()
	add_child(model)
	model.scale = Vector3.ONE * size_factor
	var mutant := kind in [2, 4, 5] or (kind == 1 and variant % 2 == 0)
	actor = MUTANT_MODEL.instantiate() if mutant else CITY_MODEL.instantiate()
	model.add_child(actor)
	actor.rotation.y = PI
	actor.scale = Vector3.ONE * (1.03 if mutant else 1.06)
	animation = actor.find_child("AnimationPlayer", true, false)
	var skeletons := actor.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		skeleton = skeletons[0]
	animation_variation = randf_range(0.84, 1.13)
	if not mutant and variant % 2 == 1:
		walk_clip = "walk_alt"
	var tint: Color = [Color(0.94, 0.94, 0.9), Color(0.8, 0.92, 0.86), Color(0.94, 0.78, 0.7), Color(0.78, 0.83, 0.97)][variant]
	if kind == 4:
		tint = [Color(0.94, 0.68, 0.5), Color(0.52, 0.87, 0.72), Color(0.94, 0.45, 0.42)][game.stage_index]
	for mesh in actor.find_children("*", "MeshInstance3D", true, false):
		# FBX/glTF rigs retain a centimetre-scale armature. Skinned vertices
		# are human-sized but the imported static mesh bounds are only 1/100
		# of that in world space. Provide bounds in the mesh's local frame.
		var body_bounds := AABB(Vector3(-1.0, -0.25, -1.0), Vector3(2.0, 2.8, 2.0))
		mesh.custom_aabb = (mesh.global_transform.affine_inverse() * model.global_transform) * body_bounds
		for surface in mesh.mesh.get_surface_count():
			var original: Material = mesh.mesh.surface_get_material(surface)
			if original is StandardMaterial3D:
				# Keep shared skin resources alive while deferred render updates
				# drain after actor deletion; also avoid a material allocation per mob.
				var key := str(original.get_instance_id()) + ":" + str(tint)
				if not skin_material_cache.has(key):
					var mat: StandardMaterial3D = original.duplicate()
					mat.albedo_color = tint
					mat.roughness = 0.87
					skin_material_cache[key] = mat
				mesh.set_surface_override_material(surface, skin_material_cache[key])
	if kind == 0:
		model.scale.x *= [0.85, 1.08, 1.0, 0.94][variant]
		if variant == 1:
			var head_mount := _mount("Head", Vector3(0, 1.78, 0))
			var helmet := Forge.sphere(head_mount, Vector3.ZERO, 0.15, Forge.material(Color(0.48, 0.3, 0.08), 0.3))
			helmet.scale.y = 0.55
		elif variant == 3:
			var chest := _mount("Spine2", Vector3(0, 1.31, -0.15))
			Forge.box(chest, Vector3.ZERO, Vector3(0.36, 0.33, 0.08), Forge.material(Color(0.08, 0.11, 0.1)))
	if kind == 1:
		model.scale.x *= 0.84
	if kind == 2:
		model.scale.x *= 1.32
		model.scale.z *= 1.15
		health_label = Forge.label(self, Vector3(0, 3.1, 0), "精英 / 屠戮者", Color(0.96, 0.35, 0.32), 30)
		health_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		health_label.pixel_size = 0.009
	if kind == 3:
		var chest := _mount("Spine2", Vector3(0, 1.28, -0.16))
		var armor := Forge.material(Color(0.075, 0.1, 0.12), 0.6)
		Forge.box(chest, Vector3.ZERO, Vector3(0.45, 0.44, 0.1), armor)
		for x in [-0.12, 0, 0.12]:
			Forge.box(chest, Vector3(x, -0.08, -0.08), Vector3(0.09, 0.16, 0.06), armor)
		var head_mount := _mount("Head", Vector3(0, 1.76, 0))
		var helmet := Forge.sphere(head_mount, Vector3.ZERO, 0.17, armor)
		helmet.scale.y = 0.65
	if kind == 5:
		var acid := Forge.material(Color(0.27, 0.58, 0.075), 0, 0.3)
		var chest := _mount("joint3", Vector3(0, 1.15, -0.17))
		for pos in [Vector3(-0.16, 0, 0), Vector3(0.14, -0.13, -0.04), Vector3(0.05, 0.18, 0)]:
			Forge.sphere(chest, pos, 0.14, acid)
	if kind == 4:
		model.scale.x *= 1.28 if game.stage_index != 1 else 1.08
		model.scale.z *= 1.2
		var core_color: Color = [Color(1, 0.27, 0.08), Color(0.25, 0.8, 0.18), Color(1, 0.06, 0.13)][game.stage_index]
		var chest := _mount("joint3", Vector3(0, 1.22, -0.23))
		weakpoint = Forge.sphere(chest, Vector3.ZERO, 0.12, Forge.material(core_color, 0, 1.5))
		var flesh := Forge.material(Color(0.3, 0.085, 0.07))
		for pos in [Vector3(-0.19, -0.13, 0.04), Vector3(0.17, 0.12, 0.04), Vector3(0.17, -0.1, 0.07)]:
			Forge.sphere(chest, pos, 0.13, flesh)
		if game.stage_index == 1:
			for side in [-1, 1]:
				Forge.sphere(chest, Vector3(side * 0.3, 0.22, 0.17), 0.18, Forge.material(Color(0.14, 0.28, 0.12)))
		elif game.stage_index == 2:
			var back := _mount("joint3", Vector3(0, 1.28, 0.2))
			for side in [-1, 1]:
				Forge.cylinder(back, Vector3(side * 0.14, 0, 0), 0.075, 0.55, Forge.material(Color(0.11, 0.1, 0.09), 0.7))
	_play_anim("run" if kind == 1 else walk_clip)
	if animation and animation.is_playing():
		animation.seek(randf() * animation.current_animation_length, true)

func _mount(hint: String, location: Vector3) -> Node3D:
	var mount := Node3D.new()
	if skeleton:
		for i in skeleton.get_bone_count():
			if hint.to_lower() in skeleton.get_bone_name(i).to_lower():
				var attachment := BoneAttachment3D.new()
				attachment.bone_idx = i
				skeleton.add_child(attachment)
				attachment.add_child(mount)
				mount.transform = skeleton.get_bone_global_rest(i).affine_inverse() * skeleton.global_transform.affine_inverse() * model.global_transform * Transform3D(Basis.IDENTITY, location)
				return mount
	model.add_child(mount)
	mount.position = location
	return mount

func _play_anim(name: String, playback: float = 1.0) -> void:
	if not animation:
		return
	var clip := ""
	for candidate in animation.get_animation_list():
		if candidate == name:
			clip = candidate
			break
	if clip.is_empty():
		clip = "walk"
	if animation.has_animation(clip):
		var resource := animation.get_animation(clip)
		resource.loop_mode = Animation.LOOP_LINEAR if clip in ["walk", "walk_alt", "run", "idle"] else Animation.LOOP_NONE
		animation.speed_scale = playback * animation_variation
		if animation.current_animation != clip or not animation.is_playing():
			animation.play(clip, 0.15)

func _physics_process(delta: float) -> void:
	if dead or network_proxy or game.state != "playing":
		return
	if global_position.y < game.level.surface_height(global_position) - 1.8 or absf(global_position.x) > 60 or absf(global_position.z) > 60:
		game.recover_enemy(self)
		return
	if is_on_floor() and game.level.is_walkable_point(global_position):
		last_safe_position = global_position
	attack_timer -= delta
	path_timer -= delta
	voice_timer -= delta
	flinch = maxf(flinch - delta * 4.0, 0)
	var target_player = game.target_for_enemy(global_position)
	if target_player == null: return
	var target: Vector3 = target_player.global_position
	var distance := global_position.distance_to(target)
	skill_timer -= delta
	if kind == 4:
		_boss_skills(delta, target, distance)
	elif kind == 5 and skill_timer <= 0 and distance < 27:
		var sight := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.45, target + Vector3.UP * 1.2, 1)
		if get_world_3d().direct_space_state.intersect_ray(sight).is_empty() and game.try_acid_attack(self, target, true):
			game.sound.positional("growl", global_position, -9)
			skill_timer = 7.5
			flinch = 0.7
		else:
			skill_timer = 1.0
	if path_timer <= 0:
		route = game.level.path(global_position, target)
		crowd_force = game.core.separation(global_position, 1.1 * size_factor)
		path_timer = randf_range(0.55, 1.0) if distance > 12 else 0.32
	if voice_timer <= 0:
		if distance < 17:
			game.sound.positional("growl", global_position, -14 if kind != 2 else -5)
		voice_timer = randf_range(5, 11)
	var direction := Vector3.ZERO
	if distance < 3.3:
		direction = target - global_position
	elif not route.is_empty():
		if global_position.distance_to(route[0]) < 0.7:
			route.remove_at(0)
		if not route.is_empty():
			direction = route[0] - global_position
	direction.y = 0
	direction = direction.normalized()
	if distance > 1.1 * size_factor:
		var movement: Vector3 = game.core.steer(direction + crowd_force * 1.6, speed, flinch, knockback)
		velocity.x = movement.x
		velocity.z = movement.z
		if kind == 5 and distance < 14:
			velocity.x *= 0.15
			velocity.z *= 0.15
	else:
		velocity.x = knockback.x + crowd_force.x * speed * 0.65
		velocity.z = knockback.z + crowd_force.z * speed * 0.65
		if attack_timer <= 0:
			target_player.take_damage(damage, global_position)
			attack_timer = 1.25 if kind != 1 else 0.85
			flinch = 0.65
	if charge_windup > 0:
		velocity.x = 0
		velocity.z = 0
	elif charge_time > 0:
		velocity.x = charge_direction.x * 16
		velocity.z = charge_direction.z * 16
		if distance < 3.5:
			target_player.take_damage(42, global_position)
			charge_time = 0
	velocity.y -= 24 * delta
	knockback = knockback.move_toward(Vector3.ZERO, delta * 12)
	move_and_slide()
	if direction.length_squared() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), minf(delta * 7, 1))
	phase += delta * speed * 3.0
	model.position.y = absf(sin(phase)) * 0.05
	model.rotation.z = sin(phase * 0.5) * 0.045
	model.rotation.x = -flinch * 0.34
	if attack_timer > 0.75:
		_play_anim("attack", 1.3)
	elif charge_time > 0 or kind == 1:
		_play_anim("run", 1.25)
	else:
		_play_anim(walk_clip, 0.82 if kind == 4 else 1.0)
	if kind == 4:
		weakpoint.scale = Vector3.ONE * (1 + sin(phase * 1.8) * 0.15)

func _boss_skills(delta: float, target: Vector3, distance: float) -> void:
	if hp < max_hp * 0.5 and not enraged:
		enraged = true
		speed *= 1.4
		skill_timer = 0.5
		game.hud.wave_banner(monster_name + " · 狂暴", "技能频率提升  //  射击头部或发光核心")
		game.sound.play("growl", -2, 0.55)
	charge_time = maxf(charge_time - delta, 0)
	if charge_windup > 0:
		charge_windup -= delta
		if charge_windup <= 0:
			charge_time = 0.9
		return
	if skill_timer > 0 or charge_time > 0:
		return
	var action: String = game.core.boss_action(game.stage_index, distance, skill_step, enraged)
	skill_step += 1
	skill_timer = 4.2 if enraged else 6.8
	game.sound.positional("growl", global_position, 0)
	match action:
		"smash":
			game.create_hazard(global_position, 7.0, "smash", 1.35 if not enraged else 1.1, 0.2, get_instance_id())
			game.hud.toast("BOSS 砸地  ·  离开红圈或跳跃", Color(1, 0.38, 0.18), 2)
			flinch = 1
		"charge":
			charge_direction = (target - global_position).normalized()
			charge_direction.y = 0
			charge_windup = 1.1
			game.fx.tracer(global_position + Vector3.UP * 0.2, target + Vector3.UP * 0.2, Color(1, 0.1, 0.04), true)
			game.hud.toast("BOSS 冲锋蓄力  ·  横向闪避", Color(1, 0.38, 0.18), 2)
		"acid":
			game.try_acid_attack(self, target, false)
		"summon":
			for i in (8 if enraged else 5):
				var a := i * TAU / 8
				game._spawn_add(global_position + Vector3(sin(a), 0, cos(a)) * 6, 1 if i % 2 == 0 else 0)
			game.hud.toast("BOSS 正在召唤尸群", Color(1, 0.38, 0.18), 2)

func take_hit(amount: float, hit_pos: Vector3, direction: Vector3, force: float) -> Dictionary:
	if dead or network_proxy:
		return {"head": false, "killed": false}
	var head := hit_pos.y - global_position.y > 1.5 * size_factor
	if kind == 4:
		var local_hit := model.to_local(hit_pos)
		head = head or (absf(local_hit.x) < 0.26 and local_hit.y > 1.0 and local_hit.y < 1.43)
	var dealt: float = game.core.hit_damage(kind, amount, head)
	if kind == 4:
		dealt *= game.core.reactor_damage_factor(game.stage_index)
	hp -= dealt
	flinch = 0.35 if kind == 4 else 1.0
	knockback += direction * force / size_factor
	game.fx.burst(hit_pos, -direction, Color(0.58, 0.07, 0.035), 9 if head else 6, 3.5)
	if health_label:
		health_label.text = "屠戮者  %d / %d" % [maxi(int(hp), 0), int(max_hp)]
	if hp <= 0:
		dead = true
		collision_layer = 0
		game.fx.retain_corpse(model, animation, global_position)
		game.zombie_killed(self, head)
		queue_free()
	return {"head": head, "killed": dead}

func _process(_delta: float) -> void:
	if network_proxy and not dead:
		_play_anim("run" if kind == 1 else walk_clip, 1.25 if kind == 1 else 1.0)
