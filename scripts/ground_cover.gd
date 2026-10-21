extends Node3D

const CELL := 48.0
const PLAY := 400.0

var builder
var blocked: PackedByteArray
var cover_map := PackedFloat32Array()
var cover_n := 96
var cover_step := 0.0
var noise := FastNoiseLite.new()
var rng := RandomNumberGenerator.new()
var grass_mesh: ArrayMesh
var grass_mat: ShaderMaterial
var chunks := {}
var built_chunks := {}
var forest_biome := false


func populate(host, features: Dictionary, placements: Array) -> Dictionary:
	builder = host
	rng.seed = 90210
	noise.seed = 90210
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 1.0
	_build_blocked(features)
	for item in placements:
		builder._mark_poly(blocked, item.poly, 3.5)
	_build_cover()
	forest_biome = builder._green_ratio() > 0.18
	var bark := _bark_material()
	var scrub_tex := _tex_res("res://assets/foliage/scrub_cards.png")
	var twig_tex := _tex_res("res://assets/foliage/twig_cards.png")
	var grass_src := _tex_res("res://assets/foliage/grass_blade.png")
	var grass_tex := _recolor_blades(grass_src, not forest_biome)
	var needle := Color(0.17, 0.26, 0.13) if forest_biome else Color(0.28, 0.32, 0.19)
	var foliage := Color(0.2, 0.28, 0.12) if forest_biome else Color(0.32, 0.34, 0.2)
	var pine_leaf := _leaf_material(_bough_tex(4402, needle), 0.05, 11.0, 0.22)
	pine_leaf.set_shader_parameter("scissor", 0.3)
	var broad_leaf := _leaf_material(_leaf_cluster_tex(918, foliage), 0.08, 5.0, 0.3)
	broad_leaf.set_shader_parameter("scissor", 0.4)
	var twig_mat := _leaf_material(twig_tex, 0.12, 6.0, 0.2)
	var pine_mesh := _conifer_mesh(bark, pine_leaf, 77)
	var leaf_mesh := _orchard_mesh(bark, broad_leaf, 31)
	var scrub_mesh := _shrub_mesh(_leaf_material(scrub_tex, 0.1, 1.8, 0.22), twig_mat)
	grass_mat = _leaf_material(grass_tex, 0.22, 0.55, 0.35)
	grass_mat.set_shader_parameter("scissor", 0.22)
	grass_mat.set_shader_parameter("lift", 0.0)
	grass_mesh = _grass_mesh()
	var buckets := {
		"pine": [],
		"broadleaf": [],
		"shrub": [],
	}
	_scatter_plants(features, buckets)
	var tree_items: Array = buckets["broadleaf"]
	var tree_max := 110 if forest_biome else 70
	var pine_max := 100 if forest_biome else 36
	var bush_max := 640 if forest_biome else 480
	if tree_items.size() > tree_max:
		tree_items = tree_items.slice(0, tree_max)
	var pine_items: Array = buckets["pine"]
	if pine_items.size() > pine_max:
		pine_items = pine_items.slice(0, pine_max)
	var bush_items: Array = buckets["shrub"]
	if bush_items.size() > bush_max:
		bush_items = bush_items.slice(0, bush_max)
	var orchard := _scatter_orchards(placements)
	_emit_fitted("Trees", leaf_mesh, tree_items, 6.2, true)
	_emit_fitted("Orchard", leaf_mesh, orchard, 4.6, true)
	_emit_fitted("Pines", pine_mesh, pine_items, 12.0, true)
	_emit_fitted("Shrubs", scrub_mesh, bush_items, 1.65, false)
	if forest_biome:
		_scatter_ferns()
		_scatter_fences(features, placements)
	_scatter_props()
	var grass := await _scatter_grass()
	print("Ground cover trees ", tree_items.size(), " orchard ", orchard.size(), " pines ", pine_items.size(), " shrubs ", bush_items.size(), " grass ", grass)
	return {
		"trees": tree_items.size() + pine_items.size() + orchard.size(),
		"shrubs": bush_items.size(),
		"grass": grass,
	}


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or grass_mesh == null:
		return
	var p := cam.global_position
	var cx := int(floor(p.x / CELL))
	var cz := int(floor(p.z / CELL))
	for dz in range(-5, 6):
		for dx in range(-5, 6):
			var key := Vector2i(cx + dx, cz + dz)
			if built_chunks.has(key):
				continue
			if absf(float(key.x) * CELL) > PLAY + CELL or absf(float(key.y) * CELL) > PLAY + CELL:
				built_chunks[key] = true
				continue
			_build_grass_chunk(key)
			return


func _build_blocked(features: Dictionary) -> void:
	blocked = PackedByteArray()
	blocked.resize(builder.GRID_N * builder.GRID_N)
	blocked.fill(0)
	for road in features.get("roads", []):
		var radius := float(road.width) * 0.5 + 1.15
		var pts: Array = road.pts
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var length := a.distance_to(b)
			var steps := maxi(int(length / 2.0), 1)
			for s in steps + 1:
				var p: Vector2 = a.lerp(b, float(s) / float(steps))
				builder._mark(blocked, p.x, p.y, radius)
	for body in features.get("water", []):
		builder._mark_poly(blocked, body.poly, 1.2)


func _build_cover() -> void:
	cover_step = (PLAY * 2.0) / float(cover_n - 1)
	cover_map.resize(cover_n * cover_n)
	var image: Image = builder.sat_image
	var bounds: Dictionary = builder.sat_bounds
	for z in cover_n:
		for x in cover_n:
			var wx := -PLAY + float(x) * cover_step
			var wz := -PLAY + float(z) * cover_step
			var ll: Vector2 = builder.latlon_at(wx, wz)
			var c: Color = builder.geo.sample_rgb(image, bounds, ll.x, ll.y)
			var excess := c.g - maxf(c.r, c.b)
			cover_map[z * cover_n + x] = clampf(excess * 5.0 + (c.g - 0.16) * 0.35, 0.0, 1.0)


func _cover_at(x: float, z: float) -> float:
	var fx := (x + PLAY) / cover_step
	var fz := (z + PLAY) / cover_step
	fx = clampf(fx, 0.0, float(cover_n - 1) - 0.001)
	fz = clampf(fz, 0.0, float(cover_n - 1) - 0.001)
	var x0 := int(floor(fx))
	var z0 := int(floor(fz))
	var x1 := mini(x0 + 1, cover_n - 1)
	var z1 := mini(z0 + 1, cover_n - 1)
	var tx := fx - float(x0)
	var tz := fz - float(z0)
	var a := lerpf(cover_map[z0 * cover_n + x0], cover_map[z0 * cover_n + x1], tx)
	var b := lerpf(cover_map[z1 * cover_n + x0], cover_map[z1 * cover_n + x1], tx)
	return lerpf(a, b, tz)


func _scatter_plants(features: Dictionary, buckets: Dictionary) -> void:
	var forests: Array = features.get("forests", [])
	for road in features.get("roads", []):
		if str(road.get("bucket", "")) == "path":
			continue
		var pts: Array = road.pts
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var seg := a.distance_to(b)
			if seg < 0.5:
				continue
			var dir := (b - a) / seg
			var side := Vector2(-dir.y, dir.x)
			var d := rng.randf_range(4.0, 10.0)
			while d < seg:
				var flip := 1.0 if rng.randf() > 0.5 else -1.0
				var off := float(road.width) * 0.5 + rng.randf_range(4.2, 12.0)
				var p: Vector2 = a + dir * d + side * flip * off
				_try_add(buckets, p, forests, true, rng.randf() < 0.62)
				d += rng.randf_range(14.0, 26.0)
	_scatter_groves(buckets, forests)
	var spacing := 9.0
	var x := -PLAY + 4.0
	while x < PLAY - 4.0:
		var z := -PLAY + 4.0
		while z < PLAY - 4.0:
			var p := Vector2(x, z) + Vector2(rng.randf_range(-4.0, 4.0), rng.randf_range(-4.0, 4.0))
			var clump := noise.get_noise_2d(p.x * 0.02, p.y * 0.02)
			var cover := _cover_at(p.x, p.y)
			var forest: bool = builder._in_polys(p, forests)
			var want := false
			if forest and clump > -0.2:
				want = rng.randf() < 0.7
			elif cover > 0.38 and clump > -0.05:
				want = rng.randf() < 0.4
			elif clump > 0.22:
				want = rng.randf() < 0.48
			elif clump > 0.05:
				want = rng.randf() < 0.1
			if want:
				_try_add(buckets, p, forests, false, false)
			z += spacing
		x += spacing


func _scatter_groves(buckets: Dictionary, forests: Array) -> void:
	var spacing := 58.0
	var x := -PLAY + 20.0
	while x < PLAY - 20.0:
		var z := -PLAY + 20.0
		while z < PLAY - 20.0:
			var center := Vector2(x, z) + Vector2(rng.randf_range(-16.0, 16.0), rng.randf_range(-16.0, 16.0))
			var n := noise.get_noise_2d(center.x * 0.012, center.y * 0.012)
			var cover := _cover_at(center.x, center.y)
			if cover < 0.14 and n < 0.5:
				z += spacing
				continue
			if n > 0.02 or cover > 0.3:
				var count := rng.randi_range(3, 6)
				for _i in count:
					var ang := rng.randf() * TAU
					var rad := rng.randf_range(1.5, 12.0)
					var p := center + Vector2(cos(ang), sin(ang)) * rad
					_try_add(buckets, p, forests, false, true)
			z += spacing
		x += spacing


func _try_add(buckets: Dictionary, p: Vector2, forests: Array, roadside: bool, force_tree: bool) -> void:
	if absf(p.x) > PLAY - 2.0 or absf(p.y) > PLAY - 2.0:
		return
	if builder._blocked(blocked, p.x, p.y):
		return
	var slope: float = builder._slope_at(p.x, p.y)
	if slope > 0.62:
		return
	var cover := _cover_at(p.x, p.y)
	var forest: bool = builder._in_polys(p, forests)
	var kind := "shrub"
	if forest_biome:
		if forest or (force_tree and cover > 0.2):
			kind = "pine" if forest or slope > 0.12 or rng.randf() < 0.3 else "broadleaf"
		elif roadside and rng.randf() < 0.3:
			kind = "broadleaf"
		elif cover > 0.3 and rng.randf() < 0.25:
			kind = "broadleaf"
	elif force_tree and (forest or cover > 0.55) and rng.randf() < 0.35:
		kind = "broadleaf"
	elif cover > 0.62 and rng.randf() < 0.2:
		kind = "pine"
	elif roadside and rng.randf() < 0.08:
		kind = "broadleaf"
	if kind == "shrub" and buckets["shrub"].size() >= 1400:
		return
	if kind != "shrub" and buckets["pine"].size() + buckets["broadleaf"].size() >= 280:
		return
	var scale := rng.randf_range(1.35, 2.6) if kind == "shrub" else rng.randf_range(1.05, 1.75)
	var tint := _tint_for(kind, cover)
	buckets[kind].append({
		"p": p,
		"yaw": rng.randf() * TAU,
		"scale": scale,
		"tint": tint,
		"phase": rng.randf(),
	})


func _tint_for(kind: String, cover: float) -> Color:
	var wet := clampf(cover, 0.0, 1.0)
	if kind == "shrub":
		if forest_biome:
			var dry := Color(rng.randf_range(0.55, 0.68), rng.randf_range(0.62, 0.74), rng.randf_range(0.38, 0.48))
			return dry.lerp(Color(0.42, 0.7, 0.32), wet)
		var dry := Color(rng.randf_range(0.46, 0.56), rng.randf_range(0.44, 0.52), rng.randf_range(0.3, 0.38))
		return dry.lerp(Color(0.55, 0.68, 0.38), wet)
	if kind == "broadleaf":
		if forest_biome:
			return Color(rng.randf_range(0.82, 1.0), rng.randf_range(0.86, 1.0), rng.randf_range(0.74, 0.92))
		return Color(rng.randf_range(0.88, 1.0), rng.randf_range(0.82, 0.94), rng.randf_range(0.68, 0.82))
	if forest_biome:
		return Color(rng.randf_range(0.8, 0.96), rng.randf_range(0.86, 1.0), rng.randf_range(0.78, 0.92))
	return Color(rng.randf_range(0.86, 1.0), rng.randf_range(0.84, 0.96), rng.randf_range(0.72, 0.84))


func _emit_fitted(node_name: String, mesh: Mesh, items: Array, target_height: float, collide: bool) -> void:
	if items.is_empty():
		return
	var aabb := mesh.get_aabb()
	var base := target_height / maxf(aabb.size.y, 0.001)
	var body: StaticBody3D = null
	if collide:
		body = StaticBody3D.new()
		body.name = node_name + "Collision"
		body.collision_layer = 1
		body.collision_mask = 0
	var xforms: Array[Transform3D] = []
	var colors := PackedColorArray()
	for i in items.size():
		var item: Dictionary = items[i]
		var p: Vector2 = item.p
		var s: float = base * float(item.scale)
		var reach := 0.3 * s if collide else maxf(aabb.size.x, aabb.size.z) * 0.3 * s
		var ground := _ground(p, reach)
		var y: float = ground - aabb.position.y * s - 0.04 * s
		var basis := Basis(Vector3.UP, float(item.yaw)).scaled(Vector3(s, s, s))
		xforms.append(Transform3D(basis, Vector3(p.x, y, p.y)))
		var tint: Color = item.tint
		colors.append(Color(tint.r, tint.g, tint.b, float(item.phase)))
		if body != null:
			var shape := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = 0.18 * s
			cyl.height = target_height * 0.45 * float(item.scale)
			shape.shape = cyl
			shape.position = Vector3(p.x, ground + cyl.height * 0.5, p.y)
			body.add_child(shape)
	_emit_cells(node_name, mesh, xforms, colors, true)
	if body != null:
		add_child(body)


func _ground(p: Vector2, reach: float) -> float:
	var h: float = builder.sample_height(p.x, p.y)
	if reach < 0.05:
		return h
	for offset in [Vector2(reach, 0), Vector2(-reach, 0), Vector2(0, reach), Vector2(0, -reach)]:
		h = minf(h, builder.sample_height(p.x + offset.x, p.y + offset.y))
	return h


func _emit_cells(node_name: String, mesh: Mesh, xforms: Array[Transform3D], colors: PackedColorArray, shadow: bool) -> void:
	if xforms.is_empty():
		return
	var size := 96.0
	var cells := {}
	for i in xforms.size():
		var o := xforms[i].origin
		var key := Vector2i(int(floor(o.x / size)), int(floor(o.z / size)))
		if not cells.has(key):
			cells[key] = []
		cells[key].append(i)
	for key in cells.keys():
		var list: Array = cells[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = not colors.is_empty()
		mm.mesh = mesh
		mm.instance_count = list.size()
		for j in list.size():
			var i: int = list[j]
			mm.set_instance_transform(j, xforms[i])
			if mm.use_colors:
				mm.set_instance_color(j, colors[i])
		var node := MultiMeshInstance3D.new()
		node.name = "%s_%d_%d" % [node_name, key.x, key.y]
		node.multimesh = mm
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.gi_mode = GeometryInstance3D.GI_MODE_STATIC
		add_child(node)


func _scatter_props() -> void:
	_scatter_yucca()
	var rock_mesh := _rock_mesh(31)
	var rock_mesh_b := _rock_mesh(77)
	var rock_mat: Material = builder.lib.get_shared("rock").duplicate()
	if rock_mat is StandardMaterial3D:
		rock_mat.albedo_color = Color(0.9, 0.86, 0.8)
		rock_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	rock_mesh.surface_set_material(0, rock_mat)
	rock_mesh_b.surface_set_material(0, rock_mat)
	var rocks: Array = []
	var spacing := 16.0
	var x := -PLAY
	while x < PLAY:
		var z := -PLAY
		while z < PLAY:
			var p := Vector2(x, z) + Vector2(rng.randf_range(-7.0, 7.0), rng.randf_range(-7.0, 7.0))
			var slope: float = builder._slope_at(p.x, p.y)
			var n := noise.get_noise_2d(p.x * 0.03, p.y * 0.03)
			var place := slope > 0.4
			if place and not builder._blocked(blocked, p.x, p.y) and absf(p.x) < PLAY and absf(p.y) < PLAY:
				rocks.append(p)
			if rocks.size() >= 180:
				break
			z += spacing
		if rocks.size() >= 180:
			break
		x += spacing
	_emit_props("RocksA", rock_mesh, rocks.slice(0, rocks.size() / 2), 0.9, 2.4)
	_emit_props("RocksB", rock_mesh_b, rocks.slice(rocks.size() / 2, rocks.size()), 1.3, 3.4)
	var dead := _extract_mesh("res://assets/nature/dead_tree_trunk_0.glb")
	if dead == null:
		return
	var logs: Array = []
	var step := 36.0
	x = -PLAY
	while x < PLAY and logs.size() < 28:
		var z := -PLAY
		while z < PLAY and logs.size() < 28:
			var p := Vector2(x, z) + Vector2(rng.randf_range(-12.0, 12.0), rng.randf_range(-12.0, 12.0))
			if noise.get_noise_2d(p.x * 0.02, p.y * 0.02) > 0.35 and not builder._blocked(blocked, p.x, p.y):
				if builder._slope_at(p.x, p.y) < 0.4:
					logs.append(p)
			z += step
		x += step
	_emit_mesh_fitted("DeadWood", dead, logs, 3.2, true)


func _scatter_yucca() -> void:
	var mesh := _yucca_mesh()
	var points: Array = []
	var spacing := 22.0
	var x := -PLAY
	while x < PLAY and points.size() < 90:
		var z := -PLAY
		while z < PLAY and points.size() < 90:
			var p := Vector2(x, z) + Vector2(rng.randf_range(-8.0, 8.0), rng.randf_range(-8.0, 8.0))
			var n := noise.get_noise_2d(p.x * 0.02, p.y * 0.02)
			if forest_biome and _cover_at(p.x, p.y) > 0.22:
				z += spacing
				continue
			if n > 0.15 and builder._slope_at(p.x, p.y) < 0.4 and not builder._blocked(blocked, p.x, p.y):
				if absf(p.x) < PLAY and absf(p.y) < PLAY:
					points.append(p)
			z += spacing
		x += spacing
	_emit_props("Yucca", mesh, points, 0.85, 1.55)


func _yucca_mesh() -> ArrayMesh:
	var trunk := SurfaceTool.new()
	trunk.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cylinder(trunk, 0.09, 0.05, 0.55, 6, 0.0)
	trunk.set_material(_bark_material())
	trunk.generate_normals()
	var mesh := trunk.commit()
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 8:
		var ang := TAU * float(i) / 8.0
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var up := Vector3(dir.x * 0.62, 1.0, dir.z * 0.62).normalized() * 1.45
		var right := Vector3(-dir.z, 0.0, dir.x) * 0.07
		_card(leaves, Vector3(0, 0.4, 0) + up * 0.45, right, up * 0.5)
	leaves.set_material(_leaf_material(_sword_tex(), 0.04, 1.6, 0.15))
	leaves.commit(mesh)
	return mesh


func _sword_tex() -> Texture2D:
	var image := Image.create(32, 128, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in 128:
		var t := float(y) / 127.0
		var half := maxi(int(round(lerpf(5.0, 1.0, t))), 1)
		for x in range(16 - half, 16 + half):
			var edge := float(abs(x - 16)) / float(half)
			var c := Color(0.42, 0.46, 0.28).lerp(Color(0.24, 0.28, 0.16), t)
			c.a = 1.0 if edge < 0.75 else 0.0
			image.set_pixel(x, 127 - y, c)
	return ImageTexture.create_from_image(image)


func _emit_props(node_name: String, mesh: ArrayMesh, points: Array, min_s: float, max_s: float) -> void:
	if points.is_empty():
		return
	var aabb: AABB = mesh.get_aabb()
	var xforms: Array[Transform3D] = []
	for i in points.size():
		var p: Vector2 = points[i]
		var s := rng.randf_range(min_s, max_s)
		var sy := s * rng.randf_range(0.65, 1.0)
		var reach := maxf(aabb.size.x, aabb.size.z) * 0.35 * s
		var y: float = _ground(p, reach) - aabb.position.y * sy - 0.03 * sy
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, sy, s))
		xforms.append(Transform3D(basis, Vector3(p.x, y, p.y)))
	_emit_cells(node_name, mesh, xforms, PackedColorArray(), true)


func _emit_mesh_fitted(node_name: String, mesh: Mesh, points: Array, target: float, fallen: bool) -> void:
	if points.is_empty():
		return
	var aabb: AABB = mesh.get_aabb()
	var longest := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	var base := target / maxf(longest, 0.001)
	var xforms: Array[Transform3D] = []
	for i in points.size():
		var p: Vector2 = points[i]
		var s := base * rng.randf_range(0.75, 1.25)
		var basis := Basis(Vector3.UP, rng.randf() * TAU)
		if fallen and rng.randf() < 0.7:
			basis = basis * Basis(Vector3(1, 0, 0), rng.randf_range(1.15, 1.5))
		basis = basis.scaled(Vector3.ONE * s)
		var low := _lowest_point(mesh, basis)
		var y: float = _ground(p, longest * s * 0.4) - low - 0.06 * s
		xforms.append(Transform3D(basis, Vector3(p.x, y, p.y)))
	_emit_cells(node_name, mesh, xforms, PackedColorArray(), true)


func _lowest_point(mesh: Mesh, basis: Basis) -> float:
	var aabb: AABB = mesh.get_aabb()
	var low := 1000000.0
	for i in 8:
		var corner := aabb.get_endpoint(i)
		low = minf(low, (basis * corner).y)
	return low


func _scatter_grass() -> int:
	var total := 0
	var x := -PLAY
	var pending := 0
	while x < PLAY:
		var z := -PLAY
		while z < PLAY:
			var key := Vector2i(int(floor(x / CELL)), int(floor(z / CELL)))
			if not built_chunks.has(key):
				total += _build_grass_chunk(key)
				pending += 1
				if pending % 8 == 0:
					await get_tree().process_frame
			z += CELL
		x += CELL
	return total


func _build_grass_chunk(key: Vector2i) -> int:
	built_chunks[key] = true
	var origin := Vector2(float(key.x) * CELL, float(key.y) * CELL)
	var cover_here := _cover_at(origin.x + CELL * 0.5, origin.y + CELL * 0.5)
	var step := 1.9 if forest_biome else 1.05
	var cap := 260 if forest_biome else 460
	var xforms: Array[Transform3D] = []
	var colors := PackedColorArray()
	var x := origin.x
	while x < origin.x + CELL:
		var z := origin.y
		while z < origin.y + CELL:
			var px := x + rng.randf_range(0.0, step)
			var pz := z + rng.randf_range(0.0, step)
			var cover := _cover_at(px, pz)
			var n := noise.get_noise_2d(px * 0.09, pz * 0.09)
			var chance := 0.0
			if forest_biome:
				if n > 0.05:
					chance = lerpf(0.25, 0.6, cover)
			elif n > 0.34:
				chance = lerpf(0.16, 0.4, cover)
			if builder._slope_at(px, pz) > 0.7:
				chance = 0.0
			if not builder._blocked(blocked, px, pz) and absf(px) < PLAY and absf(pz) < PLAY and rng.randf() < chance:
				var s := lerpf(0.7, 1.15, cover) * rng.randf_range(0.85, 1.35)
				if forest_biome:
					s = rng.randf_range(1.35, 2.1)
				var y: float = _ground(Vector2(px, pz), 0.22 * s) - 0.03
				var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * rng.randf_range(0.9, 1.35), s * rng.randf_range(0.45, 0.85), s))
				xforms.append(Transform3D(basis, Vector3(px, y, pz)))
				var dry := Color(0.82, 0.78, 0.6) if forest_biome else Color(0.42, 0.4, 0.3)
				var lush := Color(0.74, 0.8, 0.6) if forest_biome else Color(0.48, 0.62, 0.34)
				var tint := dry.lerp(lush, cover)
				colors.append(Color(tint.r, tint.g, tint.b, rng.randf()))
				if colors.size() >= cap:
					break
			z += step
		if colors.size() >= cap:
			break
		x += step
	if colors.is_empty():
		return 0
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = grass_mesh
	mm.instance_count = colors.size()
	for i in colors.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	node.visibility_range_end = 240.0
	node.visibility_range_end_margin = 28.0
	node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	node.custom_aabb = AABB(Vector3(origin.x, -30.0, origin.y), Vector3(CELL, 60.0, CELL))
	add_child(node)
	chunks[key] = node
	return colors.size()


func _bark_material() -> Material:
	var bark: Material = builder.lib.get_shared("bark").duplicate()
	if bark is StandardMaterial3D:
		bark.uv1_triplanar = true
		bark.uv1_world_triplanar = false
		bark.uv1_scale = Vector3(0.42, 0.9, 0.42)
		bark.albedo_color = Color(1.35, 1.18, 1.0)
		bark.roughness = 0.82
	return bark


func _leaf_material(tex: Texture2D, wind: float, height_ref: float, bias: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/foliage.gdshader")
	mat.set_shader_parameter("albedo_tex", tex)
	mat.set_shader_parameter("wind_strength", wind)
	mat.set_shader_parameter("height_ref", height_ref)
	mat.set_shader_parameter("scissor", 0.18)
	mat.set_shader_parameter("roughness_val", 0.84)
	mat.set_shader_parameter("lift", 0.006)
	mat.set_shader_parameter("up_normal", 0.0)
	mat.set_shader_parameter("normal_up_bias", bias)
	mat.set_shader_parameter("clip_black", 0.0)
	return mat


func _scatter_ferns() -> void:
	var mesh := _fern_mesh()
	var points: Array = []
	var spacing := 7.5
	var x := -PLAY + 6.0
	while x < PLAY - 6.0 and points.size() < 420:
		var z := -PLAY + 6.0
		while z < PLAY - 6.0 and points.size() < 420:
			var p := Vector2(x, z) + Vector2(rng.randf_range(-2.5, 2.5), rng.randf_range(-2.5, 2.5))
			var cover := _cover_at(p.x, p.y)
			if cover > 0.28 and builder._slope_at(p.x, p.y) < 0.45 and not builder._blocked(blocked, p.x, p.y):
				if rng.randf() < lerpf(0.15, 0.55, cover):
					points.append(p)
			z += spacing
		x += spacing
	_emit_props("Ferns", mesh, points, 0.7, 1.25)


func _fern_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 5:
		var ang := TAU * float(i) / 5.0
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var up := Vector3(dir.x * 0.85, 0.55, dir.z * 0.85).normalized() * 0.55
		var right := Vector3(-dir.z, 0.0, dir.x) * 0.16
		_card(st, Vector3(0, 0.12, 0) + up * 0.35, right, up * 0.5)
	st.set_material(_leaf_material(_fern_tex(), 0.05, 0.6, 0.4))
	return st.commit()


func _fern_tex() -> Texture2D:
	var image := Image.create(64, 48, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for i in 7:
		var x0 := 32
		var y0 := 40
		var ang := deg_to_rad(lerpf(-70.0, 70.0, float(i) / 6.0))
		var length := 28
		for t in length:
			var x := x0 + int(sin(ang) * float(t))
			var y := y0 - int(cos(ang) * float(t) * 0.8)
			var half := 1 + int(float(t) / 8.0)
			for dx in range(-half, half + 1):
				var px := x + dx
				var py := y
				if px < 0 or py < 0 or px >= 64 or py >= 48:
					continue
				var edge := float(abs(dx)) / float(maxi(half, 1))
				if edge > 0.85:
					continue
				var shade := 0.35 + float(t) / float(length) * 0.25
				image.set_pixel(px, py, Color(0.22 * shade, 0.55 * shade, 0.2 * shade, 1.0))
	return ImageTexture.create_from_image(image)


func _recolor_blades(tex: Texture2D, dry: bool) -> Texture2D:
	var image := tex.get_image()
	if image == null:
		return tex
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.a < 0.04:
				continue
			var lum := c.get_luminance()
			var tone := Color(0.5, 0.44, 0.26).lerp(Color(0.28, 0.26, 0.16), 1.0 - lum)
			if not dry:
				tone = Color(0.4, 0.42, 0.22).lerp(Color(0.2, 0.24, 0.12), 1.0 - lum)
			image.set_pixel(x, y, Color(tone.r, tone.g, tone.b, c.a))
	return ImageTexture.create_from_image(image)


func _mute_grass(tex: Texture2D) -> Texture2D:
	var image := tex.get_image()
	if image == null:
		return tex
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.a < 0.04:
				continue
			var lum := c.get_luminance()
			var straw := Color(0.5, 0.44, 0.26).lerp(Color(0.28, 0.26, 0.16), 1.0 - lum)
			image.set_pixel(x, y, Color(straw.r, straw.g, straw.b, c.a))
	return ImageTexture.create_from_image(image)


func _tex_res(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is Texture2D:
			return res
	var image := Image.new()
	var abs_path := ProjectSettings.globalize_path(path)
	if image.load(abs_path) == OK:
		image.generate_mipmaps()
		return ImageTexture.create_from_image(image)
	push_warning("Missing foliage texture " + path)
	var fallback := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	fallback.fill(Color(0.35, 0.48, 0.22, 1.0))
	return ImageTexture.create_from_image(fallback)


func _tree_mesh(bark: Material, leaves: Material, twigs: Material, pine: bool) -> ArrayMesh:
	var trunk := SurfaceTool.new()
	trunk.begin(Mesh.PRIMITIVE_TRIANGLES)
	if pine:
		_cylinder(trunk, 0.34, 0.1, 4.6, 8, 0.0)
	else:
		_cylinder(trunk, 0.38, 0.14, 3.4, 8, 0.0)
		_cylinder(trunk, 0.16, 0.07, 1.6, 6, 2.5)
	trunk.set_material(bark)
	trunk.generate_tangents()
	var mesh := trunk.commit()
	var crown := SurfaceTool.new()
	crown.begin(Mesh.PRIMITIVE_TRIANGLES)
	if pine:
		_crossed_planes(crown, 4.2, 1.15, 2.55, 3, 0.15)
		_crossed_planes(crown, 5.6, 1.2, 2.15, 3, 0.7)
		_crossed_planes(crown, 7.0, 1.05, 1.7, 3, 0.35)
		_crossed_planes(crown, 8.3, 0.9, 1.2, 3, 0.95)
		_crossed_planes(crown, 9.4, 0.7, 0.75, 3, 0.5)
		_crossed_planes(crown, 10.3, 0.5, 0.38, 3, 1.15)
	else:
		_crossed_planes(crown, 3.5, 1.05, 2.7, 4, 0.2)
		_crossed_planes(crown, 4.45, 1.2, 2.25, 4, 0.65)
		_crossed_planes(crown, 5.35, 0.95, 1.65, 3, 0.4)
		_crossed_planes(crown, 6.05, 0.65, 1.05, 3, 1.0)
	crown.set_material(leaves)
	crown.commit(mesh)
	var fill := SurfaceTool.new()
	fill.begin(Mesh.PRIMITIVE_TRIANGLES)
	var local := RandomNumberGenerator.new()
	local.seed = 19 if pine else 7
	if pine:
		_fillers(fill, local, 3.6, 9.2, 1.5, 6)
	else:
		_fillers(fill, local, 3.1, 5.8, 1.8, 5)
	fill.set_material(twigs)
	fill.commit(mesh)
	return mesh


func _conifer_mesh(bark: Material, boughs: Material, seed: int) -> ArrayMesh:
	var local := RandomNumberGenerator.new()
	local.seed = seed
	var height := 11.0
	var trunk := SurfaceTool.new()
	trunk.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cylinder(trunk, 0.32, 0.05, height, 8, 0.0)
	trunk.set_material(bark)
	trunk.generate_tangents()
	var mesh := trunk.commit()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var levels := 16
	for lv in levels:
		var t := float(lv) / float(levels - 1)
		var y := lerpf(2.0, height - 0.45, t) + local.randf_range(-0.12, 0.12)
		var radius := lerpf(3.0, 0.5, pow(t, 0.85)) * local.randf_range(0.85, 1.1)
		var count := 7 if t < 0.6 else 5
		var spin := local.randf() * TAU
		var width := lerpf(1.1, 0.45, t)
		for b in count:
			var ang := spin + TAU * float(b) / float(count) + local.randf_range(-0.25, 0.25)
			var out := Vector3(cos(ang), 0.0, sin(ang))
			var r := radius * local.randf_range(0.8, 1.1)
			var droop := r * lerpf(0.42, 0.18, t)
			var start := Vector3(out.x * 0.12, y, out.z * 0.12)
			var tip := start + out * r + Vector3(0, -droop, 0)
			var along := (tip - start) * 0.5
			var side := Vector3(-out.z, 0.0, out.x) * width
			var lift := along.cross(side).normalized() * width * 0.7
			var center := start + along
			_card_n(st, center, side, along, (out + Vector3(0, 0.6, 0)).normalized())
			_card_n(st, center, lift, along, (out + Vector3(0, 0.3, 0)).normalized())
	for i in 2:
		var ang := PI * 0.5 * float(i)
		var side := Vector3(cos(ang), 0, sin(ang)) * 0.3
		_card_n(st, Vector3(0, height - 0.2, 0), side, Vector3(0, 0.75, 0), Vector3(-sin(ang), 0.4, cos(ang)).normalized())
	st.set_material(boughs)
	st.commit(mesh)
	return mesh


func _orchard_mesh(bark: Material, leaves: Material, seed: int) -> ArrayMesh:
	var local := RandomNumberGenerator.new()
	local.seed = seed
	var wood := SurfaceTool.new()
	wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cylinder(wood, 0.2, 0.15, 1.5, 7, 0.0)
	for i in 4:
		var ang := TAU * float(i) / 4.0 + local.randf_range(-0.3, 0.3)
		var reach := local.randf_range(1.2, 1.9)
		var tip := Vector3(cos(ang) * reach, local.randf_range(2.8, 3.6), sin(ang) * reach)
		_limb(wood, Vector3(0, 1.4, 0), tip, 0.13, 0.05, 6)
	wood.set_material(bark)
	wood.generate_tangents()
	var mesh := wood.commit()
	var crown_c := Vector3(0, 3.3, 0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 46:
		var dir := Vector3(local.randf_range(-1.0, 1.0), local.randf_range(-0.55, 1.0), local.randf_range(-1.0, 1.0))
		if dir.length() < 0.1:
			dir = Vector3.UP
		dir = dir.normalized()
		var pos := crown_c + Vector3(dir.x * 2.5, dir.y * 1.35, dir.z * 2.5) * local.randf_range(0.55, 1.0)
		var size := local.randf_range(0.75, 1.1)
		var tangent := dir.cross(Vector3.UP)
		if tangent.length() < 0.2:
			tangent = Vector3(1, 0, 0)
		tangent = tangent.normalized().rotated(dir, local.randf() * TAU)
		var bit := dir.cross(tangent).normalized()
		_card_n(st, pos, tangent * size, bit * size, dir)
	st.set_material(leaves)
	st.commit(mesh)
	return mesh


func _limb(st: SurfaceTool, a: Vector3, b: Vector3, r0: float, r1: float, sides: int) -> void:
	var axis := (b - a).normalized()
	var ref := Vector3.UP if absf(axis.y) < 0.9 else Vector3(1, 0, 0)
	var u := axis.cross(ref).normalized()
	var v := axis.cross(u).normalized()
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var d0 := u * cos(a0) + v * sin(a0)
		var d1 := u * cos(a1) + v * sin(a1)
		var n := (d0 + d1).normalized()
		var u0 := float(i) / float(sides)
		var u1 := float(i + 1) / float(sides)
		_tri(st, a + d0 * r0, a + d1 * r0, b + d1 * r1, n, Vector2(u0, 1), Vector2(u1, 1), Vector2(u1, 0))
		_tri(st, a + d0 * r0, b + d1 * r1, b + d0 * r1, n, Vector2(u0, 1), Vector2(u1, 0), Vector2(u0, 0))


func _card_n(st: SurfaceTool, center: Vector3, axis_u: Vector3, axis_v: Vector3, n: Vector3) -> void:
	var p0 := center - axis_u - axis_v
	var p1 := center + axis_u - axis_v
	var p2 := center + axis_u + axis_v
	var p3 := center - axis_u + axis_v
	_tri(st, p0, p1, p2, n, Vector2(0, 1), Vector2(1, 1), Vector2(1, 0))
	_tri(st, p0, p2, p3, n, Vector2(0, 1), Vector2(1, 0), Vector2(0, 0))


func _stroke(image: Image, a: Vector2, b: Vector2, color: Color, thick: float) -> void:
	var length := a.distance_to(b)
	var steps := maxi(int(length * 1.5), 1)
	var r := int(ceil(thick * 0.5))
	var w := image.get_width()
	var h := image.get_height()
	for s in steps + 1:
		var p := a.lerp(b, float(s) / float(steps))
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if Vector2(dx, dy).length() > thick * 0.5 + 0.25:
					continue
				var x := int(p.x) + dx
				var y := int(p.y) + dy
				if x < 0 or y < 0 or x >= w or y >= h:
					continue
				image.set_pixel(x, y, color)


func _bough_tex(seed: int, base: Color) -> Texture2D:
	var image := Image.create(128, 256, false, Image.FORMAT_RGBA8)
	image.fill(Color(base.r, base.g, base.b, 0.0))
	var local := RandomNumberGenerator.new()
	local.seed = seed
	var stem := Color(0.3, 0.22, 0.14)
	_stroke(image, Vector2(64, 252), Vector2(64, 8), stem, 2.2)
	for i in 34:
		var t := local.randf_range(0.04, 0.92)
		var y := 252.0 - t * 240.0
		var reach := lerpf(54.0, 16.0, t) * local.randf_range(0.7, 1.0)
		var dir := -1.0 if i % 2 == 0 else 1.0
		var root := Vector2(64, y)
		var tip := Vector2(64.0 + dir * reach, y - reach * local.randf_range(0.35, 0.7))
		_stroke(image, root, tip, stem, 1.3)
		var twig := (tip - root).normalized()
		var steps := int(reach / 3.0)
		for s in steps:
			var p := root.lerp(tip, float(s) / float(maxi(steps, 1)))
			for side in [-1.0, 1.0]:
				var n := twig.rotated(local.randf_range(0.5, 1.1) * side) * local.randf_range(5.0, 10.0)
				var shade := local.randf_range(0.75, 1.2)
				_stroke(image, p, p + n, Color(base.r * shade, base.g * shade, base.b * shade, 1.0), 1.4)
	for i in 40:
		var p := Vector2(64, local.randf_range(10.0, 250.0))
		var n := Vector2(0, -1).rotated(local.randf_range(-1.2, 1.2)) * local.randf_range(5.0, 9.0)
		_stroke(image, p, p + n, Color(base.r * 0.85, base.g * 0.85, base.b * 0.85, 1.0), 1.4)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


func _leaf_cluster_tex(seed: int, base: Color) -> Texture2D:
	var image := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	image.fill(Color(base.r, base.g, base.b, 0.0))
	var local := RandomNumberGenerator.new()
	local.seed = seed
	for i in 95:
		var ang := local.randf() * TAU
		var rad := 54.0 * sqrt(local.randf())
		var c := Vector2(64, 64) + Vector2(cos(ang), sin(ang)) * rad
		var leaf_ang := local.randf() * TAU
		var dir := Vector2(cos(leaf_ang), sin(leaf_ang))
		var length := local.randf_range(7.0, 12.0)
		var shade := local.randf_range(0.7, 1.2) * lerpf(0.85, 1.12, rad / 54.0)
		var col := Color(base.r * shade, base.g * shade, base.b * shade, 1.0)
		var steps := int(length)
		for s in steps:
			var t := float(s) / float(steps)
			var p := c + dir * (t - 0.5) * length
			_stroke(image, p, p, col, maxf(sin(t * PI) * length * 0.6, 1.0))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


func _near_lot(p: Vector2, placements: Array, gap: float) -> bool:
	for item in placements:
		var reach := sqrt(float(item.area)) * 0.7 + gap
		if p.distance_to(item.center) < reach:
			return true
	return false


func _scatter_orchards(placements: Array) -> Array:
	var items: Array = []
	if not forest_biome:
		return items
	var block := 64.0
	var x := -PLAY + 34.0
	while x < PLAY - 34.0:
		var z := -PLAY + 34.0
		while z < PLAY - 34.0:
			var c := Vector2(x, z)
			var n := noise.get_noise_2d(c.x * 0.006 + 40.0, c.y * 0.006)
			if n > 0.0 and _cover_at(c.x, c.y) > 0.18 and not _near_lot(c, placements, 26.0):
				var spacing := rng.randf_range(5.8, 7.0)
				var half := block * 0.5 - 4.0
				var gx := -half
				while gx <= half:
					var gz := -half
					while gz <= half:
						var p := c + Vector2(gx, gz) + Vector2(rng.randf_range(-0.35, 0.35), rng.randf_range(-0.35, 0.35))
						if rng.randf() > 0.06 and not builder._blocked(blocked, p.x, p.y) and builder._slope_at(p.x, p.y) < 0.3 and not _near_lot(p, placements, 8.0):
							items.append({
								"p": p,
								"yaw": rng.randf() * TAU,
								"scale": rng.randf_range(0.88, 1.12),
								"tint": _tint_for("broadleaf", 0.5),
								"phase": rng.randf(),
							})
						gz += spacing
					gx += spacing
				if items.size() > 420:
					return items
			z += block + 18.0
		x += block + 18.0
	return items


func _scatter_fences(features: Dictionary, placements: Array) -> void:
	var mesh := _fence_mesh()
	var xforms: Array[Transform3D] = []
	var span := 2.8
	for road in features.get("roads", []):
		if str(road.get("bucket", "")) == "path":
			continue
		var pts: Array = road.pts
		var off := float(road.width) * 0.5 + 3.4
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var length := a.distance_to(b)
			if length < span:
				continue
			var dir := (b - a) / length
			var side := Vector2(-dir.y, dir.x)
			var yaw := atan2(-dir.y, dir.x)
			var d := span * 0.5
			while d < length - span * 0.5:
				for sgn in [-1.0, 1.0]:
					var p: Vector2 = a + dir * d + side * off * sgn
					if noise.get_noise_2d(p.x * 0.012 + sgn * 9.0, p.y * 0.012) < -0.08:
						continue
					if absf(p.x) > PLAY - 2.0 or absf(p.y) > PLAY - 2.0:
						continue
					if builder._blocked(blocked, p.x, p.y) or _near_lot(p, placements, 2.0):
						continue
					var tilt := rng.randf_range(-0.05, 0.05) if rng.randf() < 0.8 else rng.randf_range(-0.3, 0.3)
					var basis := Basis(Vector3.UP, yaw) * Basis(Vector3(1, 0, 0), tilt)
					xforms.append(Transform3D(basis, Vector3(p.x, builder.sample_height(p.x, p.y), p.y)))
				d += span
				if xforms.size() >= 1100:
					break
	if xforms.is_empty():
		return
	var body := StaticBody3D.new()
	body.name = "FenceCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(span, 1.1, 0.14)
	for i in xforms.size():
		var col := CollisionShape3D.new()
		col.shape = shape
		col.transform = xforms[i] * Transform3D(Basis.IDENTITY, Vector3(0, 0.55, 0))
		body.add_child(col)
	_emit_cells("Fences", mesh, xforms, PackedColorArray(), true)
	add_child(body)
	print("Fences ", xforms.size())


func _fence_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box_st(st, Vector3(-1.4, 0.62, 0), Vector3(0.13, 1.24, 0.13))
	_box_st(st, Vector3(0, 0.52, 0.06), Vector3(2.86, 0.1, 0.05))
	_box_st(st, Vector3(0, 0.98, 0.06), Vector3(2.86, 0.1, 0.05))
	var mat: StandardMaterial3D = builder.lib.tinted("planks", Color(0.56, 0.5, 0.4))
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	st.set_material(mat)
	return st.commit()


func _box_st(st: SurfaceTool, c: Vector3, size: Vector3) -> void:
	var h := size * 0.5
	var faces := [
		[Vector3(1, 0, 0), Vector3(0, 0, h.z), Vector3(0, h.y, 0), h.x],
		[Vector3(-1, 0, 0), Vector3(0, 0, -h.z), Vector3(0, h.y, 0), h.x],
		[Vector3(0, 1, 0), Vector3(h.x, 0, 0), Vector3(0, 0, -h.z), h.y],
		[Vector3(0, -1, 0), Vector3(h.x, 0, 0), Vector3(0, 0, h.z), h.y],
		[Vector3(0, 0, 1), Vector3(-h.x, 0, 0), Vector3(0, h.y, 0), h.z],
		[Vector3(0, 0, -1), Vector3(h.x, 0, 0), Vector3(0, h.y, 0), h.z],
	]
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var center: Vector3 = c + n * float(f[3])
		_card_n(st, center, u, v, n)


func _shrub_mesh(leaves: Material, _twigs: Material) -> ArrayMesh:
	var crown := SurfaceTool.new()
	crown.begin(Mesh.PRIMITIVE_TRIANGLES)
	_crossed_planes(crown, 0.48, 0.38, 0.95, 3, 0.25)
	_crossed_planes(crown, 0.78, 0.32, 0.62, 3, 0.9)
	var local := RandomNumberGenerator.new()
	local.seed = 13
	_fillers(crown, local, 0.28, 0.95, 0.7, 3)
	crown.set_material(leaves)
	return crown.commit()


func _crossed_planes(st: SurfaceTool, y_center: float, half_h: float, half_w: float, count: int, yaw: float) -> void:
	for i in count:
		var ang := yaw + PI * float(i) / float(count)
		var axis_u := Vector3(cos(ang), 0.0, sin(ang)) * half_w
		var axis_v := Vector3(0.0, half_h, 0.0)
		_card(st, Vector3(0.0, y_center, 0.0), axis_u, axis_v)


func _flat_plane(st: SurfaceTool, y: float, half: float) -> void:
	var axis_u := Vector3(half, 0.0, 0.0)
	var axis_v := Vector3(0.0, 0.15, half)
	_card(st, Vector3(0.0, y, 0.0), axis_u, axis_v)


func _fillers(st: SurfaceTool, local: RandomNumberGenerator, y0: float, y1: float, radius: float, count: int) -> void:
	for i in count:
		var ang := local.randf() * TAU
		var rad := radius * pow(local.randf(), 0.6)
		var y := local.randf_range(y0, y1)
		var center := Vector3(cos(ang) * rad, y, sin(ang) * rad)
		var half := local.randf_range(0.38, 0.72)
		var yaw := local.randf() * TAU
		var tilt := local.randf_range(0.25, 1.15)
		var axis_v := Vector3(sin(yaw) * sin(tilt), cos(tilt), -cos(yaw) * sin(tilt))
		if axis_v.length() < 0.001:
			axis_v = Vector3.UP
		axis_v = axis_v.normalized() * half
		var axis_u := axis_v.cross(Vector3.UP)
		if axis_u.length() < 0.15:
			axis_u = Vector3(1, 0, 0)
		axis_u = axis_u.normalized() * half * 0.85
		_card(st, center, axis_u, axis_v)


func _band(st: SurfaceTool, local: RandomNumberGenerator, y0: float, y1: float, radius: float, count: int) -> void:
	for i in count:
		var ang := local.randf() * TAU
		var rad := radius * pow(local.randf(), 0.55)
		var y := local.randf_range(y0, y1)
		var center := Vector3(cos(ang) * rad, y, sin(ang) * rad)
		var half := local.randf_range(radius * 0.34, radius * 0.62)
		var yaw := local.randf() * TAU
		var tilt := local.randf_range(0.12, 0.65)
		if local.randf() < 0.3:
			tilt = local.randf_range(1.05, 1.4)
		var axis_v := Vector3(sin(yaw) * sin(tilt), cos(tilt), -cos(yaw) * sin(tilt))
		if axis_v.length() < 0.001:
			axis_v = Vector3.UP
		axis_v = axis_v.normalized() * half * local.randf_range(0.85, 1.2)
		var axis_u := axis_v.cross(Vector3.UP)
		if axis_u.length() < 0.15:
			axis_u = Vector3(1, 0, 0)
		axis_u = axis_u.normalized() * half
		_card(st, center, axis_u, axis_v)


func _card(st: SurfaceTool, center: Vector3, axis_u: Vector3, axis_v: Vector3) -> void:
	var p0 := center - axis_u - axis_v
	var p1 := center + axis_u - axis_v
	var p2 := center + axis_u + axis_v
	var p3 := center - axis_u + axis_v
	var n := axis_u.cross(axis_v).normalized()
	if n.length() < 0.1:
		n = Vector3.UP
	_tri(st, p0, p1, p2, n, Vector2(0, 1), Vector2(1, 1), Vector2(1, 0))
	_tri(st, p0, p2, p3, n, Vector2(0, 1), Vector2(1, 0), Vector2(0, 0))


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	st.set_normal(n)
	st.set_uv(ua)
	st.set_color(Color(1, 1, 1, 1))
	st.add_vertex(a)
	st.set_normal(n)
	st.set_uv(ub)
	st.set_color(Color(1, 1, 1, 1))
	st.add_vertex(b)
	st.set_normal(n)
	st.set_uv(uc)
	st.set_color(Color(1, 1, 1, 1))
	st.add_vertex(c)


func _cylinder(st: SurfaceTool, radius_bot: float, radius_top: float, height: float, sides: int, y0: float) -> void:
	st.set_color(Color(1, 1, 1, 1))
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var p0 := Vector3(cos(a0) * radius_bot, y0, sin(a0) * radius_bot)
		var p1 := Vector3(cos(a1) * radius_bot, y0, sin(a1) * radius_bot)
		var p2 := Vector3(cos(a1) * radius_top, y0 + height, sin(a1) * radius_top)
		var p3 := Vector3(cos(a0) * radius_top, y0 + height, sin(a0) * radius_top)
		var n0 := Vector3(cos(a0), 0.15, sin(a0)).normalized()
		var n1 := Vector3(cos(a1), 0.15, sin(a1)).normalized()
		var u0 := float(i) / float(sides)
		var u1 := float(i + 1) / float(sides)
		st.set_normal(n0)
		st.set_uv(Vector2(u0, 1))
		st.add_vertex(p0)
		st.set_normal(n1)
		st.set_uv(Vector2(u1, 1))
		st.add_vertex(p1)
		st.set_normal(n1)
		st.set_uv(Vector2(u1, 0))
		st.add_vertex(p2)
		st.set_normal(n0)
		st.set_uv(Vector2(u0, 1))
		st.add_vertex(p0)
		st.set_normal(n1)
		st.set_uv(Vector2(u1, 0))
		st.add_vertex(p2)
		st.set_normal(n0)
		st.set_uv(Vector2(u0, 0))
		st.add_vertex(p3)


func _grass_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var local := RandomNumberGenerator.new()
	local.seed = 4
	for i in 5:
		var yaw := local.randf() * TAU
		var lean := local.randf_range(0.08, 0.32)
		var h := local.randf_range(0.32, 0.55)
		var w := local.randf_range(0.28, 0.46)
		var right := Vector3(cos(yaw), 0, sin(yaw)) * w
		var up := Vector3(sin(yaw) * lean, 1.0, -cos(yaw) * lean).normalized() * h
		_card(st, up * 0.5, right, up * 0.5)
	st.set_material(grass_mat)
	return st.commit()


func _rock_mesh(seed: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var local := RandomNumberGenerator.new()
	local.seed = seed
	var ring: Array[Vector3] = []
	for i in 7:
		var ang := TAU * float(i) / 7.0
		var r := local.randf_range(0.42, 0.78)
		ring.append(Vector3(cos(ang) * r, local.randf_range(-0.08, 0.12), sin(ang) * r))
	var top := Vector3(local.randf_range(-0.08, 0.08), local.randf_range(0.28, 0.48), local.randf_range(-0.08, 0.08))
	var bottom := Vector3(0, local.randf_range(-0.22, -0.08), 0)
	for i in ring.size():
		var a: Vector3 = ring[i]
		var b: Vector3 = ring[(i + 1) % ring.size()]
		_tri(st, b, a, top, (a - b).cross(top - b).normalized(), Vector2(0, 0), Vector2(1, 0), Vector2(0.5, 1))
		_tri(st, b, a, bottom, (a - b).cross(bottom - b).normalized(), Vector2(0, 0), Vector2(1, 0), Vector2(0.5, 1))
	return st.commit()


func _extract_mesh(path: String) -> Mesh:
	if not ResourceLoader.exists(path):
		return null
	var packed = load(path)
	if not packed is PackedScene:
		return null
	var inst: Node = packed.instantiate()
	var mesh_node: MeshInstance3D = null
	if inst is MeshInstance3D:
		mesh_node = inst
	else:
		var meshes: Array = inst.find_children("*", "MeshInstance3D", true, false)
		if not meshes.is_empty():
			mesh_node = meshes[0]
	if mesh_node == null or mesh_node.mesh == null:
		inst.free()
		return null
	var source: Mesh = mesh_node.mesh
	if source is ArrayMesh:
		for s in source.get_surface_count():
			var mat: Material = mesh_node.get_active_material(s)
			if mat == null:
				mat = source.surface_get_material(s)
			if mat != null:
				var copied := mat.duplicate()
				if copied is StandardMaterial3D:
					copied.cull_mode = BaseMaterial3D.CULL_DISABLED
				source.surface_set_material(s, copied)
	inst.free()
	return source
