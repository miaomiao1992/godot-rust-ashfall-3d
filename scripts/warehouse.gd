extends "res://scripts/level.gd"
## CS 1.6 cs_assault, converted from GoldSrc BSP v30 at 40 units/metre.
## PvP only: no hostage entities or rescue objective are instantiated.
const MAP_DIR := "res://assets/maps/cs_assault/"
const BrushScript = preload("res://scripts/assault_brush.gd")
const SurfaceScript = preload("res://scripts/assault_surface.gd")
const ROOF_HEIGHT := 12.0
var team_spawns: Array = [[], []]
var spawn_yaws: Array = [[], []]
var pipe_routes: Array[Dictionary] = []
var roof_routes: Array[Dictionary] = []
var ladders: Array[AABB] = []
var brush_nodes: Dictionary = {}
var navigation: NavigationRegion3D
var map_data: Dictionary
var navigation_ready := false
var scene_materials: Array[ShaderMaterial] = []

static func goldsrc(point: Vector3) -> Vector3:
	return Vector3(point.x, point.z, 1536 - point.y) / 40.0

func generate(_index: int) -> void:
	stage = 3
	spatial_type = "cs_assault_16"
	combat_hint = "CS 1.6 Assault · 正门 / 后门 / 屋顶通风管 · Ctrl 蹲伏 / W、S 爬梯"
	fall_threshold = -8
	menu_camera = goldsrc(Vector3(1400, 700, 1100))
	menu_focus = goldsrc(Vector3(0, 2200, 240))
	map_data = JSON.parse_string(FileAccess.get_file_as_string(MAP_DIR + "map.json"))
	assert(not map_data.is_empty(), "Original Assault geometry is required")
	navigation = NavigationRegion3D.new()
	navigation.name = "AssaultNavigation"
	var navmesh := NavigationMesh.new()
	navmesh.agent_height = 0.9
	navmesh.agent_radius = 0.3
	navmesh.agent_max_climb = 0.3
	navmesh.cell_size = 0.1
	navmesh.cell_height = 0.1
	navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	NavigationServer3D.map_set_cell_size(get_world_3d().navigation_map, 0.1)
	NavigationServer3D.map_set_cell_height(get_world_3d().navigation_map, 0.1)
	navmesh.filter_baking_aabb = AABB(Vector3(-40, -1, -45), Vector3(80, 25, 95))
	navigation.navigation_mesh = navmesh
	add_child(navigation)
	var materials: Array[Material] = []
	for texture in map_data.textures:
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://shaders/assault_baked.gdshader")
		if not str(texture.path).is_empty(): mat.set_shader_parameter("base_texture", load(MAP_DIR + str(texture.path)))
		mat.set_shader_parameter("baked_light", load(MAP_DIR + "lightmap.png"))
		mat.set_shader_parameter("masked", str(texture.name).begins_with("{"))
		materials.append(mat)
		scene_materials.append(mat)
	for model in map_data.models:
		if model.surfaces.is_empty(): continue
		var brush = BrushScript.new()
		brush.name = "BSPBrush_%d" % int(model.model)
		brush.level = self
		brush.brush_id = int(model.model)
		brush.entity = model.entity
		var bounds: Dictionary = map_data.model_bounds[int(model.model)]
		var a := _vec(bounds.min)
		var b := _vec(bounds.max)
		brush.bounds = AABB(a.min(b), a.max(b) - a.min(b))
		navigation.add_child(brush)
		brush_nodes[brush.brush_id] = brush
		for surface in model.surfaces:
			var arrays: Array = []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = _vectors3(surface.vertices)
			arrays[Mesh.ARRAY_NORMAL] = _vectors3(surface.normals)
			arrays[Mesh.ARRAY_TEX_UV] = _vectors2(surface.uv)
			arrays[Mesh.ARRAY_TEX_UV2] = _vectors2(surface.uv2)
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var visual := MeshInstance3D.new()
			visual.mesh = mesh
			var material: Material = materials[int(surface.texture)]
			if str(brush.entity.get("rendermode", "0")) == "2":
				material = material.duplicate()
				material.shader = preload("res://shaders/assault_glass.gdshader")
				scene_materials.append(material)
			visual.material_override = material
			brush.add_child(visual)
			if brush.entity.get("classname", "") != "func_illusionary":
				var body = SurfaceScript.new()
				body.brush = brush
				body.collision_layer = 1
				body.collision_mask = 0
				body.set_meta("surface", texture_surface(str(map_data.textures[int(surface.texture)].name)))
				brush.add_child(body)
				var shape := ConcavePolygonShape3D.new()
				shape.set_faces(arrays[Mesh.ARRAY_VERTEX])
				shape.backface_collision = true
				var collider := CollisionShape3D.new()
				collider.shape = shape
				body.add_child(collider)
		brush.configure()
	for entity in map_data.entities:
		var cls: String = entity.get("classname", "")
		if cls in ["info_player_start", "info_player_deathmatch"]:
			var team := 0 if cls == "info_player_start" else 1
			var origin := goldsrc(_origin(entity.origin))
			# GoldSrc spawn origin is capsule centre; ASHFALL origin is feet.
			team_spawns[team].append(origin - Vector3.UP * 0.9)
			spawn_yaws[team].append(deg_to_rad(-float(entity.get("angle", "0")) - 90))
		elif cls == "func_ladder":
			var bounds: Dictionary = map_data.model_bounds[int(str(entity.model).trim_prefix("*"))]
			var a := _vec(bounds.min)
			var b := _vec(bounds.max)
			ladders.append(AABB(a.min(b), a.max(b) - a.min(b)))
	player_spawn = spawn_for(0, 0)
	# Route coordinates are documented in original BSP units, not fabricated pipes.
	pipe_routes = [{"entry": goldsrc(Vector3(0, 2464, 516)), "exit": goldsrc(Vector3(0, 2784, 336))},
		{"entry": goldsrc(Vector3(0, 2464, 436)), "exit": goldsrc(Vector3(-576, 2464, 336))}]
	grid.region = Rect2i(0, 0, GRID, GRID)
	grid.cell_size = Vector2(CELL, CELL)
	grid.offset = Vector2(-56, -56)
	grid.update()
	call_deferred("_bake_navigation")

func _bake_navigation() -> void:
	navigation.bake_navigation_mesh(false)
	for ladder in ladders:
		var center := ladder.get_center()
		var link := NavigationLink3D.new()
		link.start_position = Vector3(center.x, ladder.position.y + 0.1, center.z)
		link.end_position = Vector3(center.x, ladder.end.y + 0.1, center.z)
		link.bidirectional = true
		add_child(link)
	for brush in brush_nodes.values():
		if not brush.door: continue
		var link := NavigationLink3D.new()
		var center: Vector3 = brush.bounds.get_center()
		center.y = brush.bounds.position.y + 0.1
		var normal := Vector3.RIGHT if brush.bounds.size.x < brush.bounds.size.z else Vector3.FORWARD
		link.start_position = center - normal * 1.2
		link.end_position = center + normal * 1.2
		add_child(link)
	NavigationServer3D.region_set_navigation_mesh(navigation.get_rid(), navigation.navigation_mesh)
	NavigationServer3D.map_force_update(get_world_3d().navigation_map)
	navigation_ready = true

func update_daylight(daylight: float) -> void:
	var tint := Color(0.45, 0.57, 0.78).lerp(Color(1.05, 1.03, 1.0), daylight)
	for material in scene_materials: material.set_shader_parameter("atmosphere", Vector3(tint.r, tint.g, tint.b))

func texture_surface(texture: String) -> String:
	var lower := texture.to_lower()
	if "crate" in lower or "out_box" in lower or "wood" in lower: return "wood"
	for word in ["duct", "vent", "container", "metal", "rail", "ladder", "trk_", "galv", "c1a4tnnl", "generic64"]:
		if word in lower: return "metal"
	return "concrete"

func route(from: Vector3, to: Vector3) -> PackedVector3Array:
	if not navigation_ready: return PackedVector3Array()
	return NavigationServer3D.map_get_path(get_world_3d().navigation_map, from, to, true)

func spawn_for(team: int, slot: int) -> Vector3:
	var entries: Array = team_spawns[clampi(team, 0, 1)]
	return entries[posmod(slot, entries.size())]

func spawn_yaw(team: int, slot: int) -> float:
	var entries: Array = spawn_yaws[clampi(team, 0, 1)]
	return entries[posmod(slot, entries.size())]

func ladder_at(feet: Vector3) -> AABB:
	for ladder in ladders:
		if ladder.grow(0.45).has_point(feet + Vector3.UP * 0.4): return ladder
	return AABB()

func snapshot_brushes() -> Array:
	var result: Array = []
	for brush in brush_nodes.values():
		if brush.broken: result.append(brush.brush_id)
	return result

func apply_brushes(ids: Array) -> void:
	for id in ids:
		if brush_nodes.has(int(id)): brush_nodes[int(id)].break_brush()

func _vec(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))

func _origin(text: String) -> Vector3:
	var parts := text.split(" ", false)
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))

func _vectors3(values: Array) -> PackedVector3Array:
	var result := PackedVector3Array()
	for i in range(0, values.size(), 3): result.append(Vector3(values[i], values[i + 1], values[i + 2]))
	return result

func _vectors2(values: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in range(0, values.size(), 2): result.append(Vector2(values[i], values[i + 1]))
	return result
