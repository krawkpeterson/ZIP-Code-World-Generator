extends Node3D

const MAP_HALF := 560.0
const PLAY_HALF := 400.0
const GRID_N := 501
const MAP_PX := 168
const TERRAIN_CHUNK := 50
const DESIGN := {
	"farmhouse": Vector2(11.2, 9.0),
	"craftsman": Vector2(10.4, 8.6),
	"colonial": Vector2(10.8, 8.2),
	"cottage": Vector2(12.4, 3.6),
	"ranch": Vector2(14.5, 7.4),
	"apartment": Vector2(16.0, 11.0),
	"warehouse": Vector2(34.0, 20.0),
	"factory": Vector2(42.0, 24.0),
	"shed": Vector2(4.4, 3.4),
	"garage": Vector2(7.2, 6.6),
	"barn": Vector2(16.0, 11.0),
	"chapel": Vector2(11.0, 16.0),
	"store": Vector2(12.0, 9.0),
	"gas": Vector2(8.0, 6.5),
}

var geo: Node
var lib
var heights := PackedFloat32Array()
var step := 4.0
var origin_elev := 0.0
var min_h := 0.0
var max_h := 0.0
var environment: Environment
var world_root: Node3D
var spawn := Vector3(0, 2, 0)
var spawn_dir := Vector3(0, 0, -1)
var probes := {}
var place_label := ""
var sat_image: Image
var sat_bounds: Dictionary = {}
var stats := {}
var map_image: Image
var map_tex: Texture2D

func generate(zip_code: String, host: Node) -> Dictionary:
	world_root = Node3D.new()
	world_root.name = "World"
	add_child(world_root)
	lib = preload("res://scripts/materials_lib.gd").new()
	lib.load_all()
	geo = preload("res://scripts/geo_service.gd").new()
	add_child(geo)
	var region: Dictionary = await geo.load_region(zip_code, func(text, ratio):
		host.set_status(text, ratio)
	)
	if not region.get("ok", false):
		return region
	place_label = "%s, %s  ·  %s" % [region.place, region.state, zip_code]
	sat_image = region.sat_image
	sat_bounds = region.sat_bounds
	host.set_status("Shaping the ground", 0.72)
	await get_tree().process_frame
	await _build_heights(region)
	var parsed: Dictionary = geo.parse_osm(region.osm_xml)
	var features := _collect_features(parsed)
	_level_water(features)
	var placements: Array = _choose_buildings(features)
	_flatten_pads(placements, features.water)
	_seat_roads(features.roads)
	host.set_status("Building terrain", 0.78)
	await get_tree().process_frame
	await _build_terrain()
	await _fix_terrain_collision()
	host.set_status("Raising the distant land", 0.8)
	await _build_horizon()
	host.set_status("Laying water and roads", 0.84)
	await get_tree().process_frame
	_build_water(features)
	_build_roads(features.roads)
	_add_bounds()
	host.set_status("Raising buildings", 0.9)
	await get_tree().process_frame
	await _build_buildings(placements, host)
	host.set_status("Planting the ground cover", 0.96)
	await get_tree().process_frame
	var planted: Dictionary = await _build_vegetation(features, placements)
	_atmosphere()
	_pick_spawn(features.roads)
	_paint_minimap(features, placements)
	stats = {
		"buildings": placements.size(),
		"roads": features.roads.size(),
		"water": features.water.size(),
		"streams": features.streams.size(),
		"min_elev": origin_elev + min_h,
		"max_elev": origin_elev + max_h,
		"origin_elev": origin_elev,
		"trees": int(planted.get("trees", 0)),
		"grass": int(planted.get("grass", 0)),
	}
	print("Ashen County ", place_label, " elev ", stats.origin_elev, " .. ", stats.min_elev, " to ", stats.max_elev, " roads ", stats.roads, " buildings ", stats.buildings, " water ", stats.water, " trees ", stats.trees, " grass ", stats.grass)
	return {"ok": true, "place": place_label, "stats": stats}


func sample_height(x: float, z: float) -> float:
	return _sample(heights, x, z)


func latlon_at(x: float, z: float) -> Vector2:
	return geo.to_latlon(x, z)


func _build_heights(region: Dictionary) -> void:
	var n := GRID_N
	step = (MAP_HALF * 2.0) / float(n - 1)
	var absolute := PackedFloat32Array()
	absolute.resize(n * n)
	var image: Image = region.elev_image
	var bounds: Dictionary = region.elev_bounds
	for z in n:
		if z % 40 == 0:
			await get_tree().process_frame
		for x in n:
			var world_x := -MAP_HALF + float(x) * step
			var world_z := -MAP_HALF + float(z) * step
			var ll: Vector2 = geo.to_latlon(world_x, world_z)
			var color: Color = geo.sample_rgb(image, bounds, ll.x, ll.y)
			absolute[z * n + x] = geo.terrarium_height(color)
	for _pass in 2:
		var copy := absolute.duplicate()
		for z in range(1, n - 1):
			for x in range(1, n - 1):
				var h := absolute[z * n + x]
				var avg := (
					absolute[z * n + x - 1] + absolute[z * n + x + 1]
					+ absolute[(z - 1) * n + x] + absolute[(z + 1) * n + x]
				) * 0.25
				if absf(h - avg) > 16.0:
					copy[z * n + x] = avg
		absolute = copy
	var cx := n / 2
	origin_elev = absolute[cx * n + cx]
	heights.resize(n * n)
	min_h = 100000.0
	max_h = -100000.0
	for i in absolute.size():
		var rel := absolute[i] - origin_elev
		heights[i] = rel
		min_h = min(min_h, rel)
		max_h = max(max_h, rel)


func _collect_features(parsed: Dictionary) -> Dictionary:
	var nodes: Dictionary = parsed.nodes
	var ways_by_id := {}
	var roads: Array = []
	var water: Array = []
	var streams: Array = []
	var buildings: Array = []
	var forests: Array = []
	var has_coast := false
	for way in parsed.ways:
		var tags: Dictionary = way.tags
		var pts: PackedVector2Array = geo.way_points(way, nodes)
		if pts.size() >= 2 and pts[0].distance_to(pts[pts.size() - 1]) < 1.0:
			var trimmed := PackedVector2Array()
			for i in range(pts.size() - 1):
				trimmed.append(pts[i])
			pts = trimmed
		ways_by_id[str(way.id)] = {"pts": pts, "tags": tags}
		if str(tags.get("tunnel", "")) in ["yes", "building_passage"]:
			continue
		if tags.has("highway"):
			var kind := str(tags.highway)
			if kind in ["proposed", "construction", "elevator", "escalator", "platform", "raceway", "corridor", "bus_guideway", "rest_area", "services", "no"]:
				continue
			if pts.size() >= 2:
				roads.append_array(_clip_road(pts, tags, kind))
		if tags.has("building") and str(tags.building) not in ["no", "roof", "bridge"]:
			if pts.size() >= 3:
				buildings.append({"id": int(way.id), "poly": pts, "tags": tags})
		elif tags.has("building:part"):
			pass
		var natural := str(tags.get("natural", ""))
		var landuse := str(tags.get("landuse", ""))
		var water_tag := str(tags.get("water", ""))
		var waterway := str(tags.get("waterway", ""))
		if natural in ["coastline", "coast"]:
			has_coast = true
		if pts.size() >= 3 and (natural in ["water", "bay", "wetland"] or landuse in ["reservoir", "basin"] or water_tag in ["lake", "pond", "reservoir"] or waterway == "riverbank"):
			water.append({"poly": pts, "name": str(tags.get("name", ""))})
		elif waterway in ["river", "stream", "canal", "ditch", "drain", "brook"] and pts.size() >= 2:
			streams.append({"pts": pts, "kind": waterway})
		if pts.size() >= 3 and (landuse in ["forest", "orchard", "vineyard"] or natural in ["wood", "scrub"]):
			forests.append(pts)
	for rel in parsed.relations:
		var tags: Dictionary = rel.tags
		var natural := str(tags.get("natural", ""))
		var landuse := str(tags.get("landuse", ""))
		var water_tag := str(tags.get("water", ""))
		if natural != "water" and landuse != "reservoir" and water_tag not in ["lake", "pond", "reservoir"]:
			continue
		var lines: Array = []
		for member in rel.members:
			if str(member.type) != "way" or str(member.role) not in ["outer", ""]:
				continue
			if ways_by_id.has(str(member.ref)):
				var line: PackedVector2Array = ways_by_id[str(member.ref)].pts
				if line.size() >= 2:
					lines.append(line)
		for ring in _stitch(lines):
			if ring.size() >= 3:
				water.append({"poly": ring, "name": str(tags.get("name", ""))})
	return {"roads": roads, "water": water, "streams": streams, "buildings": buildings, "forests": forests, "coast": has_coast}


func _clip_road(pts: PackedVector2Array, tags: Dictionary, kind: String) -> Array:
	var runs: Array = []
	var current: Array = []
	for p in pts:
		if absf(p.x) <= MAP_HALF + 8.0 and absf(p.y) <= MAP_HALF + 8.0:
			current.append(p)
		elif current.size() >= 2:
			runs.append(current)
			current = []
		else:
			current = []
	if current.size() >= 2:
		runs.append(current)
	var built: Array = []
	for run in runs:
		built.append({
			"pts": run,
			"kind": kind,
			"name": str(tags.get("name", "")),
			"width": _road_width(kind),
			"bridge": str(tags.get("bridge", "")) in ["yes", "viaduct", "boardwalk", "aqueduct"],
			"bucket": _road_bucket(kind),
		})
	return built


func _road_width(kind: String) -> float:
	match kind:
		"motorway", "motorway_link":
			return 13.5
		"trunk", "trunk_link":
			return 11.5
		"primary", "primary_link":
			return 9.5
		"secondary", "secondary_link":
			return 8.0
		"tertiary", "tertiary_link":
			return 7.0
		"residential", "living_street", "unclassified":
			return 6.0
		"service":
			return 3.8
		"track":
			return 3.0
		"footway", "path", "cycleway", "pedestrian", "steps", "bridleway":
			return 1.5
		_:
			return 5.4


func _road_bucket(kind: String) -> String:
	if kind in ["motorway", "motorway_link", "trunk", "trunk_link", "primary", "primary_link", "secondary", "secondary_link", "tertiary", "tertiary_link"]:
		return "major"
	if kind in ["track", "footway", "path", "cycleway", "pedestrian", "steps", "bridleway"]:
		return "path"
	return "local"


func _level_water(features: Dictionary) -> void:
	for body in features.water:
		var poly: PackedVector2Array = body.poly
		var values: Array = []
		var bounds := _poly_bounds(poly)
		var ix0 := clampi(_ix(bounds.position.x), 0, GRID_N - 1)
		var ix1 := clampi(_ix(bounds.position.x + bounds.size.x), 0, GRID_N - 1)
		var iz0 := clampi(_iz(bounds.position.y), 0, GRID_N - 1)
		var iz1 := clampi(_iz(bounds.position.y + bounds.size.y), 0, GRID_N - 1)
		for z in range(iz0, iz1 + 1):
			for x in range(ix0, ix1 + 1):
				var p := _xz(x, z)
				if Geometry2D.is_point_in_polygon(p, poly):
					values.append(heights[z * GRID_N + x])
		values.sort()
		if values.is_empty():
			body["level"] = sample_height(_poly_center(poly).x, _poly_center(poly).y)
		else:
			body["level"] = float(values[clampi(int(float(values.size()) * 0.3), 0, values.size() - 1)]) + 0.16


func _choose_buildings(features: Dictionary) -> Array:
	var ranked: Array = []
	for src in features.buildings:
		var poly: PackedVector2Array = src.poly
		var center := _poly_center(poly)
		if absf(center.x) > PLAY_HALF - 8.0 or absf(center.y) > PLAY_HALF - 8.0:
			continue
		if _point_in_water(center, features.water):
			continue
		var area := _poly_area(poly)
		if area < 10.0:
			continue
		var kind := _classify(src.tags, area, int(src.id))
		var design: Vector2 = DESIGN.get(kind, Vector2(10, 8))
		var frame := _frame_from_poly(poly)
		center = frame.center
		var max_scale := 2.6 if kind in ["warehouse", "factory", "barn"] else 1.65
		var sx := clampf(frame.size.x / design.x, 0.72, max_scale)
		var sz := clampf(frame.size.y / design.y, 0.72, max_scale)
		if kind in ["shed", "garage"] and area < 18.0:
			sx = clampf(sx, 0.65, 1.3)
			sz = clampf(sz, 0.65, 1.3)
		ranked.append({
			"kind": kind,
			"poly": poly,
			"center": center,
			"basis": frame.basis,
			"scale": Vector2(sx, sz),
			"distance": center.length(),
			"area": area,
			"id": int(src.id),
		})
	ranked.sort_custom(func(a, b): return a.distance < b.distance)
	var kept: Array = []
	var counts := {}
	for item in ranked:
		if kept.size() >= 26 and item.kind not in ["warehouse", "factory"]:
			continue
		if kept.size() >= 32:
			break
		counts[item.kind] = int(counts.get(item.kind, 0)) + 1
		kept.append(item)
	_synthesize(kept, features.roads, features.water, counts)
	_seed_wild_lots(kept, features.roads, features.water)
	for item in kept:
		item["pad"] = _median_in_poly(item.poly)
	return kept


func _synthesize(kept: Array, roads: Array, water: Array, counts: Dictionary) -> void:
	var need := []
	if int(counts.get("warehouse", 0)) < 1:
		need.append("warehouse")
	if int(counts.get("factory", 0)) < 1:
		need.append("factory")
	var houses := int(counts.get("farmhouse", 0)) + int(counts.get("craftsman", 0)) + int(counts.get("colonial", 0)) + int(counts.get("cottage", 0)) + int(counts.get("ranch", 0)) + int(counts.get("apartment", 0))
	if houses < 4:
		for kind in ["farmhouse", "craftsman", "colonial", "cottage"]:
			if houses >= 4:
				break
			need.append(kind)
			houses += 1
	if int(counts.get("shed", 0)) < 2:
		need.append("shed")
		need.append("shed")
	if int(counts.get("barn", 0)) < 1 and int(counts.get("warehouse", 0)) < 1:
		need.append("barn")
	var occupied: Array = []
	for item in kept:
		occupied.append(_poly_bounds(item.poly).grow(2.0))
	var salt := 3
	for kind in need:
		var design: Vector2 = DESIGN[kind]
		var placed := _find_lot(roads, water, occupied, design, salt)
		salt += 7
		if placed.is_empty():
			continue
		var poly: PackedVector2Array = placed.poly
		kept.append({
			"kind": kind,
			"poly": poly,
			"center": placed.center,
			"basis": placed.basis,
			"scale": Vector2.ONE,
			"distance": placed.center.length(),
			"area": design.x * design.y,
			"id": 1000 + salt,
		})
		occupied.append(_poly_bounds(poly).grow(2.0))


func _seed_wild_lots(kept: Array, roads: Array, water: Array) -> void:
	var occupied: Array = []
	for item in kept:
		occupied.append(_poly_bounds(item.poly).grow(10.0))
	var anchor := _road_anchor(roads)
	var facing := _road_dir_at(roads, anchor)
	if facing.length() < 0.2:
		facing = Vector2(1, 0)
	var side := Vector2(-facing.y, facing.x)
	var roadside := [
		{"kind": "gas", "dist": 14.0},
		{"kind": "ranch", "dist": 26.0},
		{"kind": "shed", "dist": 20.0},
	]
	for i in roadside.size():
		var spec: Dictionary = roadside[i]
		var kind := str(spec.kind)
		var design: Vector2 = DESIGN[kind]
		var reach: float = float(spec.dist) + design.y * 0.5
		var p: Vector2 = anchor + side * reach
		if not _lot_ok(p, design, facing, roads, water, occupied, 6.0, 0.32):
			p = anchor - side * reach
		if not _lot_ok(p, design, facing, roads, water, occupied, 6.0, 0.32):
			continue
		_append_lot(kept, occupied, kind, p, facing, 2100 + i)
	var wild := ["shed", "garage", "store", "cottage", "shed", "barn", "craftsman", "gas", "chapel", "garage", "shed"]
	if kept.size() > 15:
		wild = ["barn", "shed", "cottage", "gas"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 4417
	var placed := 0
	var tries := 0
	while placed < wild.size() and tries < 320:
		tries += 1
		var kind: String = wild[placed]
		var design: Vector2 = DESIGN[kind]
		var p := Vector2(rng.randf_range(-340.0, 340.0), rng.randf_range(-340.0, 340.0))
		if p.distance_to(anchor) < 55.0:
			continue
		if not _clear_of_roads(p, roads, 34.0):
			continue
		var face := Vector2(cos(rng.randf() * TAU), sin(rng.randf() * TAU))
		if not _lot_ok(p, design, face, roads, water, occupied, 8.0, 0.22):
			continue
		_append_lot(kept, occupied, kind, p, face, 3000 + placed)
		placed += 1
	print("Outposts ", kept.size(), " wild ", placed)


func _append_lot(kept: Array, occupied: Array, kind: String, p: Vector2, face: Vector2, id: int) -> void:
	var design: Vector2 = DESIGN[kind]
	var basis := Basis(Vector3(face.x, 0, face.y), Vector3.UP, Vector3(-face.y, 0, face.x))
	var poly := _rect_poly(Vector3(p.x, 0, p.y), basis, design)
	kept.append({
		"kind": kind,
		"poly": poly,
		"center": p,
		"basis": basis,
		"scale": Vector2.ONE,
		"distance": p.length(),
		"area": design.x * design.y,
		"id": id,
	})
	occupied.append(_poly_bounds(poly).grow(18.0))


func _lot_ok(p: Vector2, design: Vector2, face: Vector2, roads: Array, water: Array, occupied: Array, road_gap: float, slope_max: float) -> bool:
	if absf(p.x) > PLAY_HALF - 24.0 or absf(p.y) > PLAY_HALF - 24.0:
		return false
	if _point_in_water(p, water):
		return false
	if _slope_at(p.x, p.y) > slope_max:
		return false
	if not _clear_of_roads(p, roads, road_gap):
		return false
	var basis := Basis(Vector3(face.x, 0, face.y), Vector3.UP, Vector3(-face.y, 0, face.x))
	var poly := _rect_poly(Vector3(p.x, 0, p.y), basis, design)
	var ground := sample_height(p.x, p.y)
	for corner in poly:
		if absf(sample_height(corner.x, corner.y) - ground) > 1.6:
			return false
		if not _clear_of_roads(corner, roads, 3.5):
			return false
	var bounds := _poly_bounds(poly)
	for rect in occupied:
		if bounds.intersects(rect):
			return false
	return true


func _clear_of_roads(p: Vector2, roads: Array, extra: float) -> bool:
	for road in roads:
		if str(road.get("bucket", "")) == "path":
			continue
		var pts: Array = road.pts
		var gap := float(road.width) * 0.5 + extra
		for i in range(pts.size() - 1):
			if _dist_to_segment(p, pts[i], pts[i + 1]) < gap:
				return false
	return true


func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 0.01:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _road_anchor(roads: Array) -> Vector2:
	var best := Vector2.ZERO
	var best_d := 100000.0
	for road in roads:
		if str(road.get("bucket", "")) == "path":
			continue
		var pts: Array = road.pts
		for i in range(pts.size() - 1):
			var mid: Vector2 = (pts[i] + pts[i + 1]) * 0.5
			if absf(mid.x) > PLAY_HALF - 30.0 or absf(mid.y) > PLAY_HALF - 30.0:
				continue
			if mid.length() < best_d:
				best_d = mid.length()
				best = mid
	return best


func _road_dir_at(roads: Array, anchor: Vector2) -> Vector2:
	var best := Vector2(0, -1)
	var best_d := 100000.0
	for road in roads:
		if str(road.get("bucket", "")) == "path":
			continue
		var pts: Array = road.pts
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var d := _dist_to_segment(anchor, a, b)
			if d < best_d:
				best_d = d
				best = (b - a).normalized()
	return best


func _find_lot(roads: Array, water: Array, occupied: Array, design: Vector2, salt: int) -> Dictionary:
	var spots: Array = []
	for road in roads:
		if road.bucket == "path":
			continue
		var pts: Array = road.pts
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var seg := b - a
			var length := seg.length()
			if length < 8.0:
				continue
			var dir := seg / length
			var side := Vector2(-dir.y, dir.x)
			var offset: float = float(road.width) * 0.5 + maxf(design.x, design.y) * 0.55 + 3.5
			var d := 6.0
			while d < length - 4.0:
				for sgn in [-1.0, 1.0]:
					var p: Vector2 = a + dir * d + side * offset * sgn
					if absf(p.x) < PLAY_HALF - 18.0 and absf(p.y) < PLAY_HALF - 18.0:
						spots.append({"p": p, "dir": dir})
				d += 22.0
	if spots.is_empty():
		return {}
	var start := salt % spots.size()
	for n in range(mini(spots.size(), 40)):
		var spot: Dictionary = spots[(start + n * 3) % spots.size()]
		var dir: Vector2 = spot.dir
		var x_axis := Vector3(dir.x, 0, dir.y)
		var z_axis := Vector3(-dir.y, 0, dir.x)
		var basis := Basis(x_axis, Vector3.UP, z_axis)
		var center := Vector3(spot.p.x, 0, spot.p.y)
		var poly := _rect_poly(center, basis, design)
		if _point_in_water(spot.p, water):
			continue
		var bounds := _poly_bounds(poly)
		var hit := false
		for rect in occupied:
			if bounds.intersects(rect):
				hit = true
				break
		if hit:
			continue
		return {"center": spot.p, "basis": basis, "poly": poly}
	return {}


func _flatten_pads(placements: Array, water: Array) -> void:
	for item in placements:
		var poly: PackedVector2Array = item.poly
		var target: float = item.pad
		var bounds := _poly_bounds(poly).grow(8.0)
		var ix0 := clampi(_ix(bounds.position.x), 0, GRID_N - 1)
		var ix1 := clampi(_ix(bounds.position.x + bounds.size.x), 0, GRID_N - 1)
		var iz0 := clampi(_iz(bounds.position.y), 0, GRID_N - 1)
		var iz1 := clampi(_iz(bounds.position.y + bounds.size.y), 0, GRID_N - 1)
		for z in range(iz0, iz1 + 1):
			for x in range(ix0, ix1 + 1):
				var p := _xz(x, z)
				if _point_in_water(p, water):
					continue
				var idx := z * GRID_N + x
				if Geometry2D.is_point_in_polygon(p, poly):
					heights[idx] = target
				else:
					var dist := _dist_to_poly(p, poly)
					if dist < 8.0:
						var t := 1.0 - dist / 8.0
						t = t * t * (3.0 - 2.0 * t)
						heights[idx] = lerpf(heights[idx], target, t)


func _build_terrain() -> void:
	var n := GRID_N
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var tans := PackedFloat32Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	verts.resize(n * n)
	norms.resize(n * n)
	tans.resize(n * n * 4)
	uvs.resize(n * n)
	uv2s.resize(n * n)
	var west := float(sat_bounds.west)
	var east := float(sat_bounds.east)
	var north := float(sat_bounds.north)
	var south := float(sat_bounds.south)
	for z in n:
		for x in n:
			var world_x := -MAP_HALF + float(x) * step
			var world_z := -MAP_HALF + float(z) * step
			var i := z * n + x
			verts[i] = Vector3(world_x, heights[i], world_z)
			var hl := heights[z * n + maxi(x - 1, 0)]
			var hr := heights[z * n + mini(x + 1, n - 1)]
			var hd := heights[maxi(z - 1, 0) * n + x]
			var hu := heights[mini(z + 1, n - 1) * n + x]
			norms[i] = Vector3(hl - hr, 2.0 * step, hd - hu).normalized()
			var tan := Vector3(2.0 * step, hr - hl, 0.0).normalized()
			tans[i * 4] = tan.x
			tans[i * 4 + 1] = tan.y
			tans[i * 4 + 2] = tan.z
			tans[i * 4 + 3] = 1.0
			var ll: Vector2 = geo.to_latlon(world_x, world_z)
			var u: float = (ll.y - west) / maxf(east - west, 0.000001)
			var v: float = (north - ll.x) / maxf(north - south, 0.000001)
			uvs[i] = Vector2(clampf(u, 0.0, 1.0), clampf(1.0 - v, 0.0, 1.0))
			uv2s[i] = Vector2(world_x * 0.42, world_z * 0.42)
	var terrain := Node3D.new()
	terrain.name = "Terrain"
	world_root.add_child(terrain)
	var mat := _terrain_material()
	var cells := TERRAIN_CHUNK
	var chunks := (n - 1) / cells
	var lods := [[1, 0.0, 300.0], [2, 300.0, 640.0], [5, 640.0, 0.0]]
	for cz in chunks:
		for cx in chunks:
			for lod in lods:
				var mesh := _terrain_chunk(cx * cells, cz * cells, cells, int(lod[0]), verts, norms, tans, uvs, uv2s)
				var inst := MeshInstance3D.new()
				inst.mesh = mesh
				inst.material_override = mat
				inst.visibility_range_begin = float(lod[1])
				inst.visibility_range_end = float(lod[2])
				inst.visibility_range_begin_margin = 12.0 if float(lod[1]) > 0.0 else 0.0
				inst.visibility_range_end_margin = 12.0 if float(lod[2]) > 0.0 else 0.0
				inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if int(lod[0]) == 1 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				inst.gi_mode = GeometryInstance3D.GI_MODE_STATIC if int(lod[0]) == 1 else GeometryInstance3D.GI_MODE_DISABLED
				terrain.add_child(inst)
		await get_tree().process_frame
	_terrain_occluder(n)
	_build_terrain_collision(n)


func _terrain_occluder(n: int) -> void:
	var stride := 8
	var side := (n - 1) / stride + 1
	var pts := PackedVector3Array()
	var idx := PackedInt32Array()
	for gz in side:
		for gx in side:
			var x := mini(gx * stride, n - 1)
			var z := mini(gz * stride, n - 1)
			var lowest := heights[z * n + x]
			for dz in range(-stride, stride + 1, stride / 2):
				for dx in range(-stride, stride + 1, stride / 2):
					lowest = minf(lowest, heights[clampi(z + dz, 0, n - 1) * n + clampi(x + dx, 0, n - 1)])
			pts.append(Vector3(-MAP_HALF + float(x) * step, lowest - 1.2, -MAP_HALF + float(z) * step))
	for gz in side - 1:
		for gx in side - 1:
			var i00 := gz * side + gx
			var i10 := i00 + 1
			var i01 := i00 + side
			var i11 := i01 + 1
			idx.append_array([i00, i01, i11, i00, i11, i10])
	var occ := ArrayOccluder3D.new()
	occ.set_arrays(pts, idx)
	var node := OccluderInstance3D.new()
	node.name = "TerrainOccluder"
	node.occluder = occ
	world_root.add_child(node)


func _terrain_chunk(x0: int, z0: int, cells: int, stride: int, verts: PackedVector3Array, norms: PackedVector3Array, tans: PackedFloat32Array, uvs: PackedVector2Array, uv2s: PackedVector2Array) -> ArrayMesh:
	var n := GRID_N
	var side := cells / stride + 1
	var cv := PackedVector3Array()
	var cn := PackedVector3Array()
	var ct := PackedFloat32Array()
	var cu := PackedVector2Array()
	var cu2 := PackedVector2Array()
	var idx := PackedInt32Array()
	for gz in side:
		for gx in side:
			var i := (z0 + gz * stride) * n + (x0 + gx * stride)
			cv.append(verts[i])
			cn.append(norms[i])
			for k in 4:
				ct.append(tans[i * 4 + k])
			cu.append(uvs[i])
			cu2.append(uv2s[i])
	for gz in side - 1:
		for gx in side - 1:
			var i00 := gz * side + gx
			var i10 := i00 + 1
			var i01 := i00 + side
			var i11 := i01 + 1
			idx.append_array([i00, i11, i01, i00, i10, i11])
	if stride > 1:
		var skirt := 2.5 * float(stride)
		var ring: Array[int] = []
		for gx in side:
			ring.append(gx)
		for gz in range(1, side):
			ring.append(gz * side + side - 1)
		for gx in range(side - 2, -1, -1):
			ring.append((side - 1) * side + gx)
		for gz in range(side - 2, 0, -1):
			ring.append(gz * side)
		ring.append(0)
		var base := cv.size()
		for r in ring:
			cv.append(cv[r] - Vector3(0, skirt, 0))
			cn.append(cn[r])
			for k in 4:
				ct.append(ct[r * 4 + k])
			cu.append(cu[r])
			cu2.append(cu2[r])
		for s in ring.size() - 1:
			var a: int = ring[s]
			var b: int = ring[s + 1]
			idx.append_array([a, base + s, b, b, base + s, base + s + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = cv
	arrays[Mesh.ARRAY_NORMAL] = cn
	arrays[Mesh.ARRAY_TANGENT] = ct
	arrays[Mesh.ARRAY_TEX_UV] = cu
	arrays[Mesh.ARRAY_TEX_UV2] = cu2
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _terrain_material() -> ShaderMaterial:
	if not sat_image.has_mipmaps():
		sat_image.generate_mipmaps()
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/terrain.gdshader")
	mat.set_shader_parameter("satellite", ImageTexture.create_from_image(sat_image))
	mat.set_shader_parameter("grass_alb", _tex("forrest_ground_01_diff", Color(0.32, 0.38, 0.2)))
	mat.set_shader_parameter("grass_nor", _tex("forrest_ground_01_nor", Color(0.5, 0.5, 1.0), true))
	mat.set_shader_parameter("grass_rough", _load_res("res://assets/textures/forrest_ground_01_rough.jpg"))
	mat.set_shader_parameter("dirt_alb", _tex("dry_ground_01_diff", Color(0.4, 0.32, 0.22)))
	mat.set_shader_parameter("dirt_nor", _tex("dry_ground_01_nor", Color(0.5, 0.5, 1.0), true))
	mat.set_shader_parameter("dirt_rough", _load_res("res://assets/textures/dry_ground_01_rough.jpg"))
	mat.set_shader_parameter("duff_alb", _load_res("res://assets/textures/brown_mud_leaves_01_diff.jpg"))
	mat.set_shader_parameter("duff_nor", _load_res("res://assets/textures/brown_mud_leaves_01_nor.jpg"))
	mat.set_shader_parameter("duff_rough", _load_res("res://assets/textures/brown_mud_leaves_01_rough.jpg"))
	mat.set_shader_parameter("rock_alb", _tex("rock_face_diff", Color(0.45, 0.42, 0.38)))
	mat.set_shader_parameter("rock_nor", _tex("rock_face_nor", Color(0.5, 0.5, 1.0), true))
	mat.set_shader_parameter("rock_rough", _load_res("res://assets/textures/rock_face_rough.jpg"))
	var green := _green_ratio()
	mat.set_shader_parameter("forest", clampf((green - 0.12) / 0.28, 0.0, 1.0))
	print("Terrain green ", snapped(green, 0.01))
	return mat


func _build_terrain_collision(n: int) -> void:
	var body := StaticBody3D.new()
	body.name = "TerrainCollision"
	body.collision_layer = 1
	var shape := HeightMapShape3D.new()
	shape.map_width = n
	shape.map_depth = n
	shape.map_data = heights.duplicate()
	var col := CollisionShape3D.new()
	col.shape = shape
	col.scale = Vector3(step, 1.0, step)
	body.add_child(col)
	world_root.add_child(body)


func _build_horizon() -> void:
	var far: Dictionary = await geo.fetch_wide_elevation()
	if not far.get("ok", false):
		push_warning("Distant elevation was not available")
		return
	var image: Image = far.image
	var bounds: Dictionary = far.bounds
	var half := 16000.0
	var n := 221
	var stride := half * 2.0 / float(n - 1)
	var inner := MAP_HALF - 36.0
	var grid := PackedFloat32Array()
	grid.resize(n * n)
	var miny := 100000.0
	var maxy := -100000.0
	for z in n:
		if z % 40 == 0:
			await get_tree().process_frame
		for x in n:
			var wx := -half + float(x) * stride
			var wz := -half + float(z) * stride
			var ll: Vector2 = geo.to_latlon(wx, wz)
			var coarse: float = geo.terrarium_height(geo.sample_rgb(image, bounds, ll.x, ll.y)) - origin_elev
			var ax := clampf(wx, -MAP_HALF + 2.0, MAP_HALF - 2.0)
			var az := clampf(wz, -MAP_HALF + 2.0, MAP_HALF - 2.0)
			var edge := sample_height(ax, az)
			var outside := maxf(absf(wx), absf(wz)) - MAP_HALF
			var h := coarse
			if outside <= 0.0:
				h = sample_height(wx, wz)
			elif outside < 700.0:
				var t := clampf(outside / 700.0, 0.0, 1.0)
				t = t * t * (3.0 - 2.0 * t)
				h = lerpf(edge, coarse, t)
			grid[z * n + x] = h
			miny = minf(miny, h)
			maxy = maxf(maxy, h)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in range(n - 1):
		for x in range(n - 1):
			var inside := 0
			for corner in [Vector2i(x, z), Vector2i(x + 1, z), Vector2i(x, z + 1), Vector2i(x + 1, z + 1)]:
				var cx := -half + float(corner.x) * stride
				var cz := -half + float(corner.y) * stride
				if absf(cx) < inner and absf(cz) < inner:
					inside += 1
			if inside == 4:
				continue
			var i00 := z * n + x
			var i10 := i00 + 1
			var i01 := i00 + n
			var i11 := i01 + 1
			_horizon_vert(st, half, stride, x, z, grid[i00])
			_horizon_vert(st, half, stride, x, z + 1, grid[i01])
			_horizon_vert(st, half, stride, x + 1, z + 1, grid[i11])
			_horizon_vert(st, half, stride, x, z, grid[i00])
			_horizon_vert(st, half, stride, x + 1, z + 1, grid[i11])
			_horizon_vert(st, half, stride, x + 1, z, grid[i10])
	var mesh := st.commit()
	var normals := SurfaceTool.new()
	normals.create_from(mesh, 0)
	normals.generate_normals()
	mesh = normals.commit()
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.name = "Horizon"
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/horizon.gdshader")
	mat.set_shader_parameter("dirt_alb", _tex("dry_ground_01_diff", Color(0.45, 0.36, 0.24)))
	mat.set_shader_parameter("rock_alb", _tex("rock_face_diff", Color(0.48, 0.44, 0.38)))
	mat.set_shader_parameter("rock_nor", _tex("rock_face_nor", Color(0.5, 0.5, 1.0), true))
	mat.set_shader_parameter("biome", _biome_color())
	node.material_override = mat
	world_root.add_child(node)
	print("Horizon ", miny, " to ", maxy)


func _horizon_vert(st: SurfaceTool, half: float, stride: float, x: int, z: int, h: float) -> void:
	var p := Vector3(-half + float(x) * stride, h, -half + float(z) * stride)
	st.set_uv(Vector2(p.x, p.z) * 0.01)
	st.add_vertex(p)


func _biome_color() -> Color:
	if sat_image == null:
		return Color(0.55, 0.48, 0.36)
	var acc := Color(0, 0, 0, 0)
	var count := 0
	var w := sat_image.get_width()
	var h := sat_image.get_height()
	for y in range(0, h, 28):
		for x in range(0, w, 28):
			acc += sat_image.get_pixel(x, y)
			count += 1
	if count == 0:
		return Color(0.55, 0.48, 0.36)
	acc /= float(count)
	return Color(clampf(acc.r, 0.15, 0.85), clampf(acc.g, 0.15, 0.75), clampf(acc.b, 0.1, 0.6))


func _fix_terrain_collision() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space == null:
		return
	var from := Vector3(0, max_h + 80.0, 0)
	var to := Vector3(0, min_h - 80.0, 0)
	var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))
	var expected := sample_height(0, 0)
	if hit.is_empty() or absf(float(hit.position.y) - expected) > 1.25:
		var old := world_root.get_node_or_null("TerrainCollision")
		if old:
			old.queue_free()
		for chunk in world_root.get_node("Terrain").get_children():
			var mesh_node := chunk as MeshInstance3D
			if mesh_node == null or mesh_node.visibility_range_begin > 0.0:
				continue
			mesh_node.create_trimesh_collision()
			var generated := mesh_node.get_child(mesh_node.get_child_count() - 1)
			if generated is StaticBody3D:
				generated.collision_layer = 1
				generated.collision_mask = 0
		print("Terrain collision fallback to triangle mesh. Ray ", hit, " expected ", expected)


func _build_water(features: Dictionary) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/water.gdshader")
	mat.set_shader_parameter("deep_tint", Color(1, 1, 1))
	mat.set_shader_parameter("clarity", 0.62)
	for body in features.water:
		var poly: PackedVector2Array = _ensure_ccw(body.poly)
		var indices := Geometry2D.triangulate_polygon(poly)
		if indices.is_empty():
			poly = _reversed(poly)
			indices = Geometry2D.triangulate_polygon(poly)
		if indices.is_empty():
			continue
		var level: float = body.level
		var tint := _water_tint(poly)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in range(0, indices.size(), 3):
			for k in [0, 1, 2]:
				var p: Vector2 = poly[indices[i + k]]
				st.set_color(tint)
				st.set_uv(p * 0.05)
				st.add_vertex(Vector3(p.x, level, p.y))
		st.generate_normals()
		var node := MeshInstance3D.new()
		node.mesh = st.commit()
		node.material_override = mat
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world_root.add_child(node)
	for stream in features.streams:
		var width := 6.0 if stream.kind == "river" else 3.2 if stream.kind in ["canal", "drain"] else 2.1
		var pts: Array = []
		for p in stream.pts:
			if absf(p.x) > MAP_HALF or absf(p.y) > MAP_HALF:
				continue
			pts.append(Vector3(p.x, sample_height(p.x, p.y) + 0.08, p.y))
		if pts.size() < 2:
			continue
		var tint := Color(0.08, 0.16, 0.15)
		var mesh := _ribbon_mesh(pts, width, tint)
		if mesh == null:
			continue
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.material_override = mat
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world_root.add_child(node)
	if features.coast:
		var sea_y := 0.45 - origin_elev
		if sea_y > min_h - 2.0 and sea_y < max_h - 1.0:
			var tint := Color(0.04, 0.12, 0.13)
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var s := MAP_HALF
			for corner in [Vector3(-s, sea_y, -s), Vector3(s, sea_y, -s), Vector3(s, sea_y, s), Vector3(-s, sea_y, -s), Vector3(s, sea_y, s), Vector3(-s, sea_y, s)]:
				st.set_color(tint)
				st.add_vertex(corner)
			st.generate_normals()
			var node := MeshInstance3D.new()
			node.mesh = st.commit()
			node.material_override = mat
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			world_root.add_child(node)


func _seat_roads(roads: Array) -> void:
	for road in roads:
		if road.bucket == "path":
			continue
		var half: float = float(road.width) * 0.5 + 1.3
		var raw: Array = road.pts
		for i in range(raw.size() - 1):
			var a: Vector2 = raw[i]
			var b: Vector2 = raw[i + 1]
			var length := a.distance_to(b)
			var steps := maxi(int(ceil(length / 4.0)), 1)
			for s in steps + 1:
				var p: Vector2 = a.lerp(b, float(s) / float(steps))
				_lower_disc(p.x, p.y, half, 0.045)


func _lower_disc(x: float, z: float, radius: float, depth: float) -> void:
	var ix0 := clampi(_ix(x - radius), 1, GRID_N - 2)
	var ix1 := clampi(_ix(x + radius), 1, GRID_N - 2)
	var iz0 := clampi(_iz(z - radius), 1, GRID_N - 2)
	var iz1 := clampi(_iz(z + radius), 1, GRID_N - 2)
	for iz in range(iz0, iz1 + 1):
		for ix in range(ix0, ix1 + 1):
			var p := _xz(ix, iz)
			var d := Vector2(p.x - x, p.y - z).length()
			if d < radius:
				var t := 1.0 - d / radius
				t = t * t * (3.0 - 2.0 * t)
				var idx := iz * GRID_N + ix
				heights[idx] = heights[idx] - depth * t


func _build_roads(roads: Array) -> void:
	var buckets := {
		"major": {"line": 2.0, "shoulder": 1.45, "verts": PackedVector3Array(), "uvs": PackedVector2Array(), "idx": PackedInt32Array()},
		"local": {"line": 1.0, "shoulder": 0.9, "verts": PackedVector3Array(), "uvs": PackedVector2Array(), "idx": PackedInt32Array()},
		"path": {"line": 0.0, "shoulder": 0.2, "verts": PackedVector3Array(), "uvs": PackedVector2Array(), "idx": PackedInt32Array()},
	}
	for road in roads:
		var center: Array = _drape_centerline(road.pts, bool(road.bridge))
		var bucket: Dictionary = buckets[road.bucket]
		_append_road(bucket, center, float(road.width), float(bucket.shoulder))
	for key in buckets.keys():
		var bucket: Dictionary = buckets[key]
		if bucket.idx.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = bucket.verts
		arrays[Mesh.ARRAY_TEX_UV] = bucket.uvs
		arrays[Mesh.ARRAY_INDEX] = bucket.idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var st := SurfaceTool.new()
		st.create_from(mesh, 0)
		st.generate_normals()
		st.generate_tangents()
		mesh = st.commit()
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.name = "Roads_" + key
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://shaders/road.gdshader")
		mat.set_shader_parameter("asphalt_alb", _tex("asphalt_02_diff", Color(0.15, 0.15, 0.15)))
		mat.set_shader_parameter("asphalt_nor", _tex("asphalt_02_nor", Color(0.5, 0.5, 1.0), true))
		mat.set_shader_parameter("gravel_alb", _tex("dry_ground_01_diff", Color(0.35, 0.3, 0.24)))
		mat.set_shader_parameter("gravel_nor", _tex("dry_ground_01_nor", Color(0.5, 0.5, 1.0), true))
		mat.set_shader_parameter("line_mode", bucket.line)
		mat.set_shader_parameter("shoulder", 0.5 if str(key) == "path" else 0.07)
		node.material_override = mat
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world_root.add_child(node)
		if str(key) != "path":
			node.create_trimesh_collision()
			var generated := node.get_child(node.get_child_count() - 1)
			if generated is StaticBody3D:
				generated.collision_layer = 1
				generated.collision_mask = 0


func _build_buildings(placements: Array, host: Node) -> void:
	var kit = preload("res://scripts/building_kit.gd").new(lib)
	kit.woodland = _green_ratio() > 0.18
	var holder := Node3D.new()
	holder.name = "Buildings"
	world_root.add_child(holder)
	var index := 0
	for item in placements:
		var design: Vector2 = DESIGN.get(item.kind, Vector2(10, 8))
		var scaled := Basis(item.basis.x * item.scale.x, Vector3.UP, item.basis.z * item.scale.y)
		var origin := Vector3(item.center.x, item.pad, item.center.y)
		var built: Dictionary = kit.build(item.kind, holder, Transform3D(scaled, origin), design)
		if item.kind in ["farmhouse", "craftsman", "colonial", "cottage", "ranch", "apartment"] and not probes.has("house"):
			probes["house"] = built.probe
		if item.kind in ["warehouse", "factory"] and not probes.has("industrial"):
			probes["industrial"] = built.probe
		index += 1
		if index % 4 == 0:
			host.set_status("Raising buildings %d / %d" % [index, placements.size()], 0.9 + 0.05 * float(index) / float(maxi(placements.size(), 1)))
			await get_tree().process_frame
	_poles(holder)


func _poles(parent: Node3D) -> void:
	var wood: Material = lib.tinted("bark", Color(0.45, 0.36, 0.26))
	var count := 0
	for road_node in world_root.get_children():
		if str(road_node.name).begins_with("Roads_path"):
			continue
	# Poles follow the stored road centerlines re-sampled from collision-free logic below.
	count = 0
	for child in parent.get_children():
		if count > 40:
			break
		if not str(child.name).begins_with("farmhouse") and not str(child.name).begins_with("craftsman") and not str(child.name).begins_with("colonial") and not str(child.name).begins_with("cottage") and not str(child.name).begins_with("ranch"):
			continue
		var pole := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.09
		mesh.bottom_radius = 0.12
		mesh.height = 7.2
		pole.mesh = mesh
		pole.material_override = wood
		pole.position = child.position + child.transform.basis.z * -8.0 + Vector3(0, 3.6, 0)
		parent.add_child(pole)
		var arm := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.6, 0.08, 0.08)
		arm.mesh = box
		arm.material_override = lib.get_shared("darkmetal")
		arm.position = pole.position + Vector3(0, 3.3, 0)
		parent.add_child(arm)
		count += 1


func _build_vegetation(features: Dictionary, placements: Array) -> Dictionary:
	var cover: Node = preload("res://scripts/ground_cover.gd").new()
	cover.name = "GroundCover"
	world_root.add_child(cover)
	return await cover.populate(self, features, placements)


func _build_vegetation_unused(features: Dictionary, placements: Array) -> void:
	var blocked := PackedByteArray()
	blocked.resize(GRID_N * GRID_N)
	blocked.fill(0)
	for road in features.roads:
		var radius := float(road.width) * 0.5 + 1.4
		var pts: Array = road.pts
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var length := a.distance_to(b)
			var steps := maxi(int(length / 2.0), 1)
			for s in steps + 1:
				var p := a.lerp(b, float(s) / float(steps))
				_mark(blocked, p.x, p.y, radius)
	for item in placements:
		_mark_poly(blocked, item.poly, 2.0)
	for body in features.water:
		_mark_poly(blocked, body.poly, 1.0)
	var green := _green_ratio()
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var nature := _load_nature()
	var folder := Node3D.new()
	folder.name = "Vegetation"
	world_root.add_child(folder)
	var tree_cap := int(round(lerpf(18.0, 160.0, clampf(green * 1.4, 0.0, 1.0))))
	var shrub_cap := int(round(lerpf(20.0, 90.0, clampf(green * 1.2, 0.0, 1.0))))
	var trees := 0
	var shrubs := 0
	var spacing := lerpf(18.0, 8.5, clampf(green * 1.3, 0.0, 1.0))
	var x := -PLAY_HALF + 6.0
	while x < PLAY_HALF - 6.0:
		var z := -PLAY_HALF + 6.0
		while z < PLAY_HALF - 6.0:
			var jitter := Vector2(rng.randf_range(-2.5, 2.5), rng.randf_range(-2.5, 2.5))
			var p := Vector2(x, z) + jitter
			var slope := _slope_at(p.x, p.y)
			var forest := _in_polys(p, features.forests)
			var roll := rng.randf()
			if not _blocked(blocked, p.x, p.y):
				if slope > 0.42 and shrubs < 30:
					_spawn_boulder(folder, nature, p, rng)
					shrubs += 1
				elif (forest or roll < green * 0.85) and trees < tree_cap and slope < 0.48:
					_spawn_tree(folder, nature, p, rng, green)
					trees += 1
				elif roll < 0.35 and shrubs < shrub_cap and slope < 0.55:
					_spawn_shrub(folder, nature, p, rng, green)
					shrubs += 1
			z += spacing
		x += spacing
	_scatter_grass(folder, blocked, rng, green)
	stats["trees"] = trees
	stats["green"] = green


func _paint_minimap(features: Dictionary, placements: Array) -> void:
	var image := Image.create(MAP_PX, MAP_PX, false, Image.FORMAT_RGBA8)
	var span := PLAY_HALF * 2.0
	for y in MAP_PX:
		for x in MAP_PX:
			var wx := -PLAY_HALF + (float(x) + 0.5) / float(MAP_PX) * span
			var wz := -PLAY_HALF + (float(y) + 0.5) / float(MAP_PX) * span
			image.set_pixel(x, y, _map_color(wx, wz, features))
	for road in features.roads:
		if str(road.get("bucket", "")) == "path":
			continue
		var pts: Array = road.pts
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var length := a.distance_to(b)
			var steps := maxi(int(length / 6.0), 1)
			for s in steps + 1:
				_stamp(image, a.lerp(b, float(s) / float(steps)), Color(0.28, 0.26, 0.24), 1)
	for body in features.water:
		var poly: PackedVector2Array = body.poly
		if poly.size() < 3:
			continue
		var bounds := _poly_bounds(poly)
		var x0 := clampi(_world_to_px(bounds.position).x, 0, MAP_PX - 1)
		var y0 := clampi(_world_to_px(bounds.position).y, 0, MAP_PX - 1)
		var x1 := clampi(_world_to_px(bounds.position + bounds.size).x, 0, MAP_PX - 1)
		var y1 := clampi(_world_to_px(bounds.position + bounds.size).y, 0, MAP_PX - 1)
		for y in range(mini(y0, y1), maxi(y0, y1) + 1):
			for x in range(mini(x0, x1), maxi(x0, x1) + 1):
				var p := _px_to_world(x, y)
				if Geometry2D.is_point_in_polygon(p, poly):
					image.set_pixel(x, y, Color(0.18, 0.4, 0.48))
	for item in placements:
		_stamp(image, item.center, Color(0.92, 0.58, 0.24), 2)
	map_image = image
	map_tex = ImageTexture.create_from_image(image)


func _map_color(wx: float, wz: float, features: Dictionary) -> Color:
	if _point_in_water(Vector2(wx, wz), features.water):
		return Color(0.18, 0.4, 0.48)
	if _slope_at(wx, wz) > 0.38:
		return Color(0.45, 0.42, 0.38)
	var ll: Vector2 = geo.to_latlon(wx, wz)
	var c: Color = geo.sample_rgb(sat_image, sat_bounds, ll.x, ll.y)
	var excess := c.g - maxf(c.r, c.b)
	if excess > 0.045:
		return Color(0.16, 0.32, 0.14)
	if excess > 0.012:
		return Color(0.36, 0.4, 0.2)
	return Color(0.55, 0.43, 0.28)


func _stamp(image: Image, p: Vector2, color: Color, radius: int) -> void:
	var px := _world_to_px(p)
	for y in range(px.y - radius, px.y + radius + 1):
		for x in range(px.x - radius, px.x + radius + 1):
			if x < 0 or y < 0 or x >= MAP_PX or y >= MAP_PX:
				continue
			image.set_pixel(x, y, color)


func _world_to_px(p: Vector2) -> Vector2i:
	var span := PLAY_HALF * 2.0
	var x := int((p.x + PLAY_HALF) / span * float(MAP_PX))
	var y := int((p.y + PLAY_HALF) / span * float(MAP_PX))
	return Vector2i(x, y)


func _px_to_world(x: int, y: int) -> Vector2:
	var span := PLAY_HALF * 2.0
	return Vector2(-PLAY_HALF + (float(x) + 0.5) / float(MAP_PX) * span, -PLAY_HALF + (float(y) + 0.5) / float(MAP_PX) * span)


func terrain_label(x: float, z: float) -> String:
	if map_image == null:
		return ""
	var px := _world_to_px(Vector2(x, z))
	px.x = clampi(px.x, 0, MAP_PX - 1)
	px.y = clampi(px.y, 0, MAP_PX - 1)
	var c := map_image.get_pixel(px.x, px.y)
	var names := [
		["WATER", Color(0.18, 0.4, 0.48)],
		["ROAD", Color(0.28, 0.26, 0.24)],
		["STRUCTURE", Color(0.92, 0.58, 0.24)],
		["ROCK", Color(0.45, 0.42, 0.38)],
		["TIMBER", Color(0.16, 0.32, 0.14)],
		["SCRUB", Color(0.36, 0.4, 0.2)],
		["BARE", Color(0.55, 0.43, 0.28)],
	]
	var best := "BARE"
	var best_d := 1000.0
	for pair in names:
		var sample: Color = pair[1]
		var d := Vector3(c.r - sample.r, c.g - sample.g, c.b - sample.b).length()
		if d < best_d:
			best_d = d
			best = str(pair[0])
	return best


func _atmosphere() -> void:
	var woodland := _green_ratio() > 0.18
	var world_env := WorldEnvironment.new()
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	var biome := _biome_color()
	var sky := Sky.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://shaders/sky.gdshader")
	var dust := Color(0.78, 0.62, 0.42)
	var leaf := Color(0.58, 0.64, 0.52)
	var horizon := biome.lerp(leaf if woodland else dust, 0.5)
	sky_mat.set_shader_parameter("zenith_color", Color(0.3, 0.44, 0.6) if woodland else Color(0.4, 0.52, 0.66))
	sky_mat.set_shader_parameter("horizon_color", horizon)
	sky_mat.set_shader_parameter("ground_color", biome * 0.35)
	sky_mat.set_shader_parameter("sun_color", Color(1.0, 0.86, 0.66) if woodland else Color(1.0, 0.7, 0.4))
	sky_mat.set_shader_parameter("cloud_cover", 0.4 if woodland else 0.22)
	sky.sky_material = sky_mat
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.52 if _green_ratio() > 0.18 else 0.42
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 0.88
	environment.tonemap_white = 5.2
	environment.ssao_enabled = true
	environment.ssao_radius = 0.9
	environment.ssao_intensity = 1.35
	environment.ssao_power = 1.25
	environment.ssao_detail = 0.55
	environment.ssil_enabled = true
	environment.ssil_radius = 3.5
	environment.ssil_intensity = 0.42
	environment.glow_enabled = true
	environment.glow_intensity = 0.08
	environment.glow_bloom = 0.02
	environment.glow_hdr_threshold = 1.45
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_light_color = horizon
	environment.fog_light_energy = 0.85
	environment.fog_sun_scatter = 0.18
	environment.fog_density = 0.00115
	environment.fog_sky_affect = 0.18
	environment.fog_aerial_perspective = 0.62
	environment.fog_depth_begin = 70.0
	environment.fog_depth_end = 12000.0
	environment.fog_depth_curve = 1.55
	environment.volumetric_fog_enabled = true
	environment.volumetric_fog_density = 0.0045
	environment.volumetric_fog_albedo = horizon.lightened(0.08)
	environment.volumetric_fog_emission = Color(0, 0, 0)
	environment.volumetric_fog_emission_energy = 0.0
	environment.volumetric_fog_anisotropy = 0.32
	environment.volumetric_fog_length = 48.0
	environment.volumetric_fog_ambient_inject = 0.35
	environment.volumetric_fog_gi_inject = 0.45
	environment.volumetric_fog_detail_spread = 1.15
	environment.adjustment_enabled = true
	environment.adjustment_brightness = 1.0
	environment.adjustment_contrast = 1.16
	environment.adjustment_saturation = 0.86 if _green_ratio() > 0.18 else 0.74
	environment.ssr_enabled = true
	environment.ssr_max_steps = 32
	environment.ssr_fade_in = 0.12
	environment.ssr_fade_out = 1.8
	environment.sdfgi_enabled = true
	environment.sdfgi_use_occlusion = true
	environment.sdfgi_read_sky_light = true
	environment.sdfgi_cascades = 4
	environment.sdfgi_min_cell_size = 1.05
	environment.sdfgi_cascade0_distance = 18.0
	environment.sdfgi_max_distance = 180.0
	environment.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_75_PERCENT
	environment.sdfgi_energy = 0.55
	environment.sdfgi_normal_bias = 1.15
	environment.sdfgi_probe_bias = 1.2
	environment.sdfgi_bounce_feedback = 0.42
	world_env.environment = environment
	world_root.add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-34, -48, 0) if woodland else Vector3(-38, -58, 0)
	sun.light_color = Color(1.0, 0.86, 0.68) if woodland else Color(1.0, 0.74, 0.46)
	sun.light_energy = 1.45 if woodland else 1.7
	sun.light_specular = 0.28
	sun.light_volumetric_fog_energy = 1.1
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.92
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 150.0
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_fade_start = 0.85
	sun.shadow_blur = 1.2
	sun.light_angular_distance = 0.5
	sun.shadow_bias = 0.02
	sun.shadow_normal_bias = 1.1
	world_root.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-16, 148, 0)
	fill.light_color = Color(0.85, 0.7, 0.5)
	fill.light_energy = 0.1
	fill.shadow_enabled = false
	world_root.add_child(fill)
	var outdoor := ReflectionProbe.new()
	outdoor.name = "OutdoorProbe"
	outdoor.position = Vector3(0, 18, 0)
	outdoor.size = Vector3(720, 90, 720)
	outdoor.interior = false
	outdoor.intensity = 0.55
	outdoor.max_distance = 240.0
	outdoor.enable_shadows = false
	outdoor.update_mode = ReflectionProbe.UPDATE_ONCE
	world_root.add_child(outdoor)
	var air = preload("res://scripts/ambience.gd").new()
	air.name = "Ambience"
	air.setup(sun, _green_ratio())
	world_root.add_child(air)


func _pick_spawn(roads: Array) -> void:
	var best := Vector2(0, 12)
	var best_d := 100000.0
	var best_dir := Vector2(0, -1)
	for road in roads:
		if road.bucket == "path":
			continue
		var pts: Array = road.pts
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var mid := (a + b) * 0.5
			if absf(mid.x) > PLAY_HALF - 30.0 or absf(mid.y) > PLAY_HALF - 30.0:
				continue
			var d := mid.length()
			if d < best_d:
				best_d = d
				best = mid
				best_dir = (b - a).normalized()
	var y := sample_height(best.x, best.y) + 1.2
	spawn = Vector3(best.x, y, best.y)
	spawn_dir = Vector3(best_dir.x, 0, best_dir.y)


func _drape_centerline(raw: Array, bridge: bool) -> Array:
	var dense: Array = []
	if raw.is_empty():
		return dense
	dense.append(raw[0])
	for i in range(raw.size() - 1):
		var a: Vector2 = raw[i]
		var b: Vector2 = raw[i + 1]
		var length := a.distance_to(b)
		var steps := maxi(int(ceil(length / 5.0)), 1)
		for s in range(1, steps + 1):
			dense.append(a.lerp(b, float(s) / float(steps)))
	var lifted: Array = []
	for p in dense:
		var q: Vector2 = p
		lifted.append(sample_height(q.x, q.y))
	if bridge and lifted.size() >= 2:
		var h0: float = lifted[0]
		var h1: float = lifted[lifted.size() - 1]
		for i in lifted.size():
			var t := float(i) / float(maxi(lifted.size() - 1, 1))
			lifted[i] = lerpf(h0, h1, t)
	else:
		for _pass in 2:
			var next: Array = lifted.duplicate()
			for i in range(1, lifted.size() - 1):
				next[i] = float(lifted[i]) * 0.4 + float(lifted[i - 1]) * 0.3 + float(lifted[i + 1]) * 0.3
			lifted = next
	var pts: Array = []
	for i in dense.size():
		var q: Vector2 = dense[i]
		pts.append(Vector3(q.x, float(lifted[i]) + 0.09, q.y))
	return pts


func _append_road(bucket: Dictionary, pts: Array, asphalt_w: float, shoulder_w: float) -> void:
	if pts.size() < 2:
		return
	var cols := 5
	var base: int = int(bucket.verts.size())
	var total: float = asphalt_w + shoulder_w * 2.0
	var offsets: Array = [-total * 0.5, -asphalt_w * 0.5, 0.0, asphalt_w * 0.5, total * 0.5]
	var crowns: Array = [0.0, 0.015, 0.04, 0.015, 0.0]
	var dist := 0.0
	for i in pts.size():
		var prev: Vector3 = pts[maxi(i - 1, 0)]
		var next: Vector3 = pts[mini(i + 1, pts.size() - 1)]
		var a: Vector3 = pts[i] - prev
		var b: Vector3 = next - pts[i]
		a.y = 0.0
		b.y = 0.0
		if a.length() < 0.05:
			a = b
		if b.length() < 0.05:
			b = a
		if a.length() < 0.05:
			a = Vector3.RIGHT
		a = a.normalized()
		b = b.normalized()
		var side := Vector3(-(a.z + b.z), 0.0, a.x + b.x)
		if side.length() < 0.001:
			side = Vector3(-a.z, 0.0, a.x)
		side = side.normalized()
		var ref := Vector3(-a.z, 0.0, a.x)
		var miter: float = clampf(1.0 / maxf(side.dot(ref), 0.5), 1.0, 1.7)
		side *= miter
		if i > 0:
			dist += Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length()
		for c in cols:
			var at: Vector3 = pts[i] + side * float(offsets[c])
			at.y += float(crowns[c])
			bucket.verts.append(at)
			bucket.uvs.append(Vector2(float(c) / float(cols - 1), dist))
	for i in range(pts.size() - 1):
		var row: int = base + i * cols
		for c in cols - 1:
			var i0: int = row + c
			bucket.idx.append_array(PackedInt32Array([i0, i0 + cols, i0 + 1, i0 + 1, i0 + cols, i0 + cols + 1]))


func _append_strip(bucket: Dictionary, pts: Array, width: float) -> void:
	if pts.size() < 2:
		return
	var base: int = int(bucket.verts.size())
	var dist := 0.0
	for i in pts.size():
		var prev: Vector3 = pts[maxi(i - 1, 0)]
		var next: Vector3 = pts[mini(i + 1, pts.size() - 1)]
		var a: Vector3 = pts[i] - prev
		var b: Vector3 = next - pts[i]
		a.y = 0.0
		b.y = 0.0
		if a.length() < 0.05:
			a = b
		if b.length() < 0.05:
			b = a
		if a.length() < 0.05:
			a = Vector3.RIGHT
		a = a.normalized()
		b = b.normalized()
		var n := Vector3(-(a.z + b.z), 0, a.x + b.x)
		if n.length() < 0.001:
			n = Vector3(-a.z, 0, a.x)
		n = n.normalized()
		var side := Vector3(-a.z, 0, a.x)
		var miter := clampf(1.0 / max(n.dot(side), 0.45), 1.0, 1.8)
		n *= miter
		if i > 0:
			dist += Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length()
		var half := n * width * 0.5
		bucket.verts.append(pts[i] + half)
		bucket.verts.append(pts[i] - half)
		bucket.uvs.append(Vector2(0.0, dist))
		bucket.uvs.append(Vector2(1.0, dist))
	for i in range(pts.size() - 1):
		var i0: int = base + i * 2
		var nrm: Vector3 = (bucket.verts[i0 + 1] - bucket.verts[i0]).cross(bucket.verts[i0 + 2] - bucket.verts[i0])
		if nrm.y >= 0.0:
			bucket.idx.append_array(PackedInt32Array([i0, i0 + 1, i0 + 2, i0 + 1, i0 + 3, i0 + 2]))
		else:
			bucket.idx.append_array(PackedInt32Array([i0, i0 + 2, i0 + 1, i0 + 1, i0 + 2, i0 + 3]))


func _ribbon_mesh(pts: Array, width: float, tint: Color) -> ArrayMesh:
	var bucket := {"verts": PackedVector3Array(), "uvs": PackedVector2Array(), "idx": PackedInt32Array()}
	_append_strip(bucket, pts, width)
	if bucket.idx.is_empty():
		return null
	var colors := PackedColorArray()
	colors.resize(bucket.verts.size())
	colors.fill(tint)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = bucket.verts
	arrays[Mesh.ARRAY_TEX_UV] = bucket.uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = bucket.idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var st := SurfaceTool.new()
	st.create_from(mesh, 0)
	st.generate_normals()
	return st.commit()


func _load_nature() -> Dictionary:
	var out := {}
	var files := {
		"fir": "res://assets/nature/fir_tree_01_0.glb",
		"pine": "res://assets/nature/pine_tree_01_0.glb",
		"broadleaf": "res://assets/nature/searsia_burchellii_0.glb",
		"shrub": "res://assets/nature/shrub_01_0.glb",
		"boulder": "res://assets/nature/boulder_01_0.glb",
		"dead": "res://assets/nature/dead_tree_trunk_0.glb",
		"grass": "res://assets/nature/grass_medium_01_0.glb",
		"sapling": "res://assets/nature/pine_sapling_medium_0.glb",
	}
	for key in files.keys():
		var path: String = files[key]
		var packed: PackedScene = _load_packed(path)
		if packed != null:
			out[key] = packed
			print("Loaded ", key)
	return out


func _load_packed(path: String) -> PackedScene:
	if ResourceLoader.exists(path):
		var imported = load(path)
		if imported is PackedScene:
			return imported
	var abs_path := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(abs_path):
		return null
	var gltf := GLTFDocument.new()
	var state := GLTFState.new()
	if gltf.append_from_file(abs_path, state) != OK:
		push_warning("Could not read %s" % path)
		return null
	var generated := gltf.generate_scene(state)
	if generated == null:
		return null
	_prepare_foliage(generated)
	var packed := PackedScene.new()
	if packed.pack(generated) != OK:
		return null
	return packed


func _prepare_foliage(root: Node) -> void:
	var meshes: Array = []
	if root is MeshInstance3D:
		meshes.append(root)
	meshes.append_array(root.find_children("*", "MeshInstance3D", true, false))
	for node in meshes:
		var mesh_node := node as MeshInstance3D
		var mesh := mesh_node.mesh
		if mesh == null:
			continue
		for surface in mesh.get_surface_count():
			var mat := mesh.surface_get_material(surface)
			if mat is StandardMaterial3D:
				var std := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				if std.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
					std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
					std.alpha_scissor_threshold = 0.06
					std.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
					std.cull_mode = BaseMaterial3D.CULL_DISABLED
				std.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				mesh.surface_set_material(surface, std)


func _spawn_tree(parent: Node3D, nature: Dictionary, p: Vector2, rng: RandomNumberGenerator, green: float) -> void:
	var y := sample_height(p.x, p.y)
	var keys: Array = []
	if green < 0.12:
		keys = ["dead", "sapling", "shrub"]
	elif green < 0.28:
		keys = ["broadleaf", "sapling", "pine"]
	else:
		keys = ["fir", "pine", "broadleaf", "sapling"]
	var key := ""
	for candidate in keys:
		if nature.has(candidate):
			if rng.randf() < 0.72 or key == "":
				key = candidate
	if key != "" and rng.randf() < 0.62:
		var node := (nature[key] as PackedScene).instantiate()
		_mute_physics(node)
		parent.add_child(node)
		var h := _node_height(node)
		var target := rng.randf_range(7.0, 14.0)
		if key in ["sapling", "shrub"]:
			target = rng.randf_range(1.6, 3.4)
		if h > 0.2:
			var s := target / h
			node.scale = Vector3.ONE * s
		node.position = Vector3(p.x, y, p.y)
		node.rotation.y = rng.randf() * TAU
		_trunk_body(parent, Vector3(p.x, y + target * 0.25, p.y), 0.22, target * 0.45)
		return
	var proto := _procedural_tree(green > 0.2, rng)
	proto.position = Vector3(p.x, y, p.y)
	proto.rotation.y = rng.randf() * TAU
	proto.scale = Vector3.ONE * rng.randf_range(0.85, 1.25)
	parent.add_child(proto)


func _spawn_shrub(parent: Node3D, nature: Dictionary, p: Vector2, rng: RandomNumberGenerator, green: float) -> void:
	var y := sample_height(p.x, p.y)
	if nature.has("shrub") and rng.randf() < 0.7:
		var node := (nature.shrub as PackedScene).instantiate()
		_mute_physics(node)
		parent.add_child(node)
		var h := _node_height(node)
		var target := rng.randf_range(0.7, 1.5)
		if h > 0.05:
			node.scale = Vector3.ONE * (target / h)
		node.position = Vector3(p.x, y, p.y)
		node.rotation.y = rng.randf() * TAU
		return
	var bush := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = rng.randf_range(0.45, 0.9)
	mesh.height = mesh.radius * 1.6
	mesh.radial_segments = 10
	mesh.rings = 6
	bush.mesh = mesh
	bush.position = Vector3(p.x, y + mesh.height * 0.35, p.y)
	var tint := Color(0.45, 0.42, 0.24) if green < 0.15 else Color(0.28, 0.4, 0.18)
	bush.material_override = lib.tinted("grass", tint)
	parent.add_child(bush)


func _spawn_boulder(parent: Node3D, nature: Dictionary, p: Vector2, rng: RandomNumberGenerator) -> void:
	var y := sample_height(p.x, p.y)
	if nature.has("boulder") and rng.randf() < 0.8:
		var node := (nature.boulder as PackedScene).instantiate()
		_mute_physics(node)
		parent.add_child(node)
		var h := _node_height(node)
		var target := rng.randf_range(0.8, 2.2)
		if h > 0.05:
			node.scale = Vector3.ONE * (target / h)
		node.position = Vector3(p.x, y, p.y)
		node.rotation.y = rng.randf() * TAU
		return
	var rock := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = rng.randf_range(0.4, 1.1)
	mesh.height = mesh.radius * 1.4
	rock.mesh = mesh
	rock.position = Vector3(p.x, y + mesh.radius * 0.4, p.y)
	rock.material_override = lib.get_shared("rock")
	parent.add_child(rock)


func _scatter_grass(parent: Node3D, blocked: PackedByteArray, rng: RandomNumberGenerator, green: float) -> void:
	var count := int(round(lerpf(200.0, 1400.0, clampf(green * 1.3, 0.0, 1.0))))
	if count < 40:
		return
	var mesh := _grass_mesh()
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = mesh
	multi.instance_count = count
	var placed := 0
	var attempts := 0
	while placed < count and attempts < count * 6:
		attempts += 1
		var p := Vector2(rng.randf_range(-PLAY_HALF, PLAY_HALF), rng.randf_range(-PLAY_HALF, PLAY_HALF))
		if _blocked(blocked, p.x, p.y):
			continue
		if _slope_at(p.x, p.y) > 0.5:
			continue
		var y := sample_height(p.x, p.y)
		var s := rng.randf_range(0.75, 1.35)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s))
		multi.set_instance_transform(placed, Transform3D(basis, Vector3(p.x, y, p.y)))
		multi.set_instance_color(placed, Color(rng.randf_range(0.75, 1.05), rng.randf_range(0.85, 1.1), rng.randf_range(0.7, 0.95)))
		placed += 1
	if placed < count:
		multi.visible_instance_count = placed
	var node := MultiMeshInstance3D.new()
	node.multimesh = multi
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/foliage.gdshader")
	mat.set_shader_parameter("atlas", lib.make_grass_atlas())
	mat.set_shader_parameter("tint", Color(0.75, 0.82, 0.55) if green > 0.15 else Color(0.72, 0.68, 0.4))
	mat.set_shader_parameter("wind", 0.16)
	node.material_override = mat
	parent.add_child(node)


func _procedural_tree(broadleaf: bool, rng: RandomNumberGenerator) -> Node3D:
	var node := Node3D.new()
	var trunk := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.1
	cyl.bottom_radius = 0.26
	cyl.height = 4.2
	trunk.mesh = cyl
	trunk.position.y = 2.1
	trunk.material_override = lib.get_shared("bark")
	node.add_child(trunk)
	var leaf: Material = lib.tinted("grass", Color(rng.randf_range(0.25, 0.4), rng.randf_range(0.38, 0.55), rng.randf_range(0.14, 0.22)))
	if broadleaf:
		for i in 3:
			var sphere := SphereMesh.new()
			sphere.radius = rng.randf_range(1.1, 1.8)
			sphere.height = sphere.radius * 1.7
			sphere.radial_segments = 12
			sphere.rings = 8
			var crown := MeshInstance3D.new()
			crown.mesh = sphere
			crown.material_override = leaf
			crown.position = Vector3(rng.randf_range(-0.4, 0.4), 4.3 + float(i) * 0.7, rng.randf_range(-0.4, 0.4))
			node.add_child(crown)
	else:
		for i in 3:
			var cone := CylinderMesh.new()
			cone.top_radius = 0.02
			cone.bottom_radius = 1.8 - float(i) * 0.4
			cone.height = 2.2
			var crown := MeshInstance3D.new()
			crown.mesh = cone
			crown.material_override = leaf
			crown.position.y = 3.4 + float(i) * 1.35
			node.add_child(crown)
	return node


func _grass_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for rot in [0.0, PI * 0.5]:
		var basis := Basis(Vector3.UP, rot)
		var hw := 0.42
		var h := 0.78
		var corners := [
			[basis * Vector3(-hw, 0, 0), Vector2(0, 0)],
			[basis * Vector3(hw, 0, 0), Vector2(1, 0)],
			[basis * Vector3(hw, h, 0), Vector2(1, 1)],
			[basis * Vector3(-hw, h, 0), Vector2(0, 1)],
		]
		for tri in [[0, 1, 2], [0, 2, 3]]:
			for idx in tri:
				st.set_uv(corners[idx][1])
				st.add_vertex(corners[idx][0])
	st.generate_normals()
	return st.commit()


func _add_bounds() -> void:
	var body := StaticBody3D.new()
	body.name = "PlayBounds"
	body.collision_layer = 1
	var s := PLAY_HALF - 2.0
	var h := 30.0
	var thick := 4.0
	for spec in [
		[Vector3(0, h * 0.5, -s), Vector3(s * 2.0, h, thick)],
		[Vector3(0, h * 0.5, s), Vector3(s * 2.0, h, thick)],
		[Vector3(-s, h * 0.5, 0), Vector3(thick, h, s * 2.0)],
		[Vector3(s, h * 0.5, 0), Vector3(thick, h, s * 2.0)],
	]:
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = spec[1]
		col.shape = shape
		col.position = spec[0]
		body.add_child(col)
	world_root.add_child(body)


func _classify(tags: Dictionary, area: float, id: int) -> String:
	var b := str(tags.get("building", "yes")).to_lower()
	var amenity := str(tags.get("amenity", "")).to_lower()
	if amenity == "fuel" or b == "fuel":
		return "gas"
	if b in ["warehouse", "industrial", "storage"]:
		return "warehouse"
	if b in ["factory", "manufacture"]:
		return "factory"
	if b in ["barn", "farm_auxiliary", "stable", "cowshed"]:
		return "barn"
	if b in ["church", "chapel", "cathedral"]:
		return "chapel"
	if b in ["retail", "commercial", "supermarket", "shop", "kiosk"]:
		return "store"
	if b in ["garage", "garages", "carport"]:
		return "garage" if area > 26.0 else "shed"
	if b in ["shed", "hut", "cabin", "service", "ger", "roof"]:
		return "shed"
	if b in ["apartments", "dormitory"] or area > 560.0:
		return "apartment"
	if area > 1600.0:
		return "warehouse"
	if area > 900.0:
		return "factory"
	if area < 26.0:
		return "shed"
	if area < 55.0 and b == "yes":
		return "garage" if (id % 2 == 0) else "shed"
	var variants := ["farmhouse", "craftsman", "colonial", "cottage", "ranch"]
	return variants[posmod(id, variants.size())]


func _frame_from_poly(poly: PackedVector2Array) -> Dictionary:
	var best_len := 0.0
	var best_dir := Vector2.RIGHT
	for i in poly.size():
		var edge: Vector2 = poly[(i + 1) % poly.size()] - poly[i]
		if edge.length() > best_len:
			best_len = edge.length()
			best_dir = edge.normalized()
	var x_axis := Vector3(best_dir.x, 0, best_dir.y)
	var z_axis := Vector3(-best_dir.y, 0, best_dir.x)
	var min_x := 100000.0
	var max_x := -100000.0
	var min_z := 100000.0
	var max_z := -100000.0
	for p in poly:
		var world := Vector3(p.x, 0, p.y)
		var px := world.dot(x_axis)
		var pz := world.dot(z_axis)
		min_x = min(min_x, px)
		max_x = max(max_x, px)
		min_z = min(min_z, pz)
		max_z = max(max_z, pz)
	var center := x_axis * ((min_x + max_x) * 0.5) + z_axis * ((min_z + max_z) * 0.5)
	return {
		"basis": Basis(x_axis, Vector3.UP, z_axis),
		"size": Vector2(max(max_x - min_x, 1.0), max(max_z - min_z, 1.0)),
		"center": Vector2(center.x, center.z),
	}


func _rect_poly(center: Vector3, basis: Basis, size: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	for corner in [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz)]:
		var world: Vector3 = basis * corner + center
		pts.append(Vector2(world.x, world.z))
	return pts


func _median_in_poly(poly: PackedVector2Array) -> float:
	var values: Array = []
	var bounds := _poly_bounds(poly)
	var ix0 := clampi(_ix(bounds.position.x), 0, GRID_N - 1)
	var ix1 := clampi(_ix(bounds.position.x + bounds.size.x), 0, GRID_N - 1)
	var iz0 := clampi(_iz(bounds.position.y), 0, GRID_N - 1)
	var iz1 := clampi(_iz(bounds.position.y + bounds.size.y), 0, GRID_N - 1)
	for z in range(iz0, iz1 + 1):
		for x in range(ix0, ix1 + 1):
			var p := _xz(x, z)
			if Geometry2D.is_point_in_polygon(p, poly):
				values.append(heights[z * GRID_N + x])
	if values.is_empty():
		var c := _poly_center(poly)
		return sample_height(c.x, c.y)
	values.sort()
	return float(values[values.size() / 2])


func _water_tint(poly: PackedVector2Array) -> Color:
	var acc := Color(0, 0, 0, 1)
	var n := 0
	for i in range(0, poly.size(), maxi(int(poly.size() / 8), 1)):
		var p: Vector2 = poly[i]
		var ll: Vector2 = geo.to_latlon(p.x, p.y)
		acc += geo.sample_rgb(sat_image, sat_bounds, ll.x, ll.y)
		n += 1
		if n >= 8:
			break
	if n == 0:
		return Color(0.07, 0.15, 0.16)
	acc /= float(n)
	return Color(acc.r * 0.28 + 0.02, acc.g * 0.32 + 0.05, acc.b * 0.3 + 0.05)


func _green_ratio() -> float:
	var green := 0
	var n := 0
	var w := sat_image.get_width()
	var h := sat_image.get_height()
	for y in range(0, h, 10):
		for x in range(0, w, 10):
			var c := sat_image.get_pixel(x, y)
			n += 1
			if c.g > c.r * 1.04 and c.g > c.b and c.g > 0.13:
				green += 1
	if n == 0:
		return 0.3
	return float(green) / float(n)


func _load_res(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is Texture2D:
			return res
	var image := Image.new()
	var abs_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(abs_path) and image.load(abs_path) == OK:
		if not image.has_mipmaps():
			image.generate_mipmaps()
		return ImageTexture.create_from_image(image)
	var fallback := Image.create(4, 4, false, Image.FORMAT_RGB8)
	fallback.fill(Color(0.45, 0.4, 0.32))
	return ImageTexture.create_from_image(fallback)


func _tex(key: String, fallback: Color, normal_map := false) -> Texture2D:
	var found: Texture2D = lib.textures.get(key)
	if found != null:
		return found
	var image := Image.create(4, 4, false, Image.FORMAT_RGB8)
	image.fill(fallback if not normal_map else Color(0.5, 0.5, 1.0))
	return ImageTexture.create_from_image(image)


func _sample(data: PackedFloat32Array, x: float, z: float) -> float:
	var fx := (x + MAP_HALF) / step
	var fz := (z + MAP_HALF) / step
	fx = clampf(fx, 0.0, float(GRID_N - 1) - 0.001)
	fz = clampf(fz, 0.0, float(GRID_N - 1) - 0.001)
	var x0 := int(floor(fx))
	var z0 := int(floor(fz))
	var x1 := mini(x0 + 1, GRID_N - 1)
	var z1 := mini(z0 + 1, GRID_N - 1)
	var tx := fx - float(x0)
	var tz := fz - float(z0)
	var h00 := data[z0 * GRID_N + x0]
	var h10 := data[z0 * GRID_N + x1]
	var h01 := data[z1 * GRID_N + x0]
	var h11 := data[z1 * GRID_N + x1]
	if tz >= tx:
		return h00 + (h11 - h01) * tx + (h01 - h00) * tz
	return h00 + (h10 - h00) * tx + (h11 - h10) * tz


func _slope_at(x: float, z: float) -> float:
	var e := 2.5
	var h := sample_height(x, z)
	var dx := sample_height(x + e, z) - h
	var dz := sample_height(x, z + e) - h
	return clampf(Vector2(dx, dz).length() / e, 0.0, 1.0)


func _ix(x: float) -> int:
	return int(round((x + MAP_HALF) / step))


func _iz(z: float) -> int:
	return int(round((z + MAP_HALF) / step))


func _xz(ix: int, iz: int) -> Vector2:
	return Vector2(-MAP_HALF + float(ix) * step, -MAP_HALF + float(iz) * step)


func _poly_bounds(poly: PackedVector2Array) -> Rect2:
	var min_x := 100000.0
	var min_y := 100000.0
	var max_x := -100000.0
	var max_y := -100000.0
	for p in poly:
		min_x = min(min_x, p.x)
		min_y = min(min_y, p.y)
		max_x = max(max_x, p.x)
		max_y = max(max_y, p.y)
	return Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))


func _poly_center(poly: PackedVector2Array) -> Vector2:
	var acc := Vector2.ZERO
	if poly.is_empty():
		return acc
	for p in poly:
		acc += p
	return acc / float(poly.size())


func _poly_area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p: Vector2 = poly[i]
		var q: Vector2 = poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return absf(a) * 0.5


func _point_in_water(p: Vector2, water: Array) -> bool:
	for body in water:
		if Geometry2D.is_point_in_polygon(p, body.poly):
			return true
	return false


func _in_polys(p: Vector2, polys: Array) -> bool:
	for poly in polys:
		if Geometry2D.is_point_in_polygon(p, poly):
			return true
	return false


func _dist_to_poly(p: Vector2, poly: PackedVector2Array) -> float:
	var best := 100000.0
	for i in poly.size():
		best = min(best, _dist_to_seg(p, poly[i], poly[(i + 1) % poly.size()]))
	return best


func _dist_to_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var denom := ab.length_squared()
	if denom < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / denom, 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _ensure_ccw(poly: PackedVector2Array) -> PackedVector2Array:
	var a := 0.0
	for i in poly.size():
		var p: Vector2 = poly[i]
		var q: Vector2 = poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	if a < 0.0:
		return _reversed(poly)
	return poly


func _reversed(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(poly.size() - 1, -1, -1):
		out.append(poly[i])
	return out


func _stitch(lines: Array) -> Array:
	var unused: Array = lines.duplicate()
	var rings: Array = []
	while not unused.is_empty():
		var chain: PackedVector2Array = unused.pop_back()
		var changed := true
		while changed:
			changed = false
			var i := 0
			while i < unused.size():
				var line: PackedVector2Array = unused[i]
				if chain[chain.size() - 1].distance_to(line[0]) < 2.0:
					for k in range(1, line.size()):
						chain.append(line[k])
					unused.remove_at(i)
					changed = true
				elif chain[chain.size() - 1].distance_to(line[line.size() - 1]) < 2.0:
					for k in range(line.size() - 2, -1, -1):
						chain.append(line[k])
					unused.remove_at(i)
					changed = true
				else:
					i += 1
		if chain.size() >= 3:
			rings.append(chain)
	return rings


func _mark(blocked: PackedByteArray, x: float, z: float, radius: float) -> void:
	var ix0 := clampi(_ix(x - radius), 0, GRID_N - 1)
	var ix1 := clampi(_ix(x + radius), 0, GRID_N - 1)
	var iz0 := clampi(_iz(z - radius), 0, GRID_N - 1)
	var iz1 := clampi(_iz(z + radius), 0, GRID_N - 1)
	for zz in range(iz0, iz1 + 1):
		for xx in range(ix0, ix1 + 1):
			blocked[zz * GRID_N + xx] = 1


func _mark_poly(blocked: PackedByteArray, poly: PackedVector2Array, pad: float) -> void:
	var bounds := _poly_bounds(poly).grow(pad)
	var ix0 := clampi(_ix(bounds.position.x), 0, GRID_N - 1)
	var ix1 := clampi(_ix(bounds.position.x + bounds.size.x), 0, GRID_N - 1)
	var iz0 := clampi(_iz(bounds.position.y), 0, GRID_N - 1)
	var iz1 := clampi(_iz(bounds.position.y + bounds.size.y), 0, GRID_N - 1)
	for z in range(iz0, iz1 + 1):
		for x in range(ix0, ix1 + 1):
			var p := _xz(x, z)
			if Geometry2D.is_point_in_polygon(p, poly) or _dist_to_poly(p, poly) < pad:
				blocked[z * GRID_N + x] = 1


func _blocked(blocked: PackedByteArray, x: float, z: float) -> bool:
	var ix := clampi(_ix(x), 0, GRID_N - 1)
	var iz := clampi(_iz(z), 0, GRID_N - 1)
	return blocked[iz * GRID_N + ix] != 0


func _mute_physics(node: Node) -> void:
	if node is CollisionObject3D:
		node.collision_layer = 0
		node.collision_mask = 0
	for child in node.find_children("*", "CollisionObject3D", true, false):
		child.collision_layer = 0
		child.collision_mask = 0


func _node_height(node: Node3D) -> float:
	var top := 0.0
	for mesh_node in node.find_children("*", "MeshInstance3D", true, false):
		var aabb: AABB = mesh_node.get_aabb()
		var local: Transform3D = node.global_transform.affine_inverse() * mesh_node.global_transform
		var corner: Vector3 = local * (aabb.position + Vector3(0, aabb.size.y, 0))
		top = max(top, corner.y)
	return top


func _trunk_body(parent: Node3D, at: Vector3, radius: float, height: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = at
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	col.shape = shape
	body.add_child(col)
	parent.add_child(body)
