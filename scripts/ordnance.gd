extends RefCounted
## Host simulates trajectories and exposure; clients display snapshot replicas.
const GrenadeModel = preload("res://scripts/grenade_model.gd")
var game
var items: Dictionary = {}
var next_id := 1
var detonations := 0

func _init(owner) -> void:
	game = owner

func clear() -> void:
	for item in items.values():
		if is_instance_valid(item.node): item.node.queue_free()
	items.clear()

func _visual(kind: int, smoke: bool = false) -> Node3D:
	if smoke:
		var mat := Forge.material(Color(0.44, 0.49, 0.52, 0.94), 0, 0, 1)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var smoke_node := Forge.sphere(game.world, Vector3.ZERO, 4.5, mat)
		smoke_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return smoke_node
	return GrenadeModel.build(game.world, kind, false)

func throw_grenade(p, kind: int, yaw: float, pitch: float) -> void:
	var direction := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, clampf(pitch, -1.5, 1.5)) * Vector3.FORWARD
	var origin: Vector3 = p.global_position + Vector3.UP * 1.55
	var start: Vector3 = origin + direction * 0.5
	var hit: Dictionary = game.world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin, start, 1))
	if not hit.is_empty(): start = hit.position + hit.normal * 0.15
	var p_vel: Vector3 = p.velocity * 0.45 if "velocity" in p else Vector3.ZERO
	var throw_vel: Vector3 = direction * 19.5 + Vector3.UP * 3.2 + p_vel
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
		"life": 2.2,
		"smoke": false,
		"on_ground": false,
		"bounces": 0
	}
	item.node.position = start
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
			item.vel += Vector3.DOWN * 15.0 * dt
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
				if absf(v_normal) > 1.2:
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
				_detonate(item)
				if item.kind == 2:
					item.node.queue_free()
					item.node = _visual(2, true)
					item.pos.y = maxf(item.pos.y, 1.8)
					item.node.position = item.pos
					item.smoke = true
					item.life = 12.0
					continue
			item.node.queue_free()
			items.erase(id)

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
		game.sound.positional("hit", pos, -3)

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
		if not item.smoke:
			item.pos += item.vel * delta
			item.node.position = item.pos

func smoke_at(pos: Vector3) -> bool:
	for item in items.values():
		if item.smoke and item.pos.distance_to(pos) < 4.5: return true
	return false
