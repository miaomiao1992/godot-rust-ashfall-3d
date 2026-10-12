extends RefCounted
## Host simulates trajectories and exposure; clients display snapshot replicas.
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

func _visual(kind: int, smoke: bool = false) -> MeshInstance3D:
	var color: Color = [Color(0.3, 0.4, 0.18), Color(0.7, 0.78, 0.85), Color(0.4, 0.47, 0.5)][kind]
	var mat := Forge.material(color, 0.3)
	if smoke:
		mat = Forge.material(Color(0.44, 0.49, 0.52, 0.94), 0, 0, 1)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var node := Forge.sphere(game.world, Vector3.ZERO, 4.5 if smoke else 0.12, mat)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

func throw_grenade(p, kind: int, yaw: float, pitch: float) -> void:
	var direction := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, clampf(pitch, -1.5, 1.5)) * Vector3.FORWARD
	var origin: Vector3 = p.global_position + Vector3.UP * 1.55
	var start: Vector3 = origin + direction * 0.5
	var hit: Dictionary = game.world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin, start, 1))
	if not hit.is_empty(): start = hit.position + hit.normal * 0.15
	var item := {"node": _visual(kind), "owner": p.peer_id, "kind": kind, "pos": start, "vel": direction * 17 + Vector3.UP * 3, "life": 2.0, "smoke": false}
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
			item.vel += Vector3.DOWN * 16 * dt
			var end: Vector3 = item.pos + item.vel * dt
			var hit: Dictionary = game.world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(item.pos, end, 1))
			if hit.is_empty(): item.pos = end
			else:
				item.pos = hit.position + hit.normal * 0.13
				item.vel = item.vel.bounce(hit.normal) * 0.45
		item.node.position = item.pos
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
			if transmission > 0: game.lan.hit_player(int(item.owner), p.peer_id, 150 * (1 - distance / 9.0) * transmission, false)
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
