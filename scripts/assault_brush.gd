extends StaticBody3D
## Original brush collision; breakable grilles and proximity-opening doors.
var level
var brush_id := 0
var entity: Dictionary
var bounds := AABB()
var health := 0.0
var broken := false
var door := false
var door_offset := Vector3.ZERO
var open_amount := 0.0
var door_wait := 0.0

func configure() -> void:
	collision_layer = 1
	collision_mask = 0
	health = float(entity.get("health", "0")) if entity.get("classname", "") == "func_breakable" else 0
	door = entity.get("classname", "") in ["func_door", "func_door_rotating"]
	set_meta("surface", "metal" if int(entity.get("material", "0")) in [2, 7] else "concrete")
	if door:
		var angle := deg_to_rad(float(entity.get("angle", "0")))
		var direction := Vector3(cos(angle), 0, -sin(angle))
		if entity.get("classname") == "func_door_rotating": direction = Vector3(0, 1, 0)
		var travel := absf(direction.dot(bounds.size))
		door_offset = direction * (travel + 0.08)
	set_process(door)

func receive_damage(damage: float) -> void:
	if health <= 0 or broken: return
	if level.game.is_lan() and not level.game.lan.host(): return
	health -= damage
	if health <= 0:
		break_brush()
		level.game.lan.net.send_event("assault_break", JSON.stringify({"id": brush_id}))

func break_brush() -> void:
	broken = true
	collision_layer = 0
	for child in get_children():
		if child is MeshInstance3D: child.visible = false
		if child is StaticBody3D: child.collision_layer = 0

func _process(delta: float) -> void:
	var near := false
	if level.game.is_lan():
		for p in level.game.lan.players.values():
			if p.life == "alive" and bounds.grow(1.4).has_point(p.position + Vector3.UP): near = true
	if near: door_wait = 4.0
	else: door_wait = maxf(0, door_wait - delta)
	open_amount = move_toward(open_amount, 1.0 if door_wait > 0 else 0.0, delta * 2.5)
	position = door_offset * open_amount
