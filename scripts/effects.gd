extends Node3D

var items: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
var game
const MAX_DEBRIS := 160
var tracer_mesh: BoxMesh
const CorpseScript = preload("res://scripts/corpse_ragdoll.gd")

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

func puff(pos: Vector3, direction: Vector3, color: Color, size: float, life: float) -> void:
	if items.size() >= MAX_DEBRIS: return
	var node := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	node.mesh = quad
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/dust_puff.gdshader")
	mat.set_shader_parameter("tint", Color(color.r, color.g, color.b, 0.6))
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	node.position = pos
	node.scale = Vector3.ONE * size
	items.append({"node": node, "vel": direction * 0.7 + Vector3.UP * 0.4, "life": life, "total": life, "gravity": 0.0, "puff": true, "size": size})

func explosion(pos: Vector3) -> void:
	burst(pos, Vector3.UP, Color(0.31, 0.25, 0.18), 24, 9)
	for i in 10:
		var direction := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.15, 1), rng.randf_range(-1, 1)).normalized()
		puff(pos + direction * 0.3, direction * 3, Color(0.19, 0.17, 0.14), rng.randf_range(0.8, 1.5), rng.randf_range(1.8, 3.4))
	var glow := Forge.sphere(self, pos, 0.7, Forge.material(Color(1, 0.53, 0.14), 0, 4))
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	items.append({"node": glow, "vel": Vector3.ZERO, "life": 0.12, "gravity": 0.0, "fresh": true})
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = Color(1, 0.55, 0.22)
	light.light_energy = 5
	light.omni_range = 13
	add_child(light)
	items.append({"node": light, "vel": Vector3.ZERO, "life": 0.16, "gravity": 0.0, "fresh": true})
	if is_instance_valid(game.player):
		var distance: float = game.player.camera.global_position.distance_to(pos)
		if distance < 22:
			var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(pos, game.player.camera.global_position, 1))
			game.player.trauma = maxf(game.player.trauma, (1 - distance / 22) * (0.9 if hit.is_empty() else 0.25))

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

func retain_corpse(model: Node3D, animation: AnimationPlayer, pos: Vector3, impulse: Vector3 = Vector3.ZERO, hit_point: Vector3 = Vector3.ZERO) -> void:
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
	var body = CorpseScript.new()
	body.game = game
	add_child(body)
	if impulse.length_squared() < 0.01: impulse = -model.global_basis.z.normalized() * 1.2
	body.setup(model, animation, pos, impulse, hit_point)
	items.append({"node": body, "model": model, "vel": Vector3.ZERO, "life": 7.0, "gravity": 0.0, "corpse": true, "ground": body.ground, "settled": false})
	var stain := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * rng.randf_range(0.9, 1.4)
	stain.mesh = plane
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/blood_stain.gdshader")
	material.set_shader_parameter("spread", 0.1)
	stain.material_override = material
	stain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(stain)
	stain.position = body.ground.position + body.ground.normal * 0.009
	stain.basis = Basis(Quaternion(Vector3.UP, body.ground.normal))
	items.append({"node": stain, "vel": Vector3.ZERO, "life": 15.0, "gravity": 0.0, "blood": true})

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
		# Project the actual mesh to the support plane in native SurfaceTool.
		# A rotated AABB corner is not a real contact point on a bent ragdoll.
		var rotation := Basis(Quaternion(ground.normal, Vector3.UP))
		var support := Transform3D(rotation, -(rotation * ground.position))
		for surface in mesh.get_surface_count():
			var tool := SurfaceTool.new()
			tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			tool.append_from(mesh, surface, support * visual.global_transform)
			lowest = minf(lowest, tool.commit().get_aabb().position.y)
	return lowest

func _update_corpse(item: Dictionary, _delta: float) -> void:
	item.settled = item.node.settled
	item.ground = item.node.ground

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
		if item.get("blood", false):
			item.node.material_override.set_shader_parameter("spread", clampf((15.0 - item.life) / 0.85, 0.1, 1.0))
			continue
		if item.get("puff", false):
			var progress: float = 1 - item.life / item.total
			item.node.scale = Vector3.ONE * item.size * (1 + progress * 2.2)
			item.node.material_override.set_shader_parameter("opacity", (1 - progress) * minf(progress * 8, 1))
		if item.get("trail", false):
			item.travelled = minf(item.travelled + 600 * delta, item.distance)
			var length := minf(1.2, item.travelled)
			item.node.position = item.start + item.direction * (item.travelled - length * 0.5)
			continue
		item.vel.y -= item.gravity * delta
		var end: Vector3 = item.node.position + item.vel * delta
		if item.gravity > 0:
			var query := PhysicsRayQueryParameters3D.create(item.node.global_position, to_global(end), 1)
			var hit := get_world_3d().direct_space_state.intersect_ray(query)
			if not hit.is_empty():
				if hit.normal.length_squared() < 0.5:
					item.node.queue_free()
					items.remove_at(i)
					continue
				end = to_local(hit.position + hit.normal * 0.018)
				item.vel = item.vel.bounce(hit.normal) * 0.28
				if item.vel.length() < 0.4: item.gravity = 0; item.vel = Vector3.ZERO
		item.node.position = end
		if item.gravity > 0:
			item.node.rotation += Vector3(3, 5, 2) * delta
