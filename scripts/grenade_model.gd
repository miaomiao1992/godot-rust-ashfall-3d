class_name GrenadeModel
extends RefCounted
## Authentic Counter-Strike 3D Grenade Replicas:
## 0: M67 HE Grenade (Spherical fragmentation, equator weld, M213 fuze, curved lever, pull ring)
## 1: M84 Flashbang (Cylindrical vented stun body, white band, exhaust ports, M201A1 fuze)
## 2: M18 Smoke Grenade (Tin canister with rolled rims, vent holes, stencil band, safety spoon)

static func build(parent: Node3D, kind: int, is_first_person: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "GrenadeMesh_%d" % kind
	parent.add_child(root)
	match kind:
		0: _build_he_grenade(root, is_first_person)
		1: _build_flashbang(root, is_first_person)
		2: _build_smoke_grenade(root, is_first_person)
		_: _build_he_grenade(root, is_first_person)
	return root

# --- 1. CS M67 HE Grenade (高爆手雷) ---
static func _build_he_grenade(root: Node3D, is_fp: bool) -> void:
	var segs: int = 24 if is_fp else 16
	var rings: int = 16 if is_fp else 10
	var scale_mul: float = 1.35 if is_fp else 1.0
	var od_green := Forge.material(Color(0.22, 0.32, 0.16), 0.15, 0, 0.65)
	var steel := Forge.material(Color(0.25, 0.28, 0.30), 0.85, 0, 0.35)
	var zinc_lever := Forge.material(Color(0.32, 0.36, 0.38), 0.75, 0, 0.45)
	var yellow_band := Forge.material(Color(0.88, 0.76, 0.18), 0.1, 0, 0.55)
	var silver_pin := Forge.material(Color(0.88, 0.90, 0.94), 0.92, 0, 0.18)
	var red_tip := Forge.material(Color(0.88, 0.18, 0.14), 0.2, 0, 0.5)

	var r: float = 0.046 * scale_mul
	# Main spherical fragmentation body
	var body := Forge.sphere(root, Vector3(0, 0, 0), r, od_green, segs, rings)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Equatorial weld seam rim
	var weld := Forge.torus(root, Vector3(0, 0, 0), r * 0.96, r * 1.03, od_green, segs)
	weld.rotation.x = PI / 2
	weld.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Upper yellow identification stencil ring
	var band := Forge.torus(root, Vector3(0, r * 0.55, 0), r * 0.72, r * 0.81, yellow_band, segs)
	band.rotation.x = PI / 2
	band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# M213 Fuze assembly on top
	var collar_y: float = r * 1.08
	var collar := Forge.cylinder(root, Vector3(0, collar_y, 0), 0.016 * scale_mul, 0.018 * scale_mul, steel, -1.0, 12)
	collar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var neck := Forge.cylinder(root, Vector3(0, collar_y + 0.016 * scale_mul, 0), 0.011 * scale_mul, 0.016 * scale_mul, steel, -1.0, 10)
	neck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Curved stamped steel safety lever (spoon) hugging the spherical body contour
	var spoon_x: float = 0.014 * scale_mul
	var spoon_top := Forge.box(root, Vector3(spoon_x, collar_y + 0.022 * scale_mul, 0), Vector3(0.012, 0.007, 0.016) * scale_mul, zinc_lever)
	spoon_top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var spoon_curve1 := Forge.box(root, Vector3(spoon_x + 0.024 * scale_mul, collar_y - 0.005 * scale_mul, 0), Vector3(0.007, 0.040, 0.016) * scale_mul, zinc_lever)
	spoon_curve1.rotation.z = -0.38
	spoon_curve1.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var spoon_curve2 := Forge.box(root, Vector3(spoon_x + 0.034 * scale_mul, 0.010 * scale_mul, 0), Vector3(0.007, 0.045, 0.016) * scale_mul, zinc_lever)
	spoon_curve2.rotation.z = 0.15
	spoon_curve2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var spoon_tail := Forge.box(root, Vector3(spoon_x + 0.028 * scale_mul, -0.028 * scale_mul, 0), Vector3(0.007, 0.022, 0.016) * scale_mul, red_tip)
	spoon_tail.rotation.z = 0.48
	spoon_tail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Safety pull ring and cotter pin
	var cotter := Forge.cylinder(root, Vector3(-0.006 * scale_mul, collar_y + 0.014 * scale_mul, 0), 0.003 * scale_mul, 0.028 * scale_mul, silver_pin, -1.0, 8)
	cotter.rotation.z = PI / 2
	cotter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ring := Forge.torus(root, Vector3(-0.028 * scale_mul, collar_y + 0.014 * scale_mul, 0), 0.011 * scale_mul, 0.017 * scale_mul, silver_pin, 16)
	ring.rotation.y = 0.25
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

# --- 2. CS M84 Flashbang (闪光震慑弹) ---
static func _build_flashbang(root: Node3D, is_fp: bool) -> void:
	var segs: int = 20 if is_fp else 12
	var scale_mul: float = 1.35 if is_fp else 1.0
	var gunmetal := Forge.material(Color(0.18, 0.20, 0.22), 0.85, 0, 0.38)
	var white_band := Forge.material(Color(0.88, 0.90, 0.92), 0.1, 0, 0.45)
	var vent_hole_mat := Forge.material(Color(0.02, 0.02, 0.02), 0.1, 0, 0.9)
	var steel := Forge.material(Color(0.32, 0.36, 0.40), 0.85, 0, 0.30)
	var blue_ring := Forge.material(Color(0.15, 0.45, 0.85), 0.2, 0, 0.5)
	var silver_pin := Forge.material(Color(0.88, 0.90, 0.94), 0.92, 0, 0.18)

	var br: float = 0.032 * scale_mul
	var lower_body := Forge.cylinder(root, Vector3(0, -0.042 * scale_mul, 0), br, 0.058 * scale_mul, gunmetal, -1.0, segs)
	lower_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var upper_body := Forge.cylinder(root, Vector3(0, 0.042 * scale_mul, 0), br, 0.058 * scale_mul, gunmetal, -1.0, segs)
	upper_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Iconic wide white/silver identification band
	var mid_band := Forge.cylinder(root, Vector3(0, 0, 0), br * 1.01, 0.050 * scale_mul, white_band, -1.0, segs)
	mid_band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# 12 Venting exhaust ports
	for row in [-0.030 * scale_mul, 0.030 * scale_mul]:
		for h in 6:
			var angle: float = float(h) * TAU / 6.0
			var h_pos := Vector3(cos(angle) * br * 1.02, row, sin(angle) * br * 1.02)
			var hole := Forge.cylinder(root, h_pos, 0.0055 * scale_mul, 0.003 * scale_mul, vent_hole_mat, -1.0, 8)
			hole.rotation.y = -angle
			hole.rotation.x = PI / 2
			hole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Bottom end cap
	var base_cap := Forge.cylinder(root, Vector3(0, -0.075 * scale_mul, 0), br * 1.05, 0.014 * scale_mul, steel, -1.0, 12)
	base_cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# M201A1 Fuze assembly
	var collar := Forge.cylinder(root, Vector3(0, 0.078 * scale_mul, 0), 0.015 * scale_mul, 0.018 * scale_mul, steel, -1.0, 10)
	collar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var blue_seal := Forge.cylinder(root, Vector3(0, 0.088 * scale_mul, 0), 0.0155 * scale_mul, 0.005 * scale_mul, blue_ring, -1.0, 10)
	blue_seal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Flat straight zinc safety spoon lever
	var lever := Forge.box(root, Vector3(br + 0.004 * scale_mul, 0.030 * scale_mul, 0), Vector3(0.007, 0.105, 0.018) * scale_mul, steel)
	lever.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Safety pull ring and split pin
	var pin := Forge.cylinder(root, Vector3(-0.006 * scale_mul, 0.092 * scale_mul, 0), 0.003 * scale_mul, 0.026 * scale_mul, silver_pin, -1.0, 8)
	pin.rotation.z = PI / 2
	pin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ring := Forge.torus(root, Vector3(-0.026 * scale_mul, 0.092 * scale_mul, 0), 0.011 * scale_mul, 0.017 * scale_mul, silver_pin, 16)
	ring.rotation.y = 0.2
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

# --- 3. CS M18 Smoke Grenade (烟雾弹) ---
static func _build_smoke_grenade(root: Node3D, is_fp: bool) -> void:
	var segs: int = 24 if is_fp else 16
	var scale_mul: float = 1.35 if is_fp else 1.0
	var canister_green := Forge.material(Color(0.28, 0.36, 0.22), 0.1, 0, 0.7)
	var pale_cap := Forge.material(Color(0.58, 0.65, 0.55), 0.2, 0, 0.6)
	var rim_metal := Forge.material(Color(0.38, 0.42, 0.40), 0.7, 0, 0.4)
	var vent_hole := Forge.material(Color(0.05, 0.05, 0.05), 0.1, 0, 0.9)
	var steel := Forge.material(Color(0.28, 0.32, 0.35), 0.85, 0, 0.35)
	var silver_pin := Forge.material(Color(0.88, 0.90, 0.94), 0.92, 0, 0.18)

	var sr: float = 0.038 * scale_mul
	# Main cylindrical tin canister body
	var can := Forge.cylinder(root, Vector3(0, 0, 0), sr, 0.142 * scale_mul, canister_green, -1.0, segs)
	can.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Rolled metal rims on top and bottom
	var top_rim := Forge.torus(root, Vector3(0, 0.071 * scale_mul, 0), sr * 0.97, sr * 1.05, rim_metal, segs)
	top_rim.rotation.x = PI / 2
	top_rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var bot_rim := Forge.torus(root, Vector3(0, -0.071 * scale_mul, 0), sr * 0.97, sr * 1.05, rim_metal, segs)
	bot_rim.rotation.x = PI / 2
	bot_rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Top pale green cap with 4 circular smoke emission discharge vents
	var cap := Forge.cylinder(root, Vector3(0, 0.074 * scale_mul, 0), sr * 0.94, 0.010 * scale_mul, pale_cap, -1.0, segs)
	cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for v in 4:
		var angle: float = float(v) * TAU / 4.0 + 0.35
		var vent_pos := Vector3(cos(angle) * sr * 0.60, 0.080 * scale_mul, sin(angle) * sr * 0.60)
		var hole := Forge.cylinder(root, vent_pos, 0.0045 * scale_mul, 0.003 * scale_mul, vent_hole, -1.0, 8)
		hole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Center fuze stem
	var fuze := Forge.cylinder(root, Vector3(0, 0.092 * scale_mul, 0), 0.013 * scale_mul, 0.026 * scale_mul, steel, -1.0, 10)
	fuze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Wide stamped safety lever hugging the cylindrical side
	var lever_top := Forge.box(root, Vector3(0.016 * scale_mul, 0.100 * scale_mul, 0), Vector3(0.016, 0.007, 0.020) * scale_mul, steel)
	lever_top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var lever_body := Forge.box(root, Vector3(sr + 0.004 * scale_mul, 0.030 * scale_mul, 0), Vector3(0.007, 0.132, 0.022) * scale_mul, steel)
	lever_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Safety pull ring and pin
	var pin := Forge.cylinder(root, Vector3(-0.005 * scale_mul, 0.098 * scale_mul, 0), 0.003 * scale_mul, 0.028 * scale_mul, silver_pin, -1.0, 8)
	pin.rotation.z = PI / 2
	pin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ring := Forge.torus(root, Vector3(-0.028 * scale_mul, 0.098 * scale_mul, 0), 0.011 * scale_mul, 0.017 * scale_mul, silver_pin, 16)
	ring.rotation.y = 0.25
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

# --- 4. First-Person Tactical Hands (CS First-Person View Pose) ---
static func build_first_person_rig(rig: Node3D, kind: int) -> void:
	for child in rig.get_children():
		child.free()

	var glove_black := Forge.material(Color(0.12, 0.14, 0.15), 0.1, 0, 0.75)
	var glove_pad := Forge.material(Color(0.20, 0.23, 0.25), 0.2, 0, 0.6)
	var sleeve_camo := Forge.material(Color(0.25, 0.30, 0.22), 0.0, 0, 0.9)

	var g_anchor := Node3D.new()
	g_anchor.name = "GrenadeAnchor"
	g_anchor.position = Vector3(0.13, -0.09, -0.25)
	g_anchor.rotation_degrees = Vector3(-8, 16, -10)
	rig.add_child(g_anchor)

	build(g_anchor, kind, true)

	var r_hand := Node3D.new()
	r_hand.position = Vector3(0.13, -0.09, -0.25)
	r_hand.rotation_degrees = Vector3(-8, 16, -10)
	rig.add_child(r_hand)

	# Palm gripping the grenade body
	var palm := Forge.box(r_hand, Vector3(-0.012, -0.015, -0.015), Vector3(0.055, 0.080, 0.048), glove_black)
	palm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pad := Forge.box(r_hand, Vector3(0.015, -0.015, -0.028), Vector3(0.026, 0.072, 0.015), glove_pad)
	pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Curled fingers wrapping around grenade body
	for i in 4:
		var fy: float = 0.020 - float(i) * 0.015
		var finger := Forge.cylinder(r_hand, Vector3(0.020, fy, 0.042), 0.009, 0.042, glove_black, -1.0, 10)
		finger.rotation.z = PI / 2
		finger.rotation.y = -0.35
		finger.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Thumb holding down the safety lever
	var thumb := Forge.cylinder(r_hand, Vector3(0.042, 0.035, 0.006), 0.0095, 0.040, glove_black, -1.0, 10)
	thumb.rotation.x = PI / 3
	thumb.rotation.y = 0.2
	thumb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Right forearm and sleeve
	var r_wrist := Forge.box(r_hand, Vector3(-0.038, -0.075, -0.055), Vector3(0.062, 0.075, 0.065), glove_black)
	r_wrist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var r_arm := Forge.cylinder(r_hand, Vector3(-0.065, -0.19, -0.11), 0.052, 0.22, sleeve_camo, -1.0, 14)
	r_arm.rotation.x = 0.45
	r_arm.rotation.z = -0.30
	r_arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Left hand bracing near pull-ring
	var l_hand := Node3D.new()
	l_hand.position = Vector3(-0.04, -0.12, -0.22)
	l_hand.rotation_degrees = Vector3(12, -22, 18)
	rig.add_child(l_hand)

	var l_palm := Forge.box(l_hand, Vector3(0, 0, 0), Vector3(0.050, 0.065, 0.038), glove_black)
	l_palm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var l_index := Forge.cylinder(l_hand, Vector3(0.028, 0.026, -0.018), 0.008, 0.045, glove_black, -1.0, 10)
	l_index.rotation.z = -PI / 4
	l_index.rotation.x = 0.3
	l_index.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var l_thumb := Forge.cylinder(l_hand, Vector3(0.022, 0.015, 0.022), 0.0085, 0.034, glove_black, -1.0, 10)
	l_thumb.rotation.x = -0.5
	l_thumb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var l_arm := Forge.cylinder(l_hand, Vector3(-0.07, -0.14, -0.06), 0.048, 0.22, sleeve_camo, -1.0, 14)
	l_arm.rotation.x = 0.40
	l_arm.rotation.z = 0.35
	l_arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
