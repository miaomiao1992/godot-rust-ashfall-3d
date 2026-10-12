extends Node

var bank: Dictionary = {}
var rng := RandomNumberGenerator.new()
var music: AudioStreamPlayer

func _ready() -> void:
	rng.randomize()
	for name in ["pistol", "smg", "shotgun", "rifle", "coil", "hit", "headshot", "hurt", "reload", "unlock", "growl", "step", "empty", "explosion", "metal_hit", "wood_hit", "concrete_hit", "wood_break", "sniper", "bolt", "pinpull", "flash_pop", "smoke_hiss"]:
		bank[name] = _synthesize(name)
	music = AudioStreamPlayer.new()
	add_child(music)
	music.stream = _ambience()
	music.volume_db = -23
	music.play()

func play(name: String, volume: float = 0.0, pitch: float = 1.0) -> void:
	if not bank.has(name):
		return
	var player := AudioStreamPlayer.new()
	add_child(player)
	player.stream = bank[name]
	player.volume_db = volume
	player.pitch_scale = pitch * rng.randf_range(0.94, 1.06)
	player.finished.connect(player.queue_free)
	player.play()

func positional(name: String, pos: Vector3, volume: float = 0.0) -> void:
	if not bank.has(name): return
	var player := AudioStreamPlayer3D.new()
	add_child(player)
	player.stream = bank[name]
	player.position = pos
	player.volume_db = volume
	player.max_distance = 65.0 if name in ["explosion", "sniper"] else 28.0
	player.unit_size = 7.0
	player.pitch_scale = rng.randf_range(0.75, 1.15)
	player.finished.connect(player.queue_free)
	player.play()

func _stream(samples: PackedByteArray, loop: bool = false) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.data = samples
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = samples.size() / 2
	return stream

func _synthesize(kind: String) -> AudioStreamWAV:
	if kind in ["pinpull", "flash_pop", "smoke_hiss"]: return _grenade_sound(kind)
	var duration: float = {"pistol": 0.23, "smg": 0.16, "shotgun": 0.48, "rifle": 0.3, "coil": 0.7, "hit": 0.1, "headshot": 0.18, "hurt": 0.32, "reload": 0.45, "unlock": 0.65, "growl": 1.3, "step": 0.09, "empty": 0.06, "explosion": 1.2, "metal_hit": 0.25, "wood_hit": 0.17, "concrete_hit": 0.2, "wood_break": 0.55, "sniper": 0.85, "bolt": 0.38}[kind]
	var count := int(duration * 22050)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var low := 0.0
	for i in count:
		var t := float(i) / 22050.0
		var p := t / duration
		var noise := rng.randf_range(-1.0, 1.0)
		low = lerpf(low, noise, 0.14)
		var value := 0.0
		match kind:
			"pistol", "smg", "shotgun", "rifle":
				var bass: float = {"pistol": 95.0, "smg": 130.0, "shotgun": 55.0, "rifle": 72.0}[kind]
				value = (noise * 0.45 * exp(-t * 38.0) + low * 2.2 * exp(-t * 13.0) + sin(TAU * bass * t * (1.0 - p * 0.4)) * 0.4 * exp(-t * 22.0)) * minf(t * 1600.0, 1.0)
			"coil":
				value = (sin(TAU * (1600.0 * t - 800.0 * t * t)) * 0.34 + noise * 0.4 * exp(-t * 22.0) + sin(TAU * 52.0 * t) * 0.35) * exp(-t * 7.0)
			"hit":
				value = (noise * 0.5 + sin(t * 700.0) * 0.25) * exp(-t * 50.0)
			"headshot":
				value = (sin(t * 5800.0) * 0.32 + noise * 0.2) * exp(-t * 24.0)
			"hurt":
				value = (low * 2.0 + sin(TAU * 65.0 * t) * 0.4) * pow(1.0 - p, 2.0)
			"reload":
				value = noise * 0.38 * (exp(-t * 90.0) + exp(-absf(t - 0.2) * 130.0) + exp(-absf(t - 0.36) * 130.0))
			"unlock":
				value = sin(TAU * (440.0 if p < 0.33 else 554.0 if p < 0.66 else 660.0) * t) * 0.22 * pow(1.0 - p, 0.5)
			"growl":
				value = (sin(TAU * 55.0 * t + low * 3.0) * 0.35 + low * 1.6) * sin(PI * p) * (0.65 + 0.35 * sin(t * 31.0))
			"step":
				value = low * 2.2 * exp(-t * 48.0)
			"empty":
				value = noise * 0.25 * exp(-t * 100.0)
			"explosion":
				value = (low * 2.6 + sin(TAU * (47 * t - 9 * t * t)) * 0.5) * exp(-t * 4) + noise * 0.55 * exp(-t * 27)
			"metal_hit":
				value = (sin(TAU * 2150 * t) * 0.35 + sin(TAU * 3700 * t) * 0.15 + noise * 0.25) * exp(-t * 23)
			"wood_hit":
				value = (sin(TAU * 220 * t) * 0.4 + low * 1.2 + noise * 0.15) * exp(-t * 34)
			"concrete_hit":
				value = (low * 1.7 + noise * 0.6) * exp(-t * 46)
			"wood_break":
				value = (low * 1.8 + noise * 0.3) * exp(-t * 10)
			"sniper":
				value = noise * 0.7 * exp(-t * 40) + (low * 2 + sin(TAU * 62 * t) * 0.55) * exp(-t * 9)
			"bolt":
				value = noise * 0.5 * (exp(-t * 80) + exp(-absf(t - 0.23) * 70)) + sin(t * 3500) * 0.1 * exp(-t * 12)
		bytes.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 30000))
	return _stream(bytes)

func _grenade_sound(kind: String) -> AudioStreamWAV:
	var duration: float = 1.5 if kind == "smoke_hiss" else 0.12 if kind == "pinpull" else 0.6
	var samples := PackedByteArray()
	var count := int(duration * 22050)
	samples.resize(count * 2)
	for i in count:
		var t := float(i) / 22050
		var noise := rng.randf_range(-1, 1)
		var value: float
		if kind == "pinpull": value = (noise * 0.18 + sin(TAU * 2900 * t) * 0.20) * exp(-t * 38)
		elif kind == "flash_pop": value = noise * 0.7 * exp(-t * 36) + sin(TAU * 1800 * t) * 0.1 * exp(-t * 6)
		else: value = noise * 0.18 * sin(PI * t / duration)
		samples.encode_s16(i * 2, int(clampf(value, -1, 1) * 30000))
	return _stream(samples)

func _ambience() -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(22050 * 8 * 2)
	var low := 0.0
	for i in 22050 * 8:
		var t := float(i) / 22050.0
		low = lerpf(low, rng.randf_range(-1, 1), 0.006)
		var v := low * 1.5 + sin(TAU * 38.0 * t) * 0.13 + sin(TAU * 57.0 * t) * 0.04 + sin(TAU * 110.0 * t) * 0.025 * (0.5 + 0.5 * sin(TAU * t / 8.0))
		bytes.encode_s16(i * 2, int(clampf(v, -1, 1) * 24000))
	return _stream(bytes, true)
