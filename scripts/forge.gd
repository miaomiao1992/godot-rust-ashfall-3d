class_name Forge
extends RefCounted

static var materials: Dictionary = {}

static func material(color: Color, metallic: float = 0.0, glow: float = 0.0, roughness: float = -1.0) -> StandardMaterial3D:
	var key := str([color, metallic, glow, roughness])
	if materials.has(key):
		return materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness if roughness >= 0 else (0.83 if metallic == 0 else 0.44)
	mat.metallic = metallic
	if glow > 0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = glow
	materials[key] = mat
	return mat

static func box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material, solid: bool = false) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = mat
	visual.position = pos
	parent.add_child(visual)
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		if mat is StandardMaterial3D:
			var color: Color = mat.albedo_color
			body.set_meta("surface", "metal" if mat.metallic > 0.35 else "wood" if color.r > color.b * 1.7 and color.r > color.g * 1.25 else "concrete")
		var shape := BoxShape3D.new()
		shape.size = size
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		visual.add_child(body)
	return visual

static func cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, mat: Material, top: float = -1.0, segments: int = 16) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top < 0 else top
	mesh.height = height
	mesh.radial_segments = segments
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = mat
	visual.position = pos
	parent.add_child(visual)
	return visual

static func sphere(parent: Node3D, pos: Vector3, radius: float, mat: Material, segments: int = 20, rings: int = 12) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = segments
	mesh.rings = rings
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = mat
	visual.position = pos
	parent.add_child(visual)
	return visual

static func torus(parent: Node3D, pos: Vector3, inner_r: float, outer_r: float, mat: Material, segments: int = 16) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner_r
	mesh.outer_radius = outer_r
	mesh.rings = segments
	mesh.ring_segments = 8
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = mat
	visual.position = pos
	parent.add_child(visual)
	return visual

static func label(parent: Node3D, pos: Vector3, text: String, color: Color, size: int = 64) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.pixel_size = 0.014
	label.modulate = color
	label.outline_size = 3
	label.position = pos
	parent.add_child(label)
	return label
