extends RefCounted

var textures: Dictionary = {}
var shared: Dictionary = {}

func load_all() -> void:
	for key in ["forrest_ground_01", "dry_ground_01", "rock_face", "asphalt_02", "concrete_floor_worn_001", "red_brick", "corrugated_iron", "wood_floor", "plastered_wall", "roof_tiles", "wood_planks", "bark_willow", "painted_wood"]:
		textures[key + "_diff"] = _load_tex(key + "_diff.jpg", false)
		textures[key + "_nor"] = _load_tex(key + "_nor.jpg", true)
	shared["grass"] = _pbr("forrest_ground_01", Color(0.72, 0.78, 0.62), 0.22, 0.94, 0.0)
	shared["dirt"] = _pbr("dry_ground_01", Color(0.72, 0.58, 0.4), 0.28, 0.96, 0.0)
	shared["rock"] = _pbr("rock_face", Color(0.7, 0.62, 0.5), 0.18, 0.82, 0.0)
	shared["asphalt"] = _pbr("asphalt_02", Color(0.42, 0.38, 0.32), 0.45, 0.78, 0.0)
	shared["concrete"] = _pbr("concrete_floor_worn_001", Color(0.7, 0.62, 0.5), 0.32, 0.9, 0.0)
	shared["brick"] = _pbr("red_brick", Color(0.72, 0.52, 0.38), 0.42, 0.9, 0.0)
	shared["metal"] = _pbr("corrugated_iron", Color(0.5, 0.4, 0.28), 0.62, 0.64, 0.72)
	shared["wood"] = _pbr("wood_floor", Color(0.62, 0.48, 0.32), 0.7, 0.72, 0.0)
	shared["planks"] = _pbr("wood_planks", Color(0.64, 0.5, 0.34), 0.48, 0.78, 0.0, "wood_floor")
	shared["plaster"] = _pbr("plastered_wall", Color(0.78, 0.64, 0.46), 0.38, 0.9, 0.0)
	shared["roof"] = _pbr("roof_tiles", Color(0.5, 0.36, 0.26), 0.62, 0.84, 0.0)
	shared["bark"] = _pbr("bark_willow", Color(0.7, 0.62, 0.5), 0.4, 0.9, 0.0, "wood_planks")
	shared["glass"] = _glass(Color(0.62, 0.74, 0.78, 0.22), Color(1.0, 0.86, 0.65), 0.22)
	shared["glass_dim"] = _glass(Color(0.45, 0.55, 0.58, 0.28), Color(1.0, 0.8, 0.55), 0.08)
	shared["emit"] = _flat(Color(1.0, 0.78, 0.5), 0.4, 0.0, Color(1.0, 0.75, 0.45), 1.6)
	shared["fabric"] = _pbr("plastered_wall", Color(0.45, 0.32, 0.24), 0.8, 0.92, 0.0)
	shared["darkmetal"] = _pbr("corrugated_iron", Color(0.16, 0.16, 0.17), 0.48, 0.58, 0.88)


func get_shared(key: String) -> StandardMaterial3D:
	return shared.get(key, shared["concrete"]) as StandardMaterial3D


func tinted(key: String, color: Color) -> StandardMaterial3D:
	var base := get_shared(key)
	var copy := base.duplicate() as StandardMaterial3D
	copy.albedo_color = color
	return copy


func _load_tex(file_name: String, _is_normal: bool) -> Texture2D:
	var path := "res://assets/textures/" + file_name
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is Texture2D:
			return res
	var abs_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(abs_path):
		var image := Image.new()
		if image.load(abs_path) == OK:
			return ImageTexture.create_from_image(image)
	return null


func _pbr(key: String, tint: Color, uv_scale: float, roughness: float, metallic: float, fallback_key: String = "") -> StandardMaterial3D:
	var diff: Texture2D = textures.get(key + "_diff")
	var nor: Texture2D = textures.get(key + "_nor")
	if diff == null and fallback_key != "":
		diff = textures.get(fallback_key + "_diff")
		nor = textures.get(fallback_key + "_nor")
	if diff == null:
		diff = _solid_tex(tint)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = diff
	mat.albedo_color = tint
	mat.roughness = roughness
	mat.metallic = metallic
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE * uv_scale
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	if nor != null:
		mat.normal_enabled = true
		mat.normal_texture = nor
		mat.normal_scale = 1.0
	return mat


func _glass(albedo: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = albedo
	mat.roughness = 0.08
	mat.metallic = 0.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	mat.emission_enabled = energy > 0.02
	mat.emission = emission
	mat.emission_energy_multiplier = energy * 0.28
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	return mat


func _flat(albedo: Color, roughness: float, metallic: float, emission: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.roughness = roughness
	mat.metallic = metallic
	if energy > 0.0:
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = energy
	return mat


func _solid_tex(color: Color) -> Texture2D:
	var image := Image.create(8, 8, false, Image.FORMAT_RGB8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


func make_grass_atlas() -> Texture2D:
	var w := 96
	var h := 160
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 44021
	for blade in 18:
		var x := int(12 + (blade % 6) * 14 + rng.randi_range(-2, 2))
		var lean := rng.randf_range(-6.0, 6.0)
		var height := rng.randi_range(70, 150)
		var green := Color(rng.randf_range(0.18, 0.32), rng.randf_range(0.32, 0.5), rng.randf_range(0.08, 0.16), 1.0)
		for y in height:
			var t := float(y) / float(height)
			var px := int(round(x + lean * t))
			var py := h - 1 - y
			if px < 1 or px >= w - 1 or py < 0:
				continue
			var col := green.lerp(Color(0.55, 0.62, 0.28, 1.0), t * 0.55)
			col.a = 1.0 - smoothstep(0.75, 1.0, t) * 0.2
			image.set_pixel(px, py, col)
			if px + 1 < w:
				var edge := col
				edge.a = 0.65
				image.set_pixel(px + 1, py, edge)
	return ImageTexture.create_from_image(image)


func smoothstep(edge0: float, edge1: float, x: float) -> float:
	var t := clampf((x - edge0) / max(edge1 - edge0, 0.0001), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
