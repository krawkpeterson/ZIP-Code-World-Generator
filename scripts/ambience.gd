extends Node3D

var sun: DirectionalLight3D
var sun_energy := 1.25
var green := 0.3
var wind: AudioStreamPlayer
var dust: GPUParticles3D
var leaves: GPUParticles3D

func setup(light: DirectionalLight3D, green_ratio: float) -> void:
	sun = light
	if sun:
		sun_energy = sun.light_energy
	green = green_ratio


func _ready() -> void:
	_wind_bed()
	_dust()
	if green > 0.28:
		_leaves()


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam:
		global_position = cam.global_position + Vector3(0.0, 1.2, 0.0)
	var t := Time.get_ticks_msec() * 0.001
	var gust := 0.72 + 0.28 * sin(t * 0.21) + 0.12 * sin(t * 0.063 + 1.7)
	RenderingServer.global_shader_parameter_set("wind_gust", gust)
	var ang := 0.55 + sin(t * 0.04) * 0.4
	RenderingServer.global_shader_parameter_set("wind_dir", Vector2(cos(ang), sin(ang)))
	if sun:
		var cloud := 0.9 + 0.1 * sin(t * 0.09) * sin(t * 0.023 + 0.6)
		sun.light_energy = sun_energy * cloud
	if wind:
		wind.volume_db = lerpf(-22.0, -16.5, clampf(gust - 0.6, 0.0, 1.0))
	if leaves:
		leaves.amount_ratio = clampf(green, 0.25, 1.0)


func _wind_bed() -> void:
	wind = AudioStreamPlayer.new()
	wind.stream = _loop_noise(3.2, 22050)
	wind.volume_db = -19.0
	wind.autoplay = false
	add_child(wind)
	if DisplayServer.get_name() != "headless":
		wind.play()


func _dust() -> void:
	dust = GPUParticles3D.new()
	dust.name = "Dust"
	dust.amount = 72
	dust.lifetime = 8.0
	dust.preprocess = 5.0
	dust.local_coords = false
	dust.visibility_aabb = AABB(Vector3(-22, -6, -22), Vector3(44, 14, 44))
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(12.0, 3.2, 12.0)
	mat.direction = Vector3(1.0, 0.04, 0.25)
	mat.spread = 28.0
	mat.initial_velocity_min = 0.08
	mat.initial_velocity_max = 0.42
	mat.gravity = Vector3(0.04, -0.015, 0.0)
	mat.scale_min = 0.35
	mat.scale_max = 1.05
	mat.color = Color(0.62, 0.56, 0.46, 0.07 if green < 0.25 else 0.04)
	dust.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(0.025, 0.025)
	var draw := StandardMaterial3D.new()
	draw.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	draw.albedo_color = Color(0.55, 0.5, 0.4, 0.18)
	draw.disable_receive_shadows = true
	draw.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = draw
	dust.draw_pass_1 = quad
	add_child(dust)


func _leaves() -> void:
	leaves = GPUParticles3D.new()
	leaves.name = "Leaves"
	leaves.amount = 22
	leaves.lifetime = 9.0
	leaves.preprocess = 4.0
	leaves.local_coords = false
	leaves.visibility_aabb = AABB(Vector3(-18, -4, -18), Vector3(36, 16, 36))
	leaves.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(10.0, 4.0, 10.0)
	mat.direction = Vector3(0.6, -0.45, 0.2)
	mat.spread = 40.0
	mat.initial_velocity_min = 0.15
	mat.initial_velocity_max = 0.7
	mat.gravity = Vector3(0.12, -0.28, 0.04)
	mat.angular_velocity_min = -40.0
	mat.angular_velocity_max = 40.0
	mat.scale_min = 0.7
	mat.scale_max = 1.2
	leaves.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(0.11, 0.07)
	var draw := StandardMaterial3D.new()
	draw.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	draw.alpha_scissor_threshold = 0.2
	draw.cull_mode = BaseMaterial3D.CULL_DISABLED
	draw.albedo_texture = _leaf_tex()
	draw.albedo_color = Color(0.72, 0.58, 0.28)
	draw.roughness = 0.85
	quad.material = draw
	leaves.draw_pass_1 = quad
	add_child(leaves)


func _leaf_tex() -> Texture2D:
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in 32:
		for x in 32:
			var dx := (float(x) - 16.0) / 14.0
			var dy := (float(y) - 16.0) / 8.0
			var e := dx * dx + dy * dy
			if e < 1.0:
				var vein := smoothstep(0.08, 0.0, abs(dx))
				var col := Color(0.45, 0.38, 0.16).lerp(Color(0.72, 0.55, 0.22), clampf(float(y) / 32.0, 0.0, 1.0))
				col = col.lerp(Color(0.35, 0.28, 0.12), vein * 0.6)
				col.a = 1.0 - smoothstep(0.65, 1.0, e)
				image.set_pixel(x, y, col)
	return ImageTexture.create_from_image(image)


func _loop_noise(seconds: float, rate: int) -> AudioStreamWAV:
	var count := int(seconds * float(rate))
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 18420
	var hold := 0.0
	for i in count:
		var t := float(i) / float(rate)
		var n := rng.randf_range(-1.0, 1.0)
		hold = lerpf(hold, n, 0.04)
		var low := sin(TAU * 47.0 * t) * 0.22 + sin(TAU * 73.0 * t + 1.2) * 0.12
		var edge := minf(t, seconds - t) / 0.35
		var s := (hold * 0.72 + low) * clampf(edge, 0.0, 1.0) * 0.55
		bytes.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 28000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = bytes
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = count
	return stream


func smoothstep(edge0: float, edge1: float, x: float) -> float:
	var t := clampf((x - edge0) / maxf(edge1 - edge0, 0.0001), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
