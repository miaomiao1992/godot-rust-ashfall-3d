extends CanvasLayer

const BASE := Vector2(1440, 900)
const CYAN := Color(0.23, 0.86, 0.8)
const ORANGE := Color(1.0, 0.53, 0.23)
const WHITE := Color(0.85, 0.9, 0.89)
const MUTED := Color(0.48, 0.62, 0.64)
const DARK := Color(0.025, 0.055, 0.065, 0.86)

var game
var root: Control
var painter: Control
var menu: Control
var shade: ColorRect
var visor: ColorRect
var scope_visor: ColorRect
var font: SystemFont
var hurt := 0.0
var clock := 0.0
var hit_timer := 0.0
var hit_head := false
var hit_kill := false
var toast_text := ""
var toast_color := WHITE
var toast_timer := 0.0
var banner_title := ""
var banner_sub := ""
var banner_timer := 0.0
var kill_feed: Array[Dictionary] = []
var theme_ui: Theme
var room_list: ItemList
var room_records: Array = []
var room_refresh := 0.0
var menu_feedback: Label
var nickname_field: LineEdit
var address_field: LineEdit
var room_name_field: LineEdit
var browser_mode := "coop"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 5
	font = SystemFont.new()
	font.font_names = PackedStringArray(["PingFang SC", "Noto Sans CJK SC", "Microsoft YaHei", "Arial"])
	theme_ui = Theme.new()
	theme_ui.default_font = font
	theme_ui.default_font_size = 20
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = theme_ui
	add_child(root)
	visor = ColorRect.new()
	visor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader_material := ShaderMaterial.new()
	shader_material.shader = preload("res://shaders/visor.gdshader")
	visor.material = shader_material
	root.add_child(visor)
	scope_visor = ColorRect.new()
	scope_visor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scope_visor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var scope_material := ShaderMaterial.new()
	scope_material.shader = preload("res://shaders/sniper_scope.gdshader")
	scope_visor.material = scope_material
	root.add_child(scope_visor)
	painter = Control.new()
	painter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	painter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	painter.draw.connect(_paint)
	root.add_child(painter)
	shade = ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.008, 0.024, 0.031, 0.82)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(shade)
	menu = Control.new()
	menu.size = BASE
	menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(menu)

func _process(delta: float) -> void:
	if not is_instance_valid(game) or not is_instance_valid(game.player):
		return
	clock += delta
	hurt = move_toward(hurt, 0, delta * 1.6)
	hit_timer = maxf(hit_timer - delta, 0)
	toast_timer = maxf(toast_timer - delta, 0)
	banner_timer = maxf(banner_timer - delta, 0)
	for i in range(kill_feed.size() - 1, -1, -1):
		kill_feed[i].time -= delta
		if kill_feed[i].time <= 0:
			kill_feed.remove_at(i)
	var viewport := root.get_viewport_rect().size
	var factor := minf(viewport.x / BASE.x, viewport.y / BASE.y)
	menu.scale = Vector2.ONE * factor
	menu.position = (viewport - BASE * factor) * 0.5
	visor.material.set_shader_parameter("hurt", hurt)
	visor.material.set_shader_parameter("clock", clock)
	visor.material.set_shader_parameter("danger", 1.0 - clampf(game.player.hp / 35.0, 0, 1))
	scope_visor.visible = game.state == "playing" and game.player.scope_active()
	scope_visor.material.set_shader_parameter("active", 1.0)
	scope_visor.material.set_shader_parameter("viewport_size", viewport)
	painter.queue_redraw()
	room_refresh -= delta
	if game.state == "menu" and is_instance_valid(room_list) and room_list.is_visible_in_tree() and room_refresh <= 0:
		room_refresh = 0.8
		_refresh_rooms()

func _text(text: String, pos: Vector2, size: int, color: Color = WHITE) -> void:
	painter.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _center(text: String, y: float, size: int, color: Color = WHITE) -> void:
	_text(text, Vector2((BASE.x - font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x) * 0.5, y), size, color)

func _rect(pos: Vector2, size: Vector2, color: Color) -> void:
	painter.draw_rect(Rect2(pos, size), color)

func _bar(pos: Vector2, size: Vector2, value: float, color: Color) -> void:
	_rect(pos, size, Color(0.13, 0.2, 0.22, 0.8))
	_rect(pos, Vector2(size.x * clampf(value, 0, 1), size.y), color)

func _paint() -> void:
	painter.draw_set_transform(Vector2.ZERO, 0, painter.size / BASE)
	if game.state in ["menu", "lobby", "connecting"]:
		return
	var p = game.player
	var weapon: Dictionary = p.WEAPONS[p.weapon_index]
	# Top telemetry rail.
	_rect(Vector2(36, 32), Vector2(325, 77), DARK)
	_rect(Vector2(36, 32), Vector2(3, 77), ORANGE)
	if game.is_pvp():
		var scores: Array = game.lan.pvp_state.get("scores", [0, 0])
		var remaining := int(game.lan.pvp_state.get("remaining", 600))
		_text("仓库交锋 / 50 杀获胜", Vector2(54, 57), 15, MUTED)
		_text("RED %02d : %02d BLUE" % scores, Vector2(54, 91), 24)
		_text("剩余 %02d:%02d" % [remaining / 60, remaining % 60], Vector2(50, 137), 21, CYAN)
		_text("你的队伍：" + ("红队" if p.team == 0 else "蓝队"), Vector2(50, 163), 17, ORANGE)
	else:
		var stage_title: String = game.STAGE_NAMES[game.stage_index] if game.stage_index >= 0 and game.stage_index < game.STAGE_NAMES.size() else "突击仓库"
		_text("0%d / %s" % [game.stage_index + 1, stage_title], Vector2(54, 57), 15, MUTED)
		_text("尸潮 %d / 3" % (posmod(game.wave - 1, 3) + 1), Vector2(54, 91), 28)
		_text("%02d:%02d" % [int(game.survival_time) / 60, int(game.survival_time) % 60], Vector2(268, 88), 23, CYAN)
		_text("感染者 %03d  /  来袭 %03d" % [game.alive, game.spawn_left], Vector2(50, 137), 17, ORANGE)
		_text("下一尸潮  %.1f s" % game.next_wave if game.next_wave > 0 else game.level.combat_hint, Vector2(50, 163), 13, MUTED)
	if game.stage_index == 2:
		_text("冷却阀 %d / 3  ·  本波需 %d" % [game.objective_count, posmod(game.wave - 1, 3) + 1], Vector2(50, 188), 16, CYAN)
	# Heading ticks above the reticle.
	var heading := fposmod(-rad_to_deg(p.rotation.y), 360)
	for i in range(-4, 5):
		var x := 720 + i * 38
		painter.draw_line(Vector2(x, 42), Vector2(x, 49 if i % 2 == 0 else 46), MUTED * Color(1, 1, 1, 0.6), 1)
	_text("%03d°" % int(heading), Vector2(695, 73), 15, MUTED)
	painter.draw_line(Vector2(715, 31), Vector2(725, 31), CYAN, 2)
	if is_instance_valid(game.boss) and not game.boss.dead:
		var b = game.boss
		_rect(Vector2(449, 90), Vector2(542, 72), DARK)
		_center("BOSS / " + b.monster_name + (" · 狂暴" if b.enraged else ""), 116, 19, ORANGE)
		_bar(Vector2(470, 131), Vector2(500, 8), b.hp / b.max_hp, Color(0.96, 0.18, 0.11))
		_center("核心护罩生效 · 关闭全部冷却阀" if game.stage_index == 2 and game.objective_count < 3 else "核心与头部为弱点  /  %d HP" % int(b.hp), 156, 12, MUTED)
	_draw_radar()
	# Health and growth.
	_rect(Vector2(36, 755), Vector2(324, 111), DARK)
	_text("VITALS", Vector2(54, 780), 13, MUTED)
	_text("%03d" % int(p.hp), Vector2(52, 823), 37, Color(1, 0.3, 0.23) if p.hp < 35 else WHITE)
	_text("/ %d" % int(p.max_hp), Vector2(139, 819), 18, MUTED)
	_bar(Vector2(54, 834), Vector2(285, 6), p.hp / p.max_hp, Color(0.97, 0.28, 0.19) if p.hp < 35 else CYAN)
	_text("耐力", Vector2(219, 778), 13, MUTED)
	_bar(Vector2(256, 768), Vector2(83, 4), p.stamina / 100, ORANGE)
	if game.is_pvp():
		_text("固定装备 · 全武器解锁", Vector2(54, 858), 14, CYAN)
	else:
		_text("LV.%02d" % game.level_number, Vector2(54, 858), 14, CYAN)
		_bar(Vector2(119, 851), Vector2(155, 4), float(game.xp) / game.xp_needed, CYAN)
		_text("%d / %d" % [game.xp, game.xp_needed], Vector2(284, 858), 11, MUTED)
	# Weapon readout.
	_rect(Vector2(1100, 754), Vector2(304, 112), DARK)
	_rect(Vector2(1401, 754), Vector2(3, 112), ORANGE)
	_text(weapon.name, Vector2(1120, 781), 18, WHITE)
	_text("%02d" % p.magazines[p.weapon_index], Vector2(1116, 835), 50, ORANGE if p.magazines[p.weapon_index] < 4 else WHITE)
	_text("/  ∞" if p.weapon_index == 0 else "/  %03d" % p.reserves[p.weapon_index], Vector2(1224, 828), 24, MUTED)
	if p.reload_timer > 0:
		_bar(Vector2(1120, 847), Vector2(261, 5), 1 - p.reload_timer / p.reload_total, ORANGE)
		_text("换弹中", Vector2(1301, 806), 14, ORANGE)
	else:
		_text("R 换弹   /   右键 精确瞄准", Vector2(1120, 858), 12, MUTED)
	for i in p.WEAPONS.size():
		var pos := Vector2(400 + i * 115, 814)
		var unlocked: bool = game.level_number >= p.WEAPONS[i].level
		_rect(pos, Vector2(114, 51), Color(0.055, 0.19, 0.19, 0.92) if i == p.weapon_index else DARK)
		if i == p.weapon_index:
			_rect(pos, Vector2(114, 2), CYAN)
		_text("%d  %s" % [i + 1, p.WEAPONS[i].short], pos + Vector2(10, 22), 14, WHITE if unlocked else MUTED * Color(1, 1, 1, 0.5))
		_text("已装备" if i == p.weapon_index else "可切换" if unlocked else "LV.%d 解锁" % p.WEAPONS[i].level, pos + Vector2(10, 41), 11, CYAN if i == p.weapon_index else MUTED)
	_text("WASD 移动  ·  SHIFT 冲刺  ·  SPACE 跳跃  ·  E 操作  ·  ESC 暂停", Vector2(409, 890), 13, MUTED)
	_text("击杀 %03d  /  爆头 %03d" % [game.kills, game.headshots], Vector2(51, 727), 15, MUTED)
	if game.is_pvp():
		var f: Dictionary = game.lan.fighters.get(p.peer_id, {})
		var grenades: Array = f.get("grenades", [0, 0, 0])
		var names := ["G 手雷", "Q 闪光", "C 烟雾"]
		var g_text := ""
		for gi in 3:
			var cnt: int = int(grenades[gi]) if gi < grenades.size() else 0
			var item_str := "【%s %d (准备投掷)】" % [names[gi], cnt] if p.active_grenade == gi else "%s %d" % [names[gi], cnt]
			g_text += item_str + ("   " if gi < 2 else "")
		_text(g_text, Vector2(51, 700), 17, Color(1.0, 0.85, 0.25) if p.active_grenade >= 0 else CYAN)
		_text("击杀 %d / 死亡 %d / 爆头 %d · TAB 比分" % [int(f.get("kills", 0)), int(f.get("deaths", 0)), int(f.get("headshots", 0))], Vector2(51, 727), 15, WHITE)
		if p.life == "dead": _center("阵亡 · %.1f 秒后重生" % float(f.get("respawn", 0)), 590, 24, ORANGE)
	elif game.is_lan():
		_text("LAN 小队 %d / 4  ·  U 强化点 %d" % [game.lan.players.size(), p.upgrade_points], Vector2(51, 700), 16, CYAN)
		var row := 0
		for teammate in game.lan.players.values():
			_text("%s  %s" % [teammate.player_name, "%d HP" % int(teammate.hp) if teammate.life == "alive" else "倒地 %.0fs" % teammate.bleed if teammate.life == "downed" else "同步中" if teammate.life == "spawning" else "观战"], Vector2(50, 222 + row * 25), 15, CYAN if teammate.life == "alive" else ORANGE)
			row += 1
		if p.life == "downed":
			_center("你已倒地 · 等待队友救援 %.1fs" % p.bleed, 590, 24, ORANGE)
			_bar(Vector2(570, 610), Vector2(300, 6), p.revive_progress / 3, CYAN)
		elif p.life == "dead":
			_center("观战中 · 下一波复活", 590, 24, MUTED)
		else:
			for teammate in game.lan.players.values():
				if teammate.life == "downed" and teammate.position.distance_to(p.position) < 3.2:
					_center("按住 E 救援 " + teammate.player_name, 590, 24, CYAN)
					_bar(Vector2(570, 610), Vector2(300, 6), teammate.revive_progress / 3, CYAN)
	# Adaptive crosshair and hit confirm.
	if game.state == "playing" and not p.scope_active():
		var center := BASE * 0.5
		var gap: float = 5 + p.gun_kick * 55 + (1.0 - p.aim) * float(weapon.spread) * 130
		var cross_color := Color(0.76, 0.88, 0.85, 0.75)
		for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			painter.draw_line(center + direction * gap, center + direction * (gap + 7), cross_color, 1.5)
		painter.draw_circle(center, 1.5, WHITE)
		if hit_timer > 0:
			var c := ORANGE if hit_head else Color(0.96, 0.25, 0.17) if hit_kill else WHITE
			for d in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
				painter.draw_line(center + d * 9, center + d * 17, c, 2.2)
			if hit_head:
				_center("弱点命中", 495, 15, ORANGE)
		if hurt > 0.12:
			var a: float = p.hit_direction - PI / 2
			painter.draw_arc(center, 78, a - 0.32, a + 0.32, 18, Color(1, 0.19, 0.1, hurt), 4, true)
	if game.state == "playing" and p.scope_active(): _draw_scope()
	if banner_timer > 0:
		var alpha := minf(banner_timer, 1.0)
		_center(banner_title, 192, 38, WHITE * Color(1, 1, 1, alpha))
		_center(banner_sub, 222, 16, ORANGE * Color(1, 1, 1, alpha))
	if not game.interaction_hint.is_empty():
		_center(game.interaction_hint, 650, 24, CYAN)
	elif game.objective_waiting:
		_center("寻找雷达上的冷却阀  ·  靠近按 E", 650, 20, ORANGE)
	if toast_timer > 0:
		_center(toast_text, 769, 19, toast_color * Color(1, 1, 1, minf(toast_timer, 1)))
	for i in kill_feed.size():
		var item: Dictionary = kill_feed[i]
		_text(item.text, Vector2(1170, 250 + i * 25), 15, ORANGE if item.head else MUTED)
	if game.debug_stats:
		_text("FPS %d  /  SEED %d  /  NODES %d" % [Engine.get_frames_per_second(), game.seed_value, Performance.get_monitor(Performance.OBJECT_NODE_COUNT)], Vector2(40, 200), 15, CYAN)
		_text("CPU %.1f ms  /  PHYS %.1f ms  /  DRAW %d  /  FX %d" % [Performance.get_monitor(Performance.TIME_PROCESS) * 1000, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), game.fx.items.size()], Vector2(40, 222), 15, CYAN)
	if game.is_pvp():
		if game.lan.ordnance.smoke_at(p.camera.global_position): _rect(Vector2.ZERO, BASE, Color(0.43, 0.48, 0.5, 0.97))
		var flash_seconds := float(game.lan.fighters.get(p.peer_id, {}).get("flash", 0))
		if flash_seconds > 0: _rect(Vector2.ZERO, BASE, Color(1, 1, 1, minf(flash_seconds, 1)))
		if Input.is_action_pressed("scoreboard") and not menu.visible: _draw_scoreboard()

func _draw_radar() -> void:
	var pos := Vector2(1272, 36)
	_rect(pos - Vector2(12, 4), Vector2(144, 170), DARK)
	var map_size := 120.0
	var cell_size := map_size / 29.0
	for cell in game.level.blocked:
		_rect(pos + Vector2(cell.x, cell.y) * cell_size, Vector2.ONE * cell_size, Color(0.18, 0.29, 0.3))
	for terminal in game.level.terminals:
		var point: Vector2 = pos + Vector2(terminal.position.x + 58, terminal.position.z + 58) / 116 * map_size
		painter.draw_circle(point, 3.1, CYAN if terminal.activated else ORANGE)
	for hazard in game.hazards:
		if hazard.life > 0:
			var point: Vector2 = pos + Vector2(hazard.node.position.x + 58, hazard.node.position.z + 58) / 116 * map_size
			painter.draw_arc(point, hazard.radius / 116 * map_size, 0, TAU, 12, ORANGE if hazard.warning > 0 else Color(0.36, 0.64, 0.12), 1)
	for enemy in get_tree().get_nodes_in_group("zombies"):
		if enemy.dead:
			continue
		var point: Vector2 = Vector2(enemy.position.x + 58, enemy.position.z + 58) / 116 * map_size
		painter.draw_circle(pos + point, 2 if enemy.kind != 2 else 3.2, Color(1, 0.25, 0.12))
	var p = game.player
	var player_point := pos + Vector2(p.position.x + 58, p.position.z + 58) / 116 * map_size
	painter.draw_circle(player_point, 3, CYAN)
	var direction := Vector2(-sin(p.rotation.y), -cos(p.rotation.y))
	painter.draw_line(player_point, player_point + direction * 9, CYAN, 2)
	_text("MOTION TRACKER", pos + Vector2(0, 146), 11, CYAN)

func _draw_scope() -> void:
	var center := BASE * 0.5
	var ink := Color(0.015, 0.02, 0.02, 0.95)
	for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		painter.draw_line(center + direction * 3, center + direction * 330, ink, 1)
		painter.draw_line(center + direction * 150, center + direction * 330, ink, 3)
		for tick in 6:
			var point: Vector2 = center + direction * (tick + 1) * 20
			var tangent := Vector2(-direction.y, direction.x)
			painter.draw_line(point - tangent * 4, point + tangent * 4, ink, 1)
	painter.draw_circle(center, 2, Color(0.8, 0.08, 0.05))
	painter.draw_arc(center, 341, 0, TAU, 96, Color(0.07, 0.10, 0.11), 6, true)
	var p = game.player
	_text("SR-96 / %.0f×" % p.scope_zoom, Vector2(535, 663), 17, CYAN)
	_text("SHIFT 屏息 / 滚轮 4×·8×", Vector2(535, 692), 15, WHITE)
	_bar(Vector2(535, 708), Vector2(200, 4), p.breath / 4, CYAN if p.holding_breath else MUTED)
	if hit_timer > 0:
		for d in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
			painter.draw_line(center + d * 8, center + d * 15, ORANGE if hit_head else WHITE, 2)

func _clear_menu() -> void:
	for child in menu.get_children():
		child.queue_free()
	menu.visible = true
	shade.visible = true

func _label(text: String, pos: Vector2, size: int = 20, color: Color = WHITE, width: float = 800) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.size.x = width
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(label)
	return label

func _panel(pos: Vector2, size: Vector2, border: Color = Color(0.15, 0.29, 0.3)) -> Panel:
	var panel := Panel.new()
	panel.position = pos
	panel.size = size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.024, 0.07, 0.085, 0.94)
	style.border_color = border
	style.set_border_width_all(1)
	style.border_width_top = 2
	panel.add_theme_stylebox_override("panel", style)
	menu.add_child(panel)
	return panel

func _button(text: String, pos: Vector2, size: Vector2, callback: Callable, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.position = pos
	button.size = size
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 22)
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(color_name, Color(0.85, 0.89, 0.88))
	for state_name in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.075, 0.16, 0.17) if primary else Color(0.055, 0.10, 0.12)
		if state_name == "hover":
			style.bg_color = Color(0.14, 0.19, 0.19)
		if state_name == "pressed":
			style.bg_color = Color(0.10, 0.14, 0.15)
		style.border_color = Color(0.55, 0.36, 0.19) if state_name in ["hover", "focus"] else Color(0.21, 0.39, 0.39) if primary else Color(0.19, 0.28, 0.30)
		style.set_border_width_all(1)
		button.add_theme_stylebox_override(state_name, style)
	button.pressed.connect(callback)
	menu.add_child(button)
	return button

func show_menu() -> void:
	_clear_menu()
	shade.color = Color(0.008, 0.023, 0.03, 0.60)
	_label("A S H F A L L   /   S U R V I V A L   P R O T O C O L", Vector2(100, 65), 17, CYAN)
	_label("RUST LAN / v1.0.0", Vector2(1030, 65), 15, MUTED)
	_label("ASHFALL", Vector2(93, 199), 105, WHITE)
	_label("余 烬 禁 区", Vector2(104, 333), 43, ORANGE)
	_label("城市已失守。撤离已取消。", Vector2(108, 419), 24, WHITE)
	_label("在尸潮中成长，在枪火中活下去。\n穿过三片死地，摧毁感染源。", Vector2(108, 468), 20, MUTED)
	_label("3D  /  三大关卡  /  尸潮与 BOSS  /  成长武装", Vector2(108, 564), 16, CYAN)
	_button("单人生存   →", Vector2(108, 625), Vector2(350, 60), game.start_run, true)
	_button("局域网合作", Vector2(478, 625), Vector2(350, 60), show_lan_browser)
	_button("仓库 PvP", Vector2(108, 703), Vector2(350, 60), show_lan_browser.bind("pvp"))
	_button("退出", Vector2(478, 703), Vector2(350, 60), func(): get_tree().quit())
	_panel(Vector2(885, 216), Vector2(440, 470))
	_label("行动简报", Vector2(916, 245), 27, WHITE)
	_label("01 / 保持移动", Vector2(916, 307), 20, ORANGE)
	_label("冲刺消耗耐力。雷达会暴露逼近的感染者。", Vector2(916, 343), 15, MUTED)
	_label("02 / 击杀成长", Vector2(916, 394), 20, ORANGE)
	_label("爆头奖励经验；升级时选择生存强化。", Vector2(916, 430), 15, MUTED)
	_label("03 / 解锁武装", Vector2(916, 481), 20, ORANGE)
	_label("LV.2 冲锋枪  ·  LV.3 霰弹枪\nLV.5 突击步枪  ·  LV.7 穿透电磁炮\nLV.8 狙击枪 / 4×·8× 瞄准镜", Vector2(916, 517), 16, MUTED)
	_label("04 / 突破三片死地", Vector2(916, 588), 20, ORANGE)
	_label("断桥高架 → 沉没船坞 → 熔心实验场\n折线悬桥 / 水道码头 / 环形核心大厅", Vector2(916, 624), 15, MUTED)
	_label("个人纪录  /  尸潮 %02d   ·   击杀 %03d" % [game.best_wave, game.best_kills], Vector2(108, 797), 16, MUTED)
	_label("WASD 移动  /  鼠标 射击与瞄准  /  1–6、滚轮 切换武器  /  R 换弹", Vector2(108, 831), 15, MUTED)
	_label("THREE SECTORS. ONE SURVIVOR.", Vector2(1050, 831), 13, CYAN)

func show_upgrade() -> void:
	_clear_menu()
	shade.color = Color(0.008, 0.023, 0.03, 0.86)
	_label("S U R V I V O R   E V O L U T I O N", Vector2(480, 192), 17, CYAN)
	_label("生存等级 %02d" % game.level_number, Vector2(526, 233), 44, WHITE)
	_label("个人强化 · 战斗继续进行" if game.is_lan() else "选择一项永久强化  /  战场已暂停", Vector2(502, 302), 20, MUTED)
	var names := ["致命校准", "不屈意志", "战术机动"]
	var desc := ["所有武器伤害 +18%\n爆头与霰弹同时获得加成\n\n以攻击争取生存空间。", "生命上限 +20\n立即恢复 45 生命\n伤害减免 +4%\n\n多承受一次致命围攻。", "换弹时间 -12%\n移动速度 +0.25\n恢复部分生命与弹药\n\n永远不要停在尸群中。"]
	for i in 3:
		var x := 183 + i * 365
		_panel(Vector2(x, 386), Vector2(345, 311), CYAN if i == 0 else Color(0.19, 0.34, 0.35))
		_label("0%d / AUGMENT" % (i + 1), Vector2(x + 24, 407), 14, ORANGE)
		_label(names[i], Vector2(x + 24, 442), 28, WHITE)
		_label(desc[i], Vector2(x + 24, 498), 17, MUTED)
		_button("选择强化", Vector2(x, 713), Vector2(345, 57), game.choose_upgrade.bind(i), i == 0)
	var unlocked := ""
	for weapon in game.player.WEAPONS:
		if int(weapon.level) == game.level_number and game.level_number > 1:
			unlocked = "新武器已解锁  //  " + weapon.name
	_label(unlocked, Vector2(469, 816), 20, CYAN)

func show_death() -> void:
	_clear_menu()
	shade.color = Color(0.035, 0.008, 0.012, 0.84)
	_label("S I G N A L   L O S T", Vector2(551, 187), 21, ORANGE)
	_label("小队覆灭。" if game.is_lan() else "你倒下了。", Vector2(516, 239), 65, WHITE)
	_label("禁区仍在吞噬一切。下一次，走得更远。", Vector2(473, 340), 21, MUTED)
	_panel(Vector2(342, 419), Vector2(756, 160), Color(0.49, 0.18, 0.1))
	var stats := ["%02d" % game.wave, "%03d" % game.kills, "%02d" % game.level_number, "%02d:%02d" % [int(game.survival_time) / 60, int(game.survival_time) % 60]]
	var titles := ["抵达尸潮", "击杀感染者", "生存等级", "存活时间"]
	for i in 4:
		_label(stats[i], Vector2(376 + i * 187, 443), 43, WHITE, 170)
		_label(titles[i], Vector2(376 + i * 187, 513), 16, MUTED, 170)
	var accuracy := int(float(game.shots_hit) / maxi(game.shots_fired, 1) * 100)
	_label("爆头 %d   /   命中率 %d%%   /   最佳尸潮 %02d" % [game.headshots, accuracy, game.best_wave], Vector2(482, 608), 18, MUTED)
	var restart := _button("房主重新挑战" if game.is_lan() else "重新挑战   →", Vector2(431, 673), Vector2(363, 65), game.lan.start_battle if game.is_lan() else game.start_run, true)
	restart.disabled = game.is_lan() and not game.lan.host()
	_button("返回主菜单", Vector2(815, 673), Vector2(194, 65), game.return_to_menu)
	_label("每一次死亡都留下纪录。记住路线，下一次突破封锁。", Vector2(451, 801), 16, MUTED)

func show_victory() -> void:
	_clear_menu()
	shade.color = Color(0.008, 0.04, 0.038, 0.86)
	_label("I N F E C T I O N   S O U R C E   E L I M I N A T E D", Vector2(384, 192), 17, CYAN)
	_label("你活了下来。", Vector2(483, 245), 60, WHITE)
	_label("三片死地已肃清。感染源已摧毁。", Vector2(503, 339), 24, MUTED)
	_panel(Vector2(385, 434), Vector2(670, 157), CYAN)
	_label("03 / 03 关卡完成", Vector2(421, 453), 33, CYAN)
	_label("击杀 %d  /  生存等级 %d  /  存活 %02d:%02d" % [game.kills, game.level_number, int(game.survival_time) / 60, int(game.survival_time) % 60], Vector2(421, 524), 21, WHITE)
	var restart := _button("房主再次挑战" if game.is_lan() else "再次挑战   →", Vector2(460, 662), Vector2(326, 65), game.lan.start_battle if game.is_lan() else game.start_run, true)
	restart.disabled = game.is_lan() and not game.lan.host()
	_button("返回主菜单", Vector2(806, 662), Vector2(194, 65), game.return_to_menu)
	_label("ASHFALL / 你让余烬有了明天。", Vector2(533, 793), 18, MUTED)

func show_pause() -> void:
	_clear_menu()
	shade.color = Color(0.008, 0.023, 0.03, 0.85)
	_label("PROTOCOL / PAUSED", Vector2(550, 197), 17, CYAN)
	_label("个人菜单", Vector2(533, 242), 52, WHITE)
	if game.is_lan(): _label("联机战场继续运行", Vector2(580, 312), 18, ORANGE)
	_button("继续生存", Vector2(503, 369), Vector2(434, 61), game.resume_run, true)
	_label("鼠标灵敏度", Vector2(503, 470), 18, MUTED)
	var slider := HSlider.new()
	slider.position = Vector2(503, 515)
	slider.size = Vector2(434, 32)
	slider.min_value = 0.0008
	slider.max_value = 0.005
	slider.step = 0.0001
	slider.value = game.sensitivity
	slider.value_changed.connect(func(value: float): game.sensitivity = value; game._save_record())
	menu.add_child(slider)
	_button("返回主菜单", Vector2(503, 593), Vector2(434, 58), game.return_to_menu)
	_label("ESC 返回战场  /  F3 性能信息", Vector2(560, 706), 16, MUTED)

func hide_overlay() -> void:
	menu.visible = false
	shade.visible = false

func confirm_hit(head: bool, killed: bool) -> void:
	hit_timer = 0.22
	hit_head = head
	hit_kill = killed

func toast(text: String, color: Color = WHITE, duration: float = 3.0) -> void:
	toast_text = text
	toast_color = color
	toast_timer = duration
	if is_instance_valid(menu_feedback):
		menu_feedback.text = text
		menu_feedback.add_theme_color_override("font_color", color)

func wave_banner(title: String, subtitle: String) -> void:
	banner_title = title
	banner_sub = subtitle
	banner_timer = 4.0

func add_kill(head: bool, kind: int, reward: int) -> void:
	var name: String = ["感染者", "疾行者", "屠戮者", "装甲感染者", "BOSS", "腐蚀者"][kind]
	kill_feed.push_front({"text": ("爆头 " if head else "击杀 ") + name + "  +%d XP" % reward, "head": head, "time": 3.0})
	if kill_feed.size() > 5:
		kill_feed.pop_back()

func _entry(text: String, pos: Vector2, width: float, hint: String) -> LineEdit:
	var field := LineEdit.new()
	field.position = pos
	field.size = Vector2(width, 46)
	field.text = text
	field.placeholder_text = hint
	field.max_length = 48
	menu.add_child(field)
	return field

func show_lan_browser(battle_mode: String = "coop") -> void:
	browser_mode = battle_mode
	_clear_menu()
	game.state = "menu"
	game.lan.net.start_discovery()
	_label("L A N  /  C O - O P  P R O T O C O L", Vector2(100, 80), 19, CYAN)
	_label("仓库交锋 · 团队 PvP" if browser_mode == "pvp" else "局域网合作", Vector2(100, 126), 46, WHITE)
	_label("1v1 至 5v5 · 50 杀 / 10 分钟 · 5 秒重生 · 手雷 / 闪光 / 烟雾" if browser_mode == "pvp" else "最多 4 人 · 共享等级 · 个人强化 · 倒地救援 · 支持战斗中加入", Vector2(100, 195), 18, MUTED)
	_panel(Vector2(100, 244), Vector2(800, 445))
	_label("同一局域网的房间", Vector2(123, 264), 23)
	room_list = ItemList.new()
	room_list.position = Vector2(123, 313)
	room_list.size = Vector2(754, 300)
	room_list.add_theme_font_size_override("font_size", 18)
	room_list.item_activated.connect(func(_index: int): _join_selected())
	menu.add_child(room_list)
	_button("加入选中房间", Vector2(123, 627), Vector2(325, 46), _join_selected, true)
	_button("刷新列表", Vector2(466, 627), Vector2(180, 46), _refresh_rooms)
	_panel(Vector2(923, 244), Vector2(405, 445))
	_label("你的昵称", Vector2(946, 264), 18, MUTED)
	nickname_field = _entry(game.lan.nickname, Vector2(946, 302), 354, "幸存者昵称")
	_label("创建新房间", Vector2(946, 371), 22)
	room_name_field = _entry("余烬小队", Vector2(946, 415), 354, "房间名称")
	_button("创建房间", Vector2(946, 477), Vector2(354, 50), func(): game.lan.create_room(room_name_field.text, nickname_field.text, 42042, browser_mode), true)
	_label("或使用 IP 直接加入", Vector2(946, 552), 18, MUTED)
	address_field = _entry("127.0.0.1", Vector2(946, 587), 215, "房主 IPv4 地址")
	_button("直连", Vector2(1177, 587), Vector2(123, 46), func(): game.lan.join_room(address_field.text.strip_edges(), nickname_field.text))
	menu_feedback = _label("发现端口 UDP 42043 / 游戏端口 UDP 42042", Vector2(100, 715), 17, MUTED)
	_button("返回主菜单", Vector2(100, 789), Vector2(260, 52), show_menu)
	_refresh_rooms()

func _refresh_rooms() -> void:
	if not is_instance_valid(room_list): return
	var selected := room_list.get_selected_items()
	var index: int = selected[0] if not selected.is_empty() else -1
	room_list.clear()
	var list = JSON.parse_string(game.lan.net.rooms_json())
	room_records = list if list is Array else []
	for room in room_records:
		var status: String = ("PvP 仓库 · 战斗中" if room.playing else "PvP 仓库 · 等待开始") if room.get("mode", "coop") == "pvp" else "战斗中 · %s / 尸潮 %d" % [game.STAGE_NAMES[clampi(int(room.stage), 0, 2)], int(room.wave)] if room.playing else "等待开始 · " + game.STAGE_NAMES[clampi(int(room.stage), 0, 2)]
		room_list.add_item("%s  |  %d/%d  |  %s  |  %s" % [room.name, int(room.players), int(room.capacity), status, room.ip])
		var row := room_list.item_count - 1
		if int(room.players) >= int(room.capacity) or not room.compatible:
			room_list.set_item_disabled(row, true)
			room_list.set_item_tooltip(row, "房间已满" if room.compatible else "版本不匹配")
	if index >= 0 and index < room_list.item_count: room_list.select(index)

func _join_selected() -> void:
	var selected := room_list.get_selected_items()
	if selected.is_empty(): return
	var room: Dictionary = room_records[selected[0]]
	if int(room.players) < int(room.capacity) and room.compatible:
		game.lan.join_room(room.ip, nickname_field.text, int(room.port))

func show_lan_lobby() -> void:
	if game.is_pvp():
		show_pvp_lobby()
		return
	_clear_menu()
	_label("L A N  /  S Q U A D  R E A D Y", Vector2(470, 153), 20, CYAN)
	_label(game.lan.room_name, Vector2(465, 205), 43)
	_label("房主可直接开始 · 其余玩家可在战斗中加入", Vector2(465, 278), 19, MUTED)
	_panel(Vector2(410, 334), Vector2(620, 248))
	var row := 0
	for member in game.lan.members:
		_label("%s  %s" % ["房主" if int(member.id) == 1 else "队友", member.name], Vector2(445, 363 + row * 48), 23, CYAN if int(member.id) == game.lan.local_id() else WHITE)
		row += 1
	_label("起始地图", Vector2(410, 590), 18, WHITE)
	var maps := OptionButton.new()
	maps.name = "LobbyMapChoice"
	maps.position = Vector2(550, 586)
	maps.size = Vector2(480, 38)
	maps.add_theme_font_size_override("font_size", 18)
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		maps.add_theme_color_override(color_name, Color(0.83, 0.88, 0.88))
	for state_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.14, 0.21, 0.24) if state_name == "hover" else Color(0.10, 0.16, 0.19)
		style.border_color = Color(0.40, 0.52, 0.54)
		style.set_border_width_all(1)
		style.content_margin_left = 14
		maps.add_theme_stylebox_override(state_name, style)
	var popup := maps.get_popup()
	popup.add_theme_color_override("font_color", Color(0.85, 0.90, 0.90))
	popup.add_theme_color_override("font_hover_color", Color(0.90, 0.92, 0.89))
	popup.add_theme_font_size_override("font_size", 18)
	var popup_panel := StyleBoxFlat.new()
	popup_panel.bg_color = Color(0.10, 0.16, 0.19)
	popup_panel.border_color = Color(0.32, 0.46, 0.48)
	popup_panel.set_border_width_all(1)
	popup.add_theme_stylebox_override("panel", popup_panel)
	var popup_hover := StyleBoxFlat.new()
	popup_hover.bg_color = Color(0.19, 0.26, 0.28)
	popup.add_theme_stylebox_override("hover", popup_hover)
	for title in game.STAGE_NAMES: maps.add_item(title)
	maps.select(game.lan.start_stage)
	maps.disabled = not game.lan.host()
	maps.item_selected.connect(game.lan.set_start_stage)
	menu.add_child(maps)
	var begin := _button("开始尸潮" if game.lan.host() else "等待房主开始", Vector2(410, 631), Vector2(620, 61), game.lan.start_battle, true)
	begin.disabled = not game.lan.host()
	_button("离开房间", Vector2(410, 714), Vector2(620, 52), game.return_to_menu)
	menu_feedback = _label("", Vector2(410, 790), 17, MUTED)
	if game.lan.host():
		var ips: Array[String] = []
		for ip in IP.get_local_addresses():
			if ":" not in ip and not ip.begins_with("127."): ips.append(ip)
		menu_feedback.text = "房主地址：" + ", ".join(ips) + " :42042"

func show_lan_connecting(address: String) -> void:
	_clear_menu()
	_label("正在连接房间…", Vector2(490, 270), 43, CYAN)
	_label(address + "  /  同步关卡、队友与尸潮", Vector2(490, 360), 21, MUTED)
	_button("取消并返回", Vector2(490, 475), Vector2(470, 62), game.return_to_menu)
	menu_feedback = _label("", Vector2(490, 580), 18, ORANGE)

func show_pvp_lobby() -> void:
	_clear_menu()
	_label("WAREHOUSE / TEAM DEATHMATCH", Vector2(390, 100), 22, CYAN)
	_label(game.lan.room_name, Vector2(390, 150), 43)
	_label("1v1 至 5v5 · 无友伤 · 全武器解锁 · 真人加入可替换机器人", Vector2(300, 225), 20, MUTED)
	var fill := CheckBox.new()
	fill.name = "LobbyFillBots"
	fill.text = "缺位补机器人（可单人直接开局）"
	fill.position = Vector2(390, 250)
	fill.button_pressed = bool(game.lan.pvp_state.get("fill_bots", true))
	fill.disabled = not game.lan.host()
	fill.toggled.connect(game.lan.set_fill_bots)
	menu.add_child(fill)
	_label("机器人难度", Vector2(815, 250), 18, WHITE)
	var difficulty := OptionButton.new()
	difficulty.name = "BotDifficultyChoice"
	difficulty.position = Vector2(965, 242)
	difficulty.size = Vector2(240, 36)
	for title in ["普通", "困难", "地狱"]: difficulty.add_item(title)
	difficulty.select(game.lan.bot_difficulty)
	difficulty.disabled = not game.lan.host()
	difficulty.item_selected.connect(game.lan.set_bot_difficulty)
	_style_option(difficulty)
	menu.add_child(difficulty)
	for team in 2:
		var x := 240 + team * 500
		var color := Color(1, 0.25, 0.18) if team == 0 else Color(0.2, 0.55, 1)
		_panel(Vector2(x, 285), Vector2(460, 330), color)
		_label("RED / 红队" if team == 0 else "BLUE / 蓝队", Vector2(x + 25, 306), 25, color)
		var row := 0
		for f in game.lan.fighters.values():
			if int(f.team) != team: continue
			_label(str(f.name) + (" · 你" if int(f.id) == game.lan.local_id() else ""), Vector2(x + 25, 360 + row * 45), 21)
			row += 1
		_button("加入红队" if team == 0 else "加入蓝队", Vector2(x, 630), Vector2(460, 48), game.lan.request.bind("team", team))
	var begin := _button("开始仓库交锋" if game.lan.host() else "等待房主开始", Vector2(390, 705), Vector2(660, 60), game.lan.start_battle, true)
	begin.disabled = not game.lan.host()
	_button("离开房间", Vector2(390, 785), Vector2(660, 48), game.return_to_menu)
	menu_feedback = _label("", Vector2(390, 850), 16, MUTED)

func _style_option(choice: OptionButton) -> void:
	choice.add_theme_font_size_override("font_size", 18)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
		choice.add_theme_color_override(key, Color(0.85, 0.90, 0.90))
	for state_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.16, 0.22, 0.24) if state_name == "hover" else Color(0.10, 0.16, 0.19)
		style.border_color = Color(0.35, 0.48, 0.49)
		style.set_border_width_all(1)
		style.content_margin_left = 12
		choice.add_theme_stylebox_override(state_name, style)
	var popup := choice.get_popup()
	popup.add_theme_color_override("font_color", Color(0.85, 0.90, 0.90))
	popup.add_theme_color_override("font_hover_color", Color(0.90, 0.92, 0.89))
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.10, 0.16, 0.19)
	popup.add_theme_stylebox_override("panel", panel)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.19, 0.26, 0.28)
	popup.add_theme_stylebox_override("hover", hover)

func show_join_team() -> void:
	_clear_menu()
	_label("加入正在进行的仓库交锋", Vector2(390, 205), 36, WHITE)
	_label("先选择红队或蓝队；选队期间不会受到伤害", Vector2(390, 270), 19, MUTED)
	for team in 2:
		var x := 240 + team * 500
		var humans := 0
		var bots := 0
		for fighter in game.lan.fighters.values():
			if int(fighter.team) != team: continue
			if bool(fighter.get("is_bot", false)): bots += 1
			elif int(fighter.id) != game.lan.local_id(): humans += 1
		_panel(Vector2(x, 330), Vector2(460, 200), Color(0.65, 0.24, 0.17) if team == 0 else Color(0.17, 0.40, 0.65))
		_label("红队" if team == 0 else "蓝队", Vector2(x + 30, 360), 29, ORANGE if team == 0 else CYAN)
		_label("真人 %d / 5 · 机器人 %d" % [humans, bots], Vector2(x + 30, 420), 20, WHITE)
		var button := _button("加入红队" if team == 0 else "加入蓝队", Vector2(x, 560), Vector2(460, 60), game.lan.request.bind("join_team", team))
		button.name = "JoinRedTeam" if team == 0 else "JoinBlueTeam"
		button.disabled = humans >= 5
	_button("离开房间", Vector2(490, 675), Vector2(460, 52), game.return_to_menu)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _draw_scoreboard() -> void:
	_rect(Vector2(300, 260), Vector2(840, 405), DARK)
	_center("仓库交锋 / 击杀 · 死亡 · 爆头", 296, 25, CYAN)
	for team in 2:
		var x := 330 + team * 420
		var row := 0
		_text("红队" if team == 0 else "蓝队", Vector2(x, 335), 23, ORANGE if team == 0 else CYAN)
		for f in game.lan.fighters.values():
			if int(f.team) != team: continue
			_text("%s  %d / %d / %d" % [f.name, int(f.kills), int(f.deaths), int(f.headshots)], Vector2(x, 385 + row * 45), 19)
			row += 1

func show_pvp_result() -> void:
	_clear_menu()
	var winner := int(game.lan.pvp_state.get("winner", 2))
	_label("MATCH COMPLETE / 仓库交锋", Vector2(460, 120), 23, CYAN)
	_label("红队获胜" if winner == 0 else "蓝队获胜" if winner == 1 else "双方平局", Vector2(500, 180), 55)
	var scores: Array = game.lan.pvp_state.get("scores", [0, 0])
	_label("RED %d : %d BLUE" % scores, Vector2(535, 270), 30, ORANGE)
	for team in 2:
		var row := 0
		for f in game.lan.fighters.values():
			if int(f.team) != team: continue
			_label("%s   击杀 %d / 死亡 %d / 爆头 %d" % [f.name, int(f.kills), int(f.deaths), int(f.headshots)], Vector2(240 + team * 500, 355 + row * 48), 19)
			row += 1
	var restart := _button("房主再战一局", Vector2(390, 665), Vector2(660, 60), game.lan.start_battle, true)
	restart.disabled = not game.lan.host()
	_button("返回主菜单", Vector2(390, 755), Vector2(660, 55), game.return_to_menu)

func add_pvp_kill(data: Dictionary) -> void:
	kill_feed.push_front({"text": "%s → %s%s" % [data.attacker, data.victim, " 爆头" if data.head else ""], "head": data.head, "time": 4.0})
	if kill_feed.size() > 5: kill_feed.pop_back()
