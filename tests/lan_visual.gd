extends Node
var game

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("review")

func capture(name: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tests/previews/" + name + ".png")
	print("LAN_VISUAL ", name)

func review() -> void:
	game.test_mode = true
	game.hud.show_lan_browser()
	game.lan.net.set_discovery_port(42043)
	game.lan.create_room("余烬联合行动", "房主幸存者")
	game.state = "menu"
	game.hud.show_lan_browser()
	await get_tree().create_timer(1.5).timeout
	game.hud._refresh_rooms()
	await capture("07-lan-browser")
	game.state = "lobby"
	game.hud.show_lan_lobby()
	await capture("08-lan-lobby")
	game.lan.start_battle()
	await get_tree().create_timer(1).timeout
	await capture("09-lan-host")
	game.lan.leave()
	get_tree().quit()
