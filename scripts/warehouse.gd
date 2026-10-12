extends "res://scripts/level.gd"
## Authored symmetric three-lane warehouse; separate from the survival campaign.
var team_spawns: Array = [[], []]
var pipe_routes: Array[Dictionary] = []
var roof_routes: Array[Dictionary] = []
const ROOF_HEIGHT := 11.0

func generate(_index: int) -> void:
	stage = 3
	spatial_type = "pvp_warehouse_three_lane"
	combat_hint = "中央货仓 / 装卸道 / 维修道 / 管道 / 屋顶"
	fall_threshold = -3
	menu_camera = Vector3(46, 48, 64)
	menu_focus = Vector3(0, 0, 0)
	grid.region = Rect2i(0, 0, GRID, GRID)
	grid.cell_size = Vector2(CELL, CELL)
	grid.offset = Vector2(-56, -56)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	grid.fill_solid_region(grid.region)
	var floor_mat := Forge.material(Color(0.29, 0.31, 0.32), 0.05, 0, 0.94)
	var wall := Forge.material(Color(0.43, 0.42, 0.37), 0.1, 0, 0.9)
	var steel := Forge.material(Color(0.13, 0.18, 0.20), 0.6, 0, 0.8)
	var wood := Forge.material(Color(0.43, 0.29, 0.15), 0, 0, 0.92)
	_deck(Rect2i(3, 2, 23, 25), 0, floor_mat)
	# Outer shell, no walkable holes or inaccessible spawn pockets.
	for x in [-46.0, 46.0]: _cover(Vector3(x, 5, 0), Vector3(1, 10, 100), wall)
	for z in [-50.0, 50.0]: _cover(Vector3(0, 5, z), Vector3(92, 10, 1), wall)
	# Two internal walls separate side lanes; 8m door gaps at both ends and mid.
	for x in [-26.0, 26.0]:
		for z in [-26.0, 26.0]: _cover(Vector3(x, 4, z), Vector3(1, 8, 20), wall)
		for z in [-26.0, 0.0, 26.0]:
			Forge.box(self, Vector3(x, 8.3, z), Vector3(1.4, 0.6, 24), steel)
	# Spawn sightline blockers and staggered route entrances, mirrored for fairness.
	for side in [-1.0, 1.0]:
		_cover(Vector3(0, 2.5, side * 35), Vector3(20, 5, 2), wall)
		for x in [-36.0, 36.0]:
			_cover(Vector3(x - signf(x) * 3, 1.5, side * 26), Vector3(7, 3, 4), steel)
		for x in [-16.0, 16.0]:
			_cover(Vector3(x, 1.6, side * 18), Vector3(6, 3.2, 8), wood)
			for y in [0.3, 1.4, 2.8]: Forge.box(self, Vector3(x, y, side * 18), Vector3(6.1, 0.12, 8.1), steel)
	# Central stacks break long sightlines while preserving cross-lane flanks.
	for x in [-10.0, 10.0]:
		_cover(Vector3(x, 2, 0), Vector3(6, 4, 10), steel)
		for z in [-4.0, 4.0]: Forge.box(self, Vector3(x, 4.12, z), Vector3(5.5, 0.2, 1), wood)
	for x in [-36.0, 36.0]:
		_cover(Vector3(x, 1.2, 0), Vector3(5, 2.4, 6), wood)
	# Corrugated walls, roof girders, clerestories, overhead lamps.
	for z in range(-44, 45, 8):
		for x in [-45.4, 45.4]: Forge.box(self, Vector3(x, 5, z), Vector3(0.25, 9, 0.18), steel)
		Forge.box(self, Vector3(0, 10.5, z), Vector3(92, 0.45, 0.4), steel)
		for x in [-20.0, 20.0]:
			Forge.box(self, Vector3(x, 10.15, z), Vector3(8, 0.12, 0.7), Forge.material(Color(0.79, 0.86, 0.89), 0, 1.0))
	for x in [-38.0, 0.0, 38.0]:
		for z in [-20.0, 20.0]:
			var light := OmniLight3D.new()
			light.position = Vector3(x, 7, z)
			light.light_color = Color(0.85, 0.91, 1)
			light.light_energy = 1.5
			light.omni_range = 24
			add_child(light)
	for team in 2:
		var z := 43.0 if team == 0 else -43.0
		var color := Color(0.95, 0.12, 0.10) if team == 0 else Color(0.10, 0.43, 1.0)
		var mat := Forge.material(color, 0, 0.65)
		Forge.box(self, Vector3(0, 0.03, z), Vector3(22, 0.04, 8), mat)
		Forge.label(self, Vector3(0, 6, z + (5 if team == 0 else -5)), "RED / 红队" if team == 0 else "BLUE / 蓝队", color, 80).rotation.y = PI if team == 1 else 0
		for slot in 5: team_spawns[team].append(Vector3(-8 + slot * 4, 0.12, z))
	for x in [-36.0, 0.0, 36.0]:
		Forge.label(self, Vector3(x, 6, 0), "装卸通道" if x < 0 else "CENTRAL / 中央货仓" if x == 0 else "维修通道", Color(0.87, 0.77, 0.45), 44)
	_build_pipes(steel)
	_build_rooftop(steel, floor_mat)
	player_spawn = team_spawns[0][0]
	for x in GRID:
		for z in GRID:
			if grid.is_point_solid(Vector2i(x, z)): blocked[Vector2i(x, z)] = true
	_bake_static_geometry()

func _cover(pos: Vector3, size: Vector3, mat: Material) -> void:
	Forge.box(self, pos, size, mat, true)
	var low := world_cell(pos - size * 0.5)
	var high := world_cell(pos + size * 0.5 - Vector3(0.01, 0, 0.01))
	_block(Rect2i(low, high - low + Vector2i.ONE))

func spawn_for(team: int, slot: int) -> Vector3:
	return team_spawns[clampi(team, 0, 1)][posmod(slot, 5)]

func _build_pipes(steel: Material) -> void:
	# Hollow industrial ducts, not solid cylinders. A 4.2m bore admits the full
	# player capsule; four mirrored entrances link side lanes with the center.
	var lining := Forge.material(Color(0.31, 0.38, 0.41), 0.65, 0, 0.72)
	var marking := Forge.material(Color(0.85, 0.6, 0.16), 0.2)
	for side in [-1.0, 1.0]:
		for z in [-8.0, 8.0]:
			var center := Vector3(side * 28, 2.1, z)
			var route := {"entry": Vector3(side * 41, 0.2, z), "exit": Vector3(side * 15, 0.2, z), "center": center}
			pipe_routes.append(route)
			# A 2D A* grid cannot express a hollow tube's side walls. Route bots
			# around its envelope rather than sending them through the curved shell.
			var low := world_cell(Vector3(side * 28 - 12, 0, z - 2.2))
			var high := world_cell(Vector3(side * 28 + 12, 0, z + 2.2))
			_block(Rect2i(low, high - low + Vector2i.ONE))
			for segment in 24:
				var angle := segment * TAU / 24
				var offset := Vector3(0, cos(angle), sin(angle))
				var panel := Forge.box(self, center + offset * 2.2, Vector3(24, 0.16, 0.59), lining, true)
				panel.rotation.x = angle
				for x in [-12.0, -6.0, 0.0, 6.0, 12.0]:
					var rib := Forge.box(self, center + Vector3(x, 0, 0) + offset * 2.31, Vector3(0.16, 0.16, 0.62), steel)
					rib.rotation.x = angle
			# Existing warehouse slab is the tunnel floor: no raised lip at either
			# mouth, so a CharacterBody can enter without jumping or step climbing.
			for x in [side * 40, side * 16]:
				Forge.label(self, Vector3(x, 4.8, z), "DUCT / 可进入管道", Color(0.91, 0.74, 0.33), 27).rotation.y = -PI / 2 if side < 0 else PI / 2
				Forge.box(self, Vector3(x, 0.22, z), Vector3(0.25, 0.04, 1.6), marking)
			for x in [side * 22, side * 34]:
				var light := OmniLight3D.new()
				light.position = Vector3(x, 3, z)
				light.light_color = Color(0.58, 0.78, 0.86)
				light.light_energy = 0.8
				light.omni_range = 7
				add_child(light)

func _build_rooftop(steel: Material, floor_mat: Material) -> void:
	# Keep the two outer skylight strips open for ramps, with landing bridges
	# into the roof. This avoids an invisible ceiling blocking the final ascent.
	Forge.box(self, Vector3(0, ROOF_HEIGHT - 0.25, 0), Vector3(72, 0.5, 100), floor_mat, true)
	for z in [-50.0, 50.0]:
		Forge.box(self, Vector3(0, ROOF_HEIGHT + 0.7, z), Vector3(72, 1.4, 0.18), steel, true)
	for side in [-1.0, 1.0]:
		# Red and blue get identical lengths, rise and landing geometry.
		var x: float = side * 40
		var start := Vector3(x, 0.15, side * 42)
		var finish := Vector3(x, ROOF_HEIGHT + 0.15, side * 10)
		roof_routes.append({"entry": start, "exit": finish})
		var angle: float = side * atan2(ROOF_HEIGHT, 26)
		var ramp_length := sqrt(26 * 26 + ROOF_HEIGHT * ROOF_HEIGHT)
		var ramp := Forge.box(self, Vector3(x, ROOF_HEIGHT * 0.5 - 0.25 / cos(angle), side * 27), Vector3(6, 0.5, ramp_length), floor_mat, true)
		ramp.rotation.x = angle
		for edge in [-3.1, 3.1]:
			Forge.box(ramp, Vector3(edge, 0.95, 0), Vector3(0.18, 1.4, ramp_length), steel, true)
		Forge.box(self, Vector3(x, ROOF_HEIGHT - 0.25, side * 10), Vector3(12, 0.5, 8), floor_mat, true)
		Forge.label(self, Vector3(x, 3.5, side * 41), "ROOF ↑ / 屋顶坡道", Color(0.94, 0.78, 0.3), 33).rotation.y = PI if side < 0 else 0
		# Perimeter fencing leaves only the two landing openings.
		for section in [{"z": side * -22.0, "length": 56.0}, {"z": side * 32.0, "length": 36.0}]:
			Forge.box(self, Vector3(side * 36, ROOF_HEIGHT + 0.7, section.z), Vector3(0.18, 1.4, section.length), steel, true)
		Forge.box(self, Vector3(side * 41, ROOF_HEIGHT + 0.7, side * 6), Vector3(10, 1.4, 0.18), steel, true)
		Forge.box(self, Vector3(side * 46, ROOF_HEIGHT + 0.7, side * 10), Vector3(0.18, 1.4, 8), steel, true)
	# Ventilation units and ducts provide roof cover without a spawn-to-spawn
	# firing lane. Every visual obstruction also has a matching solid collider.
	for z in [-28.0, 28.0]:
		for x in [-18.0, 18.0]:
			Forge.box(self, Vector3(x, ROOF_HEIGHT + 1.3, z), Vector3(7, 2.6, 5), steel, true)
			for slit in 6:
				Forge.box(self, Vector3(x - 2.5 + slit, ROOF_HEIGHT + 1.5, z + 2.55), Vector3(0.15, 1.6, 0.06), Forge.material(Color(0.07, 0.09, 0.1)))
	for x in [-9.0, 9.0]:
		Forge.box(self, Vector3(x, ROOF_HEIGHT + 1.2, 0), Vector3(7, 2.4, 12), steel, true)
	Forge.label(self, Vector3(0, ROOF_HEIGHT + 4, 0), "ROOFTOP / 屋顶交战区", Color(0.89, 0.8, 0.48), 40)
