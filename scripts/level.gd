extends Node3D

const CELL := 4.0
const GRID := 29
const HALF := 58.0
const TITLES := ["断桥高架", "沉没船坞", "熔心实验场"]
var grid := AStarGrid2D.new()
var rng := RandomNumberGenerator.new()
var stage := 0
var game
var blocked: Dictionary = {}
var floor_heights: Dictionary = {}
var ramps: Array[Dictionary] = []
var spawn_points: Array[Vector3] = []
var terminals: Array[Dictionary] = []
var player_spawn := Vector3(0, 4.1, 44)
var boss_spawn := Vector3(-28, 8.1, -38)
var menu_camera := Vector3(25, 25, 48)
var menu_focus := Vector3(-12, 6, -8)
var fall_threshold := 1.0
var spatial_type := "folded_elevated_highway"
var combat_hint := "折线高架 · 留意转弯及上下坡"
var deck_regions: Array[Dictionary] = []

func generate(index: int) -> void:
	stage = index
	rng.seed = 9911 + stage * 541
	grid.region = Rect2i(0, 0, GRID, GRID)
	grid.cell_size = Vector2(CELL, CELL)
	grid.offset = Vector2(-56, -56)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	# Start with no navigable space: each sector authors its own actual floor.
	grid.fill_solid_region(grid.region)
	match stage:
		0: _highway()
		1: _docks()
		2: _laboratory()
	for x in GRID:
		for z in GRID:
			var cell := Vector2i(x, z)
			if grid.is_point_solid(cell):
				blocked[cell] = true
	_bake_static_geometry()

func _deck(rect: Rect2i, height: float, material: Material) -> void:
	# Adjacent authored platforms often overlap at junctions. Remove coplanar
	# overlap before batching: two top faces otherwise fight in the depth buffer.
	var pieces: Array[Rect2i] = [rect]
	for previous in deck_regions:
		if not is_equal_approx(height, float(previous.height)): continue
		var remaining: Array[Rect2i] = []
		for piece in pieces:
			var overlap := piece.intersection(previous.rect)
			if not overlap.has_area():
				remaining.append(piece)
				continue
			for candidate in [Rect2i(piece.position, Vector2i(piece.size.x, overlap.position.y - piece.position.y)), Rect2i(Vector2i(piece.position.x, overlap.end.y), Vector2i(piece.size.x, piece.end.y - overlap.end.y)), Rect2i(Vector2i(piece.position.x, overlap.position.y), Vector2i(overlap.position.x - piece.position.x, overlap.size.y)), Rect2i(Vector2i(overlap.end.x, overlap.position.y), Vector2i(piece.end.x - overlap.end.x, overlap.size.y))]:
				if candidate.has_area(): remaining.append(candidate)
		pieces = remaining
	for piece in pieces:
		var center := Vector3(-58 + (piece.position.x + piece.size.x * 0.5) * CELL, height - 0.3, -58 + (piece.position.y + piece.size.y * 0.5) * CELL)
		Forge.box(self, center, Vector3(piece.size.x * CELL, 0.6, piece.size.y * CELL), material, true)
		deck_regions.append({"rect": piece, "height": height})
	for x in range(rect.position.x, rect.end.x):
		for z in range(rect.position.y, rect.end.y):
			var cell := Vector2i(x, z)
			grid.set_point_solid(cell, false)
			floor_heights[cell] = maxf(float(floor_heights.get(cell, -20)), height)

func _ramp(rect: Rect2i, low: float, high: float, material: Material) -> void:
	var width := rect.size.x * CELL
	var length := rect.size.y * CELL
	var x := -58 + (rect.position.x + rect.size.x * 0.5) * CELL
	var z := -58 + (rect.position.y + rect.size.y * 0.5) * CELL
	var angle := atan2(high - low, length)
	var visual := Forge.box(self, Vector3(x, (low + high) * 0.5 - 0.3 / cos(angle), z), Vector3(width, 0.6, sqrt(length * length + pow(high - low, 2))), material, true)
	visual.rotation.x = angle
	var footprint := Rect2(Vector2(x - width * 0.5, z - length * 0.5), Vector2(width, length))
	ramps.append({"rect": footprint, "low": low, "high": high})
	for cx in range(rect.position.x, rect.end.x):
		for cz in range(rect.position.y, rect.end.y):
			var cell := Vector2i(cx, cz)
			grid.set_point_solid(cell, false)
			floor_heights[cell] = low

func _block(rect: Rect2i) -> void:
	grid.fill_solid_region(rect)

func _highway() -> void:
	var asphalt := ShaderMaterial.new()
	asphalt.shader = preload("res://shaders/asphalt.gdshader")
	var concrete := Forge.material(Color(0.33, 0.34, 0.32))
	# A folded, suspended route: south apron -> western elbow -> uphill -> north span.
	_deck(Rect2i(11, 22, 7, 6), 4, asphalt)
	_deck(Rect2i(11, 14, 5, 10), 4, asphalt)
	_deck(Rect2i(5, 12, 11, 4), 4, asphalt)
	_ramp(Rect2i(5, 8, 5, 4), 4, 8, asphalt)
	_deck(Rect2i(5, 2, 16, 6), 8, asphalt)

	_highway_substructure(concrete)
	_highway_ruins(concrete)
	_highway_guardrails()
	_highway_markings()
	_highway_gantry()
	_highway_ramp_sign()

	_car(Vector2i(11, 18), false)
	_car(Vector2i(15, 24), true)
	_car(Vector2i(7, 4), true)
	_car(Vector2i(14, 3), false)

	_highway_props()
	_highway_lamps()
	_highway_backdrop(concrete)
	_weather(true)

	spawn_points = [ground_point(Vector3(0, 0, 26)), ground_point(Vector3(-30, 0, 0)), ground_point(Vector3(-30, 0, -44)), ground_point(Vector3(20, 0, -42))]

func _docks() -> void:
	spatial_type = "comb_piers_over_water"
	combat_hint = "码头六连尸潮 · 横桥换线 · 东码头高坡"
	player_spawn = Vector3(-12, 0.1, 46)
	boss_spawn = Vector3(12, 2.9, -42)
	menu_camera = Vector3(49, 21, 59)
	menu_focus = Vector3(3, 0, -4)
	fall_threshold = -1.0
	var deck := Forge.material(Color(0.21, 0.27, 0.29), 0.1, 0, 0.85)
	var steel := Forge.material(Color(0.2, 0.27, 0.28), 0.65, 0, 0.72)
	# Water is a rough dielectric, not polished metal. Broad point-light
	# highlights on the huge water plane were overpowering the pier floor.
	var water := ShaderMaterial.new()
	water.shader = preload("res://shaders/harbor_water.gdshader")
	Forge.box(self, Vector3(0, -0.55, 0), Vector3(1600, 0.03, 1600), water).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for x in [4, 10, 16, 22]:
		_deck(Rect2i(x, 2, 3, 24), 0, deck)
	_deck(Rect2i(1, 15, 27, 2), 0, deck)
	_deck(Rect2i(1, 24, 27, 4), 0, deck)
	# Only the eastern loading pier climbs. Navigation and hazard height follow its slope.
	_deck(Rect2i(16, 2, 3, 10), 2.8, steel)
	_ramp(Rect2i(16, 12, 3, 3), 0, 2.8, steel)
	Forge.box(self, Vector3(12, 1.1, -30), Vector3(12, 2.2, 40), steel, true)
	for i in 2:
		var fill_height := 2.8 - (i + 1) * 2.8 / 3.0
		Forge.box(self, Vector3(12, fill_height * 0.5, -8 + i * 4), Vector3(12, fill_height, 4), steel, true)
	for rect in [Rect2i(4, 6, 1, 3), Rect2i(5, 12, 2, 2), Rect2i(10, 9, 1, 4), Rect2i(11, 19, 2, 2), Rect2i(17, 5, 2, 3), Rect2i(16, 9, 1, 2), Rect2i(22, 10, 1, 4), Rect2i(23, 19, 2, 2)]:
		_container(rect)
	_guardrails(Color(0.48, 0.47, 0.33))
	for x in [-36.0, -12.0, 12.0, 36.0]:
		for z in [-46.0, -12.0, 38.0]:
			var p := ground_point(Vector3(x, 0, z))
			Forge.cylinder(self, p + Vector3(0, -2.5, 0), 0.55, 5, steel)
		_lamp(ground_point(Vector3(x + 4, 0, 33)), Color(0.18, 0.76, 0.95), 7)
		var label := Forge.label(self, ground_point(Vector3(x, 0, -47)) + Vector3.UP * 3, "PIER %02d" % int((x + 36) / 24 + 1), Color(0.3, 0.83, 0.92), 48)
		label.pixel_size = 0.009
	# Massive gantry frames, ropes and a moored hull occupy the actual water skyline.
	var crane_mat := Forge.material(Color(0.53, 0.31, 0.11), 0.65)
	for x in [-32.0, 40.0]:
		for side in [-1, 1]:
			Forge.box(self, Vector3(x + side * 7, 11, -30), Vector3(0.8, 22, 1.0), crane_mat)
		Forge.box(self, Vector3(x, 22, -30), Vector3(17, 1.4, 1.5), crane_mat)
		Forge.box(self, Vector3(x, 22, -17), Vector3(1.5, 1.5, 31), crane_mat)
		Forge.cylinder(self, Vector3(x, 16, -9), 0.045, 12, steel)
		Forge.box(self, Vector3(x, 9.8, -9), Vector3(0.6, 0.45, 0.6), crane_mat)
	_ship_hull(Vector3(-63, 0, -10), Forge.material(Color(0.085, 0.12, 0.14), 0.45, 0, 0.75))
	Forge.box(self, Vector3(-63, 5.7, 9), Vector3(12, 6.2, 14), Forge.material(Color(0.38, 0.42, 0.39)))
	Forge.box(self, Vector3(-63, 10, 9), Vector3(10, 2, 10), Forge.material(Color(0.075, 0.16, 0.18), 0.7))
	for x in [-19.0, 5.0, 29.0]:
		for z in range(-46, 32, 8):
			Forge.box(self, Vector3(x, -0.5, z), Vector3(7, 0.01, 0.07), Forge.material(Color(0.09, 0.24, 0.28), 0.6))
	Forge.label(self, Vector3(-8, 4.0, 39), "横桥换线 ← → CROSS DOCK", Color(0.53, 0.86, 0.87), 42)
	spawn_points = [ground_point(Vector3(-36, 0, -46)), ground_point(Vector3(-12, 0, -46)), ground_point(Vector3(12, 0, -46)), ground_point(Vector3(36, 0, -46))]
	_harbor_detail(crane_mat)
	_weather(false)

func _laboratory() -> void:
	spatial_type = "enclosed_annular_core_arena"
	combat_hint = "四向轮换尸潮 · E 关闭三个冷却阀"
	player_spawn = Vector3(0, 0.1, 34)
	boss_spawn = Vector3(0, 0.1, -42)
	menu_camera = Vector3(38, 28, 43)
	menu_focus = Vector3(0, 8, 0)
	fall_threshold = -2.0
	var floor_mat := Forge.material(Color(0.15, 0.16, 0.17), 0.35, 0, 0.78)
	var steel := Forge.material(Color(0.13, 0.14, 0.16), 0.75)
	var light_panel := Forge.material(Color(0.52, 0.56, 0.56), 0.3)
	var base := Forge.cylinder(self, Vector3(0, -0.3, 0), 49, 0.6, floor_mat)
	base.mesh.radial_segments = 64
	_add_cylinder_collision(Vector3(0, -0.3, 0), 49, 0.6)
	for x in GRID:
		for z in GRID:
			var cell := Vector2i(x, z)
			var pos := Vector2(-56 + x * 4, -56 + z * 4)
			if pos.length() <= 46 and pos.length() >= 11:
				grid.set_point_solid(cell, false)
				floor_heights[cell] = 0.0
	# Cylindrical core blocks sight and forces real clockwise/counter-clockwise flanks.
	var core_base := Forge.cylinder(self, Vector3(0, 7.5, 0), 8.3, 15, steel)
	core_base.mesh.radial_segments = 32
	_add_cylinder_collision(Vector3(0, 7.5, 0), 8.3, 15)
	for y in [2.0, 6.0, 10.0, 14.0]:
		_torus(Vector3(0, y, 0), 8.45, 0.11, Forge.material(Color(1, 0.27, 0.08), 0, 1.5))
	var core_light := Forge.cylinder(self, Vector3(0, 17, 0), 5.8, 7, Forge.material(Color(1, 0.11, 0.045), 0, 1.2))
	core_light.mesh.radial_segments = 32
	_torus(Vector3(0, 21, 0), 7, 0.25, steel)
	for i in 32:
		var a := i * TAU / 32
		var dir := Vector3(sin(a), 0, cos(a))
		if i % 8 != 0:
			var wall := Forge.box(self, dir * 48 + Vector3.UP * 5.5, Vector3(9.6, 11, 1.3), light_panel, true)
			wall.rotation.y = a
			var trim := Forge.box(self, dir * 47.25 + Vector3.UP * 3.4, Vector3(9.1, 0.22, 0.08), Forge.material(Color(0.17, 0.66, 0.76), 0, 0.8))
			trim.rotation.y = a
		Forge.cylinder(self, dir * 46 + Vector3.UP * 6, 0.22, 12, steel)
		var beam := Forge.box(self, dir * 31 + Vector3.UP * 12, Vector3(0.4, 0.4, 30), steel)
		beam.rotation.y = a
	for i in 4:
		var a := i * PI / 2
		var dir := Vector3(sin(a), 0, cos(a))
		var gate := Node3D.new()
		add_child(gate)
		gate.position = dir * 46
		gate.rotation.y = a
		for side in [-1, 1]:
			Forge.box(gate, Vector3(side * 4.8, 4, 0), Vector3(1, 8, 3), steel, true)
		Forge.box(gate, Vector3(0, 8, 0), Vector3(10.5, 1, 3), steel)
		# Enemies enter on the arena side. A physical rear bulkhead prevents
		# shotgun knockback from ejecting them off the circular floor.
		Forge.box(gate, Vector3(0, 3.5, 1.6), Vector3(8.6, 7, 0.4), steel, true)
		for side in [-1, 1]:
			Forge.box(gate, Vector3(side * 3.5, 3.5, 1.38), Vector3(0.14, 5.5, 0.04), Forge.material(Color(0.17, 0.66, 0.76), 0, 0.8))
		Forge.label(gate, Vector3(0, 6.5, -1.6), "AIRLOCK %s" % ["S", "E", "N", "W"][i], Color(0.72, 0.91, 0.9), 48)
		for r in range(15, 44, 5):
			Forge.box(self, dir * r + Vector3.UP * 0.022, Vector3(0.12, 0.02, 2) if i % 2 == 0 else Vector3(2, 0.02, 0.12), Forge.material(Color(0.73, 0.41, 0.12)))
	_torus(Vector3(0, 0.022, 0), 20, 0.04, Forge.material(Color(0.3, 0.52, 0.54), 0, 0.5))
	_torus(Vector3(0, 0.025, 0), 36, 0.04, Forge.material(Color(0.3, 0.52, 0.54), 0, 0.5))
	for p in [Vector3(-22, 0, -22), Vector3(22, 0, -22), Vector3(-22, 0, 22), Vector3(22, 0, 22)]:
		var cell := world_cell(p)
		var origin := cell - Vector2i.ONE
		_block(Rect2i(origin, Vector2i(2, 2)))
		var center := Vector3(-58 + (origin.x + 1) * 4, 0, -58 + (origin.y + 1) * 4)
		Forge.box(self, center + Vector3.UP * 2, Vector3(7.2, 4, 7.2), steel, true)
		for offset in [-1.8, 1.8]:
			Forge.cylinder(self, center + Vector3(offset, 5.8, 0), 0.7, 3.6, light_panel)
		Forge.box(self, center + Vector3(0, 2.7, 3.65), Vector3(5, 0.65, 0.08), Forge.material(Color(0.2, 0.69, 0.8), 0, 1))
	for p in [Vector3(-28, 0, 0), Vector3(28, 0, 16), Vector3(8, 0, -32)]:
		_terminal(p, terminals.size())
	for i in 8:
		var a := i * TAU / 8 + PI / 8
		_lamp(Vector3(sin(a) * 39, 0, cos(a) * 39), Color(0.66, 0.83, 0.9), 7)
	var glow := OmniLight3D.new()
	glow.position = Vector3(0, 17, 0)
	glow.omni_range = 43
	glow.light_color = Color(1, 0.24, 0.08)
	glow.light_energy = 3
	add_child(glow)
	spawn_points = [Vector3(0, 0, -42), Vector3(42, 0, 0), Vector3(0, 0, 42), Vector3(-42, 0, 0)]

func _terminal(pos: Vector3, index: int) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = pos
	Forge.box(root, Vector3(0, 0.65, 0), Vector3(1.4, 1.3, 1.1), Forge.material(Color(0.22, 0.24, 0.25), 0.65), true)
	var screen := Forge.box(root, Vector3(0, 1.45, -0.12), Vector3(1.2, 0.65, 0.18), Forge.material(Color(0.94, 0.3, 0.06), 0, 1))
	var valve := Forge.cylinder(root, Vector3(0, 1.6, 0.14), 0.32, 0.12, Forge.material(Color(0.53, 0.55, 0.53), 0.65))
	valve.rotation.x = PI / 2
	var name: String = "冷却阀 " + ["A", "B", "C"][index]
	var label := Forge.label(root, Vector3(0, 2.35, 0), name + " / E", Color(1, 0.65, 0.2), 36)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.01
	_block(Rect2i(world_cell(pos), Vector2i.ONE))
	terminals.append({"position": pos, "name": name, "activated": false, "screen": screen, "label": label})

func activate_terminal(index: int) -> void:
	var terminal: Dictionary = terminals[index]
	terminal.activated = true
	terminal.screen.material_override = Forge.material(Color(0.12, 0.69, 0.42), 0, 1)
	terminal.label.text = terminal.name + " / 已关闭"
	terminal.label.modulate = Color(0.25, 0.9, 0.6)

func _guardrails(color: Color) -> void:
	var mat := Forge.material(color, 0.6)
	for cell in floor_heights:
		for dir in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if floor_heights.has(cell + dir):
				continue
			var pos := cell_world(cell) + Vector3(dir.x * 2.0, 0, dir.y * 2.0)
			pos.y = surface_height(pos - Vector3(dir.x, 0, dir.y) * 0.05)
			var size := Vector3(0.13, 0.9, 4) if dir.x != 0 else Vector3(4, 0.9, 0.13)
			Forge.box(self, pos + Vector3.UP * 0.48, size, mat, true)

func _container(rect: Rect2i) -> void:
	var base := cell_world(rect.position)
	var center := base + Vector3((rect.size.x - 1) * 2, 0, (rect.size.y - 1) * 2)
	var color: Color = [Color(0.1, 0.25, 0.3), Color(0.43, 0.22, 0.11), Color(0.25, 0.31, 0.18)][rect.position.x % 3]
	for layer in 2:
		Forge.box(self, center + Vector3.UP * (1.45 + layer * 2.9), Vector3(rect.size.x * 4 - 0.25, 2.8, rect.size.y * 4 - 0.25), Forge.material(color, 0.5), layer == 0)
		for z in rect.size.y * 3:
			for side in [-1, 1]:
				Forge.box(self, center + Vector3(side * (rect.size.x * 2 - 0.1), 1.5 + layer * 2.9, -rect.size.y * 2 + 0.6 + z * 1.3), Vector3(0.08, 2.5, 0.08), Forge.material(color.darkened(0.35), 0.6))
		var door := Forge.material(color.darkened(0.35), 0.4, 0, 0.78)
		for side in [-1, 1]:
			var x: float = side * rect.size.x * 0.85
			Forge.box(self, center + Vector3(x, 1.45 + layer * 2.9, rect.size.y * 2 - 0.09), Vector3(rect.size.x * 1.6, 2.48, 0.035), door)
			Forge.cylinder(self, center + Vector3(x, 1.45 + layer * 2.9, rect.size.y * 2 - 0.04), 0.033, 2.25, Forge.material(Color(0.45, 0.45, 0.38), 0.7, 0, 0.65))
	_block(rect)
	Forge.label(self, center + Vector3(0, 1.8, rect.size.y * 2), "CARGO / %02d" % rect.position.y, Color(0.73, 0.83, 0.8), 40).pixel_size = 0.007

func _car(cell: Vector2i, burned: bool) -> void:
	if cell == Vector2i(15, 24):
		_build_police_car(cell)
	elif cell == Vector2i(11, 18):
		_build_civilian_car(cell)
	elif cell == Vector2i(7, 4):
		_build_burned_car(cell)
	elif cell == Vector2i(14, 3):
		_build_pickup_truck(cell)
	else:
		_build_civilian_car(cell)

func _build_police_car(cell: Vector2i) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = cell_world(cell)
	var paint_black := Forge.material(Color(0.06, 0.065, 0.07), 0.45, 0, 0.45)
	var paint_white := Forge.material(Color(0.85, 0.86, 0.87), 0.20, 0, 0.45)
	var dark_steel := Forge.material(Color(0.14, 0.16, 0.18), 0.75, 0, 0.50)
	var glass := Forge.material(Color(0.07, 0.11, 0.14), 0.20, 0, 0.25)
	var tire_mat := Forge.material(Color(0.04, 0.045, 0.05), 0.0, 0, 0.90)
	var rim_mat := Forge.material(Color(0.40, 0.42, 0.44), 0.65, 0, 0.40)
	var red_glow := Forge.material(Color(1.0, 0.15, 0.08), 0.0, 3.0, 0.2)
	var blue_glow := Forge.material(Color(0.12, 0.45, 1.0), 0.0, 3.0, 0.2)
	var head_glow := Forge.material(Color(1.0, 0.95, 0.85), 0.0, 2.0, 0.2)
	var amber_mat := Forge.material(Color(1.0, 0.65, 0.12), 0.0, 0.5, 0.4)

	Forge.box(root, Vector3(0, 0.62, 0), Vector3(1.85, 0.62, 4.2), paint_black, true)
	Forge.box(root, Vector3(0, 1.40, -0.15), Vector3(1.50, 0.06, 1.7), paint_white)
	for side in [-1, 1]:
		Forge.box(root, Vector3(side * 0.93, 0.70, -0.1), Vector3(0.04, 0.48, 1.5), paint_white)
	Forge.box(root, Vector3(0, 1.15, -0.15), Vector3(1.52, 0.62, 1.6), glass, true)
	Forge.box(root, Vector3(0, 0.65, 2.22), Vector3(1.70, 0.55, 0.12), dark_steel, true)
	for px in [-0.60, 0.60]:
		Forge.cylinder(root, Vector3(px, 0.65, 2.22), 0.04, 0.55, dark_steel)
	Forge.box(root, Vector3(0, 1.50, -0.15), Vector3(1.25, 0.05, 0.22), dark_steel)
	Forge.box(root, Vector3(-0.35, 1.56, -0.15), Vector3(0.55, 0.10, 0.20), red_glow)
	Forge.box(root, Vector3(0.35, 1.56, -0.15), Vector3(0.55, 0.10, 0.20), blue_glow)
	Forge.box(root, Vector3(0, 1.56, -0.15), Vector3(0.14, 0.09, 0.18), dark_steel)
	for x in [-0.94, 0.94]:
		for z in [-1.25, 1.25]:
			var tire := Forge.cylinder(root, Vector3(x, 0.38, z), 0.36, 0.22, tire_mat)
			tire.rotation.z = PI / 2
			var rim := Forge.cylinder(root, Vector3(x * 1.08, 0.38, z), 0.20, 0.04, rim_mat)
			rim.rotation.z = PI / 2
	for hx in [-0.62, 0.62]:
		Forge.box(root, Vector3(hx, 0.72, 2.12), Vector3(0.28, 0.12, 0.06), head_glow)
		Forge.box(root, Vector3(hx * 1.25, 0.72, 2.11), Vector3(0.12, 0.10, 0.05), amber_mat)
		Forge.box(root, Vector3(hx, 0.72, -2.12), Vector3(0.30, 0.12, 0.06), red_glow)
	for side in [-1, 1]:
		Forge.box(root, Vector3(side * 0.98, 1.15, 0.60), Vector3(0.16, 0.12, 0.14), paint_black)
	for side in [-1, 1]:
		var lbl := Forge.label(root, Vector3(side * 0.96, 0.75, -0.1), "POLICE", Color(0.15, 0.15, 0.15), 32)
		lbl.pixel_size = 0.006
		lbl.rotation.y = side * PI / 2
	_block(Rect2i(cell, Vector2i.ONE))

func _build_civilian_car(cell: Vector2i) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = cell_world(cell)
	var blue_paint := Forge.material(Color(0.16, 0.24, 0.30), 0.60, 0, 0.40)
	var dark_trim := Forge.material(Color(0.08, 0.09, 0.10), 0.30, 0, 0.60)
	var glass := Forge.material(Color(0.08, 0.12, 0.15), 0.20, 0, 0.25)
	var tire_mat := Forge.material(Color(0.04, 0.045, 0.05), 0.0, 0, 0.90)
	var rim_mat := Forge.material(Color(0.55, 0.58, 0.60), 0.75, 0, 0.35)
	var head_glow := Forge.material(Color(1.0, 0.95, 0.85), 0.0, 2.0, 0.2)
	var red_lens := Forge.material(Color(0.85, 0.12, 0.08), 0.0, 0.8, 0.3)
	var leather := Forge.material(Color(0.32, 0.20, 0.12), 0.0, 0, 0.85)

	Forge.box(root, Vector3(0, 0.58, 0), Vector3(1.80, 0.60, 4.0), blue_paint, true)
	Forge.box(root, Vector3(0, 1.12, -0.10), Vector3(1.48, 0.60, 1.8), glass, true)
	Forge.box(root, Vector3(0, 1.40, -0.10), Vector3(1.44, 0.06, 1.7), blue_paint)
	for x in [-0.92, 0.92]:
		for z in [-1.2, 1.2]:
			var tire := Forge.cylinder(root, Vector3(x, 0.36, z), 0.35, 0.20, tire_mat)
			tire.rotation.z = PI / 2
			var rim := Forge.cylinder(root, Vector3(x * 1.06, 0.36, z), 0.19, 0.04, rim_mat)
			rim.rotation.z = PI / 2
	for hx in [-0.58, 0.58]:
		Forge.box(root, Vector3(hx, 0.68, 2.02), Vector3(0.26, 0.11, 0.05), head_glow)
		Forge.box(root, Vector3(hx, 0.68, -2.02), Vector3(0.28, 0.11, 0.05), red_lens)
	Forge.box(root, Vector3(0, 0.62, 2.02), Vector3(0.70, 0.18, 0.04), dark_trim)
	var open_door := Forge.box(root, Vector3(1.02, 0.80, 0.15), Vector3(0.05, 0.52, 0.95), blue_paint)
	open_door.rotation.y = 0.35
	Forge.box(root, Vector3(1.65, 0.15, 0.30), Vector3(0.65, 0.28, 0.45), leather)
	Forge.box(root, Vector3(1.75, 0.10, -0.45), Vector3(0.55, 0.20, 0.38), dark_trim)
	_block(Rect2i(cell, Vector2i.ONE))

func _build_burned_car(cell: Vector2i) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = cell_world(cell)
	var charred_metal := Forge.material(Color(0.08, 0.085, 0.09), 0.25, 0, 0.90)
	var rust_metal := Forge.material(Color(0.22, 0.14, 0.09), 0.35, 0, 0.85)
	var soot_mat := Forge.material(Color(0.03, 0.03, 0.035), 0.0, 0, 0.98)
	var tire_mat := Forge.material(Color(0.04, 0.045, 0.05), 0.0, 0, 0.90)

	Forge.box(root, Vector3(0, 0.012, 0), Vector3(3.8, 0.015, 5.2), soot_mat)
	Forge.box(root, Vector3(0, 0.62, 0), Vector3(1.85, 0.65, 4.1), charred_metal, true)
	Forge.box(root, Vector3(0, 1.15, 0.10), Vector3(1.50, 0.60, 1.7), charred_metal, true)
	var hood := Forge.box(root, Vector3(0, 1.05, 1.45), Vector3(1.40, 0.05, 1.1), rust_metal)
	hood.rotation.x = -0.35
	Forge.box(root, Vector3(0, 0.70, 1.40), Vector3(0.70, 0.35, 0.65), rust_metal)
	for x in [-0.92, 0.92]:
		for z in [-1.2, 1.2]:
			if x > 0 and z > 0:
				var rotor := Forge.cylinder(root, Vector3(x * 0.95, 0.28, z), 0.20, 0.06, rust_metal)
				rotor.rotation.z = PI / 2
			else:
				var tire := Forge.cylinder(root, Vector3(x, 0.36, z), 0.35, 0.20, tire_mat)
				tire.rotation.z = PI / 2
	_block(Rect2i(cell, Vector2i.ONE))

func _build_pickup_truck(cell: Vector2i) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = cell_world(cell)
	var olive_paint := Forge.material(Color(0.24, 0.29, 0.22), 0.30, 0, 0.65)
	var dark_steel := Forge.material(Color(0.14, 0.16, 0.18), 0.70, 0, 0.55)
	var wood_crate := Forge.material(Color(0.42, 0.32, 0.20), 0.0, 0, 0.85)
	var fuel_can := Forge.material(Color(0.75, 0.18, 0.12), 0.20, 0, 0.60)
	var tire_mat := Forge.material(Color(0.04, 0.045, 0.05), 0.0, 0, 0.90)
	var glass := Forge.material(Color(0.08, 0.12, 0.15), 0.20, 0, 0.25)

	Forge.box(root, Vector3(0, 0.75, 0.5), Vector3(1.90, 0.70, 2.2), olive_paint, true)
	Forge.box(root, Vector3(0, 1.35, 0.3), Vector3(1.60, 0.65, 1.6), glass, true)
	Forge.box(root, Vector3(0, 1.68, 0.3), Vector3(1.55, 0.06, 1.5), olive_paint)
	Forge.box(root, Vector3(0, 0.50, -1.2), Vector3(1.85, 0.35, 2.0), olive_paint, true)
	for side in [-1, 1]:
		Forge.box(root, Vector3(side * 0.90, 0.85, -1.2), Vector3(0.08, 0.45, 2.0), olive_paint)
	Forge.box(root, Vector3(0, 0.85, -2.18), Vector3(1.75, 0.45, 0.08), olive_paint)
	Forge.box(root, Vector3(-0.35, 0.82, -1.1), Vector3(0.75, 0.55, 0.75), wood_crate)
	Forge.box(root, Vector3(0.45, 0.78, -0.9), Vector3(0.60, 0.50, 0.60), wood_crate)
	Forge.box(root, Vector3(0.42, 0.72, -1.6), Vector3(0.24, 0.38, 0.32), fuel_can)
	Forge.box(root, Vector3(0.12, 0.72, -1.6), Vector3(0.24, 0.38, 0.32), fuel_can)
	for x in [-0.96, 0.96]:
		for z in [-1.15, 1.15]:
			var tire := Forge.cylinder(root, Vector3(x, 0.45, z), 0.44, 0.26, tire_mat)
			tire.rotation.z = PI / 2
			var rim := Forge.cylinder(root, Vector3(x * 1.08, 0.45, z), 0.22, 0.05, dark_steel)
			rim.rotation.z = PI / 2
	Forge.box(root, Vector3(0, 0.65, 1.65), Vector3(1.95, 0.45, 0.22), dark_steel, true)
	_block(Rect2i(cell, Vector2i.ONE))

func _highway_substructure(concrete: Material) -> void:
	var girder_concrete := Forge.material(Color(0.28, 0.29, 0.29), 0.05, 0, 0.85)
	var dark_steel := Forge.material(Color(0.18, 0.20, 0.22), 0.70, 0, 0.55)
	var pvc_pipe := Forge.material(Color(0.12, 0.13, 0.14), 0.20, 0, 0.60)
	var bearing_mat := Forge.material(Color(0.08, 0.08, 0.09), 0.10, 0, 0.90)

	for gx in [-7.5, 0.5]:
		Forge.box(self, Vector3(gx, 2.5, 34.0), Vector3(1.1, 1.6, 40.0), girder_concrete)
	for dz in [18.0, 28.0, 38.0, 48.0]:
		Forge.box(self, Vector3(-3.5, 2.6, dz), Vector3(3.0, 1.4, 0.4), girder_concrete)
	for gz in [-2.0, 3.0]:
		Forge.box(self, Vector3(-26.0, 2.5, gz), Vector3(24.0, 1.6, 1.1), girder_concrete)
	for gx in [-28.0, -10.0]:
		Forge.box(self, Vector3(gx, 6.4, -38.0), Vector3(1.2, 1.8, 24.0), girder_concrete)
	for dz in [-44.0, -32.0]:
		Forge.box(self, Vector3(-19.0, 6.5, dz), Vector3(16.8, 1.6, 0.4), girder_concrete)

	for p in [Vector3(-8, 0, 28), Vector3(-8, 0, 12), Vector3(-28, 0, -2), Vector3(-28, 0, -36), Vector3(8, 0, -40)]:
		var top := ground_point(p)
		var support_top := top.y - 0.62
		Forge.box(self, Vector3(p.x, support_top * 0.5 - 4, p.z), Vector3(2.7, support_top + 8, 3.2), concrete)
		var cap_y := support_top - 0.55
		Forge.box(self, Vector3(p.x, cap_y, p.z), Vector3(4.8, 0.7, 3.2), concrete)
		for bx in [-1.5, 1.5]:
			Forge.box(self, Vector3(p.x + bx, support_top - 0.12, p.z), Vector3(0.6, 0.15, 0.6), bearing_mat)
		Forge.cylinder(self, Vector3(p.x + 1.42, (support_top - 4) * 0.5, p.z + 1.65), 0.07, support_top + 4, pvc_pipe)
		for pipe_y in range(0, int(support_top), 4):
			Forge.box(self, Vector3(p.x + 1.38, pipe_y, p.z + 1.62), Vector3(0.18, 0.06, 0.18), dark_steel)

func _highway_ruins(concrete: Material) -> void:
	var asphalt := ShaderMaterial.new()
	asphalt.shader = preload("res://shaders/asphalt.gdshader")
	var rusty_rebar := Forge.material(Color(0.28, 0.17, 0.11), 0.45, 0, 0.85)
	var galv := Forge.material(Color(0.52, 0.56, 0.58), 0.72, 0, 0.40)

	for x in [-40.0, 30.0]:
		Forge.box(self, Vector3(x, 13.1, 15), Vector3(30, 1.4, 14), concrete)
		Forge.box(self, Vector3(x, 13.85, 15), Vector3(30, 0.1, 13), asphalt)
		for support in [-8.0, 8.0]:
			Forge.box(self, Vector3(x + support, 2, 15), Vector3(2.4, 21, 3), concrete)

	for i in 9:
		var rebar := Forge.cylinder(self, Vector3(-24.5 + float(i % 3) * 0.4, 13.1 - float(i) * 0.18, 10.0 + i * 1.1), 0.035, 3.8 + (i % 3) * 1.2, rusty_rebar)
		rebar.rotation.z = PI / 2 - 0.25 * float(i % 3)
		rebar.rotation.y = (i % 2) * 0.2

	for side_z in [8.2, 21.8]:
		var bent_rail := Forge.box(self, Vector3(-24.0, 13.4, side_z), Vector3(3.2, 0.35, 0.1), galv)
		bent_rail.rotation.z = -0.45

	for i in 8:
		var rebar := Forge.cylinder(self, Vector3(14.5 - float(i % 3) * 0.4, 13.1 - float(i) * 0.18, 10.5 + i * 1.1), 0.035, 3.5 + (i % 3) * 1.1, rusty_rebar)
		rebar.rotation.z = -PI / 2 + 0.25 * float(i % 3)
	for side_z in [8.2, 21.8]:
		var bent_rail := Forge.box(self, Vector3(14.0, 13.4, side_z), Vector3(3.2, 0.35, 0.1), galv)
		bent_rail.rotation.z = 0.45

	var hung_lamp := Forge.cylinder(self, Vector3(-24.8, 14.5, 8.5), 0.07, 6.0, galv)
	hung_lamp.rotation.z = -0.75
	hung_lamp.rotation.y = 0.3

	for i in 5:
		var slab := Forge.box(self, Vector3(17 + i * 4, -5 + i * 0.9, 18), Vector3(5, 1.4, 8), concrete)
		slab.rotation_degrees = Vector3(17 + i * 4, 13 * i, 20)
	for i in 6:
		var rx := -10.0 + i * 5.0
		var rubble := Forge.box(self, Vector3(rx, -11.2, 15.0 + (i % 3) * 2.0), Vector3(3.5, 2.2, 4.0), concrete)
		rubble.rotation_degrees = Vector3(15 * (i % 3), 35 * i, -12 * (i % 2))

func _highway_guardrails() -> void:
	var concrete := Forge.material(Color(0.33, 0.34, 0.32))
	var galv := Forge.material(Color(0.52, 0.56, 0.58), 0.72, 0, 0.40)
	var post_steel := Forge.material(Color(0.24, 0.27, 0.29), 0.65, 0, 0.55)
	var refl_amber := Forge.material(Color(1.0, 0.72, 0.12), 0, 1.8, 0.2)
	var refl_red := Forge.material(Color(1.0, 0.18, 0.10), 0, 1.8, 0.2)
	for cell in floor_heights:
		for dir in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if floor_heights.has(cell + dir):
				continue
			var pos := cell_world(cell) + Vector3(dir.x * 2.0, 0, dir.y * 2.0)
			pos.y = surface_height(pos - Vector3(dir.x, 0, dir.y) * 0.05)
			var size := Vector3(0.13, 0.9, 4) if dir.x != 0 else Vector3(4, 0.9, 0.13)
			var body := StaticBody3D.new()
			body.position = pos + Vector3.UP * 0.48
			body.collision_layer = 1
			body.collision_mask = 0
			var col := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = size
			col.shape = shape
			body.add_child(col)
			add_child(body)

			var curb_size := Vector3(0.24, 0.32, 4.0) if dir.x != 0 else Vector3(4.0, 0.32, 0.24)
			Forge.box(self, pos + Vector3.UP * 0.16, curb_size, concrete)
			var rail_size := Vector3(0.08, 0.34, 4.0) if dir.x != 0 else Vector3(4.0, 0.34, 0.08)
			Forge.box(self, pos + Vector3.UP * 0.68, rail_size, galv)
			for offset in [-1.0, 1.0]:
				var post_pos := pos + (Vector3(0, 0, offset) if dir.x != 0 else Vector3(offset, 0, 0))
				Forge.box(self, post_pos + Vector3.UP * 0.46, Vector3(0.10, 0.88, 0.10), post_steel)
				var refl_offset := -Vector3(dir.x, 0, dir.y) * 0.09
				var refl_mat := refl_amber if (cell.x + cell.y) % 2 == 0 else refl_red
				Forge.box(self, post_pos + Vector3.UP * 0.72 + refl_offset, Vector3(0.04, 0.10, 0.06) if dir.x != 0 else Vector3(0.06, 0.10, 0.04), refl_mat)

func _highway_markings() -> void:
	var white_line := Forge.material(Color(0.88, 0.90, 0.88), 0.0, 0, 0.65)
	var yellow_line := Forge.material(Color(0.88, 0.70, 0.18), 0.0, 0, 0.55)
	var skid_mat := Forge.material(Color(0.04, 0.04, 0.045), 0.0, 0, 0.95)

	Forge.box(self, Vector3(-13.5, 4.018, 33.5), Vector3(0.18, 0.016, 39.0), white_line)
	Forge.box(self, Vector3(13.5, 4.018, 41.5), Vector3(0.18, 0.016, 23.0), white_line)
	Forge.box(self, Vector3(5.5, 4.018, 22.0), Vector3(0.18, 0.016, 16.0), white_line)
	Forge.box(self, Vector3(9.5, 4.018, 30.0), Vector3(8.0, 0.016, 0.18), white_line)

	for z in range(6, 50, 7):
		Forge.box(self, Vector3(-5, 4.017, z), Vector3(0.16, 0.018, 3.0), Forge.material(Color(0.7, 0.61, 0.3)))
		Forge.box(self, Vector3(-0.5, 4.017, z), Vector3(0.16, 0.018, 3.0), white_line)
		Forge.box(self, Vector3(-9.5, 4.017, z), Vector3(0.16, 0.018, 3.0), white_line)

	for x in range(-34, 26, 7):
		Forge.box(self, Vector3(x, 8.017, -40), Vector3(3, 0.018, 0.16), Forge.material(Color(0.7, 0.61, 0.3)))
		Forge.box(self, Vector3(x, 8.017, -35), Vector3(3, 0.018, 0.16), white_line)
	Forge.box(self, Vector3(-16.0, 8.018, -49.5), Vector3(44.0, 0.016, 0.18), white_line)
	Forge.box(self, Vector3(-16.0, 8.018, -26.5), Vector3(44.0, 0.016, 0.18), white_line)

	for y_offset in [-0.12, 0.12]:
		Forge.box(self, Vector3(-26.0, 4.018, -2.0 + y_offset), Vector3(23.0, 0.016, 0.15), yellow_line)

	for offset_x in [-0.85, 0.85]:
		for i in 6:
			var t: float = float(i) / 5.0
			var sz: float = 22.0 + t * 7.0
			var sx: float = -4.0 + float(offset_x) + sin(t * 1.5) * 1.2
			var skid := Forge.box(self, Vector3(sx, 4.020, sz), Vector3(0.24, 0.012, 1.4), skid_mat)
			skid.rotation.y = -0.15 * t

func _highway_gantry() -> void:
	var steel := Forge.material(Color(0.25, 0.28, 0.30), 0.70, 0, 0.45)
	var dark_metal := Forge.material(Color(0.12, 0.14, 0.16), 0.80, 0, 0.55)
	var sign_green := Forge.material(Color(0.045, 0.20, 0.14), 0.15, 0, 0.65)
	var border_white := Forge.material(Color(0.88, 0.90, 0.88), 0.10, 0, 0.50)
	var vms_screen := Forge.material(Color(0.02, 0.025, 0.03), 0.0, 0, 0.95)
	var amber_glow := Forge.material(Color(1.0, 0.60, 0.12), 0.0, 3.2, 0.20)
	var flood_glow := Forge.material(Color(1.0, 0.90, 0.75), 0.0, 2.5, 0.20)

	for tower_x in [-14.2, 1.8]:
		Forge.box(self, Vector3(float(tower_x), 4.2, 28.0), Vector3(0.8, 0.4, 0.8), dark_metal)
		for dx in [-0.26, 0.26]:
			for dz in [-0.26, 0.26]:
				Forge.cylinder(self, Vector3(float(tower_x) + float(dx), 7.8, 28.0 + float(dz)), 0.045, 7.2, steel)
		for y in [5.4, 7.0, 8.6, 10.2]:
			Forge.box(self, Vector3(float(tower_x), float(y), 28.0), Vector3(0.60, 0.06, 0.60), steel)

	var truss_span := 16.0
	var truss_center_x := -6.2
	for ty in [10.4, 11.6]:
		for tz in [27.7, 28.3]:
			var chord := Forge.cylinder(self, Vector3(truss_center_x, ty, tz), 0.045, truss_span, steel)
			chord.rotation.z = PI / 2
	for i in 12:
		var x_step := -13.6 + i * 1.25
		Forge.box(self, Vector3(x_step, 11.0, 28.0), Vector3(0.05, 1.2, 0.6), steel)

	Forge.box(self, Vector3(truss_center_x, 9.9, 28.0), Vector3(truss_span - 0.8, 0.08, 0.9), dark_metal)
	Forge.box(self, Vector3(truss_center_x, 10.7, 27.5), Vector3(truss_span - 0.8, 0.05, 0.05), steel)

	Forge.box(self, Vector3(-9.2, 10.65, 28.30), Vector3(7.4, 2.3, 0.10), sign_green)
	Forge.box(self, Vector3(-9.2, 10.65, 28.27), Vector3(7.5, 2.4, 0.05), border_white)
	var sign_lbl := Forge.label(self, Vector3(-9.2, 10.65, 28.38), "出口 07     EXIT 07     >>\n新城高架 · 前方断桥坍塌\nBRIDGE COLLAPSED - 500m", Color(0.88, 0.98, 0.92), 44)
	sign_lbl.pixel_size = 0.010
	for fx in [-11.5, -6.9]:
		Forge.box(self, Vector3(fx, 11.95, 28.55), Vector3(0.35, 0.12, 0.35), dark_metal)
		Forge.box(self, Vector3(fx, 11.90, 28.55), Vector3(0.28, 0.04, 0.28), flood_glow)
		_beam(Vector3(fx, 11.6, 28.3), Vector3(fx, 11.95, 28.55), 0.04, steel)

	Forge.box(self, Vector3(-2.2, 10.65, 28.30), Vector3(5.6, 2.1, 0.16), dark_metal)
	Forge.box(self, Vector3(-2.2, 10.65, 28.36), Vector3(5.3, 1.8, 0.04), vms_screen)
	var vms_lbl := Forge.label(self, Vector3(-2.2, 10.65, 28.40), "[!] 警报: 余烬禁区 · 全线封锁 [!]\nBIOHAZARD - EVAC TERMINATED\n! 严禁通行  NO PASSAGE !", Color(1.0, 0.65, 0.12), 34)
	vms_lbl.pixel_size = 0.009
	for bx in [-4.8, 0.4]:
		Forge.cylinder(self, Vector3(bx, 11.85, 28.34), 0.10, 0.24, amber_glow)

	var gantry_light := OmniLight3D.new()
	gantry_light.position = Vector3(-5.5, 9.8, 28.2)
	gantry_light.light_color = Color(1.0, 0.75, 0.45)
	gantry_light.light_energy = 1.8
	gantry_light.omni_range = 14.0
	gantry_light.shadow_enabled = false
	add_child(gantry_light)

func _highway_ramp_sign() -> void:
	var dark_steel := Forge.material(Color(0.18, 0.20, 0.22), 0.70, 0, 0.55)
	var sign_yellow := Forge.material(Color(0.85, 0.65, 0.10), 0.10, 0, 0.60)
	var border_black := Forge.material(Color(0.08, 0.08, 0.09), 0.0, 0, 0.80)
	Forge.cylinder(self, Vector3(-17.5, 7.0, -1.0), 0.14, 6.0, dark_steel)
	_beam(Vector3(-17.5, 9.8, -1.0), Vector3(-28.0, 9.8, -1.0), 0.12, dark_steel)
	Forge.box(self, Vector3(-26.0, 9.7, -1.0), Vector3(7.2, 1.6, 0.10), sign_yellow)
	Forge.box(self, Vector3(-26.0, 9.7, -0.98), Vector3(7.4, 1.7, 0.04), border_black)
	var label := Forge.label(self, Vector3(-26.0, 9.7, -0.92), "前方连续坡道 · 减速慢行\n>> STEEP UPHILL GRADE - REDUCE SPEED >>", Color(0.1, 0.1, 0.1), 38)
	label.pixel_size = 0.010

func _highway_props() -> void:
	var dark_steel := Forge.material(Color(0.18, 0.20, 0.22), 0.70, 0, 0.55)
	var rust_drum := Forge.material(Color(0.42, 0.22, 0.12), 0.35, 0, 0.80)
	var yellow_drum := Forge.material(Color(0.85, 0.65, 0.10), 0.20, 0, 0.55)

	for cp in [Vector3(1.0, 4.0, 35.0), Vector3(0.0, 4.0, 36.5), Vector3(-1.2, 4.0, 38.0), Vector3(-11.5, 4.0, 15.5), Vector3(4.0, 8.0, -38.0)]:
		_traffic_cone(cp)

	_jersey_barrier(Vector3(3.5, 4.0, 31.0), 0.25)
	_jersey_barrier(Vector3(-10.5, 4.0, 16.0), -0.40)
	_jersey_barrier(Vector3(-22.0, 8.0, -48.0), 0.0)

	_oil_drum(Vector3(2.4, 4.0, 34.0), false, rust_drum)
	_oil_drum(Vector3(3.1, 4.0, 34.6), false, yellow_drum)
	_oil_drum(Vector3(-13.0, 4.0, 20.0), true, rust_drum)

	Forge.box(self, Vector3(-13.6, 4.9, 32.0), Vector3(0.35, 1.8, 0.35), Forge.material(Color(0.96, 0.45, 0.08)))
	Forge.box(self, Vector3(-13.6, 5.1, 32.2), Vector3(0.30, 0.45, 0.15), Forge.material(Color(0.10, 0.35, 0.85)))
	var sos_lbl := Forge.label(self, Vector3(-13.6, 5.1, 32.29), "SOS", Color(1, 1, 1), 32)
	sos_lbl.pixel_size = 0.007
	var panel := Forge.box(self, Vector3(-13.6, 5.95, 32.0), Vector3(0.55, 0.04, 0.45), dark_steel)
	panel.rotation.x = 0.4

func _traffic_cone(pos: Vector3) -> void:
	Forge.box(self, pos + Vector3.UP * 0.02, Vector3(0.36, 0.04, 0.36), Forge.material(Color(0.12, 0.12, 0.12)))
	Forge.cylinder(self, pos + Vector3.UP * 0.35, 0.14, 0.70, Forge.material(Color(0.96, 0.38, 0.06)), 0.03)
	Forge.cylinder(self, pos + Vector3.UP * 0.36, 0.11, 0.14, Forge.material(Color(0.92, 0.94, 0.92), 0.1, 0.5, 0.4), 0.08)

func _jersey_barrier(pos: Vector3, rot_y: float) -> void:
	var barrier := Forge.box(self, pos + Vector3.UP * 0.42, Vector3(2.4, 0.84, 0.55), Forge.material(Color(0.35, 0.36, 0.35)), true)
	barrier.rotation.y = rot_y
	for i in 4:
		var stripe := Forge.box(barrier, Vector3(-0.9 + i * 0.6, 0.0, 0.28), Vector3(0.24, 0.65, 0.02), Forge.material(Color(0.92, 0.68, 0.12) if i % 2 == 0 else Color(0.1, 0.1, 0.1)))
		stripe.rotation.z = 0.5

func _oil_drum(pos: Vector3, tipped: bool, mat: Material) -> void:
	var drum := Forge.cylinder(self, pos + Vector3.UP * (0.28 if tipped else 0.45), 0.28, 0.88, mat)
	if tipped:
		drum.rotation.z = PI / 2
		drum.rotation.y = 0.5
	else:
		for hy in [0.22, 0.66]:
			Forge.cylinder(self, pos + Vector3.UP * hy, 0.295, 0.04, mat)

func _highway_cobra_lamp(pos: Vector3, color: Color, height: float, arm_dir: Vector3) -> void:
	var steel := Forge.material(Color(0.24, 0.27, 0.29), 0.65, 0, 0.45)
	var dark_metal := Forge.material(Color(0.12, 0.14, 0.16), 0.8, 0, 0.5)
	var lamp_glow := Forge.material(color, 0, 3.2, 0.2)
	Forge.box(self, pos + Vector3.UP * 0.1, Vector3(0.5, 0.2, 0.5), dark_metal)
	Forge.cylinder(self, pos + Vector3.UP * (height * 0.5), 0.12, height, steel, 0.08)
	var arm_len := 2.6
	var dir := arm_dir.normalized()
	var tip_pos := pos + Vector3.UP * (height + 0.5) + dir * arm_len
	var mid_pos := pos + Vector3.UP * (height + 0.3) + dir * (arm_len * 0.5)
	_beam(pos + Vector3.UP * (height - 0.2), mid_pos, 0.09, steel)
	_beam(mid_pos, tip_pos, 0.08, steel)
	var head := Forge.box(self, tip_pos + Vector3.DOWN * 0.08, Vector3(0.42, 0.16, 0.85), dark_metal)
	head.look_at(tip_pos + dir)
	var lens := Forge.box(self, tip_pos + Vector3.DOWN * 0.14, Vector3(0.32, 0.05, 0.65), lamp_glow)
	lens.look_at(tip_pos + dir)
	var light := OmniLight3D.new()
	light.position = tip_pos + Vector3.DOWN * 0.35
	light.light_color = color
	light.light_energy = 2.8
	light.omni_range = 16.0
	light.shadow_enabled = false
	add_child(light)

func _highway_lamps() -> void:
	var lamp_color := Color(1.0, 0.65, 0.28)
	_highway_cobra_lamp(Vector3(2, 4, 32), lamp_color, 6.8, Vector3(-1, 0, 0))
	_highway_cobra_lamp(Vector3(-14, 4, 14), lamp_color, 6.8, Vector3(1, 0, 0))
	_highway_cobra_lamp(Vector3(-35, 4, -2), lamp_color, 6.8, Vector3(0, 0, 1))
	_highway_cobra_lamp(Vector3(-35, 8, -35), lamp_color, 6.8, Vector3(1, 0, 0))
	_highway_cobra_lamp(Vector3(20, 8, -35), lamp_color, 6.8, Vector3(-1, 0, 0))

func _highway_backdrop(concrete: Material) -> void:
	var dark_facade := Forge.material(Color(0.10, 0.13, 0.15), 0.2, 0, 0.8)
	var dark_steel := Forge.material(Color(0.14, 0.16, 0.18), 0.7, 0, 0.55)
	var red_beacon := Forge.material(Color(1.0, 0.10, 0.05), 0.0, 3.5, 0.2)

	Forge.box(self, Vector3(0, -12.4, 0), Vector3(400, 0.4, 400), Forge.material(Color(0.065, 0.07, 0.075)))

	for i in 28:
		var a := i * TAU / 28.0 + 0.05
		var dist := 72.0 + (i % 4) * 16.0
		var p := Vector3(sin(a), 0, cos(a)) * dist
		var h := 16.0 + (i % 7) * 5.5
		Forge.box(self, p + Vector3(0, h * 0.5 - 12, 0), Vector3(12.0, h, 14.0), dark_facade)
		_city_facade(p, h, i)
		if h > 24.0:
			var crown_h := h * 0.35
			Forge.box(self, p + Vector3(0, h - 12 + crown_h * 0.5, 0), Vector3(8.0, crown_h, 9.0), dark_facade)
			Forge.cylinder(self, p + Vector3(0, h - 12 + crown_h + 3.0, 0), 0.08, 6.0, dark_steel)
			Forge.sphere(self, p + Vector3(0, h - 12 + crown_h + 6.0, 0), 0.25, red_beacon)
			if i % 3 == 0:
				Forge.cylinder(self, p + Vector3(2.5, h - 12 + crown_h + 1.2, 2.0), 1.2, 2.4, Forge.material(Color(0.28, 0.20, 0.14)))
			elif i % 3 == 1:
				Forge.box(self, p + Vector3(-2.0, h - 12 + crown_h + 0.8, -1.5), Vector3(2.8, 1.6, 2.2), dark_steel)

	for ring in [Vector3(0, 16.0, -110.0), Vector3(-110.0, 22.0, 10.0), Vector3(115.0, 18.0, -30.0)]:
		Forge.box(self, ring, Vector3(90.0, 1.8, 12.0), concrete)
		Forge.box(self, ring + Vector3.DOWN * 10.0, Vector3(3.2, 20.0, 3.2), concrete)

	var bb_pos := Vector3(-24.0, 0.0, 48.0)
	Forge.cylinder(self, bb_pos + Vector3.UP * 9.0, 0.42, 18.0, dark_steel)
	Forge.box(self, bb_pos + Vector3.UP * 18.0, Vector3(14.0, 5.5, 0.4), dark_steel)
	Forge.box(self, bb_pos + Vector3(0, 18.0, -0.22), Vector3(13.6, 5.1, 0.05), Forge.material(Color(0.12, 0.14, 0.16)))
	var bb_lbl := Forge.label(self, bb_pos + Vector3(0, 18.0, -0.28), "[!] CINDER BIO-SCIENCES [!]\nQUARANTINE SECTOR 01 · 禁区封锁\nEVACUATION TERMINATED // NO SURVIVORS", Color(1.0, 0.80, 0.55), 44)
	bb_lbl.pixel_size = 0.012
	for fx in [-5.0, 5.0]:
		Forge.box(self, bb_pos + Vector3(fx, 21.2, -1.2), Vector3(0.4, 0.2, 0.4), dark_steel)
		_beam(bb_pos + Vector3(fx, 20.5, 0.0), bb_pos + Vector3(fx, 21.2, -1.2), 0.06, dark_steel)

	for z in [42.0, 38.0, 34.0]:
		for side in [-1, 1]:
			var mark := Forge.box(self, Vector3(side * 8.4, 4.034, z), Vector3(1.1, 0.014, 0.20), Forge.material(Color(0.68, 0.46, 0.17), 0, 0, 0.91))
			mark.rotation.y = side * 0.55
	for x in [-25.0, 15.0]:
		for i in 5:
			var z := 11.0 + i * 1.65
			_beam(Vector3(x, 13.45, z), Vector3(x + (2 if x < 0 else -2), 12.85, z + 0.45), 0.045, Forge.material(Color(0.25, 0.16, 0.095), 0.4, 0, 0.84))
	for pos in [Vector3(-13, 4, 36), Vector3(-33, 8, -34)]:
		Forge.box(self, pos + Vector3(0, 0.16, 0), Vector3(0.65, 0.32, 0.75), concrete)
		for i in 3:
			var slab := Forge.box(self, pos + Vector3(i * 0.30, 0.08, 0.45 + i * 0.22), Vector3(0.35, 0.12, 0.55), concrete)
			slab.rotation.y = i * 0.7

func _beam(a: Vector3, b: Vector3, thickness: float, material: Material) -> void:
	var beam := Forge.box(self, (a + b) * 0.5, Vector3(thickness, thickness, a.distance_to(b)), material)
	beam.look_at(b)

func _city_facade(p: Vector3, height: float, index: int) -> void:
	var frame := Forge.material(Color(0.12, 0.135, 0.15), 0.2)
	var glass := Forge.material(Color(0.16, 0.24, 0.29), 0.25, 0, 0.7)
	var lit := Forge.material(Color(0.58, 0.39, 0.19), 0, 0.20)
	var cyan_lit := Forge.material(Color(0.22, 0.55, 0.62), 0, 0.25)
	for y in range(-7, int(height - 13), 4):
		for x in [-3.4, -1.2, 1.2, 3.4]:
			for side in [-1, 1]:
				var is_lit := (index + y + int(x * 3)) % 7 == 0
				var lit_mat := cyan_lit if (index + int(x)) % 3 == 0 else lit
				var window := Forge.box(self, p + Vector3(x, y, side * 6.015), Vector3(1.05, 1.65, 0.035), lit_mat if is_lit else glass)
				window.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Forge.box(self, p + Vector3(0, height - 11.6, 0), Vector3(10.6, 0.55, 12.6), frame)
	Forge.box(self, p + Vector3(2, height - 10.7, 1), Vector3(2.5, 1.25, 3.0), frame)

func _ship_hull(center: Vector3, material: Material) -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	for section in [Vector2(-30, 1.8), Vector2(-22, 7.5), Vector2(20, 7.5), Vector2(30, 0.45)]:
		rings.append([center + Vector3(-section.y, 3.8, section.x), center + Vector3(section.y, 3.8, section.x), center + Vector3(section.y * 0.62, -0.8, section.x), center + Vector3(-section.y * 0.62, -0.8, section.x)])
	for i in range(rings.size() - 1):
		for face in 4:
			var next := (face + 1) % 4
			for vertex in [rings[i][face], rings[i + 1][face], rings[i + 1][next], rings[i][face], rings[i + 1][next], rings[i][next]]:
				tool.add_vertex(vertex)
	tool.generate_normals()
	var visual := MeshInstance3D.new()
	visual.mesh = tool.commit()
	visual.material_override = material
	add_child(visual)

func _harbor_detail(crane_material: Material) -> void:
	var rubber := Forge.material(Color(0.035, 0.04, 0.04), 0, 0, 0.92)
	var rust := Forge.material(Color(0.29, 0.18, 0.10), 0.45, 0, 0.83)
	var rail := Forge.material(Color(0.40, 0.40, 0.34), 0.5, 0, 0.7)
	for x in [-36.0, -12.0, 12.0, 36.0]:
		for z in [-38.0, -24.0, 3.0, 24.0, 42.0]:
			for side in [-1, 1]:
				var p := ground_point(Vector3(x + side * 5.3, 0, z))
				Forge.cylinder(self, p + Vector3.UP * 0.28, 0.18, 0.56, rust)
				Forge.box(self, p + Vector3.UP * 0.57, Vector3(0.65, 0.09, 0.22), rail)
				var fender := Forge.cylinder(self, p + Vector3(side * 0.55, -0.37, 0), 0.43, 0.19, rubber)
				fender.rotation.z = PI / 2
	for x in [-32.0, 40.0]:
		for y in [3.0, 9.0, 15.0]:
			_beam(Vector3(x - 7, y, -30), Vector3(x + 7, y + 6, -30), 0.19, crane_material)
			_beam(Vector3(x + 7, y, -30), Vector3(x - 7, y + 6, -30), 0.19, crane_material)
		Forge.box(self, Vector3(x, 21, -27), Vector3(3.5, 2.6, 3.5), crane_material)
		Forge.box(self, Vector3(x, 21.3, -25.2), Vector3(2.8, 1.4, 0.08), Forge.material(Color(0.065, 0.13, 0.16), 0.2, 0, 0.35))
	for x in [-84.0, 70.0, 98.0]:
		Forge.box(self, Vector3(x, 7, -74), Vector3(23, 14, 32), Forge.material(Color(0.20, 0.23, 0.23), 0.2, 0, 0.87))
		Forge.box(self, Vector3(x, 14.6, -74), Vector3(25, 1.2, 34), Forge.material(Color(0.12, 0.15, 0.16), 0.45, 0, 0.8))
	for z in range(-27, 15, 6):
		for side in [-1, 1]:
			Forge.cylinder(self, Vector3(-63 + side * 7.2, 4.5, z), 0.045, 1.4, rail)
			Forge.box(self, Vector3(-63 + side * 7.2, 5.15, z), Vector3(0.06, 0.06, 6), rail)
	Forge.box(self, Vector3(-70.4, 2.65, -12), Vector3(0.045, 0.27, 39), Forge.material(Color(0.46, 0.23, 0.11), 0.3))
	Forge.label(self, Vector3(-62.9, 7.8, 16.1), "C I N D E R  /  0 7", Color(0.63, 0.65, 0.56), 48).pixel_size = 0.012

func _lamp(pos: Vector3, color: Color, height: float) -> void:
	Forge.cylinder(self, pos + Vector3.UP * height * 0.5, 0.07, height, Forge.material(Color(0.14, 0.18, 0.19), 0.7))
	Forge.box(self, pos + Vector3(0.4, height, 0), Vector3(1.1, 0.15, 0.45), Forge.material(color, 0, 1.7))
	var light := OmniLight3D.new()
	light.position = pos + Vector3(0.4, height - 0.25, 0)
	light.light_color = color
	light.light_energy = 2.4
	light.omni_range = 13
	add_child(light)

func _add_cylinder_collision(pos: Vector3, radius: float, height: float) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	collision.shape = shape
	body.add_child(collision)
	add_child(body)

func _torus(pos: Vector3, radius: float, thickness: float, material: Material) -> void:
	var visual := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius - thickness
	mesh.outer_radius = radius + thickness
	mesh.rings = 64
	mesh.ring_segments = 8
	visual.mesh = mesh
	visual.material_override = material
	visual.position = pos
	add_child(visual)

func _weather(ash: bool) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.045, 0.075, 0.045) if ash else Vector3(0.008, 0.38, 0.008)
	var shader := Shader.new()
	if ash:
		shader.code = "shader_type spatial;\nrender_mode unshaded, cull_disabled, depth_draw_never;\nvarying flat float is_ember;\nvoid vertex() {\n\tVERTEX.y -= mod(TIME * 2.4 + float(INSTANCE_ID) * 0.17, 26.0);\n\tVERTEX.x += sin(TIME * 0.85 + float(INSTANCE_ID) * 0.31) * 0.6;\n\tVERTEX.z += cos(TIME * 0.65 + float(INSTANCE_ID) * 0.47) * 0.5;\n\tis_ember = (INSTANCE_ID % 3 == 0) ? 1.0 : 0.0;\n}\nvoid fragment() {\n\tALBEDO = (is_ember > 0.5) ? vec3(1.0, 0.44, 0.12) : vec3(0.24, 0.22, 0.20);\n\tALPHA = (is_ember > 0.5) ? 0.85 : 0.32;\n}"
	else:
		shader.code = "shader_type spatial; render_mode unshaded, cull_disabled, depth_draw_never; void vertex(){ VERTEX.y -= mod(TIME * 18.0 + float(INSTANCE_ID) * 0.13, 26.0); } void fragment(){ ALBEDO = vec3(0.47,0.57,0.62); ALPHA = 0.28; }"
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = 360 if ash else 240
	for i in multi.instance_count:
		multi.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(rng.randf_range(-56, 56), 26, rng.randf_range(-56, 56))))
	var visual := MultiMeshInstance3D.new()
	visual.multimesh = multi
	visual.material_override = mat
	visual.custom_aabb = AABB(Vector3(-58, 0, -58), Vector3(116, 30, 116))
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if is_instance_valid(game) and game.test_mode:
		visual.visible = false
	add_child(visual)

func _bake_static_geometry() -> void:
	var batches: Dictionary = {}
	for visual in find_children("*", "MeshInstance3D", true, false):
		# Interactable screens must remain independently recolorable.
		if not terminals.is_empty() and terminals.any(func(t: Dictionary): return t.screen == visual):
			continue
		if visual.mesh == null or visual.material_override == null:
			continue
		var key := str(visual.material_override.get_instance_id()) + ":" + str(visual.cast_shadow)
		if not batches.has(key):
			var tool := SurfaceTool.new()
			tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			tool.set_material(visual.material_override)
			batches[key] = {"tool": tool, "shadow": visual.cast_shadow}
		batches[key].tool.append_from(visual.mesh, 0, global_transform.affine_inverse() * visual.global_transform)
		for child in visual.get_children():
			if child is StaticBody3D:
				child.reparent(self, true)
		visual.queue_free()
	for key in batches:
		var visual := MeshInstance3D.new()
		visual.mesh = batches[key].tool.commit()
		visual.cast_shadow = batches[key].shadow
		add_child(visual)

func world_cell(pos: Vector3) -> Vector2i:
	return Vector2i(clampi(int((pos.x + HALF) / CELL), 0, GRID - 1), clampi(int((pos.z + HALF) / CELL), 0, GRID - 1))

func cell_world(cell: Vector2i) -> Vector3:
	var pos := Vector3(-56 + cell.x * CELL, 0, -56 + cell.y * CELL)
	pos.y = surface_height(pos)
	return pos

func surface_height(pos: Vector3) -> float:
	for ramp in ramps:
		if ramp.rect.has_point(Vector2(pos.x, pos.z)):
			return lerpf(ramp.high, ramp.low, (pos.z - ramp.rect.position.y) / ramp.rect.size.y)
	return float(floor_heights.get(world_cell(pos), 0))

func ground_point(pos: Vector3) -> Vector3:
	return Vector3(pos.x, surface_height(pos), pos.z)

func ground_angle(pos: Vector3) -> float:
	for ramp in ramps:
		if ramp.rect.has_point(Vector2(pos.x, pos.z)):
			return atan2(ramp.high - ramp.low, ramp.rect.size.y)
	return 0.0

func is_walkable_point(pos: Vector3) -> bool:
	return absf(pos.x) < HALF and absf(pos.z) < HALF and not grid.is_point_solid(world_cell(pos))

func nearest_open(cell: Vector2i) -> Vector2i:
	if not grid.is_point_solid(cell):
		return cell
	for radius in range(1, GRID):
		for x in range(-radius, radius + 1):
			for z in range(-radius, radius + 1):
				if absi(x) != radius and absi(z) != radius:
					continue
				var candidate := cell + Vector2i(x, z)
				if grid.is_in_boundsv(candidate) and not grid.is_point_solid(candidate):
					return candidate
	return world_cell(player_spawn)

func safe_ground(pos: Vector3) -> Vector3:
	return cell_world(nearest_open(world_cell(pos)))

func find_enemy_spawn(requested: Vector3, size_factor: float) -> Dictionary:
	# Validate against real static collision, not just the A* grid. This also
	# applies to summons and recovery, so no actor is counted before placement.
	var shape := CapsuleShape3D.new()
	shape.radius = 0.32 * size_factor
	shape.height = 1.9 * size_factor
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1
	var origin := nearest_open(world_cell(requested))
	var target := nearest_open(world_cell(game.player.position)) if is_instance_valid(game.player) else world_cell(player_spawn)
	var candidates: Array[Vector3] = []
	if is_walkable_point(requested):
		candidates.append(ground_point(requested))
	for radius in range(0, 5):
		for x in range(-radius, radius + 1):
			for z in range(-radius, radius + 1):
				if radius > 0 and absi(x) != radius and absi(z) != radius:
					continue
				var cell := origin + Vector2i(x, z)
				if grid.is_in_boundsv(cell) and not grid.is_point_solid(cell):
					candidates.append(cell_world(cell))
	for candidate in candidates:
		var position := candidate + Vector3.UP * 0.12
		query.transform = Transform3D(Basis.IDENTITY, position + Vector3.UP * 0.95 * size_factor)
		if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			continue
		if grid.get_id_path(world_cell(candidate), target).is_empty():
			continue
		return {"position": position}
	return {}

func path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var result := PackedVector3Array()
	var cells := grid.get_id_path(nearest_open(world_cell(from)), nearest_open(world_cell(to)))
	for i in range(1, cells.size()):
		result.append(cell_world(cells[i]))
	result.append(ground_point(to) if is_walkable_point(to) else safe_ground(to))
	return result
