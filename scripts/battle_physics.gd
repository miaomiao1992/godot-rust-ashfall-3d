extends Node3D
## Bounded surface history and host-owned interactable scenery.
const PropScript = preload("res://scripts/physics_prop.gd")
const MAX_MARKS := 192
const MAX_FRAGMENTS := 48
var game
var props: Dictionary = {}
var marks: Dictionary = {}
var next_prop := 1
var next_mark := 1
var rng := RandomNumberGenerator.new()
var prop_breaks := 0

func authority() -> bool:
	return not game.is_lan() or game.lan.host()

func setup() -> void:
	rng.seed = 77291
	if not game.is_pvp(): return
	# Mirrored placements sit off the routes, pipe mouths, ramps and spawns.
	for side in [-1.0, 1.0]:
		for x in [-21.0, 21.0]:
			spawn_prop("crate", Vector3(x, 0.46, side * 29))
			spawn_prop("drum", Vector3(x + signf(x) * 1.7, 0.54, side * 29))
		for x in [-30.0, 30.0]:
			spawn_prop("cone", Vector3(x, 0.34, side * 40))
		for x in [-28.0, 28.0]:
			spawn_prop("drum", Vector3(x, 11.54, side * 20))
			spawn_prop("crate", Vector3(x - signf(x) * 2, 11.46, side * 20))

func spawn_prop(kind: String, pos: Vector3, id: int = 0):
	var prop = PropScript.new()
	prop.arena = self
	prop.prop_id = next_prop if id == 0 else id
	next_prop = maxi(next_prop, prop.prop_id + 1)
	prop.kind = kind
	prop.position = pos
	add_child(prop)
	props[prop.prop_id] = prop
	return prop

func surface_of(body) -> String:
	return str(body.get_meta("surface", "concrete"))

func impact(hit: Dictionary, direction: Vector3, damage: float, force: float) -> Dictionary:
	var body = hit.collider
	var surface := surface_of(body)
	var kind := 1 if surface == "metal" else 2 if surface == "wood" else 0
	var data := make_mark(hit.position, hit.normal, kind, 0.18 if kind == 0 else 0.14, 100, body)
	impact_visual(hit.position, hit.normal, surface)
	if body.has_method("shot"): body.shot(damage, hit.position, direction, force)
	return data

func make_mark(pos: Vector3, normal: Vector3, kind: int, size: float, life: float, body = null) -> Dictionary:
	var target := 0
	if is_instance_valid(body) and body.has_method("shot"):
		target = body.prop_id
		pos = body.to_local(pos)
		normal = body.global_basis.inverse() * normal
	var data := {"id": next_mark, "pos": pack(pos), "normal": pack(normal.normalized()), "kind": kind, "size": size, "life": life, "target": target, "seed": rng.randf_range(0, 1000)}
	next_mark += 1
	apply_mark(data)
	return data

func apply_mark(data: Dictionary) -> void:
	var id := int(data.id)
	if marks.has(id): return
	while marks.size() >= MAX_MARKS: remove_mark(int(marks.keys()[0]))
	if int(data.target) > 0 and not props.has(int(data.target)): return
	var parent: Node3D = props.get(int(data.target), self)
	if parent != self and parent.broken: return
	var node := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * float(data.size)
	node.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/impact_mark.gdshader")
	mat.set_shader_parameter("kind", int(data.kind))
	mat.set_shader_parameter("seed", float(data.seed))
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	var normal := unpack(data.normal).normalized()
	node.position = unpack(data.pos) + normal * (0.005 + float(id % 5) * 0.0003)
	node.basis = Basis(Quaternion(Vector3.UP, normal))
	marks[id] = {"node": node, "data": data.duplicate(true), "life": float(data.life)}

func remove_mark(id: int) -> void:
	if is_instance_valid(marks[id].node): marks[id].node.queue_free()
	marks.erase(id)

func impact_visual(pos: Vector3, normal: Vector3, surface: String) -> void:
	var color := Color(1, 0.72, 0.28) if surface == "metal" else Color(0.47, 0.30, 0.15) if surface == "wood" else Color(0.56, 0.54, 0.48)
	game.fx.burst(pos, normal, color, 5 if surface == "metal" else 4, 2.5)
	if surface == "metal": game.fx.puff(pos, normal, Color(0.53, 0.55, 0.54), 0.28, 0.5)
	else: game.fx.puff(pos, normal, color, 0.35, 0.9)
	game.sound.positional("metal_hit" if surface == "metal" else "wood_hit" if surface == "wood" else "concrete_hit", pos, -15)

func show_impact(data: Dictionary) -> void:
	var fresh := not marks.has(int(data.id))
	apply_mark(data)
	if fresh:
		var parent: Node3D = props.get(int(data.target), self)
		var pos := parent.to_global(unpack(data.pos))
		var normal := parent.global_basis * unpack(data.normal)
		impact_visual(pos, normal, "metal" if int(data.kind) == 1 else "wood" if int(data.kind) == 2 else "concrete")

func exposed(pos: Vector3, prop) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(pos, prop.global_position, 1, [prop.get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func material_exit(hit: Dictionary, direction: Vector3, limit: float, excluded: Array[RID] = []) -> Dictionary:
	if limit <= 0: return {}
	# Reverse from outside the allowed depth: thick solids leave this start
	# inside, so the ray cannot falsely report a zero-thickness transmission.
	var reverse := PhysicsRayQueryParameters3D.create(hit.position + direction * (limit + 0.012), hit.position - direction * 0.006, 1, excluded)
	var ignored: Array[RID] = excluded.duplicate()
	for candidate in 8:
		var back := get_world_3d().direct_space_state.intersect_ray(reverse)
		if back.is_empty(): return {}
		if back.collider != hit.collider:
			ignored.append(back.collider.get_rid())
			reverse.exclude = ignored
			continue
		var thickness: float = hit.position.distance_to(back.position)
		if thickness < 0.012 or thickness > limit + 0.002: return {}
		return {"pos": back.position, "normal": back.normal, "thickness": thickness}
	return {}

func bullet_exit(hit: Dictionary, direction: Vector3, weapon: int, excluded: Array[RID]) -> Dictionary:
	var surface := surface_of(hit.collider)
	var limit: float = game.core.penetration_limit(weapon, surface)
	var exit := material_exit(hit, direction, limit, excluded)
	if exit.is_empty(): return {}
	exit["factor"] = game.core.penetration_factor(weapon, surface, exit.thickness)
	return exit

func blast_transmission(origin: Vector3, target: Vector3, excluded: Array[RID] = []) -> float:
	var direction := (target - origin).normalized()
	var start := origin
	var factor := 1.0
	# Every obstruction is measured. Multiple walls compound attenuation.
	for layer in 4:
		var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start, target, 1, excluded))
		if hit.is_empty(): return factor
		var surface := surface_of(hit.collider)
		var exit := material_exit(hit, direction, game.core.blast_cover_limit(surface), excluded)
		if exit.is_empty(): return 0.0
		factor *= float(game.core.blast_cover_factor(surface, exit.thickness))
		if factor < 0.01: return 0.0
		start = exit.pos + direction * 0.018
		if (target - start).dot(direction) <= 0: return factor
	return 0.0

func explosion(pos: Vector3) -> Array:
	var scars: Array = []
	# Project onto actual nearby surfaces, including sloped ramps and roofs.
	var directions: Array[Vector3] = [Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]
	for direction in directions:
		var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.08, pos + direction * 4, 1))
		if not hit.is_empty(): scars.append(make_mark(hit.position, hit.normal, 3, 4.0 if direction == Vector3.DOWN else 2.4, 150, hit.collider))
	for prop in props.values().duplicate():
		if prop.broken: continue
		var offset: Vector3 = prop.global_position - pos
		var distance := offset.length()
		if distance > 9: continue
		var transmission := blast_transmission(pos, prop.global_position, [prop.get_rid()])
		if transmission <= 0: continue
		var falloff := (1 - distance / 9) * transmission
		prop.sleeping = false
		var blast_dir := (offset.normalized() + Vector3.UP * 0.75).normalized()
		var impulse_mag := minf(prop.mass, 24.0) * 18.0 * falloff
		var contact_offset := Vector3(rng.randf_range(-0.15, 0.15), -0.2, rng.randf_range(-0.15, 0.15))
		prop.apply_impulse(blast_dir * impulse_mag, contact_offset)
		prop.hurt(130 * falloff)
	return scars

func break_prop(prop) -> void:
	prop_breaks += 1
	var origin: Vector3 = prop.global_position
	var velocity: Vector3 = prop.linear_velocity
	prop.set_broken()
	for id in marks.keys():
		if int(marks[id].data.target) == prop.prop_id: remove_mark(id)
	for piece in 6:
		var fragments: Array = props.values().filter(func(p): return p.lifetime > 0)
		if fragments.size() >= MAX_FRAGMENTS:
			var oldest = fragments[0]
			props.erase(oldest.prop_id)
			oldest.queue_free()
		var fragment = spawn_prop("plank" if prop.kind == "crate" else "scrap", origin + Vector3(rng.randf_range(-0.3, 0.3), piece * 0.1, rng.randf_range(-0.3, 0.3)))
		fragment.lifetime = 18
		fragment.rotation = Vector3(rng.randf(), rng.randf() * TAU, rng.randf())
		fragment.linear_velocity = velocity * 0.45 + Vector3(rng.randf_range(-3, 3), rng.randf_range(2, 5), rng.randf_range(-3, 3))
		fragment.angular_velocity = Vector3(rng.randf_range(-5, 5), 3, rng.randf_range(-5, 5))
	if prop.kind == "drum":
		var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin + Vector3.UP * 0.3, origin + Vector3.DOWN * 3, 1))
		if not hit.is_empty(): make_mark(hit.position, hit.normal, 4, 2.8, 180, hit.collider)
	game.fx.puff(origin, Vector3.UP, Color(0.46, 0.38, 0.25), 1.1, 2)
	game.sound.positional("wood_break" if prop.kind == "crate" else "metal_hit", origin, -8)

func snapshot() -> Dictionary:
	var objects: Array = []
	for prop in props.values():
		objects.append({"id": prop.prop_id, "kind": prop.kind, "pos": pack(prop.position), "rot": pack(prop.rotation), "hp": prop.hp, "broken": prop.broken, "life": prop.lifetime})
	var history: Array = []
	for item in marks.values():
		var data: Dictionary = item.data.duplicate(true)
		data.life = item.life
		history.append(data)
	return {"props": objects, "marks": history, "mark_cursor": next_mark - 1}

func apply_snapshot(data: Dictionary) -> void:
	var present: Dictionary = {}
	for entry in data.get("props", []):
		var id := int(entry.id)
		present[id] = true
		var fresh := not props.has(id)
		var prop = props[id] if not fresh else spawn_prop(str(entry.kind), unpack(entry.pos), id)
		prop.target_transform = Transform3D(Basis.from_euler(unpack(entry.rot)), unpack(entry.pos))
		if fresh: prop.global_transform = prop.target_transform
		prop.hp = float(entry.hp)
		prop.lifetime = float(entry.life)
		if entry.broken and not prop.broken: prop.set_broken()
	for id in props.keys():
		if not present.has(id): props[id].queue_free(); props.erase(id)
	present.clear()
	for entry in data.get("marks", []):
		present[int(entry.id)] = true
		apply_mark(entry)
		if marks.has(int(entry.id)): marks[int(entry.id)].life = float(entry.life)
	for id in marks.keys():
		if not present.has(id) and id <= int(data.get("mark_cursor", 0)): remove_mark(id)

func _process(delta: float) -> void:
	for id in marks.keys():
		var item: Dictionary = marks[id]
		item.life -= delta
		if item.life <= 0 or not is_instance_valid(item.node): remove_mark(id); continue
		item.node.material_override.set_shader_parameter("opacity", minf(item.life / 5, 1))
	if not authority(): return
	for id in props.keys():
		var prop = props[id]
		if prop.lifetime > 0:
			prop.lifetime -= delta
			if prop.lifetime <= 0: prop.queue_free(); props.erase(id); continue
		if prop.position.y < -15: prop.queue_free(); props.erase(id)

static func pack(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

static func unpack(v: Array) -> Vector3:
	return Vector3(v[0], v[1], v[2])
