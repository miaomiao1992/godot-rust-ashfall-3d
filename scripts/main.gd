extends Node3D

const PlayerScript = preload("res://scripts/player.gd")
const ZombieScript = preload("res://scripts/zombie.gd")
const LevelScript = preload("res://scripts/level.gd")
const EffectsScript = preload("res://scripts/effects.gd")
const SoundScript = preload("res://scripts/sound.gd")
const HudScript = preload("res://scripts/hud.gd")

var world: Node3D
var level
var player
var fx
var sound
var hud
var state := "menu"
var wave := 0
var level_number := 1
var xp := 0
var xp_needed := 80
var kills := 0
var headshots := 0
var shots_fired := 0
var shots_hit := 0
var survival_time := 0.0
var next_wave := 0.0
var spawn_left := 0
var spawn_timer := 0.0
var alive := 0
var seed_value := 0
var sensitivity := 0.0023
var best_wave := 0
var best_kills := 0
var hitstop_left := 0.0
var levelup_pending := 0
var upgrade_due := 0.0
var pickups: Array[Dictionary] = []
var menu_time := 0.0
var rng := RandomNumberGenerator.new()
var ambience: WorldEnvironment
var debug_stats := false
var core
var stage_index := 0
var boss
var boss_pending := false
var hazards: Array[Dictionary] = []
var test_mode := false
var crowd_timer := 0.0
var spawn_cursor := 0
var acid_cast_cooldown := 0.0
var interaction_hint := ""
var objective_count := 0
var objective_waiting := false
const STAGE_NAMES := ["断桥高架", "沉没船坞", "熔心实验场"]
const BOSS_NAMES := ["断街暴君", "溺潮巨骸", "疫潮母体"]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	test_mode = "--smoke-test" in OS.get_cmdline_user_args() or "--arena-regression" in OS.get_cmdline_user_args()
	core = ClassDB.instantiate("AshfallCore")
	assert(core != null, "Rust GDExtension must be built before launching")
	rng.randomize()
	_setup_inputs()
	_load_record()
	_setup_environment()
	_build_run()
	hud = HudScript.new()
	hud.game = self
	add_child(hud)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_menu()
	if "--smoke-test" in OS.get_cmdline_user_args():
		call_deferred("_smoke_test")
	if "--visual-review" in OS.get_cmdline_user_args():
		call_deferred("_visual_review")
	if "--arena-regression" in OS.get_cmdline_user_args():
		call_deferred("_arena_regression")

func _setup_inputs() -> void:
	var keys := {"forward": KEY_W, "back": KEY_S, "left": KEY_A, "right": KEY_D, "sprint": KEY_SHIFT, "jump": KEY_SPACE, "reload": KEY_R, "flashlight": KEY_F, "interact": KEY_E, "weapon_1": KEY_1, "weapon_2": KEY_2, "weapon_3": KEY_3, "weapon_4": KEY_4, "weapon_5": KEY_5}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var event := InputEventKey.new()
			event.physical_keycode = keys[action]
			InputMap.action_add_event(action, event)
	var mouse := {"shoot": MOUSE_BUTTON_LEFT, "aim": MOUSE_BUTTON_RIGHT, "next_weapon": MOUSE_BUTTON_WHEEL_DOWN, "previous_weapon": MOUSE_BUTTON_WHEEL_UP}
	for action in mouse:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var event := InputEventMouseButton.new()
			event.button_index = mouse[action]
			InputMap.action_add_event(action, event)

func _setup_environment() -> void:
	ambience = WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.025, 0.075, 0.1)
	sky_material.sky_horizon_color = Color(0.2, 0.28, 0.29)
	sky_material.ground_bottom_color = Color(0.03, 0.055, 0.065)
	sky_material.ground_horizon_color = Color(0.17, 0.24, 0.26)
	sky_material.sun_angle_max = 3
	sky.sky_material = sky_material
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.43, 0.61, 0.66)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.12, 0.22, 0.25)
	env.fog_light_energy = 0.7
	env.fog_density = 0.009
	ambience.environment = env
	add_child(ambience)
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-48, -30, 0)
	moon.light_color = Color(0.58, 0.76, 0.85)
	moon.light_energy = 0.85
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 65
	add_child(moon)

func _build_run() -> void:
	if is_instance_valid(world):
		world.free()
	world = Node3D.new()
	world.name = "ProceduralBattlefield"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	seed_value = rng.randi_range(100000, 999999)
	level = LevelScript.new()
	level.game = self
	world.add_child(level)
	level.generate(stage_index)
	fx = EffectsScript.new()
	fx.game = self
	world.add_child(fx)
	sound = SoundScript.new()
	world.add_child(sound)
	player = PlayerScript.new()
	player.game = self
	player.position = level.player_spawn
	world.add_child(player)
	pickups.clear()
	hazards.clear()
	boss = null
	boss_pending = false
	objective_count = 0
	interaction_hint = ""
	acid_cast_cooldown = 0
	_style_environment()

func start_run() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	core.reset_run()
	stage_index = 0
	if state == "dead" or state == "victory" or wave > 0:
		_build_run()
	wave = 0
	level_number = 1
	xp = 0
	xp_needed = 80
	kills = 0
	headshots = 0
	shots_fired = 0
	shots_hit = 0
	survival_time = 0
	alive = 0
	levelup_pending = 0
	hitstop_left = 0
	upgrade_due = 0
	state = "playing"
	player.camera.position = Vector3(0, 1.65, 0)
	player.camera.rotation = Vector3.ZERO
	player.rotation = Vector3.ZERO
	player.aim_pitch = 0
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.hide_overlay()
	_begin_wave()
	hud.toast("保持移动。瞄准头部。活下来。", Color(0.68, 0.89, 0.86), 4.0)

func _begin_wave() -> void:
	var data: Dictionary = core.advance_wave()
	if int(data.stage) != stage_index:
		_change_stage(int(data.stage))
	wave = data.wave
	spawn_left = data.budget
	spawn_cursor = 0
	spawn_timer = 0.2
	next_wave = 0
	hud.wave_banner("%s  /  尸潮 %d·3" % [STAGE_NAMES[stage_index], data.stage_wave], "感染者正在逼近" if not data.boss else "BOSS 来袭  //  " + BOSS_NAMES[stage_index])
	boss_pending = data.boss
	if boss_pending:
		boss = _spawn_add(level.boss_spawn, 4)
		boss_pending = boss == null
	sound.play("growl", -12, 0.6)

func _process(delta: float) -> void:
	if state == "menu":
		menu_time += delta
		player.camera.global_position = level.menu_camera + Vector3(sin(menu_time * 0.07) * 3, 0, 0)
		player.camera.look_at(level.menu_focus)
		player.rig.visible = false
		return
	player.rig.visible = state != "dead"
	if state != "playing":
		return
	if hitstop_left > 0:
		hitstop_left -= delta / maxf(Engine.time_scale, 0.01)
		if hitstop_left <= 0:
			Engine.time_scale = 1
	survival_time += delta
	acid_cast_cooldown = maxf(acid_cast_cooldown - delta, 0)
	_update_interaction()
	if player.position.y < level.fall_threshold:
		player.take_damage(24, player.position)
		if state != "playing":
			return
		player.position = level.safe_ground(player.position) + Vector3.UP * 0.12
		player.velocity = Vector3.ZERO
		hud.toast("跌落救援 · 生命受损", Color(1, 0.56, 0.24), 2)
	crowd_timer -= delta
	if crowd_timer <= 0:
		var positions: Array[Vector3] = []
		for enemy in get_tree().get_nodes_in_group("zombies"):
			if not enemy.dead and not enemy.is_queued_for_deletion() and enemy.get_parent() == world:
				positions.append(enemy.global_position)
		alive = positions.size()
		core.update_crowd(positions)
		crowd_timer = 0.1
	if levelup_pending > 0:
		upgrade_due -= delta
		if upgrade_due <= 0:
			_open_upgrade()
			return
	spawn_timer -= delta
	if boss_pending and spawn_timer <= 0:
		boss = _spawn_add(level.boss_spawn, 4)
		boss_pending = boss == null
		if boss_pending:
			spawn_timer = 0.5
	if spawn_left > 0 and spawn_timer <= 0 and alive < 100:
		_spawn_zombie()
	if spawn_left == 0 and alive == 0 and not boss_pending:
		_clear_hazards()
		var required: int = core.objective_required(stage_index, posmod(wave - 1, 3) + 1)
		if objective_count < required:
			if not objective_waiting:
				hud.wave_banner("关闭冷却阀", "本波需要 %d / 3 · 靠近控制台按 E" % required)
			objective_waiting = true
			next_wave = 0
			return
		objective_waiting = false
		if wave >= 9:
			win()
			return
		if next_wave <= 0:
			next_wave = 12.0
			player.resupply(true)
			hud.wave_banner("关卡肃清" if wave % 3 == 0 else "暂时安全", "12 秒后进入 " + STAGE_NAMES[mini(stage_index + 1, 2)] if wave % 3 == 0 else "补给已送达 · 恢复生命与弹药")
		else:
			next_wave -= delta
			if next_wave <= 0:
				_begin_wave()
	_update_pickups(delta)
	_update_hazards(delta)

func _spawn_zombie() -> void:
	var plan: Dictionary = core.encounter(stage_index, wave, spawn_cursor, level.spawn_points.size())
	var gate: int = plan.gate
	for offset in level.spawn_points.size():
		var candidate: Vector3 = level.spawn_points[posmod(gate + offset, level.spawn_points.size())]
		if candidate.distance_to(player.global_position) > 16:
			gate = posmod(gate + offset, level.spawn_points.size())
			break
	var point: Vector3 = level.spawn_points[gate]
	var kind: int = core.spawn_kind(wave, rng.randf())
	if kind == 5:
		var spitters := 0
		for enemy in get_tree().get_nodes_in_group("zombies"):
			if enemy.kind == 5 and not enemy.dead:
				spitters += 1
		if spitters >= int(plan.max_spitters):
			kind = 0
	var zombie = _create_enemy(kind, point + Vector3(rng.randf_range(-0.8, 0.8), 0, rng.randf_range(-0.8, 0.8)))
	if zombie == null:
		spawn_timer = 0.5
		return
	spawn_left -= 1
	spawn_cursor += 1
	spawn_timer = plan.interval

func zombie_killed(zombie, head: bool) -> void:
	alive = maxi(alive - 1, 0)
	_clear_hazards(zombie.get_instance_id(), zombie.kind != 4)
	var old_level := level_number
	var data: Dictionary = core.register_kill(zombie.kind, head)
	kills = data.kills
	headshots = data.headshots
	xp = data.xp
	xp_needed = data.xp_needed
	level_number = data.level
	hud.add_kill(head, zombie.kind, data.reward)
	levelup_pending += int(data.levels_gained)
	if data.levels_gained > 0:
		upgrade_due = 0.8
		for i in range(1, 5):
			if old_level < int(player.WEAPONS[i].level) and level_number >= int(player.WEAPONS[i].level):
				hud.toast("武器解锁  //  %s  ·  按 %d 装备" % [player.WEAPONS[i].name, i + 1], Color(0.15, 0.9, 0.84), 5)
				sound.play("unlock", -6)
	if zombie.kind == 4:
		boss = null
		player.resupply(true)
		hud.wave_banner("%s 已击败" % BOSS_NAMES[stage_index], "肃清剩余感染者，继续前进")
	if rng.randf() < 0.26 or zombie.kind == 2 or zombie.kind == 4:
		_drop_pickup(zombie.global_position, "health" if rng.randf() < 0.32 else "ammo")

func _drop_pickup(pos: Vector3, kind: String) -> void:
	if pickups.size() >= 24:
		var oldest: Dictionary = pickups.pop_front()
		oldest.node.queue_free()
	var root := Node3D.new()
	world.add_child(root)
	root.position = Vector3(pos.x, 0.42, pos.z)
	var color := Color(0.24, 0.91, 0.65) if kind == "health" else Color(1, 0.68, 0.23)
	Forge.box(root, Vector3.ZERO, Vector3(0.36, 0.28, 0.3), Forge.material(Color(0.1, 0.17, 0.18), 0.5))
	Forge.box(root, Vector3(0, 0.15, 0), Vector3(0.22, 0.02, 0.07), Forge.material(color, 0, 2))
	Forge.box(root, Vector3(0, 0.15, 0), Vector3(0.07, 0.02, 0.22), Forge.material(color, 0, 2))
	Forge.cylinder(root, Vector3(0, -0.36, 0), 0.4, 0.015, Forge.material(color, 0, 0.8))
	pickups.append({"node": root, "kind": kind, "life": 35.0, "base": root.position.y})

func _update_pickups(delta: float) -> void:
	for i in range(pickups.size() - 1, -1, -1):
		var item: Dictionary = pickups[i]
		item.life -= delta
		item.node.rotation.y += delta
		item.node.position.y = item.base + sin(survival_time * 3 + i) * 0.07
		if item.node.global_position.distance_to(player.global_position + Vector3.UP * 0.5) < 2.1:
			if item.kind == "health":
				player.hp = minf(player.hp + 24, player.max_hp)
				hud.toast("急救包  +24 HP", Color(0.3, 0.94, 0.69), 1.2)
			else:
				player.resupply()
				hud.toast("弹药回收  +补给", Color(1, 0.7, 0.3), 1.2)
			sound.play("reload", -15, 1.5)
			item.life = 0
		if item.life <= 0:
			item.node.queue_free()
			pickups.remove_at(i)

func _open_upgrade() -> void:
	state = "upgrade"
	Engine.time_scale = 1
	hitstop_left = 0
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_upgrade()

func choose_upgrade(index: int) -> void:
	var data: Dictionary = core.apply_upgrade(index)
	player.damage_multiplier = data.damage_multiplier
	player.max_hp = data.max_hp
	player.hp = minf(player.hp + float(data.heal), player.max_hp)
	player.resistance = data.resistance
	player.reload_multiplier = data.reload_multiplier
	player.speed_bonus = data.speed_bonus
	if index == 2:
		player.resupply()
	levelup_pending = maxi(levelup_pending - 1, 0)
	upgrade_due = 1.0
	state = "playing"
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.hide_overlay()
	sound.play("unlock", -10)

func hit_stop(duration: float) -> void:
	hitstop_left = duration
	Engine.time_scale = 0.38

func die() -> void:
	state = "dead"
	Engine.time_scale = 1
	hitstop_left = 0
	best_wave = maxi(best_wave, wave)
	best_kills = maxi(best_kills, kills)
	_save_record()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_death()

func pause_run() -> void:
	if state == "playing":
		state = "paused"
		Engine.time_scale = 1
		get_tree().paused = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		hud.show_pause()
	elif state == "paused":
		resume_run()

func resume_run() -> void:
	state = "playing"
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.hide_overlay()

func return_to_menu() -> void:
	get_tree().paused = false
	Engine.time_scale = 1
	state = "menu"
	wave = 0
	stage_index = 0
	_build_run()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_menu()

func _change_stage(index: int) -> void:
	for item in pickups:
		item.node.queue_free()
	pickups.clear()
	for item in hazards:
		item.node.queue_free()
	hazards.clear()
	level.free()
	fx.free()
	stage_index = index
	level = LevelScript.new()
	level.game = self
	world.add_child(level)
	level.generate(stage_index)
	core.reset_sector_goals()
	objective_count = 0
	objective_waiting = false
	interaction_hint = ""
	acid_cast_cooldown = 0
	fx = EffectsScript.new()
	fx.game = self
	world.add_child(fx)
	player.position = level.player_spawn
	player.velocity = Vector3.ZERO
	player.rotation.y = 0
	player.aim_pitch = 0
	player.resupply(true)
	_style_environment()

func _style_environment() -> void:
	var env := ambience.environment
	var sky_mat: ProceduralSkyMaterial = env.sky.sky_material
	var colors := [Color(0.12, 0.22, 0.25), Color(0.055, 0.17, 0.24), Color(0.25, 0.06, 0.04)]
	env.fog_light_color = colors[stage_index]
	env.fog_density = [0.009, 0.014, 0.011][stage_index]
	sky_mat.sky_top_color = colors[stage_index] * 0.3
	sky_mat.sky_horizon_color = colors[stage_index] * 1.35
	env.ambient_light_color = [Color(0.43, 0.61, 0.66), Color(0.3, 0.57, 0.7), Color(0.7, 0.36, 0.28)][stage_index]

func _spawn_add(pos: Vector3, kind: int):
	if alive >= 100:
		return null
	return _create_enemy(kind, pos + Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4)))

func _create_enemy(kind: int, requested: Vector3):
	var stats: Dictionary = core.monster_stats(kind, wave)
	var placement: Dictionary = level.find_enemy_spawn(requested, float(stats.scale))
	if placement.is_empty():
		return null
	var zombie := ZombieScript.new()
	zombie.game = self
	zombie.kind = kind
	zombie.position = placement.position
	world.add_child(zombie)
	alive += 1
	return zombie

func recover_enemy(enemy) -> bool:
	var placement: Dictionary = level.find_enemy_spawn(enemy.last_safe_position, enemy.size_factor)
	if placement.is_empty():
		for entrance in level.spawn_points:
			placement = level.find_enemy_spawn(entrance, enemy.size_factor)
			if not placement.is_empty():
				break
	if placement.is_empty():
		return false
	enemy.position = placement.position
	enemy.velocity = Vector3.ZERO
	enemy.knockback = Vector3.ZERO
	enemy.route.clear()
	enemy.path_timer = 0
	enemy.last_safe_position = enemy.position
	# Recovery is not a kill: retain HP, XP, spawn budget, and the live actor.
	return true

func try_acid_attack(caster, target: Vector3, elite: bool) -> bool:
	if acid_cast_cooldown > 0:
		return false
	var pattern: Dictionary = core.acid_pattern(stage_index, caster.acid_step, elite)
	var points: Array[Vector3] = []
	var delays: Array[float] = []
	# Stage patterns use fixed world axes. Once locked, they never track movement.
	for offset in pattern.spots:
		var pos: Vector3 = target + Vector3(offset.x, 0, -offset.z)
		if level.is_walkable_point(pos):
			for h in hazards:
				if h.kind == "acid" and h.life > 0 and Vector2(pos.x - h.node.position.x, pos.z - h.node.position.z).length() < float(pattern.radius) + h.radius + 0.35:
					return false
			points.append(level.ground_point(pos))
			delays.append(float(offset.y))
	var existing := 0
	for h in hazards:
		if h.kind == "acid" and h.life > 0:
			existing += 1
	if points.is_empty() or existing + points.size() > 6:
		return false
	for i in points.size():
		create_hazard(points[i], pattern.radius, "acid", float(pattern.warning) + delays[i], pattern.active, caster.get_instance_id())
	acid_cast_cooldown = 3.4 if elite else 4.2
	caster.acid_step += 1
	hud.toast(pattern.name + " · " + pattern.hint, Color(1, 0.7, 0.28), 2.8)
	return true

func create_hazard(pos: Vector3, radius: float, kind: String, warning: float = 1.15, duration: float = 3.2, source_id: int = 0) -> void:
	var root := Node3D.new()
	world.add_child(root)
	root.position = level.ground_point(pos) + Vector3.UP * 0.055
	var visual := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2.ONE * radius * 2.0
	visual.mesh = mesh
	var angle: float = level.ground_angle(pos)
	visual.rotation.x = angle
	visual.scale.z = 1.0 / cos(angle)
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/hazard.gdshader")
	mat.set_shader_parameter("active_color", Color(0.36, 0.64, 0.12) if kind == "acid" else Color(1, 0.12, 0.025))
	visual.material_override = mat
	root.add_child(visual)
	hazards.append({"node": root, "material": mat, "radius": radius, "kind": kind, "warning": warning, "warning_total": warning, "life": duration if kind == "acid" else 0.2, "tick": 0.0, "activated": false, "source": source_id})

func _update_hazards(delta: float) -> void:
	for i in range(hazards.size() - 1, -1, -1):
		var h: Dictionary = hazards[i]
		var active_delta := delta
		if h.warning > 0:
			var prior_warning: float = h.warning
			h.warning = maxf(h.warning - delta, 0)
			h.material.set_shader_parameter("progress", 1.0 - h.warning / h.warning_total)
			if h.warning > 0:
				continue
			active_delta = maxf(delta - prior_warning, 0)
		if not h.activated:
			h.activated = true
			h.material.set_shader_parameter("phase", 1.0)
			if h.kind != "acid":
				fx.burst(h.node.position, Vector3.UP, Color(0.8, 0.26, 0.08), 28, 7)
				sound.play("shotgun", -5, 0.4)
		h.life -= active_delta
		h.tick -= active_delta
		var flat_distance := Vector2(h.node.position.x - player.position.x, h.node.position.z - player.position.z).length()
		if h.life > 0 and h.tick <= 0 and flat_distance < h.radius and absf(player.position.y - level.surface_height(player.position)) < 0.85:
			player.take_damage(12 if h.kind == "acid" else 45, h.node.position)
			h.tick = 0.65
		if h.life <= 0:
			h.material.set_shader_parameter("fade", clampf(1.0 + h.life / 0.55, 0, 1))
		if h.life <= -0.55:
			h.node.queue_free()
			hazards.remove_at(i)

func _clear_hazards(source_id: int = 0, warnings_only: bool = false) -> void:
	for i in range(hazards.size() - 1, -1, -1):
		var h: Dictionary = hazards[i]
		if (source_id == 0 or h.source == source_id) and (not warnings_only or not h.activated):
			h.node.queue_free()
			hazards.remove_at(i)

func _update_interaction() -> void:
	interaction_hint = ""
	for terminal in level.terminals:
		if not terminal.activated and player.position.distance_to(terminal.position) < 3.4:
			interaction_hint = "E 关闭 " + terminal.name
			return

func interact() -> void:
	if state != "playing":
		return
	for i in level.terminals.size():
		var terminal: Dictionary = level.terminals[i]
		if not terminal.activated and player.position.distance_to(terminal.position) < 3.4 and core.activate_terminal(i):
			level.activate_terminal(i)
			objective_count = core.objective_progress()
			player.hp = minf(player.hp + 12, player.max_hp)
			player.resupply()
			sound.play("unlock", -8)
			hud.wave_banner("冷却阀已关闭  %d / 3" % objective_count, "核心护罩解除" if objective_count == 3 else "其余阀门已在雷达标记")
			return

func win() -> void:
	state = "victory"
	Engine.time_scale = 1
	best_wave = maxi(best_wave, wave)
	best_kills = maxi(best_kills, kills)
	_save_record()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_victory()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		interact()
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			pause_run()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F3:
			debug_stats = not debug_stats

func _load_record() -> void:
	if test_mode:
		return
	if FileAccess.file_exists("user://record.json"):
		var data = JSON.parse_string(FileAccess.get_file_as_string("user://record.json"))
		if data is Dictionary:
			best_wave = int(data.get("wave", 0))
			best_kills = int(data.get("kills", 0))
			sensitivity = float(data.get("sensitivity", 0.0023))

func _save_record() -> void:
	if test_mode:
		return
	var file := FileAccess.open("user://record.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"wave": best_wave, "kills": best_kills, "sensitivity": sensitivity}))

func _smoke_test() -> void:
	var tester = load("res://tests/smoke_test.gd").new()
	tester.game = self
	add_child(tester)

func _visual_review() -> void:
	var reviewer = load("res://tests/visual_review.gd").new()
	reviewer.game = self
	add_child(reviewer)

func _arena_regression() -> void:
	var tester = load("res://tests/arena_regression.gd").new()
	tester.game = self
	add_child(tester)
