extends RefCounted
## Host simulates trajectories and exposure; clients display snapshot replicas.
const GrenadeModel = preload("res://scripts/grenade_model.gd")
var game
var items: Dictionary = {}
var next_id := 1
var detonations := 0
const SMOKE_SECONDS := 25.0
const THROW_ARC_DEGREES := 18.0

func _init(owner) -> void:
	game = owner

func clear() -> void:
	for item in items.values():
		if is_instance_valid(item.node): item.node.queue_free()
	items.clear()

func _visual(kind: int, smoke: bool = false) -> Node3D:
	if smoke:
		var smoke_node := Node3D.new()
		game.world.add_child(smoke_node)
		for i in 12:
			var mat := ShaderMaterial.new()
			mat.shader = preload("res://shaders/grenade_smoke.gdshader")
			mat.set_shader_parameter("seed", float(i) * 3.71)
			var angle := float(i) * TAU / 12
			var puff := Forge.sphere(smoke_node, Vector3(cos(angle) * 2.3, sin(float(i) * 2.1) * 0.8, sin(angle) * 2.3), 2.3, mat, 12, 8)
			puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return smoke_node
	return GrenadeModel.build(game.world, kind, false)

func throw_grenade(p, kind: int, yaw: float, pitch: float, soft: bool = false) -> void:
	# Pitch-dependent release, capped at 750 GoldSrc units/s. Lift the neutral
	# arc slightly for readability while retaining a low underhand trajectory.
	var degrees := rad_to_deg(clampf(pitch, -1.5, 1.5))
	var mapped := (8.0 if soft else THROW_ARC_DEGREES) + degrees * (80.0 / 90.0 if degrees >= 0 else 100.0 / 90.0)
	var direction := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, deg_to_rad(mapped)) * Vector3.FORWARD
	var origin: Vector3 = p.global_position + Vector3.UP * (0.72 if p.crouching else 1.55)
	var start: Vector3 = origin + direction * 0.5
	var hit: Dictionary = game.world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin, start, 1))
	if not hit.is_empty(): start = hit.position + hit.normal * 0.15
	var p_vel: Vector3 = p.velocity
	var throw_vel: Vector3 = direction * minf((90.0 + mapped) * 6.0, 750.0) / 40.0 * (0.4 if soft else 1.0) + p_vel
	var rng: RandomNumberGenerator = game.rng if is_instance_valid(game) and "rng" in game else RandomNumberGenerator.new()
	var spin := Vector3(rng.randf_range(6.0, 12.0), rng.randf_range(-3.0, 3.0), rng.randf_range(4.0, 8.0))
	var item := {
		"node": _visual(kind),
		"owner": p.peer_id,
		"kind": kind,
		"pos": start,
		"vel": throw_vel,
		"rot": Vector3.ZERO,
		"spin": spin,
		"life": 1.5,
		"smoke": false,
		"on_ground": false,
		"bounces": 0
	}
	item.node.position = start
	item.node.scale = Vector3.ONE * 1.25
	items[next_id] = item
	next_id += 1

func process(delta: float) -> void:
	# Substeps keep fast grenades from tunneling through thin cover.
	var simulation_time := minf(delta, 0.5)
	var steps := maxi(1, ceili(simulation_time / 0.016))
	var dt := simulation_time / steps
	for id in items.keys():
		var item: Dictionary = items[id]
		item.life -= delta
		for step in steps:
			if item.smoke: continue
			if item.on_ground:
				var support: Dictionary = game.world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(item.pos, item.pos + Vector3.DOWN * 0.16, 1))
				if not support.is_empty() and support.normal.y > 0.65:
					item.vel.y = 0
					item.vel = item.vel.move_toward(Vector3.ZERO, 4.8 * dt)
					var rolling_end: Vector3 = item.pos + item.vel * dt
					var obstacle: Dictionary = game.world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(item.pos, rolling_end, 1))
					if obstacle.is_empty(): item.pos = rolling_end
					else: item.vel = Vector3.ZERO
					if item.vel.length() > 0.05: item.rot += support.normal.cross(item.vel.normalized()) * item.vel.length() / 0.08 * dt
					continue
				item.on_ground = false
			item.vel += Vector3.DOWN * 10.0 * dt
			item.vel *= (1.0 - 0.02 * dt)
			var end: Vector3 = item.pos + item.vel * dt
			var hit: Dictionary = game.world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(item.pos, end, 1))
			if hit.is_empty():
				item.pos = end
				item.on_ground = false
				item.rot += item.spin * dt
			else:
				var normal: Vector3 = hit.normal
				var v_normal: float = item.vel.dot(normal)
				var v_tangent: Vector3 = item.vel - normal * v_normal
				item.pos = hit.position + normal * 0.08
				if absf(v_normal) > (1.8 if normal.y > 0.65 else 1.2):
					var restitution: float = 0.45
					item.vel = v_tangent * 0.82 - normal * (v_normal * restitution)
					var rng: RandomNumberGenerator = game.rng if is_instance_valid(game) and "rng" in game else RandomNumberGenerator.new()
					item.spin = Vector3(rng.randf_range(-8.0, 8.0), rng.randf_range(-6.0, 6.0), rng.randf_range(-8.0, 8.0))
					item.bounces += 1
					if is_instance_valid(game.sound):
						game.sound.positional("metal_hit", item.pos, -12)
				else:
					item.on_ground = true
					item.vel = v_tangent
					var friction: float = 4.8 * dt
					item.vel = item.vel.move_toward(Vector3.ZERO, friction)
					var roll_speed: float = item.vel.length()
					if roll_speed > 0.05:
						var roll_axis := normal.cross(item.vel.normalized())
						item.rot += roll_axis * (roll_speed / 0.08) * dt
		item.node.position = item.pos
		item.node.rotation = item.rot
		if item.life <= 0:
			if not item.smoke:
				if item.kind == 2 and (not item.on_ground or item.vel.length() > 0.2):
					item.life = 0.2
					continue
				_detonate(item)
				if item.kind == 2:
					item.node.queue_free()
					item.node = _visual(2, true)
					item.pos.y = maxf(item.pos.y, 1.8)
					item.node.position = item.pos
					item.smoke = true
					item.life = SMOKE_SECONDS
					continue
			item.node.queue_free()
			items.erase(id)
		elif item.smoke:
			_update_smoke(item)

func _update_smoke(item: Dictionary) -> void:
	var age: float = SMOKE_SECONDS - float(item.life)
	item.node.scale = Vector3.ONE * clampf(age / 1.2, 0.08, 1.0)
	var density: float = minf(age / 0.8, 1.0) * clampf(float(item.life) / 4.0, 0, 1)
	for puff in item.node.get_children(): puff.material_override.set_shader_parameter("density", density)

func exposed(origin: Vector3, target: Vector3) -> bool:
	return game.world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin, target, 1)).is_empty()

func _detonate(item: Dictionary) -> void:
	detonations += 1
	var data := {"kind": item.kind, "pos": game.lan.vec(item.pos)}
	var transmission_by_peer: Dictionary = {}
	if int(item.kind) == 0:
		# Measure before the same explosion destroys movable cover, so its
		# absorbed energy is not accidentally restored by removing its collider.
		for p in game.lan.players.values():
			if p.life == "alive": transmission_by_peer[p.peer_id] = game.battle.blast_transmission(item.pos, p.global_position + Vector3.UP * 1.4)
	if int(item.kind) == 0: data["scars"] = game.battle.explosion(item.pos)
	game.lan.net.send_event("detonate", JSON.stringify(data))
	show_detonation(data)
	if item.kind == 2: return
	for p in game.lan.players.values():
		if p.life != "alive": continue
		var target: Vector3 = p.global_position + Vector3.UP * 1.4
		var distance: float = item.pos.distance_to(target)
		if distance > (9.0 if item.kind == 0 else 18.0): continue
		if item.kind == 0:
			var transmission: float = transmission_by_peer.get(p.peer_id, 0.0)
			if transmission > 0:
				game.lan.hit_player(int(item.owner), p.peer_id, 150 * (1 - distance / 9.0) * transmission, false)
				var knockback: Vector3 = (target - item.pos).normalized()
				p.velocity += (knockback + Vector3.UP * 0.4).normalized() * (16.0 * (1.0 - distance / 9.0) * transmission)
		else:
			if not exposed(item.pos, target): continue
			var facing: float = (-p.camera.global_basis.z).dot((item.pos - target).normalized())
			game.core.pvp_flash(p.peer_id, (3.5 if facing > 0.2 else 0.7) * (1 - distance / 20.0))
	game.lan.sync_stats()

func show_detonation(data: Dictionary) -> void:
	if not is_instance_valid(game.fx): return
	var pos: Vector3 = game.lan.unvec(data.pos)
	if int(data.kind) == 0:
		for scar in data.get("scars", []): game.battle.apply_mark(scar)
		game.fx.explosion(pos)
		game.sound.positional("explosion", pos, -2)
	else:
		game.fx.puff(pos, Vector3.UP, Color(0.8, 0.84, 0.86), 0.9, 1)
		game.sound.positional("flash_pop" if int(data.kind) == 1 else "smoke_hiss", pos, -6)

func snapshot() -> Array:
	var result: Array = []
	for id in items:
		var item: Dictionary = items[id]
		result.append({"id": id, "kind": item.kind, "owner": item.owner, "pos": game.lan.vec(item.pos), "vel": game.lan.vec(item.vel), "life": item.life, "smoke": item.smoke})
	return result

func apply_snapshot(data: Array) -> void:
	var present: Dictionary = {}
	for entry in data:
		var id := int(entry.id)
		present[id] = true
		if items.has(id) and bool(items[id].smoke) != bool(entry.smoke):
			items[id].node.queue_free()
			items.erase(id)
		if not items.has(id): items[id] = {"node": _visual(int(entry.kind), bool(entry.smoke))}
		var item: Dictionary = items[id]
		item.merge(entry, true)
		item.pos = game.lan.unvec(entry.pos)
		item.vel = game.lan.unvec(entry.vel)
		item.node.position = item.pos
	for id in items.keys():
		if not present.has(id): items[id].node.queue_free(); items.erase(id)

func process_visuals(delta: float) -> void:
	for item in items.values():
		if item.smoke:
			item.life = maxf(0, float(item.life) - delta)
			_update_smoke(item)
		else:
			item.pos += item.vel * delta
			item.node.position = item.pos

func smoke_at(pos: Vector3) -> bool:
	for item in items.values():
		if item.smoke and item.pos.distance_to(pos) < 4.5: return true
	return false

func smoke_blocks(origin: Vector3, target: Vector3) -> bool:
	var segment := target - origin
	var length_sq := segment.length_squared()
	for item in items.values():
		if not item.smoke or float(item.life) < 0.4: continue
		var t := clampf((item.pos - origin).dot(segment) / maxf(length_sq, 0.001), 0, 1)
		if item.pos.distance_to(origin + segment * t) < 4.5: return true
	return false
