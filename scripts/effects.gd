extends Node3D

var items: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
var game

func _ready() -> void:
	rng.randomize()

func burst(pos: Vector3, direction: Vector3, color: Color, amount: int = 7, force: float = 3.0) -> void:
	for i in amount:
		var size := rng.randf_range(0.035, 0.095)
		var visual := Forge.box(self, pos, Vector3.ONE * size, Forge.material(color))
		visual.rotation = Vector3(rng.randf() * 6, rng.randf() * 6, 0)
		var vel := direction * rng.randf_range(0.4, force) + Vector3(rng.randf_range(-1.4, 1.4), rng.randf_range(0.5, 3.2), rng.randf_range(-1.4, 1.4))
		items.append({"node": visual, "vel": vel, "life": rng.randf_range(0.28, 0.7), "gravity": 7.0})

func tracer(start: Vector3, end: Vector3, color: Color = Color(1.0, 0.66, 0.24)) -> void:
	var distance := start.distance_to(end)
	if distance < 0.1:
		return
	var visual := Forge.box(self, (start + end) * 0.5, Vector3(0.013, 0.013, distance), Forge.material(color, 0, 3))
	visual.look_at(end)
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	items.append({"node": visual, "vel": Vector3.ZERO, "life": 0.045, "gravity": 0.0})

func casing(pos: Vector3, right: Vector3) -> void:
	var visual := Forge.box(self, pos, Vector3(0.028, 0.028, 0.09), Forge.material(Color(0.7, 0.5, 0.18), 0.7))
	items.append({"node": visual, "vel": right * rng.randf_range(1.5, 3.0) + Vector3.UP * 2.2, "life": 1.5, "gravity": 9.0})

func corpse(pos: Vector3, color: Color, scale_factor: float, direction: Vector3) -> void:
	var body := Node3D.new()
	add_child(body)
	body.position = pos + Vector3(0, 0.25, 0)
	body.rotation.y = atan2(direction.x, direction.z)
	body.rotation.x = PI / 2
	Forge.box(body, Vector3(0, 0.0, 0), Vector3(0.58, 0.75, 0.35) * scale_factor, Forge.material(color))
	Forge.box(body, Vector3(0, 0.56, 0), Vector3.ONE * 0.35 * scale_factor, Forge.material(Color(0.28, 0.33, 0.27)))
	Forge.box(body, Vector3(-0.18, -0.66, 0), Vector3(0.22, 0.65, 0.24) * scale_factor, Forge.material(Color(0.11, 0.15, 0.16)))
	Forge.box(body, Vector3(0.18, -0.66, 0), Vector3(0.22, 0.65, 0.24) * scale_factor, Forge.material(Color(0.11, 0.15, 0.16)))
	items.append({"node": body, "vel": Vector3.ZERO, "life": 6.0, "gravity": 0.0})
	var stain := Forge.cylinder(self, Vector3(pos.x, 0.015, pos.z), rng.randf_range(0.4, 0.75), 0.008, Forge.material(Color(0.19, 0.035, 0.03)))
	items.append({"node": stain, "vel": Vector3.ZERO, "life": 18.0, "gravity": 0.0})

func retain_corpse(model: Node3D, animation: AnimationPlayer, pos: Vector3) -> void:
	var corpses := 0
	for item in items:
		if item.get("corpse", false):
			corpses += 1
	if corpses >= 14:
		for i in items.size():
			if items[i].get("corpse", false):
				items[i].node.queue_free()
				items.remove_at(i)
				break
	model.reparent(self, true)
	if animation and animation.has_animation("death"):
		animation.speed_scale = 1
		animation.play("death", 0.08)
	else:
		if animation:
			animation.stop()
		var tween := create_tween()
		tween.tween_property(model, "rotation:x", -PI / 2, 0.45)
	items.append({"node": model, "vel": Vector3.ZERO, "life": 7.0, "gravity": 0.0, "corpse": true})
	var stain := Forge.cylinder(self, Vector3(pos.x, 0.015, pos.z), rng.randf_range(0.4, 0.7), 0.008, Forge.material(Color(0.19, 0.035, 0.03)))
	items.append({"node": stain, "vel": Vector3.ZERO, "life": 15.0, "gravity": 0.0})

func _process(delta: float) -> void:
	for i in range(items.size() - 1, -1, -1):
		var item: Dictionary = items[i]
		item.life -= delta
		if item.life <= 0:
			item.node.queue_free()
			items.remove_at(i)
			continue
		item.vel.y -= item.gravity * delta
		item.node.position += item.vel * delta
		if item.gravity > 0:
			item.node.rotation += Vector3(3, 5, 2) * delta
			if item.node.position.y < 0.04:
				item.node.position.y = 0.04
				item.vel *= 0.35
				item.vel.y = absf(item.vel.y)
