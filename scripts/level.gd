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
	for p in [Vector3(-8, 0, 28), Vector3(-8, 0, 12), Vector3(-28, 0, -2), Vector3(-28, 0, -36), Vector3(8, 0, -40)]:
		var top := ground_point(p)
		# Stop below the 0.6 m bridge slab. Flush concrete/asphalt top faces
		# produced flickering rectangular patches and diagonal depth-fight lines.
		var support_top := top.y - 0.62
		Forge.box(self, Vector3(p.x, support_top * 0.5 - 4, p.z), Vector3(2.7, support_top + 8, 3.2), concrete)
	for z in range(6, 50, 7):
		Forge.box(self, Vector3(-5, 4.017, z), Vector3(0.16, 0.018, 3.0), Forge.material(Color(0.7, 0.61, 0.3)))
	for x in range(-34, 26, 7):
		Forge.box(self, Vector3(x, 8.017, -40), Vector3(3, 0.018, 0.16), Forge.material(Color(0.7, 0.61, 0.3)))
	# A second highway crosses overhead and has visibly broken-away ends.
	for x in [-40.0, 30.0]:
		Forge.box(self, Vector3(x, 13.1, 15), Vector3(30, 1.4, 14), concrete)
		Forge.box(self, Vector3(x, 13.85, 15), Vector3(30, 0.1, 13), asphalt)
		for support in [-8.0, 8.0]:
			Forge.box(self, Vector3(x + support, 2, 15), Vector3(2.4, 21, 3), concrete)
	for i in 7:
		var steel := Forge.cylinder(self, Vector3(-23 + i * 0.45, 13.2, 15), 0.035, 4.5, Forge.material(Color(0.18, 0.17, 0.14), 0.6))
		steel.rotation.z = PI / 2
	for i in 4:
		var slab := Forge.box(self, Vector3(17 + i * 4, -5 + i * 0.9, 18), Vector3(5, 1.4, 8), concrete)
		slab.rotation_degrees = Vector3(17 + i * 4, 13 * i, 20)
	_car(Vector2i(11, 18), false)
	_car(Vector2i(15, 24), true)
	_car(Vector2i(7, 4), true)
	_car(Vector2i(14, 3), false)
	_guardrails(Color(0.41, 0.43, 0.4))
	for p in [Vector3(2, 4, 32), Vector3(-14, 4, 14), Vector3(-35, 4, -2), Vector3(-35, 8, -35), Vector3(20, 8, -35)]:
		_lamp(p, Color(1, 0.48, 0.2), 6.5)
	var sign := Forge.label(self, Vector3(-8, 9.6, 28), "EXIT 07  ←  BRIDGE COLLAPSED", Color(0.65, 0.88, 0.77), 56)
	sign.pixel_size = 0.011
	Forge.box(self, Vector3(-8, 10, 28.1), Vector3(15, 2, 0.25), Forge.material(Color(0.055, 0.19, 0.15)))
	Forge.label(self, Vector3(-28, 9.7, -1), "前方坡道 / UPHILL", Color(1, 0.64, 0.24), 36)
	# The city is below the suspended route, rather than a playable flat street grid.
	for i in 24:
		var a := i * TAU / 24
		var p := Vector3(sin(a), 0, cos(a)) * 69
		var h := 12 + (i % 5) * 4
		Forge.box(self, p + Vector3(0, h * 0.5 - 12, 0), Vector3(10, h, 12), Forge.material(Color(0.1, 0.16, 0.19)))
		_city_facade(p, h, i)
	_highway_detail(concrete)
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
	var root := Node3D.new()
	add_child(root)
	root.position = cell_world(cell)
	var metal := Forge.material(Color(0.12, 0.13, 0.13) if burned else Color(0.25, 0.35, 0.37), 0.55)
	Forge.box(root, Vector3(0, 0.65, 0), Vector3(1.75, 0.75, 3.2), metal, true)
	Forge.box(root, Vector3(0, 1.15, 0.2), Vector3(1.5, 0.65, 1.6), Forge.material(Color(0.05, 0.09, 0.1), 0.6), true)
	for x in [-0.89, 0.89]:
		for z in [-1, 1]:
			Forge.cylinder(root, Vector3(x, 0.4, z), 0.35, 0.18, Forge.material(Color(0.045, 0.05, 0.05))).rotation.z = PI / 2
			var rim := Forge.cylinder(root, Vector3(x * 1.10, 0.4, z), 0.17, 0.035, Forge.material(Color(0.20, 0.21, 0.20), 0.55, 0, 0.7))
			rim.rotation.z = PI / 2
	var trim := Forge.material(Color(0.06, 0.065, 0.065), 0.2)
	for z in [-1.62, 1.62]:
		Forge.box(root, Vector3(0, 0.55, z), Vector3(1.68, 0.16, 0.075), trim)
		for x in [-0.58, 0.58]:
			Forge.box(root, Vector3(x, 0.80, z), Vector3(0.28, 0.11, 0.055), Forge.material(Color(0.30, 0.27, 0.17) if burned else Color(0.61, 0.57, 0.40), 0, 0.18))
	for side in [-1, 1]:
		Forge.box(root, Vector3(side * 0.76, 1.18, 0.2), Vector3(0.025, 0.37, 1.2), Forge.material(Color(0.10, 0.17, 0.19), 0.15, 0, 0.35))
		Forge.box(root, Vector3(side * 0.79, 1.15, 0.25), Vector3(0.04, 0.65, 0.055), metal)
		Forge.box(root, Vector3(side * 0.9, 0.77, 0.12), Vector3(0.045, 0.04, 0.22), trim)
	_block(Rect2i(cell, Vector2i.ONE))

func _beam(a: Vector3, b: Vector3, thickness: float, material: Material) -> void:
	var beam := Forge.box(self, (a + b) * 0.5, Vector3(thickness, thickness, a.distance_to(b)), material)
	beam.look_at(b)

func _city_facade(p: Vector3, height: float, index: int) -> void:
	var frame := Forge.material(Color(0.12, 0.135, 0.15), 0.2)
	var glass := Forge.material(Color(0.16, 0.24, 0.29), 0.25, 0, 0.7)
	var lit := Forge.material(Color(0.58, 0.39, 0.19), 0, 0.20)
	for y in range(-7, int(height - 13), 4):
		for x in [-3.4, -1.2, 1.2, 3.4]:
			for side in [-1, 1]:
				var window := Forge.box(self, p + Vector3(x, y, side * 6.015), Vector3(1.05, 1.65, 0.035), lit if (index + y + int(x * 3)) % 7 == 0 else glass)
				window.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Forge.box(self, p + Vector3(0, height - 11.6, 0), Vector3(10.6, 0.55, 12.6), frame)
	Forge.box(self, p + Vector3(2, height - 10.7, 1), Vector3(2.5, 1.25, 3.0), frame)

func _highway_detail(concrete: Material) -> void:
	var rust := Forge.material(Color(0.25, 0.16, 0.095), 0.4, 0, 0.84)
	var paint := Forge.material(Color(0.68, 0.46, 0.17), 0, 0, 0.91)
	Forge.box(self, Vector3(0, -12.4, 0), Vector3(400, 0.4, 400), Forge.material(Color(0.07, 0.075, 0.08)))
	for i in 18:
		var angle := i * TAU / 18 + 0.08
		var height := 28.0 + (i % 6) * 7.5
		var p := Vector3(sin(angle) * 135, height * 0.5 - 12, cos(angle) * 135)
		Forge.box(self, p, Vector3(10 + i % 4 * 3, height, 13), Forge.material(Color(0.105, 0.13, 0.145)))
		Forge.box(self, p + Vector3(0, height * 0.5 + 1, 0), Vector3(7, 2, 9), Forge.material(Color(0.075, 0.09, 0.105)))
	for z in [42.0, 38.0, 34.0]:
		for side in [-1, 1]:
			var mark := Forge.box(self, Vector3(side * 8.4, 4.034, z), Vector3(1.1, 0.014, 0.20), paint)
			mark.rotation.y = side * 0.55
	for x in [-25.0, 15.0]:
		for i in 5:
			var z := 11.0 + i * 1.65
			_beam(Vector3(x, 13.45, z), Vector3(x + (2 if x < 0 else -2), 12.85, z + 0.45), 0.045, rust)
	for pos in [Vector3(-13, 4, 36), Vector3(-33, 8, -34)]:
		Forge.box(self, pos + Vector3(0, 0.16, 0), Vector3(0.65, 0.32, 0.75), concrete)
		for i in 3:
			var slab := Forge.box(self, pos + Vector3(i * 0.30, 0.08, 0.45 + i * 0.22), Vector3(0.35, 0.12, 0.55), concrete)
			slab.rotation.y = i * 0.7

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
	mesh.size = Vector3(0.03, 0.07, 0.03) if ash else Vector3(0.008, 0.38, 0.008)
	var shader := Shader.new()
	shader.code = "shader_type spatial; render_mode unshaded, cull_disabled, depth_draw_never; void vertex(){ VERTEX.y -= mod(TIME * " + ("1.8" if ash else "18.0") + " + float(INSTANCE_ID) * 0.13, 26.0); } void fragment(){ ALBEDO = vec3(" + ("0.7,0.25,0.08" if ash else "0.47,0.57,0.62") + "); ALPHA = 0.28; }"
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = 240
	for i in multi.instance_count:
		multi.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(rng.randf_range(-56, 56), 26, rng.randf_range(-56, 56))))
	var visual := MultiMeshInstance3D.new()
	visual.multimesh = multi
	visual.material_override = mat
	visual.custom_aabb = AABB(Vector3(-58, 0, -58), Vector3(116, 30, 116))
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
