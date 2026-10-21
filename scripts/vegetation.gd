extends Node3D

const PLAY_HALF := 400.0
const CHUNK := 28.0
const COVER_N := 161
const TREE_CAP := 3600
const SHRUB_CAP := 2800
const HERO_RANGE := {
	"fir": 48.0,
	"pine": 48.0,
	"shrub": 60.0,
	"broadleaf": 60.0,
	"sapling": 72.0,
}
const HERO_COUNT := {
	"fir": 0,
	"pine": 0,
	"shrub": 8,
	"broadleaf": 6,
	"sapling": 4,
}

var ground: Node
var _rng := RandomNumberGenerator.new()
var _scenes := {}
var _cards := {}
var _card_mesh := {}
var _canopy := PackedByteArray()
var _greenery := PackedByteArray()
var _cover_step := 5.0
var _grass_mesh: Mesh
var _bermuda_src: Material
var _grass_mat: ShaderMaterial
var _card_mat: ShaderMaterial
var _litter_mat: ShaderMaterial
var _litter_mesh: Mesh
var _flat_normal: Texture2D
var _species_names: Array = []
var _pos := PackedVector3Array()
var _yaw := PackedFloat32Array()
var _scale := PackedFloat32Array()
var _tint := PackedColorArray()
var _species_id := PackedInt32Array()
var _mm_index := PackedInt32Array()
var _hash := {}
var _impostors := {}
var _local_bottom := {}
var _pools := {}
var _concealed := {}
var _last_anchor := Vector3(100000, 0, 100000)
var _grass_height := 0.6
var _tree_total := 0
var _clump_total := 0
var _card_total := 0
var _litter_total := 0
var _plant_block := PackedByteArray()
var _ground_ready := {}
const GROUND_STEP := 0.58

func populate(builder: Node, features: Dictionary, placements: Array) -> Dictionary:
	set_process(false)
	ground = builder
	_rng.seed = 90210
	_flat_normal = _solid_normal()
	_load_scenes()
	await _build_impostors()
	await _raster_cover(features.forests)
	var tree_block := _clearance_mask(features, placements, 4.8, 3.2, 2.4)
	var plant_block := _clearance_mask(features, placements, 1.35, 1.4, 1.1)
	var counts: Dictionary = await _scatter(features, tree_block, plant_block)
	_make_pools()
	_refresh_heroes(Vector3.ZERO)
	set_process(true)
	print("Vegetation trees ", counts.trees, " shrubs ", counts.shrubs, " grass ", counts.grass, " cards ", counts.cards)
	return counts


func _process(_delta: float) -> void:
	var anchor := _anchor()
	if not _pos.is_empty() and anchor.distance_squared_to(_last_anchor) >= 2.25:
		_refresh_heroes(anchor)
	_stream_ground(anchor, 1)


func _load_scenes() -> void:
	var files := {
		"fir": "res://assets/nature/fir_tree_01_0.glb",
		"pine": "res://assets/nature/pine_tree_01_0.glb",
		"broadleaf": "res://assets/nature/searsia_burchellii_0.glb",
		"shrub": "res://assets/nature/shrub_01_0.glb",
		"boulder": "res://assets/nature/boulder_01_0.glb",
		"dead": "res://assets/nature/dead_tree_trunk_0.glb",
		"grass": "res://assets/nature/grass_medium_01_0.glb",
		"bermuda": "res://assets/nature/bermuda/grass_bermuda_01_1k.gltf",
		"sapling": "res://assets/nature/pine_sapling_medium_0.glb",
	}
	for key in files.keys():
		var packed: PackedScene = ground._load_packed(str(files[key]))
		if packed == null:
			push_warning("Missing nature model " + str(key))
			continue
		_scenes[key] = packed
		print("Loaded ", key)


func _build_impostors() -> void:
	for key in ["fir", "pine", "shrub", "broadleaf", "sapling", "bermuda"]:
		if not _scenes.has(key):
			continue
		if key == "fir" or key == "pine":
			var built: Dictionary = _conifer_impostor(key == "fir")
			_impostors[key] = built
			print("Conifer ", key, " ", built.height)
			continue
		var tall: bool = key == "fir" or key == "pine"
		if key == "bermuda":
			var patch: Dictionary = _bermuda_patch(_scenes[key])
			_grass_mesh = patch.mesh
			_bermuda_src = patch.mat
		var captured: Dictionary = await _capture_impostor(key, _scenes[key], tall, key != "bermuda")
		if captured.is_empty():
			push_warning("Impostor failed for " + key)
			continue
		var tex: Texture2D = captured.texture
		var card_h: float = float(captured.height)
		var card_w: float = float(captured.width)
		_cards[key] = tex
		_card_mesh[key] = _cross_card(card_w, card_h, 3)
		var wind := 0.18 if tall else 0.1
		var scissor := 0.08
		if key == "bermuda":
			wind = 0.1
			scissor = 0.04
		var face_up := 0.88 if key == "bermuda" else 0.0
		var mat := _foliage_mat(tex, null, card_h, wind, scissor, 0.72, 0.02, face_up)
		_impostors[key] = {"mesh": _card_mesh[key], "mat": mat, "multimesh": null}
		print("Impostor ", key, " ", card_w, " x ", card_h)


func _capture_impostor(key: String, packed: PackedScene, tall: bool, thicken: bool = true) -> Dictionary:
	var version := "v12" if key == "bermuda" else "v6"
	var cache := "user://ashen/impostors/%s_%s.png" % [key, version]
	var meta_path := "user://ashen/impostors/%s_%s.json" % [key, version]
	if FileAccess.file_exists(cache) and FileAccess.file_exists(meta_path):
		var cached := Image.new()
		if cached.load(cache) == OK and cached.get_width() > 16:
			var meta_text := FileAccess.get_file_as_string(meta_path)
			var parsed: Variant = JSON.parse_string(meta_text)
			if parsed is Dictionary:
				var meta: Dictionary = parsed
				if float(meta.get("height", 0.0)) > 0.04:
					return {
						"texture": ImageTexture.create_from_image(cached),
						"width": float(meta.get("width", 1.0)),
						"height": float(meta.get("height", 1.0)),
					}
	var box := AABB()
	if key == "bermuda" and _grass_mesh != null:
		box = _grass_mesh.get_aabb()
	else:
		var probe: Node3D = packed.instantiate()
		add_child(probe)
		await get_tree().process_frame
		box = _merged_aabb(probe)
		probe.queue_free()
	if box.size.y < 0.05:
		return {}
	var tree_h: float = box.size.y
	var tree_w: float = maxf(box.size.x, box.size.z)
	var pad_h: float = tree_h * 1.08
	var pad_w: float = maxf(tree_w * 1.16, pad_h * 0.28)
	var vp_h := 1152 if tall else (512 if key == "bermuda" else 768)
	var vp_limit := 4096 if key == "bermuda" else 1280
	var vp_w := clampi(int(round(float(vp_h) * pad_w / pad_h)), 280, vp_limit)
	var layer := CanvasLayer.new()
	layer.layer = 80
	add_child(layer)
	var holder := SubViewportContainer.new()
	holder.custom_minimum_size = Vector2(vp_w, vp_h)
	holder.size = Vector2(vp_w, vp_h)
	holder.stretch = true
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(holder)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = false
	vp.size = Vector2i(vp_w, vp_h)
	vp.msaa_3d = Viewport.MSAA_2X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.handle_input_locally = false
	holder.add_child(vp)
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(1, 0, 1, 1)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.15
	env_node.environment = env
	vp.add_child(env_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 28, 0)
	sun.light_energy = 1.35
	sun.shadow_enabled = false
	vp.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-12, 180, 0)
	fill.light_color = Color(0.75, 0.82, 0.95)
	fill.light_energy = 0.45
	fill.shadow_enabled = false
	vp.add_child(fill)
	var inst: Node3D
	if key == "bermuda" and _grass_mesh != null:
		var card_src := MeshInstance3D.new()
		card_src.mesh = _grass_mesh
		if _bermuda_src != null:
			card_src.material_override = _bermuda_src
		inst = card_src
	else:
		inst = packed.instantiate()
	vp.add_child(inst)
	_force_cutout(inst)
	await get_tree().process_frame
	var aabb := _merged_aabb(inst)
	var shift := Vector3(aabb.get_center().x, aabb.position.y, aabb.get_center().z)
	inst.position -= shift
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = pad_h
	cam.position = Vector3(0.0, pad_h * 0.5, maxf(pad_w, pad_h) + 4.0)
	cam.rotation = Vector3.ZERO
	cam.current = true
	vp.add_child(cam)
	for _frame in 6:
		await RenderingServer.frame_post_draw
	var image := vp.get_texture().get_image()
	layer.queue_free()
	if image == null or image.get_width() < 8:
		return {}
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	_key_magenta(image)
	if not thicken:
		_key_black(image)
		_bleed_color(image)
	if thicken:
		image = await _dilate_image(image, 3.0)
		image = await _dilate_image(image, 2.0)
	var opaque := 0
	var samples := 0
	for y in range(0, image.get_height(), 6):
		for x in range(0, image.get_width(), 6):
			samples += 1
			if image.get_pixel(x, y).a > 0.35:
				opaque += 1
	if samples == 0 or float(opaque) / float(samples) < 0.01:
		push_warning("Impostor %s captured empty" % key)
		return {}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://ashen/impostors"))
	image.save_png(cache)
	var meta_file := FileAccess.open(meta_path, FileAccess.WRITE)
	if meta_file:
		meta_file.store_string(JSON.stringify({"width": pad_w, "height": pad_h}))
		meta_file.close()
	var visible_w: float = pad_h * float(vp_w) / float(vp_h)
	return {
		"texture": ImageTexture.create_from_image(image),
		"width": visible_w,
		"height": pad_h,
	}


func _force_cutout(root: Node) -> void:
	var meshes: Array = []
	if root is MeshInstance3D:
		meshes.append(root)
	meshes.append_array(root.find_children("*", "MeshInstance3D", true, false))
	for node in meshes:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh_node.lod_bias = 8.0
		for s in mesh_node.mesh.get_surface_count():
			var base := mesh_node.get_active_material(s)
			if base is StandardMaterial3D:
				var dup := (base as StandardMaterial3D).duplicate() as StandardMaterial3D
				dup.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				dup.alpha_scissor_threshold = 0.22
				dup.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_OFF
				dup.cull_mode = BaseMaterial3D.CULL_DISABLED
				dup.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mesh_node.set_surface_override_material(s, dup)


func _dilate_image(source: Image, radius: float) -> Image:
	var tex := ImageTexture.create_from_image(source)
	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.size = source.get_size()
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.disable_3d = true
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	var holder := SubViewportContainer.new()
	holder.size = Vector2(source.get_width(), source.get_height())
	holder.stretch = true
	layer.add_child(holder)
	holder.add_child(vp)
	var rect := ColorRect.new()
	rect.size = Vector2(source.get_width(), source.get_height())
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/dilate.gdshader")
	mat.set_shader_parameter("source", tex)
	mat.set_shader_parameter("radius", radius)
	rect.material = mat
	vp.add_child(rect)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := vp.get_texture().get_image()
	layer.queue_free()
	if image == null:
		return source
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image


func _key_magenta(image: Image) -> void:
	var data: PackedByteArray = image.get_data()
	var i := 0
	while i + 3 < data.size():
		var r := int(data[i])
		var g := int(data[i + 1])
		var b := int(data[i + 2])
		var mag := mini(r, b) - g
		if mag > 28 and r > 90 and b > 90:
			data[i] = 0
			data[i + 1] = 0
			data[i + 2] = 0
			data[i + 3] = 0
		else:
			data[i + 3] = 255
		i += 4
	image.set_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, data)


func _bermuda_patch(packed: PackedScene) -> Dictionary:
	var root: Node3D = packed.instantiate()
	add_child(root)
	var meshes: Array = root.find_children("*", "MeshInstance3D", true, false)
	var kept: Array[MeshInstance3D] = []
	for node in meshes:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		var n := str(mesh_node.name)
		if mesh_node.get_parent() != null:
			n += " " + str(mesh_node.get_parent().name)
		if (n.contains("medium") or n.contains("small")) and not n.contains("seedling"):
			kept.append(mesh_node)
	if kept.is_empty():
		for node in meshes:
			var mesh_node := node as MeshInstance3D
			if mesh_node.mesh != null:
				kept.append(mesh_node)
			if kept.size() >= 8:
				break
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mat: Material = null
	var cols := 4
	for i in kept.size():
		var mesh_node := kept[i]
		if mat == null:
			mat = mesh_node.mesh.surface_get_material(0)
		if mat == null:
			mat = mesh_node.get_active_material(0)
		var ab: AABB = mesh_node.mesh.get_aabb()
		var center := Vector3(ab.get_center().x, ab.position.y, ab.get_center().z)
		var col := i % cols
		var row := int(float(i) / float(cols))
		var basis := Basis(Vector3.UP, float(i) * 0.85)
		var at := Vector3((float(col) - 1.5) * 0.05, 0.0, (float(row) - 1.0) * 0.045)
		var xf := Transform3D(basis, at) * Transform3D(Basis.IDENTITY, -center)
		for s in mesh_node.mesh.get_surface_count():
			st.append_from(mesh_node.mesh, s, xf)
	root.queue_free()
	mat = _bermuda_material()
	st.set_material(mat)
	var mesh := st.commit()
	var bounds := mesh.get_aabb()
	print("Bermuda patch ", bounds.size, " from ", kept.size())
	return {"mesh": mesh, "mat": mat}


func _bermuda_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _image_tex("res://assets/nature/bermuda/textures/grass_bermuda_01_diff_1k.jpg")
	mat.roughness = 0.82
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var nor := _image_tex("res://assets/nature/bermuda/textures/grass_bermuda_01_nor_gl_1k.jpg")
	if nor != null:
		mat.normal_enabled = true
		mat.normal_texture = nor
	return mat


func _image_tex(path: String) -> Texture2D:
	var image := Image.new()
	if image.load(path) != OK:
		push_warning("Missing texture " + path)
		return null
	return ImageTexture.create_from_image(image)


func _key_black(image: Image) -> void:
	var data: PackedByteArray = image.get_data()
	var i := 0
	while i + 3 < data.size():
		var r := int(data[i])
		var g := int(data[i + 1])
		var b := int(data[i + 2])
		if r < 26 and g < 30 and b < 26:
			data[i + 3] = 0
		i += 4
	image.set_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, data)


func _isolate_tuft(root: Node3D) -> void:
	var kept: Array[MeshInstance3D] = []
	var meshes: Array = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	for node in meshes:
		var mesh_node := node as MeshInstance3D
		var n := str(mesh_node.name)
		if not n.contains("medium") and not n.contains("small") and mesh_node.get_parent() != null:
			n = str(mesh_node.get_parent().name)
		var lush := (n.contains("medium") or n.contains("small")) and not n.contains("seedling")
		if lush:
			kept.append(mesh_node)
		else:
			mesh_node.visible = false
	var count := kept.size()
	if count == 0:
		return
	var cols := 4
	for i in count:
		var node := kept[i]
		if node.get_parent() != root:
			node.reparent(root, false)
		var col := i % cols
		var row := int(float(i) / float(cols))
		var jitter := float((i * 17) % 5) * 0.01
		node.position = Vector3((float(col) - 1.5) * 0.16 + jitter, 0.0, (float(row) - 1.0) * 0.16)
		node.rotation = Vector3(0.0, float(i) * 0.9, 0.0)


func _bleed_color(image: Image) -> void:
	var w := image.get_width()
	var h := image.get_height()
	var src := image.duplicate()
	for y in h:
		for x in w:
			var c: Color = src.get_pixel(x, y)
			if c.a > 0.25:
				continue
			var red := 0.0
			var green := 0.0
			var blue := 0.0
			var n := 0
			for oy in range(-3, 4):
				var sy := clampi(y + oy, 0, h - 1)
				for ox in range(-3, 4):
					var sx := clampi(x + ox, 0, w - 1)
					var s: Color = src.get_pixel(sx, sy)
					if s.a > 0.45:
						red += s.r
						green += s.g
						blue += s.b
						n += 1
			if n > 0:
				var inv := 1.0 / float(n)
				image.set_pixel(x, y, Color(red * inv, green * inv, blue * inv, c.a))


func _raster_cover(forests: Array) -> void:
	_cover_step = (PLAY_HALF * 2.0) / float(COVER_N - 1)
	_canopy.resize(COVER_N * COVER_N)
	_greenery.resize(COVER_N * COVER_N)
	var img: Image = ground.sat_image
	var bounds: Dictionary = ground.sat_bounds
	var geo: Node = ground.geo
	for z in COVER_N:
		var wz := -PLAY_HALF + float(z) * _cover_step
		for x in COVER_N:
			var wx := -PLAY_HALF + float(x) * _cover_step
			var ll: Vector2 = ground.latlon_at(wx, wz)
			var col: Color = geo.sample_rgb(img, bounds, ll.x, ll.y)
			var lum := col.get_luminance()
			var mx := maxf(col.r, maxf(col.g, col.b))
			var mn := minf(col.r, minf(col.g, col.b))
			var chroma := mx - mn
			var canopy := 0.0
			var green := 0.0
			if lum < 0.78 and chroma > 0.025 and lum > 0.04:
				green = clampf(0.25 + chroma * 3.0 + (0.55 - lum), 0.0, 1.0)
			if lum < 0.5 and chroma > 0.035:
				canopy = clampf((0.52 - lum) / 0.34, 0.0, 1.0) * clampf(chroma * 6.0, 0.35, 1.0)
			if lum > 0.62 and col.g > col.r * 0.95:
				canopy *= 0.2
				green = maxf(green, 0.55)
			if lum > 0.84 or chroma < 0.015 and lum > 0.45:
				canopy = 0.0
				green *= 0.15
			var i := z * COVER_N + x
			_canopy[i] = int(clampf(canopy, 0.0, 1.0) * 255.0)
			_greenery[i] = int(clampf(green, 0.0, 1.0) * 255.0)
		if z % 40 == 0:
			await get_tree().process_frame
	for poly in forests:
		var pts: PackedVector2Array = poly
		if pts.size() < 3:
			continue
		var bounds_r := _poly_bounds(pts)
		var x0 := clampi(_cover_x(bounds_r.position.x), 0, COVER_N - 1)
		var x1 := clampi(_cover_x(bounds_r.position.x + bounds_r.size.x), 0, COVER_N - 1)
		var z0 := clampi(_cover_z(bounds_r.position.y), 0, COVER_N - 1)
		var z1 := clampi(_cover_z(bounds_r.position.y + bounds_r.size.y), 0, COVER_N - 1)
		for z in range(z0, z1 + 1):
			for x in range(x0, x1 + 1):
				var p := Vector2(-PLAY_HALF + float(x) * _cover_step, -PLAY_HALF + float(z) * _cover_step)
				if Geometry2D.is_point_in_polygon(p, pts):
					var i := z * COVER_N + x
					_canopy[i] = maxi(_canopy[i], 220)
					_greenery[i] = maxi(_greenery[i], 180)


func _scatter(features: Dictionary, tree_block: PackedByteArray, plant_block: PackedByteArray) -> Dictionary:
	var shrubs := 0
	_plant_block = plant_block
	_prepare_grass()
	_litter_mesh = _ground_quad(1.15)
	_litter_mat = _foliage_mat(_leaf_texture(), null, 0.2, 0.0, 0.4, 0.92, 0.0)
	var spots: Array[Vector2] = []
	var x := -PLAY_HALF + 6.0
	while x < PLAY_HALF - 6.0:
		var z := -PLAY_HALF + 6.0
		while z < PLAY_HALF - 6.0:
			spots.append(Vector2(x, z))
			z += 13.0
		x += 13.0
	spots.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.length() < b.length())
	for spot in spots:
		if _tree_total >= TREE_CAP:
			break
		var jx: float = spot.x + _rng.randf_range(-3.2, 3.2)
		var jz: float = spot.y + _rng.randf_range(-3.2, 3.2)
		var canopy := _canopy_at(jx, jz)
		var green := _green_at(jx, jz)
		if float(ground._slope_at(jx, jz)) > 0.5:
			continue
		if ground._blocked(tree_block, jx, jz):
			continue
		if canopy > 0.34 and _rng.randf() < lerpf(0.45, 0.98, canopy):
			_add_woody(jx, jz, canopy, true)
		elif green > 0.5 and _rng.randf() < 0.12:
			_add_woody(jx, jz, canopy, true)
	_roadside(features.roads, tree_block)
	var sx := -PLAY_HALF + 4.0
	while sx < PLAY_HALF - 4.0:
		var sz := -PLAY_HALF + 4.0
		while sz < PLAY_HALF - 4.0:
			if shrubs >= SHRUB_CAP:
				break
			var px := sx + _rng.randf_range(-2.0, 2.0)
			var pz := sz + _rng.randf_range(-2.0, 2.0)
			var canopy2 := _canopy_at(px, pz)
			var green2 := _green_at(px, pz)
			if float(ground._slope_at(px, pz)) < 0.52 and not ground._blocked(plant_block, px, pz):
				if _rng.randf() < lerpf(0.15, 0.85, maxf(canopy2, green2 * 0.35)):
					_add_woody(px, pz, canopy2, false)
					shrubs += 1
			sz += 8.0
		if shrubs >= SHRUB_CAP:
			break
		sx += 8.0
		if int(sx) % 64 == 0:
			await get_tree().process_frame
	_place_deadwood(tree_block)
	await _flush_chunks({})
	_build_trunks()
	await _warm_ground(Vector3.ZERO)
	return {"trees": _tree_total, "shrubs": shrubs, "grass": _clump_total, "cards": _card_total, "litter": _litter_total}


func _warm_ground(anchor: Vector3) -> void:
	var built := 0
	while built < 150:
		if not _stream_ground(anchor, 1):
			break
		built += 1
		if built % 3 == 0:
			await get_tree().process_frame


func _stream_ground(anchor: Vector3, budget: int) -> bool:
	if _card_mat == null or _plant_block.is_empty():
		return false
	var made := false
	var left := budget
	var cx := int(floor((anchor.x + PLAY_HALF) / CHUNK))
	var cz := int(floor((anchor.z + PLAY_HALF) / CHUNK))
	for radius in range(0, 14):
		for oz in range(-radius, radius + 1):
			for ox in range(-radius, radius + 1):
				if radius > 0 and maxi(absi(ox), absi(oz)) != radius:
					continue
				if left <= 0:
					return made
				var cell := Vector2i(cx + ox, cz + oz)
				if _ground_ready.has(cell):
					continue
				var center := _chunk_center(cell)
				if center.distance_to(Vector2(anchor.x, anchor.z)) > 344.0:
					continue
				_build_ground_chunk(cell)
				_ground_ready[cell] = true
				made = true
				left -= 1
	return made


func _build_ground_chunk(cell: Vector2i) -> void:
	var x0 := -PLAY_HALF + float(cell.x) * CHUNK
	var z0 := -PLAY_HALF + float(cell.y) * CHUNK
	if x0 > PLAY_HALF or z0 > PLAY_HALF or x0 + CHUNK < -PLAY_HALF or z0 + CHUNK < -PLAY_HALF:
		return
	var bucket := {"grass": [], "gcol": [], "card": [], "ccol": [], "litter": [], "lcol": []}
	var x := x0 + 0.35
	var ix := 0
	while x < x0 + CHUNK - 0.2:
		var z := z0 + 0.35
		var iz := 0
		while z < z0 + CHUNK - 0.2:
			var jx := x + _rng.randf_range(-0.48, 0.48)
			var jz := z + _rng.randf_range(-0.48, 0.48)
			if _rng.randf() < 0.18:
				z += GROUND_STEP
				iz += 1
				continue
			if absf(jx) < PLAY_HALF - 2.0 and absf(jz) < PLAY_HALF - 2.0 and not ground._blocked(_plant_block, jx, jz):
				var green := _green_at(jx, jz)
				var canopy := _canopy_at(jx, jz)
				var clump := _clump_noise(jx, jz)
				var gate := 0.62 - clampf(green, 0.0, 1.0) * 0.4
				if clump < gate:
					z += GROUND_STEP
					iz += 1
					continue
				if green > 0.08 and float(ground._slope_at(jx, jz)) < 0.6:
					_push_card(bucket, jx, jz, canopy, green)
					_card_total += 1
					if posmod(ix * 5 + iz, 17) == 0:
						_push_clump(bucket, jx, jz, canopy, green)
						_clump_total += 1
					if canopy > 0.45 and posmod(ix + iz, 5) == 0:
						_push_litter(bucket, jx, jz, canopy)
						_litter_total += 1
			z += GROUND_STEP
			iz += 1
		x += GROUND_STEP
		ix += 1
	_emit_multi(bucket.card, bucket.ccol, _card_mesh_ground(), _card_mat, 208.0, false)
	_emit_multi(bucket.grass, bucket.gcol, _grass_mesh, _grass_mat, 42.0, false)
	_emit_multi(bucket.litter, bucket.lcol, _litter_mesh, _litter_mat, 176.0, false)


func _chunk_center(cell: Vector2i) -> Vector2:
	return Vector2(-PLAY_HALF + (float(cell.x) + 0.5) * CHUNK, -PLAY_HALF + (float(cell.y) + 0.5) * CHUNK)


func _add_woody(x: float, z: float, canopy: float, tree: bool) -> void:
	var species := "shrub"
	var scale := _rng.randf_range(0.85, 1.35)
	var green := _green_at(x, z)
	var arid := green < 0.22
	var want_tree := tree and not (arid and _rng.randf() < 0.8)
	if want_tree:
		var roll := _rng.randf()
		var prefer_pine := green < 0.4
		if not prefer_pine and roll < 0.58 and _impostors.has("fir"):
			species = "fir"
			scale = _rng.randf_range(0.78, 1.22)
		elif _impostors.has("pine"):
			species = "pine"
			scale = _rng.randf_range(0.72, 1.18)
		elif _impostors.has("fir"):
			species = "fir"
		else:
			return
		if canopy < 0.55:
			scale *= _rng.randf_range(0.55, 0.8)
		if arid:
			scale *= 0.7
	else:
		var roll2 := _rng.randf()
		if roll2 < 0.4 and _impostors.has("broadleaf"):
			species = "broadleaf"
			scale = _rng.randf_range(0.9, 1.6)
		elif roll2 < 0.62 and _impostors.has("sapling"):
			species = "sapling"
			scale = _rng.randf_range(0.7, 1.15)
		elif _impostors.has("shrub"):
			species = "shrub"
			scale = _rng.randf_range(2.6, 4.4)
		else:
			return
	if not _impostors.has(species):
		return
	var y := float(ground.sample_height(x, z))
	var yaw := _rng.randf() * TAU
	var tint := _tint_at(x, z, 0.62 if want_tree else 0.45)
	tint = Color(tint.r * _rng.randf_range(0.9, 1.08), tint.g * _rng.randf_range(0.9, 1.08), tint.b * _rng.randf_range(0.88, 1.05))
	var info: Dictionary = _impostors[species]
	if info.multimesh == null:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = info.mesh
		info.transforms = []
		info.colors = []
		info.multimesh = mm
		_impostors[species] = info
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale)
	info.transforms.append(Transform3D(basis, Vector3(x, y, z)))
	info.colors.append(Color(tint.r, tint.g, tint.b, _rng.randf()))
	var local_index: int = info.transforms.size() - 1
	var sid := _species_index(species)
	_pos.append(Vector3(x, y, z))
	_yaw.append(yaw)
	_scale.append(scale)
	_tint.append(tint)
	_species_id.append(sid)
	_mm_index.append(local_index)
	if want_tree:
		_tree_total += 1
	var global_index := _pos.size() - 1
	var key := _hash_key(x, z)
	if not _hash.has(key):
		_hash[key] = []
	(_hash[key] as Array).append(global_index)


func _roadside(roads: Array, tree_block: PackedByteArray) -> void:
	for road in roads:
		var width := float(road.width)
		var bucket := str(road.bucket)
		var spacing := 16.0 if bucket != "path" else 24.0
		var offset := width * 0.5 + (6.2 if bucket != "path" else 2.6)
		var pts: Array = road.pts
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var length := a.distance_to(b)
			if length < 0.5:
				continue
			var dir := (b - a) / length
			var side := Vector2(-dir.y, dir.x)
			var traveled := 0.0
			while traveled < length:
				var p := a + dir * traveled
				for sign_i in 2:
					var sign := -1.0 if sign_i == 0 else 1.0
					var at: Vector2 = p + side * offset * sign
					at += side * _rng.randf_range(-0.6, 0.6)
					if absf(at.x) > PLAY_HALF - 4.0 or absf(at.y) > PLAY_HALF - 4.0:
						continue
					if ground._blocked(tree_block, at.x, at.y):
						continue
					if float(ground._slope_at(at.x, at.y)) > 0.48:
						continue
					if _tree_total >= TREE_CAP:
						return
					_add_woody(at.x, at.y, maxf(_canopy_at(at.x, at.y), 0.6), true)
				traveled += spacing


func _push_clump(bucket: Dictionary, x: float, z: float, canopy: float, green: float) -> void:
	if _grass_mesh == null:
		return
	var y := float(ground.sample_height(x, z))
	var s := _rng.randf_range(2.4, 4.2)
	if canopy > 0.65:
		s *= 0.85
	if green < 0.22:
		s *= 0.7
	var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s * _rng.randf_range(0.85, 1.25), s * 0.72, s))
	var tint := _tint_at(x, z, 0.35)
	if canopy > 0.55:
		tint = tint.lerp(Color(0.62, 0.58, 0.42), 0.35)
	tint *= _rng.randf_range(0.88, 1.08)
	(bucket.grass as Array).append(Transform3D(basis, Vector3(x, y, z)))
	(bucket.gcol as Array).append(Color(tint.r, tint.g, tint.b, _rng.randf()))


func _push_card(bucket: Dictionary, x: float, z: float, canopy: float, green: float) -> void:
	var y := float(ground.sample_height(x, z)) + 0.015
	var s := _rng.randf_range(5.5, 9.5)
	if canopy > 0.7:
		s *= 0.8
	if green < 0.25:
		s *= 0.62
	var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s * _rng.randf_range(1.05, 1.55), s * _rng.randf_range(0.42, 0.7), s))
	var tint := _tint_at(x, z, 0.55)
	if green < 0.4:
		tint = tint.lerp(Color(0.62, 0.58, 0.34), clampf((0.4 - green) * 1.4, 0.25, 0.75))
	(bucket.card as Array).append(Transform3D(basis, Vector3(x, y, z)))
	(bucket.ccol as Array).append(Color(tint.r, tint.g, tint.b, _rng.randf()))


func _push_litter(bucket: Dictionary, x: float, z: float, canopy: float) -> void:
	var y := float(ground.sample_height(x, z)) + 0.02
	var s := _rng.randf_range(0.7, 1.5)
	var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, 1.0, s * _rng.randf_range(0.7, 1.2)))
	var tint := _tint_at(x, z, 0.7).lerp(Color(0.55, 0.38, 0.2), 0.45)
	(bucket.litter as Array).append(Transform3D(basis, Vector3(x, y, z)))
	(bucket.lcol as Array).append(Color(tint.r, tint.g, tint.b, _rng.randf()))


func _flush_chunks(buckets: Dictionary) -> void:
	var n := 0
	for key in buckets.keys():
		var bucket: Dictionary = buckets[key]
		_emit_multi(bucket.grass, bucket.gcol, _grass_mesh, _grass_mat, 42.0, false)
		_emit_multi(bucket.card, bucket.ccol, _card_mesh_ground(), _card_mat, 208.0, false)
		_emit_multi(bucket.litter, bucket.lcol, _litter_mesh, _litter_mat, 176.0, false)
		n += 1
		if n % 24 == 0:
			await get_tree().process_frame
	for species in _impostors.keys():
		var info: Dictionary = _impostors[species]
		if info.multimesh == null:
			continue
		var xforms: Array = info.transforms
		var colors: Array = info.colors
		var mm: MultiMesh = info.multimesh
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i])
			mm.set_instance_color(i, colors[i])
		var node := MultiMeshInstance3D.new()
		node.multimesh = mm
		if info.mat != null:
			node.material_override = info.mat
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if bool(info.get("plain", false)) else GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
		node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		node.name = "Impostor_" + str(species)
		add_child(node)
		info.node = node


func _emit_multi(xforms: Array, colors: Array, mesh: Mesh, mat: Material, end_dist: float, shadows: bool) -> void:
	if xforms.is_empty() or mesh == null or mat == null:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = mat
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_end = end_dist
	node.visibility_range_end_margin = 36.0
	node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(node)


func _place_prop(species: String, x: float, z: float, scale: float, fallen: bool) -> void:
	if not _scenes.has(species):
		return
	if not _impostors.has(species + "_prop"):
		var inst: Node3D = (_scenes[species] as PackedScene).instantiate()
		add_child(inst)
		var source := _first_mesh_node(inst)
		inst.queue_free()
		if source == null or source.mesh == null:
			return
		var mesh: Mesh = source.mesh
		var active: Material = source.get_active_material(0)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		_impostors[species + "_prop"] = {"mesh": mesh, "mat": active, "multimesh": mm, "transforms": [], "colors": [], "plain": true}
	var info: Dictionary = _impostors[species + "_prop"]
	var y := float(ground.sample_height(x, z))
	var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * scale)
	if fallen:
		basis = Basis(Vector3.RIGHT, deg_to_rad(78.0)) * basis
	var tint := Color(_rng.randf_range(0.85, 1.05), _rng.randf_range(0.85, 1.05), _rng.randf_range(0.85, 1.05))
	info.transforms.append(Transform3D(basis, Vector3(x, y, z)))
	info.colors.append(tint)


func _place_deadwood(tree_block: PackedByteArray) -> void:
	var placed := 0
	var guard := 0
	while placed < 48 and guard < 400:
		guard += 1
		var p := Vector2(_rng.randf_range(-PLAY_HALF + 8.0, PLAY_HALF - 8.0), _rng.randf_range(-PLAY_HALF + 8.0, PLAY_HALF - 8.0))
		if _canopy_at(p.x, p.y) < 0.45:
			continue
		if ground._blocked(tree_block, p.x, p.y):
			continue
		_place_prop("dead", p.x, p.y, _rng.randf_range(0.7, 1.3), _rng.randf() < 0.55)
		placed += 1
	var rocks := 0
	guard = 0
	while rocks < 36 and guard < 300:
		guard += 1
		var p2 := Vector2(_rng.randf_range(-PLAY_HALF + 8.0, PLAY_HALF - 8.0), _rng.randf_range(-PLAY_HALF + 8.0, PLAY_HALF - 8.0))
		if float(ground._slope_at(p2.x, p2.y)) < 0.34:
			continue
		if ground._blocked(tree_block, p2.x, p2.y):
			continue
		_place_prop("boulder", p2.x, p2.y, _rng.randf_range(0.45, 1.8), false)
		rocks += 1


func _build_trunks() -> void:
	var body := StaticBody3D.new()
	body.name = "Trunks"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape_up := CylinderShape3D.new()
	shape_up.radius = 0.28
	shape_up.height = 6.2
	for i in _pos.size():
		var sid: int = _species_id[i]
		if sid < 0 or sid >= _species_names.size():
			continue
		var name: String = str(_species_names[sid])
		if name != "fir" and name != "pine":
			continue
		var col := CollisionShape3D.new()
		col.shape = shape_up
		var p: Vector3 = _pos[i]
		var s: float = _scale[i]
		col.position = Vector3(p.x, p.y + 3.1 * s, p.z)
		col.scale = Vector3(s, s, s)
		body.add_child(col)
	add_child(body)


func _make_pools() -> void:
	for species in HERO_COUNT.keys():
		if not _scenes.has(species):
			continue
		var count: int = int(HERO_COUNT[species])
		if count < 1:
			continue
		var pool: Array = []
		var probe: Node3D = (_scenes[species] as PackedScene).instantiate()
		add_child(probe)
		var aabb := _merged_aabb(probe)
		_local_bottom[species] = Vector3(aabb.get_center().x, aabb.position.y, aabb.get_center().z)
		_prep_overrides(probe)
		probe.visible = false
		pool.append(probe)
		for _i in range(1, count):
			var extra: Node3D = (_scenes[species] as PackedScene).instantiate()
			add_child(extra)
			_prep_overrides(extra)
			extra.visible = false
			pool.append(extra)
		_pools[species] = pool


func _refresh_heroes(anchor: Vector3) -> void:
	_last_anchor = anchor
	var wanted := {}
	for species in _pools.keys():
		var reach: float = float(HERO_RANGE.get(species, 20.0))
		var cap: int = int(HERO_COUNT.get(species, 1))
		var best: Array = []
		var cx := int(floor(anchor.x / 36.0))
		var cz := int(floor(anchor.z / 36.0))
		var span := 3 if reach > 50.0 else (2 if reach > 20.0 else 1)
		for oz in range(-span, span + 1):
			for ox in range(-span, span + 1):
				var key := Vector2i(cx + ox, cz + oz)
				if not _hash.has(key):
					continue
				for idx in _hash[key]:
					var i: int = int(idx)
					if str(_species_names[_species_id[i]]) != str(species):
						continue
					var p: Vector3 = _pos[i]
					var d := Vector2(p.x - anchor.x, p.z - anchor.z).length()
					if d > reach:
						continue
					best.append({"i": i, "d": d})
		best.sort_custom(func(a, b): return float(a.d) < float(b.d))
		if best.size() > cap:
			best.resize(cap)
		wanted[species] = best
		var pool: Array = _pools[species]
		for n in pool.size():
			var node: Node3D = pool[n]
			if n < best.size():
				var rec: Dictionary = best[n]
				var i: int = int(rec.i)
				var bottom: Vector3 = _local_bottom[species]
				var sc: float = _scale[i]
				var basis := Basis(Vector3.UP, _yaw[i]).scaled(Vector3.ONE * sc)
				var at: Vector3 = _pos[i] - basis * bottom
				node.transform = Transform3D(basis, at)
				node.visible = true
				_apply_tint(node, _tint[i])
			else:
				node.visible = false
	var keep := {}
	for species in wanted.keys():
		for rec in wanted[species]:
			var i: int = int(rec.i)
			var token := str(_species_names[_species_id[i]]) + ":" + str(_mm_index[i])
			keep[token] = true
			if _concealed.has(token):
				continue
			var info: Dictionary = _impostors.get(_species_names[_species_id[i]], {})
			var mm: MultiMesh = info.get("multimesh", null)
			if mm == null or bool(info.get("plain", false)):
				continue
			var mi: int = _mm_index[i]
			_concealed[token] = {"mm": mm, "index": mi, "xform": mm.get_instance_transform(mi)}
			var p: Vector3 = _pos[i]
			mm.set_instance_transform(mi, Transform3D(Basis.IDENTITY.scaled(Vector3(0.001, 0.001, 0.001)), p))
	var stale: Array = []
	for token in _concealed.keys():
		if not keep.has(token):
			stale.append(token)
	for token in stale:
		var hidden: Dictionary = _concealed[token]
		var mm2: MultiMesh = hidden.mm
		mm2.set_instance_transform(int(hidden.index), hidden.xform)
		_concealed.erase(token)


func _prepare_grass() -> void:
	var source_key := "bermuda" if _scenes.has("bermuda") else "grass"
	if _grass_mesh != null and source_key == "bermuda":
		_grass_height = maxf(_grass_mesh.get_aabb().size.y, 0.08)
	elif not _scenes.has(source_key):
		_grass_mesh = _cross_card(0.7, 0.55, 3)
		_grass_height = 0.55
	else:
		var inst: Node3D = (_scenes[source_key] as PackedScene).instantiate()
		add_child(inst)
		_grass_mesh = _merge_meshes(inst)
		var box := _merged_aabb(inst)
		_grass_height = maxf(box.size.y, 0.12)
		inst.queue_free()
	var alb: Texture2D = null
	var nor: Texture2D = null
	if _bermuda_src is StandardMaterial3D:
		var src := _bermuda_src as StandardMaterial3D
		alb = src.albedo_texture
		nor = src.normal_texture
	elif _grass_mesh != null and _grass_mesh.get_surface_count() > 0 and _grass_mesh.surface_get_material(0) is StandardMaterial3D:
		var std := _grass_mesh.surface_get_material(0) as StandardMaterial3D
		alb = std.albedo_texture
		nor = std.normal_texture
	if alb == null:
		alb = _tuft_texture()
	_grass_mat = _foliage_mat(alb, nor, _grass_height, 0.09, 0.02, 0.78, 0.03, 0.82)
	if _impostors.has("bermuda") and _card_mesh.has("bermuda"):
		var info: Dictionary = _impostors.bermuda
		_card_mesh["ground"] = info.mesh
		_card_mat = info.mat
	else:
		_card_mat = _foliage_mat(_tuft_texture(), null, 0.4, 0.14, 0.18, 0.82, 0.04)
		_card_mesh["ground"] = _cross_card(0.82, 0.4, 3)


func _foliage_mat(alb: Texture2D, nor: Texture2D, height_ref: float, wind: float, scissor: float, rough: float, lift: float, face_up: float = 0.0) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/foliage.gdshader")
	mat.set_shader_parameter("albedo_tex", alb)
	mat.set_shader_parameter("normal_tex", nor if nor != null else _flat_normal)
	mat.set_shader_parameter("has_normal", 1.0 if nor != null else 0.0)
	mat.set_shader_parameter("wind_strength", wind)
	mat.set_shader_parameter("height_ref", height_ref)
	mat.set_shader_parameter("scissor", scissor)
	mat.set_shader_parameter("roughness_val", rough)
	mat.set_shader_parameter("lift", lift)
	mat.set_shader_parameter("up_normal", face_up)
	mat.set_shader_parameter("clip_black", 1.0 if face_up > 0.5 else 0.0)
	return mat


func _tuft_texture() -> Texture2D:
	var w := 160
	var h := 256
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 44021
	for blade in 46:
		var x := int(18 + rng.randi_range(0, w - 36))
		var lean := rng.randf_range(-18.0, 18.0)
		var curl := rng.randf_range(-10.0, 10.0)
		var height := rng.randi_range(120, 246)
		var width := rng.randi_range(2, 4)
		var root := Color(rng.randf_range(0.12, 0.22), rng.randf_range(0.22, 0.34), rng.randf_range(0.06, 0.12), 1.0)
		var tip := Color(rng.randf_range(0.35, 0.62), rng.randf_range(0.48, 0.72), rng.randf_range(0.16, 0.3), 1.0)
		if rng.randf() < 0.18:
			tip = Color(0.62, 0.52, 0.28, 1.0)
		for y in height:
			var t := float(y) / float(height)
			var px := int(round(float(x) + lean * t + curl * t * t))
			var py := h - 1 - y
			var col := root.lerp(tip, t)
			col.a = 1.0 - smoothstep(0.82, 1.0, t) * 0.35
			for dx in range(-width, width + 1):
				var xx := px + dx
				if xx < 0 or xx >= w or py < 0 or py >= h:
					continue
				var edge := 1.0 - float(abs(dx)) / float(width + 1)
				var pix := col
				pix.a *= edge
				var old := image.get_pixel(xx, py)
				if pix.a > old.a:
					image.set_pixel(xx, py, pix)
	return ImageTexture.create_from_image(image)


func _leaf_texture() -> Texture2D:
	var image := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 22018
	for leaf in 14:
		var cx := rng.randi_range(16, 112)
		var cy := rng.randi_range(16, 112)
		var rx := rng.randi_range(7, 16)
		var ry := rng.randi_range(4, 9)
		var rot := rng.randf() * TAU
		var col := Color(rng.randf_range(0.28, 0.55), rng.randf_range(0.16, 0.32), rng.randf_range(0.06, 0.14), 0.95)
		if rng.randf() < 0.4:
			col = Color(rng.randf_range(0.35, 0.6), rng.randf_range(0.28, 0.45), rng.randf_range(0.08, 0.16), 0.95)
		for y in range(cy - ry - 1, cy + ry + 2):
			for x in range(cx - rx - 1, cx + rx + 2):
				if x < 0 or y < 0 or x >= 128 or y >= 128:
					continue
				var dx := float(x - cx)
				var dy := float(y - cy)
				var lx := dx * cos(rot) + dy * sin(rot)
				var ly := -dx * sin(rot) + dy * cos(rot)
				var e := (lx * lx) / float(rx * rx) + (ly * ly) / float(ry * ry)
				if e < 1.0:
					var pix := col
					pix.a *= 1.0 - smoothstep(0.7, 1.0, e)
					var old := image.get_pixel(x, y)
					if pix.a > old.a:
						image.set_pixel(x, y, pix)
	return ImageTexture.create_from_image(image)


func _conifer_impostor(fir: bool) -> Dictionary:
	var height := 18.4 if fir else 21.0
	var leaf_st := SurfaceTool.new()
	leaf_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var layers := 12 if fir else 10
	var crown_base := height * (0.2 if fir else 0.3)
	var base_r := 4.3 if fir else 3.6
	for i in layers:
		var t := float(i) / float(maxi(layers - 1, 1))
		var y := lerpf(crown_base, height * 0.98, t)
		var radius := lerpf(base_r, 0.22, pow(t, 0.7 if fir else 1.02))
		var quad_h := lerpf(3.4, 1.45, t)
		for p in 5:
			var ang := float(p) * PI / 5.0 + float(i) * 0.47
			_add_needle_plane(leaf_st, y, ang, radius, quad_h)
	leaf_st.generate_normals()
	var leaves := leaf_st.commit()
	var leaf_mat := _foliage_mat(_needle_texture(fir), null, height, 0.22, 0.18, 0.8, 0.018, 0.12)
	leaf_mat.set_shader_parameter("normal_up_bias", 0.4)
	leaves.surface_set_material(0, leaf_mat)
	var trunk_st := SurfaceTool.new()
	trunk_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_cylinder(trunk_st, height * (0.48 if fir else 0.58), 0.36, 0.1)
	trunk_st.generate_normals()
	var trunk := trunk_st.commit()
	var bark := StandardMaterial3D.new()
	bark.albedo_texture = _image_tex("res://assets/nature/pine_tree_01_0_pine_tree_01_bark_diff_1k.jpg")
	bark.albedo_color = Color(0.62, 0.52, 0.4)
	bark.roughness = 0.9
	bark.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	bark.uv1_scale = Vector3(1.0, 0.28, 1.0)
	trunk.surface_set_material(0, bark)
	return {"mesh": _join_meshes(leaves, trunk), "mat": null, "multimesh": null, "height": height}


func _add_needle_plane(st: SurfaceTool, y: float, angle: float, radius: float, quad_h: float) -> void:
	var right := Vector3(cos(angle), 0.0, sin(angle))
	var a := Vector3(-right.x * radius, y - quad_h * 0.5, -right.z * radius)
	var b := Vector3(right.x * radius, y - quad_h * 0.5, right.z * radius)
	var c := Vector3(right.x * radius, y + quad_h * 0.5, right.z * radius)
	var d := Vector3(-right.x * radius, y + quad_h * 0.5, -right.z * radius)
	_add_quad(st, a, b, c, d, Vector2(0, 1), Vector2(2, 1), Vector2(2, 0), Vector2(0, 0))


func _add_cylinder(st: SurfaceTool, height: float, radius_bottom: float, radius_top: float) -> void:
	var sides := 7
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var b0 := Vector3(cos(a0) * radius_bottom, 0.0, sin(a0) * radius_bottom)
		var b1 := Vector3(cos(a1) * radius_bottom, 0.0, sin(a1) * radius_bottom)
		var t0 := Vector3(cos(a0) * radius_top, height, sin(a0) * radius_top)
		var t1 := Vector3(cos(a1) * radius_top, height, sin(a1) * radius_top)
		var u0 := float(i) / float(sides)
		var u1 := float(i + 1) / float(sides)
		_add_quad(st, b0, b1, t1, t0, Vector2(u0, 1), Vector2(u1, 1), Vector2(u1, 0), Vector2(u0, 0))


func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, uva: Vector2, uvb: Vector2, uvc: Vector2, uvd: Vector2) -> void:
	var n := (b - a).cross(c - a)
	if n.length() < 0.0001:
		return
	n = n.normalized()
	for corner in [[a, uva], [b, uvb], [c, uvc]]:
		st.set_normal(n)
		st.set_uv(corner[1])
		st.add_vertex(corner[0])
	for corner in [[a, uva], [c, uvc], [d, uvd]]:
		st.set_normal(n)
		st.set_uv(corner[1])
		st.add_vertex(corner[0])


func _join_meshes(first: ArrayMesh, second: ArrayMesh) -> ArrayMesh:
	var out := ArrayMesh.new()
	for source in [first, second]:
		for s in source.get_surface_count():
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, source.surface_get_arrays(s))
			out.surface_set_material(out.get_surface_count() - 1, source.surface_get_material(s))
	return out


func _needle_texture(fir: bool) -> Texture2D:
	var size := 384
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4402 if fir else 8811
	var base := Color(0.15, 0.34, 0.13) if fir else Color(0.28, 0.36, 0.12)
	for sprig in 42:
		var ox := rng.randf_range(20.0, size - 20.0)
		var oy := rng.randf_range(20.0, size - 20.0)
		var ang := rng.randf() * TAU
		var length := rng.randf_range(54.0, 140.0)
		var tone := base.lerp(Color(0.4, 0.46, 0.18), rng.randf())
		var count := rng.randi_range(16, 28)
		for n in count:
			var t := float(n) / float(count)
			var px := ox + cos(ang) * length * t
			var py := oy + sin(ang) * length * t
			var nlen := lerpf(34.0, 12.0, t) * rng.randf_range(0.8, 1.2)
			var spread := 0.55 + t * 0.55
			_paint_line(image, px, py, ang + spread, nlen, tone)
			_paint_line(image, px, py, ang - spread, nlen, tone.darkened(0.12))
	return ImageTexture.create_from_image(image)


func _paint_line(image: Image, x: float, y: float, angle: float, length: float, color: Color) -> void:
	var steps := maxi(int(length), 1)
	var size := image.get_width()
	for i in steps:
		var t := float(i) / float(steps)
		var px := int(round(x + cos(angle) * length * t))
		var py := int(round(y + sin(angle) * length * t))
		var col := color
		col.a = 1.0 - smoothstep(0.72, 1.0, t) * 0.35
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var xx := px + dx
				var yy := py + dy
				if xx < 0 or yy < 0 or xx >= size or yy >= size:
					continue
				var edge := 1.0 if dx == 0 and dy == 0 else 0.55
				var pix := col
				pix.a *= edge
				var old := image.get_pixel(xx, yy)
				if pix.a > old.a:
					image.set_pixel(xx, yy, pix)


func _clump_noise(x: float, z: float) -> float:
	var a := _hash2(Vector2(floor(x * 0.065), floor(z * 0.065)))
	var b := _hash2(Vector2(floor(x * 0.18 + 5.0), floor(z * 0.18 - 3.0)))
	return a * 0.64 + b * 0.36


func _hash2(p: Vector2) -> float:
	var v := sin(p.x * 127.1 + p.y * 311.7) * 43758.5453
	return v - floor(v)


func _cross_card(width: float, height: float, planes: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in planes:
		var ang := PI * float(i) / float(planes)
		var right := Vector3(cos(ang), 0.0, sin(ang))
		var hw := width * 0.5
		var c0 := -right * hw
		var c1 := right * hw
		var c2 := right * hw + Vector3(0, height, 0)
		var c3 := -right * hw + Vector3(0, height, 0)
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		var corners := [c0, c1, c2, c3]
		for tri in [[0, 1, 2], [0, 2, 3]]:
			for idx in tri:
				st.set_uv(uvs[idx])
				st.add_vertex(corners[idx])
	st.generate_normals()
	return st.commit()


func _ground_quad(size: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := size * 0.5
	var corners := [Vector3(-h, 0.02, -h), Vector3(h, 0.02, -h), Vector3(h, 0.02, h), Vector3(-h, 0.02, h)]
	var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for tri in [[0, 2, 1], [0, 3, 2]]:
		for idx in tri:
			st.set_uv(uvs[idx])
			st.add_vertex(corners[idx])
	st.generate_normals()
	return st.commit()


func _card_mesh_ground() -> Mesh:
	return _card_mesh.get("ground", null)


func _on_slope(x: float, z: float, yaw: float, scale: Vector3) -> Basis:
	var e := 1.4
	var h := float(ground.sample_height(x, z))
	var dx := float(ground.sample_height(x + e, z)) - h
	var dz := float(ground.sample_height(x, z + e)) - h
	var n := Vector3(-dx, e, -dz).normalized()
	var yawed := Basis(Vector3.UP, yaw)
	var x_axis := yawed.x
	x_axis = (x_axis - n * x_axis.dot(n)).normalized()
	var z_axis := n.cross(x_axis).normalized()
	return Basis(x_axis * scale.x, n * scale.y, z_axis * scale.z)


func _clearance_mask(features: Dictionary, placements: Array, road_extra: float, building_pad: float, water_pad: float) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(int(ground.GRID_N) * int(ground.GRID_N))
	mask.fill(0)
	for road in features.roads:
		var radius := float(road.width) * 0.5 + road_extra
		var pts: Array = road.pts
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var length := a.distance_to(b)
			var steps := maxi(int(length / 2.0), 1)
			for s in steps + 1:
				var p := a.lerp(b, float(s) / float(steps))
				ground._mark(mask, p.x, p.y, radius)
	for item in placements:
		ground._mark_poly(mask, item.poly, building_pad)
	for body in features.water:
		ground._mark_poly(mask, body.poly, water_pad)
	for stream in features.streams:
		var spts: PackedVector2Array = stream.pts
		for i in range(spts.size() - 1):
			var a2 := spts[i]
			var b2 := spts[i + 1]
			var length2 := a2.distance_to(b2)
			var steps2 := maxi(int(length2 / 2.0), 1)
			for s2 in steps2 + 1:
				var p2 := a2.lerp(b2, float(s2) / float(steps2))
				ground._mark(mask, p2.x, p2.y, 2.2)
	return mask


func _tint_at(x: float, z: float, strength: float) -> Color:
	var ll: Vector2 = ground.latlon_at(x, z)
	var geo: Node = ground.geo
	var col: Color = geo.sample_rgb(ground.sat_image, ground.sat_bounds, ll.x, ll.y)
	var lum := maxf(col.get_luminance(), 0.04)
	var hue := Color(col.r / lum, col.g / lum, col.b / lum)
	var peak := maxf(hue.r, maxf(hue.g, hue.b))
	if peak > 0.001:
		hue /= peak
	var tinted := Color(1, 1, 1).lerp(hue, strength)
	var cover := _green_at(x, z)
	if cover < 0.28:
		tinted = tinted.lerp(Color(0.78, 0.68, 0.42), (0.28 - cover) / 0.28 * 0.55)
	return tinted


func _canopy_at(x: float, z: float) -> float:
	return float(_sample_cover(_canopy, x, z)) / 255.0


func _green_at(x: float, z: float) -> float:
	return float(_sample_cover(_greenery, x, z)) / 255.0


func _sample_cover(data: PackedByteArray, x: float, z: float) -> int:
	if data.is_empty():
		return 0
	var fx := (x + PLAY_HALF) / _cover_step
	var fz := (z + PLAY_HALF) / _cover_step
	var ix := clampi(int(round(fx)), 0, COVER_N - 1)
	var iz := clampi(int(round(fz)), 0, COVER_N - 1)
	return data[iz * COVER_N + ix]


func _cover_x(x: float) -> int:
	return int(round((x + PLAY_HALF) / _cover_step))


func _cover_z(z: float) -> int:
	return int(round((z + PLAY_HALF) / _cover_step))


func _chunk_of(x: float, z: float) -> Vector2i:
	return Vector2i(int(floor((x + PLAY_HALF) / CHUNK)), int(floor((z + PLAY_HALF) / CHUNK)))


func _hash_key(x: float, z: float) -> Vector2i:
	return Vector2i(int(floor(x / 36.0)), int(floor(z / 36.0)))


func _species_index(species: String) -> int:
	var found := _species_names.find(species)
	if found >= 0:
		return found
	_species_names.append(species)
	return _species_names.size() - 1


func _count_species(names: Array) -> int:
	var n := 0
	for i in _species_id.size():
		var sname: String = str(_species_names[_species_id[i]])
		if names.has(sname):
			n += 1
	return n


func _merged_aabb(root: Node3D) -> AABB:
	var found := false
	var box := AABB()
	var meshes: Array = []
	if root is MeshInstance3D:
		meshes.append(root)
	meshes.append_array(root.find_children("*", "MeshInstance3D", true, false))
	for node in meshes:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null or not mesh_node.visible:
			continue
		var xf := root.global_transform.affine_inverse() * mesh_node.global_transform
		var ab: AABB = xf * mesh_node.get_aabb()
		if not found:
			box = ab
			found = true
		else:
			box = box.merge(ab)
	return box


func _merge_meshes(root: Node3D) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var meshes: Array = []
	if root is MeshInstance3D:
		meshes.append(root)
	meshes.append_array(root.find_children("*", "MeshInstance3D", true, false))
	var wrote := false
	for node in meshes:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null or not mesh_node.visible:
			continue
		var xf := root.global_transform.affine_inverse() * mesh_node.global_transform
		for s in mesh_node.mesh.get_surface_count():
			st.append_from(mesh_node.mesh, s, xf)
			wrote = true
	if not wrote:
		return null
	return st.commit()


func _first_mesh_node(root: Node) -> MeshInstance3D:
	if root is MeshInstance3D and (root as MeshInstance3D).mesh != null:
		return root
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh != null:
			return mesh_node
	return null


func _first_mesh(root: Node) -> Mesh:
	if root is MeshInstance3D and (root as MeshInstance3D).mesh != null:
		return (root as MeshInstance3D).mesh
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh != null:
			return mesh_node.mesh
	return null


func _prep_overrides(root: Node) -> void:
	var meshes: Array = []
	if root is MeshInstance3D:
		meshes.append(root)
	meshes.append_array(root.find_children("*", "MeshInstance3D", true, false))
	var leaf_shader: Shader = preload("res://shaders/leaf.gdshader")
	for node in meshes:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		mesh_node.lod_bias = 3.0
		mesh_node.gi_mode = GeometryInstance3D.GI_MODE_STATIC
		for s in mesh_node.mesh.get_surface_count():
			var base := mesh_node.mesh.surface_get_material(s)
			if not base is StandardMaterial3D:
				continue
			var std := base as StandardMaterial3D
			var label := (str(std.resource_name) + " " + str(std.albedo_texture.resource_path if std.albedo_texture else "")).to_lower()
			var foliage := std.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or label.contains("twig") or label.contains("leaf") or label.contains("needle")
			if foliage:
				var mat := ShaderMaterial.new()
				mat.shader = leaf_shader
				mat.set_shader_parameter("albedo_tex", std.albedo_texture)
				mat.set_shader_parameter("normal_tex", std.normal_texture if std.normal_enabled else _flat_normal)
				mat.set_shader_parameter("has_normal", 1.0 if std.normal_enabled and std.normal_texture != null else 0.0)
				mat.set_shader_parameter("tint", Vector3(1, 1, 1))
				mat.set_shader_parameter("height_ref", 8.0)
				mesh_node.set_surface_override_material(s, mat)
				mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			else:
				var dup := std.duplicate() as StandardMaterial3D
				dup.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				if dup.roughness_texture == null:
					dup.roughness = maxf(dup.roughness, 0.72)
				mesh_node.set_surface_override_material(s, dup)


func _apply_tint(root: Node, tint: Color) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		for s in mesh_node.mesh.get_surface_count():
			var mat := mesh_node.get_surface_override_material(s)
			if mat is StandardMaterial3D:
				(mat as StandardMaterial3D).albedo_color = tint
			elif mat is ShaderMaterial:
				(mat as ShaderMaterial).set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))


func _anchor() -> Vector3:
	var parent := get_parent()
	if parent:
		for child in parent.get_children():
			if child is CharacterBody3D:
				return (child as Node3D).global_position
	var cam := get_viewport().get_camera_3d()
	if cam:
		return cam.global_position
	return Vector3.ZERO


func _poly_bounds(poly: PackedVector2Array) -> Rect2:
	var min_x := 100000.0
	var min_y := 100000.0
	var max_x := -100000.0
	var max_y := -100000.0
	for p in poly:
		min_x = minf(min_x, p.x)
		min_y = minf(min_y, p.y)
		max_x = maxf(max_x, p.x)
		max_y = maxf(max_y, p.y)
	return Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))


func _solid_normal() -> Texture2D:
	var image := Image.create(2, 2, false, Image.FORMAT_RGB8)
	image.fill(Color(0.5, 0.5, 1.0))
	return ImageTexture.create_from_image(image)


func smoothstep(edge0: float, edge1: float, x: float) -> float:
	var t := clampf((x - edge0) / maxf(edge1 - edge0, 0.0001), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
