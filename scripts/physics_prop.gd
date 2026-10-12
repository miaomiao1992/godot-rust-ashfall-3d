extends RigidBody3D
## Only the authority simulates: replicas are frozen kinematic colliders.
var arena
var prop_id := 0
var kind := "crate"
var hp := 65.0
var broken := false
var lifetime := -1.0
var target_transform := Transform3D.IDENTITY
var push_cooldown := 0.0
var visual: Node3D

func _ready() -> void:
	collision_layer = 1
	collision_mask = 1
	continuous_cd = true
	linear_damp = 0.4
	angular_damp = 0.8
	var physical := PhysicsMaterial.new()
	physical.friction = 0.7
	physical.bounce = 0.15
	physics_material_override = physical
	freeze = not arena.authority()
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	visual = Node3D.new()
	add_child(visual)
	var collider := CollisionShape3D.new()
	var steel := Forge.material(Color(0.2, 0.27, 0.29), 0.65, 0, 0.72)
	var wood := Forge.material(Color(0.43, 0.28, 0.14), 0, 0, 0.93)
	var shape := BoxShape3D.new()
	match kind:
		"drum":
			mass = 18
			hp = 100
			set_meta("surface", "metal")
			var cylinder := CylinderShape3D.new()
			cylinder.radius = 0.38
			cylinder.height = 1.05
			collider.shape = cylinder
			var paint := Forge.material(Color(0.27, 0.38, 0.15), 0.45, 0, 0.79)
			var drum := Forge.cylinder(visual, Vector3.ZERO, 0.38, 1.05, paint)
			drum.mesh.radial_segments = 20
			for y in [-0.42, 0.42]: Forge.cylinder(visual, Vector3(0, y, 0), 0.40, 0.07, steel).mesh.radial_segments = 20
			Forge.box(visual, Vector3(0, 0, 0.383), Vector3(0.23, 0.22, 0.012), Forge.material(Color(0.92, 0.72, 0.16)))
		"cone":
			mass = 2
			hp = 9999
			set_meta("surface", "plastic")
			shape.size = Vector3(0.45, 0.65, 0.45)
			collider.shape = shape
			Forge.box(visual, Vector3(0, -0.29, 0), Vector3(0.48, 0.07, 0.48), steel)
			Forge.cylinder(visual, Vector3(0, 0.025, 0), 0.22, 0.58, Forge.material(Color(1, 0.32, 0.08)), 0.045)
			Forge.cylinder(visual, Vector3(0, 0.08, 0), 0.11, 0.10, Forge.material(Color(0.86, 0.9, 0.88)), 0.08)
		"plank", "scrap":
			mass = 1.2
			hp = 9999
			shape.size = Vector3(0.7, 0.13, 0.22)
			collider.shape = shape
			Forge.box(visual, Vector3.ZERO, shape.size, wood if kind == "plank" else steel)
			set_meta("surface", "wood" if kind == "plank" else "metal")
		_:
			mass = 12
			set_meta("surface", "wood")
			shape.size = Vector3.ONE * 0.9
			collider.shape = shape
			Forge.box(visual, Vector3.ZERO, shape.size, wood)
			for y in [-0.35, 0.35]:
				Forge.box(visual, Vector3(0, y, 0), Vector3(0.94, 0.10, 0.94), steel)
	add_child(collider)
	target_transform = global_transform

func shot(damage: float, point: Vector3, direction: Vector3, force: float) -> void:
	if not arena.authority() or broken: return
	sleeping = false
	apply_impulse(direction * clampf(force * 4.5, 2, 45), point - global_position)
	hurt(damage)

func hurt(damage: float) -> void:
	if broken or kind in ["cone", "plank", "scrap"]: return
	hp = maxf(0, hp - damage)
	if hp == 0: arena.break_prop(self)

func push(direction: Vector3) -> void:
	if not arena.authority() or broken or push_cooldown > 0: return
	push_cooldown = 0.15
	sleeping = false
	apply_central_impulse(direction * minf(mass, 12) * 0.7)

func set_broken() -> void:
	broken = true
	visual.visible = false
	collision_layer = 0
	freeze = true

func _process(delta: float) -> void:
	push_cooldown = maxf(0, push_cooldown - delta)
	if not arena.authority() and not broken:
		global_transform = global_transform.interpolate_with(target_transform, minf(1, delta * 20))
