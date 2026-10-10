extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for object in [RigidBody3D.new(), PinJoint3D.new(), ConeTwistJoint3D.new(), Environment.new()]:
		for property in object.get_property_list():
			if property.name.begins_with("params/") or property.name in ["fog_sky_affect", "fog_height", "fog_height_density", "ambient_light_sky_contribution", "shadow_bias", "node_a", "node_b", "freeze", "linear_damp", "angular_damp"]:
				print(object.get_class(), " ", property.name, " = ", object.get(property.name))
		if object is Node: object.free()
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.test_mode = true
	game.start_run()
	game.state = "testing"
	for kind in [0, 2]:
		var enemy = game._spawn_add(Vector3(-8, 4, 32), kind)
		enemy.set_physics_process(false)
		enemy.animation.pause()
		print("RIG ", kind, " clips=", enemy.animation.get_animation_list())
		for bone in enemy.skeleton.get_bone_count():
			print(bone, " ", enemy.skeleton.get_bone_name(bone), " parent=", enemy.skeleton.get_bone_parent(bone), " world=", enemy.skeleton.to_global(enemy.skeleton.get_bone_global_pose(bone).origin))
	quit()
