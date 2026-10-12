extends "res://scripts/level.gd"
## CS_ASSAULT (突击 / 仓库 / 7273) authentic reconstruction.
## Features the iconic loading platform, center slope ramp, roll-up garage door,
## four red cargo bays, security CCTV room, ceiling trusses, hanging fluorescent fixtures,
## roof skylights admitting sun/moonlight, and the famous ventilation duct (The Vent).

var team_spawns: Array = [[], []]
var pipe_routes: Array[Dictionary] = []
var roof_routes: Array[Dictionary] = []
const ROOF_HEIGHT := 11.0

func generate(_index: int) -> void:
	stage = 3
	spatial_type = "pvp_warehouse_three_lane"
	combat_hint = "CS_ASSAULT 仓库突击 · 大卷帘门 / 装卸台大斜坡 / 红货位 / 管道 / 天窗"
	fall_threshold = -3
	menu_camera = Vector3(36, 44, 58)
	menu_focus = Vector3(0, 3.2, 0)
	grid.region = Rect2i(0, 0, GRID, GRID)
	grid.cell_size = Vector2(CELL, CELL)
	grid.offset = Vector2(-56, -56)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	grid.fill_solid_region(grid.region)

	# --- Authentic PBR Materials (Poly Haven CC0 Real-World PBR Textures) ---
	var concrete_mat := _pbr("concrete", 0.22, Color(0.92, 0.94, 0.95))
	var driveway_mat := _pbr("asphalt", 0.18, Color(0.75, 0.77, 0.80))
	var steel_wall := _pbr("corrugated", 0.25, Color(0.85, 0.88, 0.92), 0.75, 0.45)
	var garage_door_mat := _pbr("shutter", 0.30, Color(0.82, 0.85, 0.88), 0.80, 0.40)
	var container_blue := _pbr("container", 0.25, Color(0.22, 0.52, 0.88), 0.70, 0.45)
	var container_red := _pbr("container", 0.25, Color(0.85, 0.28, 0.22), 0.70, 0.45)
	var dark_steel := Forge.material(Color(0.12, 0.15, 0.17), 0.85, 0, 0.40)
	var wood := _pbr("wood", 0.45, Color(0.90, 0.75, 0.55), 0.0, 0.85)
	var yellow_curb := Forge.material(Color(0.88, 0.72, 0.15), 0.1, 0, 0.65)
	var red_bay_mat := Forge.material(Color(0.68, 0.15, 0.12), 0.2, 0, 0.70)
	var cctv_screen_mat := Forge.material(Color(0.12, 0.85, 0.65), 0, 1.8, 0.2)

	# 1. Base Main Deck (Floor slab spanning the entire warehouse interior)
	_deck(Rect2i(3, 2, 23, 25), 0, driveway_mat)

	# 2. Outer Warehouse Perimeter Walls (Corrugated industrial steel walls)
	for x in [-46.0, 46.0]: _cover(Vector3(x, 5, 0), Vector3(1, 10, 100), steel_wall)
	for z in [-50.0, 50.0]: _cover(Vector3(0, 5, z), Vector3(92, 10, 1), steel_wall)

	# 3. Giant Front Roll-Up Garage Door (CS_ASSAULT 大卷帘门) on front wall (z = 49)
	# Opens partially from y = 1.6 to 6.8 with safety hazard header
	Forge.box(self, Vector3(0.0, 5.2, 49.2), Vector3(26.0, 6.4, 0.35), garage_door_mat, true)
	Forge.box(self, Vector3(0.0, 8.5, 49.3), Vector3(27.0, 0.6, 0.5), dark_steel, true)
	Forge.box(self, Vector3(0.0, 1.2, 49.2), Vector3(26.0, 0.4, 0.3), yellow_curb)
	Forge.label(self, Vector3(0.0, 8.8, 48.6), "BAY 01 // MAIN ROLLING GATE", Color(0.92, 0.78, 0.25), 36)

	# 4. Interior Longitudinal Separator Walls with door passages
	for x in [-26.0, 26.0]:
		for z in [-26.0, 26.0]: _cover(Vector3(x, 4, z), Vector3(1, 8, 20), steel_wall)
		for z in [-26.0, 0.0, 26.0]:
			Forge.box(self, Vector3(x, 8.3, z), Vector3(1.4, 0.6, 24), dark_steel)

	# 5. CS_ASSAULT The Raised Concrete Loading Platform (装卸大高台)
	# Platform is on the right side: x in [14, 44], z in [-48, -14], height 2.8m
	const PLATFORM_Y: float = 2.8
	Forge.box(self, Vector3(29.0, PLATFORM_Y * 0.5, -31.0), Vector3(30.0, PLATFORM_Y, 34.0), concrete_mat, true)
	Forge.box(self, Vector3(29.0, PLATFORM_Y + 0.08, -14.0), Vector3(30.0, 0.16, 0.35), yellow_curb)

	# 6. CS_ASSAULT The Iconic Concrete Slope Ramp (装卸平台大斜坡)
	# Connects floor at z = 2.0 to platform at z = -14.0, x in [4, 13]
	var ramp_dx: float = 9.0
	var ramp_dz: float = 16.0
	var ramp_len: float = sqrt(ramp_dz * ramp_dz + PLATFORM_Y * PLATFORM_Y)
	var ramp_angle: float = atan2(PLATFORM_Y, ramp_dz)
	var ramp := Forge.box(self, Vector3(8.5, PLATFORM_Y * 0.5, -6.0), Vector3(ramp_dx, 0.4, ramp_len), concrete_mat, true)
	ramp.rotation.x = ramp_angle
	for side in [-1.0, 1.0]:
		Forge.box(ramp, Vector3(side * (ramp_dx * 0.5 - 0.2), 0.25, 0), Vector3(0.3, 0.18, ramp_len), yellow_curb)

	# 7. CS_ASSAULT Four Red Cargo Recessed Loading Bays (红货位) along back wall (z = -48)
	for i in 4:
		var bx: float = 16.0 + float(i) * 6.5
		Forge.box(self, Vector3(bx, PLATFORM_Y + 3.0, -48.2), Vector3(5.8, 5.6, 0.8), red_bay_mat)
		Forge.box(self, Vector3(bx, PLATFORM_Y + 5.8, -47.8), Vector3(6.2, 0.45, 0.6), dark_steel)
		var bay_light := OmniLight3D.new()
		bay_light.position = Vector3(bx, PLATFORM_Y + 5.0, -47.0)
		bay_light.light_color = Color(1.0, 0.22, 0.15)
		bay_light.light_energy = 1.25
		bay_light.omni_range = 8.0
		add_child(bay_light)
		Forge.label(self, Vector3(bx, PLATFORM_Y + 4.2, -47.5), "DOCK 0%d" % (i + 1), Color(1.0, 0.65, 0.65), 26)

	# 8. CS_ASSAULT Upper Catwalk & Security CCTV Camera Room (二楼猫道与监控室)
	Forge.box(self, Vector3(36.0, 5.8, -32.0), Vector3(8.0, 0.25, 24.0), dark_steel, true)
	Forge.box(self, Vector3(36.0, 7.8, -42.0), Vector3(8.0, 3.8, 8.0), steel_wall, true)
	for row in 2:
		for col in 2:
			var scr_x: float = 34.5 + float(col) * 1.6
			var scr_y: float = 7.4 + float(row) * 1.1
			Forge.box(self, Vector3(scr_x, scr_y, -37.8), Vector3(1.2, 0.85, 0.08), cctv_screen_mat)
	Forge.label(self, Vector3(36.0, 8.8, -37.6), "CCTV // SECURITY", Color(0.2, 0.95, 0.75), 24)

	# 9. Stacked Shipping Containers (Red & Blue Half-Life style containers)
	for side in [-1.0, 1.0]:
		_cover(Vector3(0, 2.5, side * 35), Vector3(20, 5, 2), steel_wall)
		for x in [-36.0, 36.0]:
			_cover(Vector3(x - signf(x) * 3, 1.5, side * 26), Vector3(7, 3, 4), dark_steel)
		for x in [-16.0, 16.0]:
			_cover(Vector3(x, 1.6, side * 18), Vector3(6, 3.2, 8), wood)
			for y in [0.3, 1.4, 2.8]: Forge.box(self, Vector3(x, y, side * 18), Vector3(6.1, 0.12, 8.1), dark_steel)
	for x in [-36.0, 36.0]:
		_cover(Vector3(x, 1.2, 0), Vector3(5, 2.4, 6), wood)

	# Stacked containers on the driveway side
	Forge.box(self, Vector3(-18.0, 1.5, 22.0), Vector3(6.0, 3.0, 12.0), container_red, true)
	Forge.box(self, Vector3(-18.0, 4.5, 22.0), Vector3(6.0, 3.0, 12.0), container_blue, true)
	Forge.box(self, Vector3(18.0, 1.5, 22.0), Vector3(6.0, 3.0, 12.0), container_blue, true)
	Forge.box(self, Vector3(18.0, 4.5, 22.0), Vector3(6.0, 3.0, 12.0), container_red, true)

	# Wooden crates on the platform
	for p in [Vector3(-6.0, PLATFORM_Y + 0.6, -20.0), Vector3(-4.0, PLATFORM_Y + 0.6, -20.0), Vector3(-5.0, PLATFORM_Y + 1.6, -20.0),
	          Vector3(6.0, PLATFORM_Y + 0.6, -24.0), Vector3(8.0, PLATFORM_Y + 0.6, -24.0)]:
		Forge.box(self, p, Vector3(1.4, 1.2, 1.4), wood, true)

	# 10. Ceiling Triangular Steel Roof Trusses (三角钢桁架)
	for z in range(-44, 45, 12):
		_build_roof_truss(float(z), dark_steel)

	# 11. Suspended Rectangular Fluorescent Luminaires (长方形悬吊荧光吊灯箱)
	var luminaire_frame := dark_steel
	var luminaire_panel := Forge.material(Color(0.95, 0.98, 1.0), 0, 2.4, 0.1)
	for x in [-22.0, 0.0, 22.0]:
		for z in [-24.0, 18.0]:
			Forge.box(self, Vector3(x, 8.8, z), Vector3(6.0, 0.35, 2.4), luminaire_frame)
			Forge.box(self, Vector3(x, 8.6, z), Vector3(5.6, 0.08, 2.0), luminaire_panel)
			for cx in [-2.5, 2.5]:
				for cz in [-0.9, 0.9]:
					Forge.cylinder(self, Vector3(x + cx, 9.8, z + cz), 0.03, 2.0, dark_steel)
			var lamp := OmniLight3D.new()
			lamp.position = Vector3(x, 8.2, z)
			lamp.light_color = Color(0.92, 0.96, 1.0)
			lamp.light_energy = 1.45
			lamp.omni_range = 24.0
			add_child(lamp)

	# 12. CS_ASSAULT Roof Skylights (采光玻璃天窗)
	_build_skylights(dark_steel)

	# 13. Spawn Bases
	for team in 2:
		var z: float = 43.0 if team == 0 else -43.0
		var color := Color(0.12, 0.45, 1.0) if team == 0 else Color(0.95, 0.18, 0.12)
		var mat := Forge.material(color, 0, 0.65)
		Forge.box(self, Vector3(0, 0.03, z), Vector3(22, 0.04, 8), mat)
		Forge.label(self, Vector3(0, 6, z + (5 if team == 0 else -5)), "CT / 反恐精英" if team == 0 else "T / 恐怖分子", color, 72).rotation.y = PI if team == 1 else 0
		for slot in 5: team_spawns[team].append(Vector3(-8 + slot * 4, 0.12, z))

	Forge.label(self, Vector3(-18.0, 6.0, 0), "装卸车道 / DRIVEWAY", Color(0.85, 0.78, 0.45), 36)
	Forge.label(self, Vector3(0.0, PLATFORM_Y + 4.5, -28.0), "装卸高台 / CARGO PLATFORM", Color(0.85, 0.78, 0.45), 36)

	# 14. Ducts & Rooftop
	_build_pipes(dark_steel)
	_build_rooftop(dark_steel, concrete_mat)

	player_spawn = team_spawns[0][0]
	for x in GRID:
		for z in GRID:
			if grid.is_point_solid(Vector2i(x, z)): blocked[Vector2i(x, z)] = true
	_bake_static_geometry()

func _build_roof_truss(z: float, dark_steel: Material) -> void:
	Forge.box(self, Vector3(0, 9.4, z), Vector3(92.0, 0.35, 0.4), dark_steel)
	for side in [-1.0, 1.0]:
		var rafter_len: float = sqrt(46.0 * 46.0 + 1.8 * 1.8)
		var rafter_angle: float = side * atan2(1.8, 46.0)
		var rafter := Forge.box(self, Vector3(side * 23.0, 10.3, z), Vector3(rafter_len, 0.30, 0.4), dark_steel)
		rafter.rotation.z = -rafter_angle
	for x in [-32.0, -16.0, 0.0, 16.0, 32.0]:
		Forge.box(self, Vector3(x, 10.0, z), Vector3(0.25, 1.4, 0.3), dark_steel)

func _build_skylights(dark_steel: Material) -> void:
	var glass := ShaderMaterial.new()
	glass.shader = preload("res://shaders/skylight_glass.gdshader")
	for side in [-1.0, 1.0]:
		var skylight := Forge.box(self, Vector3(side * 12.0, 10.8, 0), Vector3(10.0, 0.12, 88.0), glass)
		skylight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for z in range(-40, 41, 8):
			Forge.box(self, Vector3(side * 12.0, 10.85, float(z)), Vector3(10.2, 0.16, 0.28), dark_steel)

func _cover(pos: Vector3, size: Vector3, mat: Material) -> void:
	Forge.box(self, pos, size, mat, true)
	var low := world_cell(pos - size * 0.5)
	var high := world_cell(pos + size * 0.5 - Vector3(0.01, 0, 0.01))
	_block(Rect2i(low, high - low + Vector2i.ONE))

func spawn_for(team: int, slot: int) -> Vector3:
	return team_spawns[clampi(team, 0, 1)][posmod(slot, 5)]

func _build_pipes(steel: Material) -> void:
	var lining := Forge.material(Color(0.32, 0.38, 0.42), 0.72, 0, 0.55)
	var marking := Forge.material(Color(0.88, 0.62, 0.18), 0.2)
	for side in [-1.0, 1.0]:
		for z in [-8.0, 8.0]:
			var center := Vector3(side * 28, 2.1, z)
			var route := {"entry": Vector3(side * 41, 0.2, z), "exit": Vector3(side * 15, 0.2, z), "center": center}
			pipe_routes.append(route)
			var low := world_cell(Vector3(side * 28 - 12, 0, z - 2.2))
			var high := world_cell(Vector3(side * 28 + 12, 0, z + 2.2))
			_block(Rect2i(low, high - low + Vector2i.ONE))
			for segment in 24:
				var angle: float = float(segment) * TAU / 24.0
				var offset := Vector3(0, cos(angle), sin(angle))
				var panel := Forge.box(self, center + offset * 2.2, Vector3(24, 0.16, 0.59), lining, true)
				panel.rotation.x = angle
				for x in [-12.0, -6.0, 0.0, 6.0, 12.0]:
					var rib := Forge.box(self, center + Vector3(x, 0, 0) + offset * 2.31, Vector3(0.16, 0.16, 0.62), steel)
					rib.rotation.x = angle
			for x in [side * 40, side * 16]:
				Forge.label(self, Vector3(x, 4.8, z), "VENT // 通风管道", Color(0.92, 0.76, 0.35), 28).rotation.y = -PI / 2 if side < 0 else PI / 2
				Forge.box(self, Vector3(x, 0.22, z), Vector3(0.25, 0.04, 1.6), marking)
			for x in [side * 22, side * 34]:
				var light := OmniLight3D.new()
				light.position = Vector3(x, 3, z)
				light.light_color = Color(0.58, 0.78, 0.86)
				light.light_energy = 0.8
				light.omni_range = 7
				add_child(light)

func _build_rooftop(steel: Material, floor_mat: Material) -> void:
	# Split roof to leave dual longitudinal skylight openings so real sun/moon rays beam down into warehouse
	# Center ridge walkway (connects directly to center route points)
	Forge.box(self, Vector3(0, ROOF_HEIGHT - 0.25, 0), Vector3(14, 0.5, 100), floor_mat, true)
	# Side roof platforms
	for side in [-1.0, 1.0]:
		Forge.box(self, Vector3(side * 26.5, ROOF_HEIGHT - 0.25, 0), Vector3(19, 0.5, 100), floor_mat, true)
	for z in [-50.0, 50.0]:
		Forge.box(self, Vector3(0, ROOF_HEIGHT + 0.7, z), Vector3(72, 1.4, 0.18), steel, true)
	for side in [-1.0, 1.0]:
		var x: float = side * 40
		var start := Vector3(x, 0.15, side * 42)
		var finish := Vector3(x, ROOF_HEIGHT + 0.15, side * 10)
		roof_routes.append({"entry": start, "exit": finish})
		var angle: float = side * atan2(ROOF_HEIGHT, 26.0)
		var ramp_length: float = sqrt(26.0 * 26.0 + ROOF_HEIGHT * ROOF_HEIGHT)
		var ramp := Forge.box(self, Vector3(x, ROOF_HEIGHT * 0.5 - 0.25 / cos(angle), side * 27), Vector3(6, 0.5, ramp_length), floor_mat, true)
		ramp.rotation.x = angle
		for edge in [-3.1, 3.1]:
			Forge.box(ramp, Vector3(edge, 0.95, 0), Vector3(0.18, 1.4, ramp_length), steel, true)
		Forge.box(self, Vector3(x, ROOF_HEIGHT - 0.25, side * 10), Vector3(12, 0.5, 8), floor_mat, true)
		Forge.label(self, Vector3(x, 3.5, side * 41), "ROOF ↑ / 屋顶坡道", Color(0.94, 0.78, 0.3), 33).rotation.y = PI if side < 0 else 0
		for section in [{"z": side * -22.0, "length": 56.0}, {"z": side * 32.0, "length": 36.0}]:
			Forge.box(self, Vector3(side * 36, ROOF_HEIGHT + 0.7, float(section.z)), Vector3(0.18, 1.4, float(section.length)), steel, true)
		Forge.box(self, Vector3(side * 41, ROOF_HEIGHT + 0.7, side * 6), Vector3(10, 1.4, 0.18), steel, true)
		Forge.box(self, Vector3(side * 46, ROOF_HEIGHT + 0.7, side * 10), Vector3(0.18, 1.4, 8), steel, true)
	for z in [-28.0, 28.0]:
		for x in [-18.0, 18.0]:
			Forge.box(self, Vector3(x, ROOF_HEIGHT + 1.3, z), Vector3(7, 2.6, 5), steel, true)
			for slit in 6:
				Forge.box(self, Vector3(x - 2.5 + float(slit), ROOF_HEIGHT + 1.5, z + 2.55), Vector3(0.15, 1.6, 0.06), Forge.material(Color(0.07, 0.09, 0.1)))
	for x in [-9.0, 9.0]:
		Forge.box(self, Vector3(x, ROOF_HEIGHT + 1.2, 0), Vector3(7, 2.4, 12), steel, true)
	Forge.label(self, Vector3(0, ROOF_HEIGHT + 4, 0), "ROOFTOP / 屋顶交战区", Color(0.89, 0.8, 0.48), 40)

func _pbr(texture_name: String, uv_scale: float = 0.25, tint: Color = Color.WHITE, metallic: float = 0.0, roughness_mult: float = 1.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var diff_path := "res://assets/textures/pbr/%s_diff.jpg" % texture_name
	var nor_path := "res://assets/textures/pbr/%s_nor.jpg" % texture_name
	var rough_path := "res://assets/textures/pbr/%s_rough.jpg" % texture_name
	var diff_img := Image.load_from_file(ProjectSettings.globalize_path(diff_path))
	if diff_img != null:
		mat.albedo_texture = ImageTexture.create_from_image(diff_img)
	var nor_img := Image.load_from_file(ProjectSettings.globalize_path(nor_path))
	if nor_img != null:
		mat.normal_enabled = true
		mat.normal_texture = ImageTexture.create_from_image(nor_img)
		mat.normal_scale = 1.2
	var rough_img := Image.load_from_file(ProjectSettings.globalize_path(rough_path))
	if rough_img != null:
		mat.roughness_texture = ImageTexture.create_from_image(rough_img)
	mat.albedo_color = tint
	mat.metallic = metallic
	mat.roughness = roughness_mult
	mat.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	mat.uv1_triplanar = true
	return mat
