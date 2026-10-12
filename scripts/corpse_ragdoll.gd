extends Node3D
## World-unit rigid bodies drive the imported centimetre-scale skeleton.
## Only dead actors use this rig; no player, damage or navigation collision.

var game
var model: Node3D
var skeleton: Skeleton3D
var parts: Array[Dictionary] = []
var joints: Array[Joint3D] = []
var ground: Dictionary
var age := 0.0
var settled := false
var released := false
var correction := Vector3.ZERO
var correction_applied := Vector3.ZERO
var settling_time := 0.0
static var radius_profiles: Dictionary = {}

func setup(actor_model: Node3D, animation: AnimationPlayer, pos: Vector3, impulse: Vector3, hit_point: Vector3) -> void:
	model = actor_model
	global_position = pos
	model.reparent(self, true)
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	skeleton = skeletons[0] if not skeletons.is_empty() else null
	assert(skeleton != null, "Corpse model must preserve its skeleton")
	ground = game.fx._corpse_ground(pos)
	if animation: animation.pause()
	var city := _bone("Hips") >= 0
	var chains: Array = [
		["Hips", "Spine", 0.12, 12.0], ["Spine", "Neck", 0.14, 15.0], ["Neck", "HeadTop_End", 0.085, 3.0],
		["LeftArm", "LeftForeArm", 0.065, 2.4], ["LeftForeArm", "LeftHand", 0.050, 1.6], ["LeftHand", "LeftHandMiddle3", 0.043, 0.5],
		["RightArm", "RightForeArm", 0.065, 2.4], ["RightForeArm", "RightHand", 0.050, 1.6], ["RightHand", "RightHandMiddle3", 0.043, 0.5],
		["LeftUpLeg", "LeftLeg", 0.075, 5.0], ["LeftLeg", "LeftFoot", 0.060, 3.5], ["LeftFoot", "LeftToe_End", 0.045, 0.8],
		["RightUpLeg", "RightLeg", 0.075, 5.0], ["RightLeg", "RightFoot", 0.060, 3.5], ["RightFoot", "RightToe_End", 0.045, 0.8]
	] if city else [
		["joint1", "joint2", 0.13, 14.0], ["joint2", "joint4", 0.15, 17.0], ["joint4", "joint16", 0.09, 3.5],
		["joint14", "joint11", 0.07, 2.6], ["joint11", "joint12", 0.055, 1.8], ["joint12", "joint23", 0.048, 0.6],
		["joint14.001", "joint11.001", 0.07, 2.6], ["joint11.001", "joint12.001", 0.055, 1.8], ["joint12.001", "joint23.003", 0.048, 0.6],
		["joint5", "joint6", 0.080, 5.5], ["joint6", "joint7", 0.060, 3.8], ["joint7", "joint9", 0.050, 0.8],
		["joint64", "joint6.001", 0.080, 5.5], ["joint6.001", "joint7.001", 0.060, 3.8], ["joint7.001", "joint9.001", 0.050, 0.8]
	]
	var scale_factor := model.global_basis.get_scale().y
	var material := PhysicsMaterial.new()
	material.friction = 0.95
	material.bounce = 0.0
	var bone_parts: Dictionary = {}
	var transforms: Dictionary = {}
	for chain in chains:
		var bone := _bone(chain[0])
		var end := _bone(chain[1])
		if bone < 0 or end < 0: continue
		transforms[bone] = skeleton.global_transform * skeleton.get_bone_global_pose(bone)
		var start: Vector3 = transforms[bone].origin
		var finish: Vector3 = skeleton.to_global(skeleton.get_bone_global_pose(end).origin)
		var axis := (finish - start).normalized()
		if axis.length_squared() < 0.1: axis = Vector3.UP
		var body := RigidBody3D.new()
		body.name = "Part%d" % parts.size()
		body.mass = float(chain[3]) * scale_factor
		body.collision_layer = 8
		body.collision_mask = 1
		body.physics_material_override = material
		body.gravity_scale = 1.8
		body.linear_damp = 2.6
		body.angular_damp = 3.5
		body.continuous_cd = true
		body.freeze = true
		add_child(body)
		body.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, axis)), (start + finish) * 0.5)
		var collision := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = float(chain[2]) * scale_factor
		capsule.height = start.distance_to(finish) + capsule.radius * 2.0
		collision.shape = capsule
		body.add_child(collision)
		body.linear_velocity = impulse.limit_length(6.0) * 0.20
		bone_parts[bone] = parts.size()
		parts.append({"bone": bone, "body": body, "shape": capsule, "start": start, "end": finish, "offset": body.global_transform.affine_inverse() * transforms[bone]})
	_fit_collision_shapes(city, scale_factor)
	for part in parts:
		part.body.freeze = false
		part.body.linear_velocity = impulse.limit_length(6.0) * 0.20
	for part in parts:
		var parent: int = skeleton.get_bone_parent(part.bone)
		while parent >= 0 and not bone_parts.has(parent): parent = skeleton.get_bone_parent(parent)
		if parent < 0: continue
		var joint := PinJoint3D.new()
		add_child(joint)
		joint.global_position = transforms[part.bone].origin
		joint.node_a = joint.get_path_to(parts[bone_parts[parent]].body)
		joint.node_b = joint.get_path_to(part.body)
		joint.set("params/bias", 0.45)
		joint.set("params/damping", 1.0)
		joints.append(joint)
	if not parts.is_empty():
		var closest := 1 if parts.size() > 1 else 0
		var distance := INF
		if hit_point != Vector3.ZERO:
			for i in parts.size():
				var candidate: float = parts[i].body.global_position.distance_squared_to(hit_point)
				if candidate < distance: distance = candidate; closest = i
		var hit_body: RigidBody3D = parts[closest].body
		hit_body.apply_central_impulse(impulse.limit_length(6) * hit_body.mass * 0.25)
		parts[0].body.angular_velocity = Vector3(1.1, 0.2, -0.5)
	for visual in model.find_children("*", "MeshInstance3D", true, false):
		visual.custom_aabb = (visual.global_transform.affine_inverse() * global_transform) * AABB(Vector3(-4, -4, -4) * scale_factor, Vector3(8, 8, 8) * scale_factor)

func _bone(hint: String) -> int:
	if not skeleton: return -1
	for i in skeleton.get_bone_count():
		var name: String = skeleton.get_bone_name(i)
		if name == hint or name.ends_with("_" + hint): return i
	return -1

func _apply_pose() -> void:
	var inverse := skeleton.global_transform.affine_inverse()
	for part in parts:
		skeleton.set_bone_global_pose_override(part.bone, inverse * part.body.global_transform * part.offset, 1.0, true)

func _fit_collision_shapes(city: bool, scale_factor: float) -> void:
	if DisplayServer.get_name() == "headless": return
	var key := str(city) + ":" + str(model.global_basis.get_scale().snapped(Vector3.ONE * 0.01))
	var radii: Array = []
	if radius_profiles.has(key):
		radii = radius_profiles[key]
	else:
		for part in parts: radii.append(part.shape.radius)
		for visual in model.find_children("*", "MeshInstance3D", true, false):
			if not visual.skin: continue
			var mesh: Mesh = visual.bake_mesh_from_current_skeleton_pose()
			if mesh == null: continue
			for surface in mesh.get_surface_count():
				var vertices: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
				# A bounded sample fits real flesh thickness, not a guessed joint
				# radius. Cache the profile for each asset/proportion combination.
				for index in range(0, vertices.size(), maxi(1, vertices.size() / 400)):
					var point: Vector3 = visual.to_global(vertices[index])
					var nearest := 0
					var distance := INF
					for i in parts.size():
						var axis: Vector3 = parts[i].end - parts[i].start
						var along := clampf((point - parts[i].start).dot(axis) / maxf(axis.length_squared(), 0.0001), 0, 1)
						var d: float = point.distance_squared_to(parts[i].start + axis * along)
						if d < distance: distance = d; nearest = i
					radii[nearest] = maxf(radii[nearest], sqrt(distance) + 0.014 * scale_factor)
		radius_profiles[key] = radii
	for i in parts.size():
		parts[i].shape.radius = float(radii[i])
		parts[i].shape.height = parts[i].start.distance_to(parts[i].end) + float(radii[i]) * 2.0

func _physics_process(delta: float) -> void:
	if settled: return
	age += delta
	if not released:
		_apply_pose()
		var resting := age > 1.4
		for part in parts:
			resting = resting and part.body.linear_velocity.length_squared() < 0.03 and part.body.angular_velocity.length_squared() < 0.08
		if resting or age > 2.8: release_physics()
	elif settling_time > 0:
		settling_time = maxf(settling_time - delta, 0)
		var weight := 1.0 - settling_time / 0.22
		var target := correction * (weight * weight * (3 - 2 * weight))
		global_position += target - correction_applied
		correction_applied = target
		if settling_time == 0: settled = true
	else:
		# Bone attachments update after the final physics pose. Measure next tick.
		var clearance: float = game.fx.corpse_clearance(model, ground)
		if is_finite(clearance): correction = ground.normal * clampf(0.006 - clearance, -1.5 * model.global_basis.get_scale().y, 1.5 * model.global_basis.get_scale().y)
		settling_time = 0.22

func release_physics() -> void:
	if released: return
	_apply_pose()
	if not parts.is_empty(): ground = game.fx._corpse_ground(parts[0].body.global_position)
	for joint in joints: joint.queue_free()
	for part in parts:
		part.body.freeze = true
		part.body.queue_free()
	released = true
