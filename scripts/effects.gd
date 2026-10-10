extends Node3D

var items: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
var game
const MAX_DEBRIS := 160
var tracer_mesh: BoxMesh

func _ready() -> void:
	rng.randomize()
	tracer_mesh = BoxMesh.new()
	tracer_mesh.size = Vector3(0.013, 0.013, 1.0)

func burst(pos: Vector3, direction: Vector3, color: Color, amount: int = 7, force: float = 3.0) -> void:
	for i in mini(amount, maxi(MAX_DEBRIS - items.size(), 0)):
		var size := rng.randf_range(0.035, 0.095)
		var visual := Forge.box(self, pos, Vector3.ONE * size, Forge.material(color))
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.rotation = Vector3(rng.randf() * 6, rng.randf() * 6, 0)
		var vel := direction * rng.randf_range(0.4, force) + Vector3(rng.randf_range(-1.4, 1.4), rng.randf_range(0.5, 3.2), rng.randf_range(-1.4, 1.4))
		items.append({"node": visual, "vel": vel, "life": rng.randf_range(0.28, 0.7), "gravity": 7.0})

func tracer(start: Vector3, end: Vector3, color: Color = Color(1.0, 0.66, 0.24), beam: bool = false) -> void:
	var distance := start.distance_to(end)
	if distance < 0.1:
		return
	var visual := MeshInstance3D.new()
	visual.mesh = tracer_mesh
	visual.material_override = Forge.material(color, 0, 3 if beam else 1.8)
	add_child(visual)
	var length := distance if beam else minf(distance, 1.2)
	var direction := (end - start).normalized()
	visual.position = start + direction * length * 0.5
	visual.look_at(end)
	visual.scale.z = length
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var item := {"node": visual, "vel": Vector3.ZERO, "life": 0.075 if beam else distance / 600.0 + 0.025, "gravity": 0.0, "fresh": true}
	if not beam:
		item["trail"] = true
		item["start"] = start
		item["direction"] = direction
		item["distance"] = distance
		item["travelled"] = length
	items.append(item)

func casing(pos: Vector3, right: Vector3) -> void:
	if items.size() >= MAX_DEBRIS: return
	var visual := Forge.box(self, pos, Vector3(0.028, 0.028, 0.09), Forge.material(Color(0.7, 0.5, 0.18), 0.7))
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	items.append({"node": visual, "vel": right * rng.randf_range(1.5, 3.0) + Vector3.UP * 2.2, "life": 1.5, "gravity": 9.0})

func corpse(pos: Vector3, color: Color, scale_factor: float, direction: Vector3) -> void:
	var body := Node3D.new()
	add_child(body)
	body.position = pos + Vector3(0, 0.25, 0)
	body.rotation.y = atan2(direction.x, direction.z)
	body.rotation.x = PI / 2
	Forge.box(body, Vector3(0, 0.0, 0), Vector3(0.58, 0.75, 0.35) * scale_factor, Forge.material(color))
	Forge.box(body, Vector3(0, 0.56, 0), Vector3.ONE * 0.35 * scale_factor, Forge.material(Color(0.28, 0.33, 0.27)))
	Forge.box(body, Vector3(-0.18, -0.66, 0), Vector3(0.22, 0.65, 0.24) * scale_factor, Forge.material(Color(0.11, 0.15, 0.16)))
	Forge.box(body, Vector3(0.18, -0.66, 0), Vector3(0.22, 0.65, 0.24) * scale_factor, Forge.material(Color(0.11, 0.15, 0.16)))
	items.append({"node": body, "vel": Vector3.ZERO, "life": 6.0, "gravity": 0.0})
	var stain := Forge.cylinder(self, Vector3(pos.x, 0.015, pos.z), rng.randf_range(0.4, 0.75), 0.008, Forge.material(Color(0.19, 0.035, 0.03)))
	items.append({"node": stain, "vel": Vector3.ZERO, "life": 18.0, "gravity": 0.0})

func retain_corpse(model: Node3D, animation: AnimationPlayer, pos: Vector3) -> void:
	var corpses := 0
	for item in items:
		if item.get("corpse", false):
			corpses += 1
	if corpses >= 14:
		for i in items.size():
			if items[i].get("corpse", false):
				items[i].node.queue_free()
				items.remove_at(i)
				break
	var ground := _corpse_ground(pos)
	var body := Node3D.new()
	add_child(body)
	body.global_position = pos
	body.rotation.y = model.global_rotation.y
	model.reparent(body, true)
	# Discard walking bob/flinch on the model, keeping its authored scale.
	model.position = Vector3.ZERO
	model.rotation = Vector3.ZERO
	var settle_after := 0.45
	if animation and animation.has_animation("death"):
		animation.speed_scale = 1
		animation.get_animation("death").loop_mode = Animation.LOOP_NONE
		animation.play("death", 0.08)
		settle_after = animation.get_animation("death").length + 0.08
	else:
		if animation:
			animation.pause()
		var tween := create_tween()
		tween.tween_property(model, "rotation:x", -PI / 2, 0.45)
	items.append({"node": body, "model": model, "animation": animation, "vel": Vector3.ZERO, "life": 7.0, "gravity": 0.0, "corpse": true, "ground": ground, "settle_after": settle_after, "settled": false, "fall_speed": 0.0})
	var stain := Forge.cylinder(self, ground.position + ground.normal * 0.015, rng.randf_range(0.4, 0.7), 0.008, Forge.material(Color(0.19, 0.035, 0.03)))
	stain.basis = Basis(Quaternion(Vector3.UP, ground.normal))
	items.append({"node": stain, "vel": Vector3.ZERO, "life": 15.0, "gravity": 0.0})

func _corpse_ground(pos: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.5, pos + Vector3.DOWN * 100, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty(): return {"position": hit.position, "normal": hit.normal.normalized()}
	var ground: Vector3 = game.level.ground_point(pos)
	return {"position": ground, "normal": Basis(Vector3.RIGHT, game.level.ground_angle(pos)) * Vector3.UP}

func corpse_clearance(model: Node3D, ground: Dictionary) -> float:
	var lowest := INF
	var headless := DisplayServer.get_name() == "headless"
	if headless:
		# The dummy renderer never registers skin RIDs. Server-only corpses
		# use a cheap skeleton envelope; graphical peers measure deformed meshes.
		for skeleton in model.find_children("*", "Skeleton3D", true, false):
			for bone in skeleton.get_bone_count():
				var point: Vector3 = skeleton.to_global(skeleton.get_bone_global_pose(bone).origin)
				lowest = minf(lowest, (point - ground.position).dot(ground.normal) - 0.12 * model.scale.y)
	for visual in model.find_children("*", "MeshInstance3D", true, false):
		if headless and visual.skin: continue
		# Imported custom_aabb is a standing culling envelope, not a corpse's
		# deformed bounds. Bake once after death to measure the actual pose.
		var mesh: Mesh = visual.bake_mesh_from_current_skeleton_pose() if visual.skin else visual.mesh
		if mesh == null: continue
		if not visual.skin:
			# Bone-mounted helmets/core ornaments can rotate arbitrarily; AABB
			# corners would create a false underside and leave the body hovering.
			for surface in mesh.get_surface_count():
				var arrays: Array = mesh.surface_get_arrays(surface)
				for vertex in arrays[Mesh.ARRAY_VERTEX]:
					var point: Vector3 = visual.to_global(vertex)
					lowest = minf(lowest, (point - ground.position).dot(ground.normal))
			continue
		var bounds := mesh.get_aabb()
		for corner in 8:
			var point: Vector3 = visual.to_global(bounds.get_endpoint(corner))
			lowest = minf(lowest, (point - ground.position).dot(ground.normal))
	return lowest

func _update_corpse(item: Dictionary, delta: float) -> void:
	if item.settled: return
	item.settle_after -= delta
	item.fall_speed += 24 * delta
	item.node.global_position.y = maxf(item.ground.position.y, item.node.global_position.y - item.fall_speed * delta)
	if item.settle_after > 0 or item.node.global_position.y > item.ground.position.y + 0.001: return
	if not item.get("prepared", false):
		if is_instance_valid(item.animation):
			if item.animation.has_animation("death"):
				item.animation.seek(item.animation.get_animation("death").length, true)
			item.animation.pause()
		if not is_instance_valid(item.animation) or not item.animation.has_animation("death"):
			item.model.rotation.x = -PI / 2
		# Let Skeleton3D and BoneAttachment3D propagate the final pose before
		# measuring; settling on the last tween frame used stale attachment bounds.
		item.node.basis = Basis(Quaternion(Vector3.UP, item.ground.normal)) * item.node.basis
		item.prepared = true
		return
	var clearance := corpse_clearance(item.model, item.ground)
	if is_finite(clearance): item.node.global_position += item.ground.normal * (0.015 - clearance)
	item.settled = true

func _process(delta: float) -> void:
	for i in range(items.size() - 1, -1, -1):
		var item: Dictionary = items[i]
		if item.get("fresh", false):
			item.fresh = false
			continue
		item.life -= delta
		if item.life <= 0:
			item.node.queue_free()
			items.remove_at(i)
			continue
		if item.get("corpse", false):
			_update_corpse(item, delta)
			continue
		if item.get("trail", false):
			item.travelled = minf(item.travelled + 600 * delta, item.distance)
			var length := minf(1.2, item.travelled)
			item.node.position = item.start + item.direction * (item.travelled - length * 0.5)
			continue
		item.vel.y -= item.gravity * delta
		item.node.position += item.vel * delta
		if item.gravity > 0:
			item.node.rotation += Vector3(3, 5, 2) * delta
			if item.node.position.y < 0.04:
				item.node.position.y = 0.04
				item.vel *= 0.35
				item.vel.y = absf(item.vel.y)
