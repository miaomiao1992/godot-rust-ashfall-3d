extends RefCounted
## Bots produce the same movement inputs and actions as connected humans.
var game
var brains: Dictionary = {}
var tick := 0.0
var rng := RandomNumberGenerator.new()
const DIFFICULTIES := [
	{"think": 0.24, "reaction": 1.0, "error": 0.075, "turn": 2.4, "cadence": 0.28, "burst": 3, "pause": 0.85, "range": 42.0, "strafe": 0.20, "height": 1.0},
	{"think": 0.14, "reaction": 0.5, "error": 0.030, "turn": 4.8, "cadence": 0.10, "burst": 5, "pause": 0.40, "range": 65.0, "strafe": 0.40, "height": 1.2},
	{"think": 0.08, "reaction": 0.22, "error": 0.008, "turn": 8.0, "cadence": 0.02, "burst": 7, "pause": 0.16, "range": 90.0, "strafe": 0.65, "height": 1.45}
]

func settings() -> Dictionary:
	return DIFFICULTIES[clampi(game.lan.bot_difficulty, 0, 2)]

func _init(owner) -> void:
	game = owner
	rng.randomize()

func clear() -> void:
	brains.clear()

func input_for(id: int) -> Dictionary:
	return brains.get(id, {}).get("input", {"x": 0.0, "z": 0.0, "yaw": 0.0, "pitch": 0.0, "buttons": 0})

func action(id: int, brain: Dictionary, kind: String, arg: int = 0) -> void:
	brain.seq += 1
	var input: Dictionary = brain.input
	game.lan.apply_action(id, {"kind": kind, "arg": arg, "seq": brain.seq, "yaw": input.yaw, "pitch": input.pitch})

func process(delta: float) -> void:
	if not game.lan.host() or game.state != "playing": return
	tick += delta
	var skill := settings()
	for id in game.lan.fighters:
		var f: Dictionary = game.lan.fighters[id]
		if not f.get("is_bot", false) or not game.lan.players.has(id): continue
		var p = game.lan.players[id]
		if not brains.has(id): brains[id] = {"seq": 0, "think": 0.0, "observed": 0.0, "fire": 0.6, "reaction": 0.0, "target": 0, "burst": 0, "error": Vector2.ZERO, "input": {"x": 0.0, "z": 0.0, "yaw": p.rotation.y, "pitch": 0.0, "buttons": 0}, "last_pos": p.position, "stuck": 0.0}
		var brain: Dictionary = brains[id]
		brain.think -= delta
		brain.fire -= delta
		brain.observed += delta
		if p.life != "alive":
			brain.input.x = 0.0
			brain.input.z = 0.0
			brain.input.buttons = 0
			brain.reaction = 0.0
			brain.observed = 0.0
			brain.think = 0.0
			brain.burst = 0
			brain.fire = maxf(float(brain.fire), float(skill.reaction))
			continue
		if brain.think > 0: continue
		var elapsed: float = brain.observed
		brain.observed = 0.0
		brain.think = float(skill.think)
		var target = null
		var closest := INF
		for candidate in game.lan.active_players():
			if candidate.team == p.team: continue
			var distance: float = p.position.distance_squared_to(candidate.position)
			if distance < closest: closest = distance; target = candidate
		if target == null: continue
		var aim_at: Vector3 = target.global_position + Vector3.UP * (float(skill.height) * (0.52 if target.crouching else 1.0))
		var origin: Vector3 = p.camera.global_position
		var line := aim_at - origin
		var visible: bool = game.world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin, aim_at, 1)).is_empty()
		visible = visible and not game.lan.ordnance.smoke_blocks(origin, aim_at) and float(f.get("flash", 0)) < 0.2
		var distance := line.length()
		# Roof enemies are pursued via the bot's own access ramp.
		var goal: Vector3 = target.position
		if game.level.spatial_type != "cs_assault_16" and target.position.y > 9 and p.position.y < 9:
			# Routes are blue (-z) then red (+z), whereas team zero is red.
			var route: Dictionary = game.level.roof_routes[1 - p.team]
			goal = route.entry if p.position.distance_to(route.entry) > 3 and p.position.y < 0.5 else route.exit
		elif game.level.spatial_type != "cs_assault_16" and p.position.y > 9 and target.position.y < 9:
			var route: Dictionary = game.level.roof_routes[1 - p.team]
			goal = route.exit if Vector2(p.position.x - route.exit.x, p.position.z - route.exit.z).length() > 2 else route.entry
		var move := Vector3.ZERO
		var climb_input := 0.0
		if not visible or distance > 17:
			if game.level.spatial_type == "cs_assault_16":
				var path: PackedVector3Array = game.level.route(p.position, goal)
				if path.size() > 1:
					var next := path[1]
					move = Vector3(next.x - p.position.x, 0, next.z - p.position.z).normalized()
					if game.level.ladder_at(p.position).size != Vector3.ZERO and absf(next.y - p.position.y) > 0.4:
						climb_input = -signf(next.y - p.position.y)
			elif p.position.y > 0.8 or goal.y > 9:
				move = Vector3(goal.x - p.position.x, 0, goal.z - p.position.z).normalized()
			else:
				var start_cell: Vector2i = game.level.nearest_open(game.level.world_cell(p.position))
				var goal_cell: Vector2i = game.level.nearest_open(game.level.world_cell(goal))
				var path: PackedVector2Array = game.level.grid.get_point_path(start_cell, goal_cell)
				if path.size() > 1:
					var waypoint := Vector3(path[1].x, p.position.y, path[1].y)
					move = (waypoint - p.position).normalized()
		else:
			# Modest strafing and imperfect aim keep bots readable and beatable.
			move = Vector3(-line.z, 0, line.x).normalized() * sin(tick * 0.8 + float(id % 7)) * float(skill.strafe)
		if p.position.distance_to(brain.last_pos) < 0.07 and move.length() > 0.2: brain.stuck += elapsed
		else: brain.stuck = 0.0
		brain.last_pos = p.position
		var yaw := atan2(-line.x, -line.z)
		var pitch := atan2(line.y, Vector2(line.x, line.z).length())
		if brain.fire <= 0:
			brain.error = Vector2(rng.randf_range(-1, 1), rng.randf_range(-0.7, 0.7)) * float(skill.error)
		yaw = rotate_toward(p.rotation.y, yaw + brain.error.x, float(skill.turn) * elapsed)
		pitch = move_toward(p.aim_pitch, pitch + brain.error.y, float(skill.turn) * 0.6 * elapsed)
		var local_move := Basis(Vector3.UP, yaw).inverse() * move
		if climb_input != 0: local_move.z = climb_input
		brain.input = {"x": local_move.x, "z": local_move.z, "yaw": yaw, "pitch": pitch, "buttons": (4 if visible else 0) | (1 if brain.stuck > 0.8 else 0)}
		var ceiling := PhysicsRayQueryParameters3D.create(p.position + Vector3.UP * 0.5, p.position + Vector3.UP * 1.8, 1)
		if not game.world.get_world_3d().direct_space_state.intersect_ray(ceiling).is_empty(): brain.input.buttons |= 8
		if int(brain.target) != target.peer_id: brain.reaction = 0.0
		brain.target = target.peer_id
		brain.reaction = brain.reaction + elapsed if visible else 0.0
		if p.magazines[p.weapon_index] == 0:
			if p.reload_timer <= 0: action(id, brain, "reload")
		elif visible and distance < float(skill.range) and brain.reaction > float(skill.reaction) and brain.fire <= 0 and p.reload_timer <= 0:
			brain.burst += 1
			brain.fire = float(p.WEAPONS[p.weapon_index].rate) + float(skill.cadence)
			if int(brain.burst) >= int(skill.burst):
				brain.fire += float(skill.pause)
				brain.burst = 0
			action(id, brain, "fire", p.weapon_index)
