extends Node

const MAP_HALF := 560.0
const ELEV_ZOOM := 15
const IMAGE_ZOOM := 17
const USER_AGENT := "AshenCounty/1.0 (educational geographic survival-horror; local play)"

var origin_lat := 0.0
var origin_lon := 0.0
var meters_per_lat := 111320.0
var meters_per_lon := 111320.0
var active_zip := ""
var http: HTTPRequest

func _ready() -> void:
	http = HTTPRequest.new()
	http.timeout = 45.0
	http.accept_gzip = true
	add_child(http)


func load_region(zip_code: String, progress: Callable) -> Dictionary:
	active_zip = zip_code
	var cached := _read_cache(zip_code)
	if not cached.is_empty():
		progress.call("Using saved map data for %s" % zip_code, 0.2)
		await get_tree().process_frame
		return cached
	progress.call("Looking up ZIP code %s" % zip_code, 0.04)
	await get_tree().process_frame
	var place := await _geocode(zip_code)
	if not place.get("ok", false):
		return place
	origin_lat = place.lat
	origin_lon = place.lon
	meters_per_lon = 111320.0 * cos(deg_to_rad(origin_lat))
	var bounds := _bounds(MAP_HALF + 40.0)
	progress.call("Reading elevation for %s, %s" % [place.place, place.state], 0.1)
	await get_tree().process_frame
	var elev := await _fetch_elevation(bounds, progress)
	if not elev.get("ok", false):
		return elev
	progress.call("Downloading USGS aerial imagery", 0.38)
	await get_tree().process_frame
	var imagery := await _fetch_imagery(bounds, progress)
	if not imagery.get("ok", false):
		return imagery
	progress.call("Downloading roads, water, and buildings", 0.62)
	await get_tree().process_frame
	var osm := await _fetch_osm(bounds)
	if not osm.get("ok", false):
		var smaller := _bounds(340.0)
		progress.call("Map area was dense. Trying a closer neighborhood.", 0.66)
		await get_tree().process_frame
		osm = await _fetch_osm(smaller)
		if not osm.get("ok", false):
			return osm
	var region := {
		"ok": true,
		"zip": zip_code,
		"place": place.place,
		"state": place.state,
		"lat": origin_lat,
		"lon": origin_lon,
		"meters_per_lat": meters_per_lat,
		"meters_per_lon": meters_per_lon,
		"elev_image": elev.image,
		"elev_bounds": elev.bounds,
		"sat_image": imagery.image,
		"sat_bounds": imagery.bounds,
		"osm_xml": osm.xml,
	}
	_write_cache(zip_code, region)
	return region


func to_xz(lat: float, lon: float) -> Vector2:
	return Vector2((lon - origin_lon) * meters_per_lon, -(lat - origin_lat) * meters_per_lat)


func to_latlon(x: float, z: float) -> Vector2:
	return Vector2(origin_lat - z / meters_per_lat, origin_lon + x / meters_per_lon)


func _bounds(half_m: float) -> Dictionary:
	var dlat := half_m / meters_per_lat
	var dlon := half_m / meters_per_lon
	return {
		"south": origin_lat - dlat,
		"north": origin_lat + dlat,
		"west": origin_lon - dlon,
		"east": origin_lon + dlon,
	}


func _geocode(zip_code: String) -> Dictionary:
	var url := "https://api.zippopotam.us/us/" + zip_code
	var response := await _http_get(url)
	if not response.ok:
		return {"ok": false, "error": "Could not find ZIP code %s. Check the five digits and your connection." % zip_code}
	var parsed: Variant = JSON.parse_string(response.text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "ZIP lookup returned an unexpected result."}
	var places: Array = parsed.get("places", [])
	if places.is_empty():
		return {"ok": false, "error": "No mapped place was found for ZIP %s." % zip_code}
	var first: Dictionary = places[0]
	return {
		"ok": true,
		"lat": float(first.get("latitude", "0")),
		"lon": float(first.get("longitude", "0")),
		"place": str(first.get("place name", "Unknown place")),
		"state": str(first.get("state", "")),
	}


func _fetch_elevation(bounds: Dictionary, progress: Callable) -> Dictionary:
	var tiles := _tile_range(bounds, ELEV_ZOOM)
	if tiles.count > 16:
		return {"ok": false, "error": "Elevation coverage was unexpectedly large."}
	var atlas := Image.create(tiles.nx * 256, tiles.ny * 256, false, Image.FORMAT_RGB8)
	var got := 0
	for ty in range(tiles.y0, tiles.y1 + 1):
		for tx in range(tiles.x0, tiles.x1 + 1):
			var url := "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/%d/%d/%d.png" % [ELEV_ZOOM, tx, ty]
			var response := await _http_get(url, PackedStringArray(), false)
			got += 1
			progress.call("Elevation tiles %d / %d" % [got, tiles.count], 0.1 + 0.22 * float(got) / float(tiles.count))
			await get_tree().process_frame
			if not response.ok:
				return {"ok": false, "error": "Elevation tile failed (%s)." % response.code}
			var tile := Image.new()
			if tile.load_png_from_buffer(response.body) != OK:
				return {"ok": false, "error": "Elevation tile could not be decoded."}
			if tile.get_format() != Image.FORMAT_RGB8:
				tile.convert(Image.FORMAT_RGB8)
			atlas.blit_rect(tile, Rect2i(0, 0, tile.get_width(), tile.get_height()), Vector2i((tx - tiles.x0) * 256, (ty - tiles.y0) * 256))
	return {"ok": true, "image": atlas, "bounds": _pixel_bounds(tiles, ELEV_ZOOM)}


func fetch_wide_elevation() -> Dictionary:
	if active_zip == "":
		return {"ok": false}
	var base := _cache_base(active_zip)
	var png_path := base + "/elev_far.png"
	var meta_path := base + "/far.json"
	if FileAccess.file_exists(png_path) and FileAccess.file_exists(meta_path):
		var cached := Image.new()
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
		if cached.load(ProjectSettings.globalize_path(png_path)) == OK and parsed is Dictionary:
			var meta: Dictionary = parsed
			return {"ok": true, "image": cached, "bounds": meta.bounds}
	var bounds := _bounds(16000.0)
	var zoom := 12
	var tiles := _tile_range(bounds, zoom)
	if int(tiles.count) > 36:
		zoom = 11
		tiles = _tile_range(bounds, zoom)
	if int(tiles.count) > 48:
		return {"ok": false}
	var atlas := Image.create(int(tiles.nx) * 256, int(tiles.ny) * 256, false, Image.FORMAT_RGB8)
	var x0 := int(tiles.x0)
	var y0 := int(tiles.y0)
	for ty in range(y0, int(tiles.y1) + 1):
		for tx in range(x0, int(tiles.x1) + 1):
			var url := "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/%d/%d/%d.png" % [zoom, tx, ty]
			var response: Dictionary = await _http_get(url, PackedStringArray(), false)
			if not response.ok:
				return {"ok": false}
			var tile := Image.new()
			if tile.load_png_from_buffer(response.body) != OK:
				return {"ok": false}
			if tile.get_format() != Image.FORMAT_RGB8:
				tile.convert(Image.FORMAT_RGB8)
			atlas.blit_rect(tile, Rect2i(0, 0, tile.get_width(), tile.get_height()), Vector2i((tx - x0) * 256, (ty - y0) * 256))
			await get_tree().process_frame
	var far_bounds := _pixel_bounds(tiles, zoom)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base))
	atlas.save_png(ProjectSettings.globalize_path(png_path))
	var meta_file := FileAccess.open(meta_path, FileAccess.WRITE)
	if meta_file:
		meta_file.store_string(JSON.stringify({"bounds": far_bounds}))
		meta_file.close()
	return {"ok": true, "image": atlas, "bounds": far_bounds}


func _fetch_imagery(bounds: Dictionary, progress: Callable) -> Dictionary:
	var zoom := IMAGE_ZOOM
	var tiles := _tile_range(bounds, zoom)
	if tiles.count > 25:
		zoom = 16
		tiles = _tile_range(bounds, zoom)
	var atlas := Image.create(tiles.nx * 256, tiles.ny * 256, false, Image.FORMAT_RGB8)
	var got := 0
	for ty in range(tiles.y0, tiles.y1 + 1):
		for tx in range(tiles.x0, tiles.x1 + 1):
			var url := "https://basemap.nationalmap.gov/arcgis/rest/services/USGSImageryOnly/MapServer/tile/%d/%d/%d" % [zoom, ty, tx]
			var response := await _http_get(url, PackedStringArray(), false)
			got += 1
			progress.call("Aerial imagery %d / %d" % [got, tiles.count], 0.36 + 0.22 * float(got) / float(tiles.count))
			await get_tree().process_frame
			if not response.ok:
				return {"ok": false, "error": "USGS imagery tile failed (%s)." % response.code}
			var tile := Image.new()
			var decoded := tile.load_jpg_from_buffer(response.body)
			if decoded != OK:
				decoded = tile.load_png_from_buffer(response.body)
			if decoded != OK:
				return {"ok": false, "error": "USGS imagery tile could not be decoded."}
			if tile.get_format() != Image.FORMAT_RGB8:
				tile.convert(Image.FORMAT_RGB8)
			if tile.get_width() != 256 or tile.get_height() != 256:
				tile.resize(256, 256, Image.INTERPOLATE_LANCZOS)
			atlas.blit_rect(tile, Rect2i(0, 0, 256, 256), Vector2i((tx - tiles.x0) * 256, (ty - tiles.y0) * 256))
	return {"ok": true, "image": atlas, "bounds": _pixel_bounds(tiles, zoom)}


func _fetch_osm(bounds: Dictionary) -> Dictionary:
	var url := "https://api.openstreetmap.org/api/0.6/map?bbox=%s,%s,%s,%s" % [
		_num(bounds.west), _num(bounds.south), _num(bounds.east), _num(bounds.north)
	]
	var headers := PackedStringArray(["User-Agent: " + USER_AGENT, "Accept: application/xml"])
	var response := await _http_get(url, headers)
	if not response.ok:
		var detail: String = str(response.text).substr(0, 180)
		return {"ok": false, "error": "OpenStreetMap did not return this area (%s). %s" % [response.code, detail]}
	if response.text.find("<osm") == -1:
		return {"ok": false, "error": "OpenStreetMap returned an unexpected document."}
	return {"ok": true, "xml": response.text}


func parse_osm(xml_text: String) -> Dictionary:
	var nodes := {}
	var ways: Array = []
	var relations: Array = []
	var cur_way: Dictionary = {}
	var cur_rel: Dictionary = {}
	var in_way := false
	var in_rel := false
	var parser := XMLParser.new()
	if parser.open_buffer(xml_text.to_utf8_buffer()) != OK:
		return {"ways": [], "relations": [], "nodes": {}}
	while parser.read() == OK:
		var typ := parser.get_node_type()
		if typ == XMLParser.NODE_ELEMENT:
			var name := parser.get_node_name()
			if name == "node":
				var id := _attr(parser, "id")
				var lat := _attr(parser, "lat")
				var lon := _attr(parser, "lon")
				if id != "" and lat != "" and lon != "":
					nodes[id] = Vector2(float(lon), float(lat))
			elif name == "way":
				in_way = true
				in_rel = false
				cur_way = {"id": int(_attr(parser, "id")), "refs": [], "tags": {}}
			elif name == "relation":
				in_rel = true
				in_way = false
				cur_rel = {"id": int(_attr(parser, "id")), "members": [], "tags": {}}
			elif name == "nd" and in_way:
				cur_way.refs.append(_attr(parser, "ref"))
			elif name == "tag":
				var key := _attr(parser, "k")
				var value := _attr(parser, "v")
				if in_way:
					cur_way.tags[key] = value
				elif in_rel:
					cur_rel.tags[key] = value
			elif name == "member" and in_rel:
				cur_rel.members.append({
					"type": _attr(parser, "type"),
					"ref": _attr(parser, "ref"),
					"role": _attr(parser, "role"),
				})
		elif typ == XMLParser.NODE_ELEMENT_END:
			var end_name := parser.get_node_name()
			if end_name == "way" and in_way:
				ways.append(cur_way)
				in_way = false
			elif end_name == "relation" and in_rel:
				relations.append(cur_rel)
				in_rel = false
	return {"ways": ways, "relations": relations, "nodes": nodes}


func way_points(way: Dictionary, nodes: Dictionary) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for ref in way.refs:
		if nodes.has(ref):
			var lonlat: Vector2 = nodes[ref]
			var xz := to_xz(lonlat.y, lonlat.x)
			if pts.is_empty() or pts[pts.size() - 1].distance_to(xz) > 0.35:
				pts.append(xz)
	return pts


func _tile_range(bounds: Dictionary, zoom: int) -> Dictionary:
	var nw := _tile_f(bounds.west, bounds.north, zoom)
	var se := _tile_f(bounds.east, bounds.south, zoom)
	var x0 := int(floor(nw.x))
	var x1 := int(floor(se.x))
	var y0 := int(floor(nw.y))
	var y1 := int(floor(se.y))
	return {
		"x0": x0, "x1": x1, "y0": y0, "y1": y1,
		"nx": x1 - x0 + 1, "ny": y1 - y0 + 1,
		"count": (x1 - x0 + 1) * (y1 - y0 + 1),
		"zoom": zoom,
	}


func _pixel_bounds(tiles: Dictionary, zoom: int) -> Dictionary:
	var nw := _tile_to_lonlat(tiles.x0, tiles.y0, zoom)
	var se := _tile_to_lonlat(tiles.x1 + 1, tiles.y1 + 1, zoom)
	return {"west": nw.x, "north": nw.y, "east": se.x, "south": se.y}


func _tile_f(lon: float, lat: float, zoom: int) -> Vector2:
	var n := pow(2.0, zoom)
	var xf := (lon + 180.0) / 360.0 * n
	var lat_r := deg_to_rad(lat)
	var yf := (1.0 - _asinh(tan(lat_r)) / PI) / 2.0 * n
	return Vector2(xf, yf)


func _tile_to_lonlat(tx: int, ty: int, zoom: int) -> Vector2:
	var n := pow(2.0, zoom)
	var lon := float(tx) / n * 360.0 - 180.0
	var lat_r := atan(sinh(PI * (1.0 - 2.0 * float(ty) / n)))
	return Vector2(lon, rad_to_deg(lat_r))


func _asinh(v: float) -> float:
	return log(v + sqrt(v * v + 1.0))


func sample_rgb(image: Image, bounds: Dictionary, lat: float, lon: float) -> Color:
	var u: float = (lon - float(bounds.west)) / maxf(float(bounds.east) - float(bounds.west), 0.0000001)
	var v: float = (float(bounds.north) - lat) / maxf(float(bounds.north) - float(bounds.south), 0.0000001)
	var x := clampf(u, 0.0, 0.999) * float(image.get_width() - 1)
	var y := clampf(v, 0.0, 0.999) * float(image.get_height() - 1)
	var x0 := int(floor(x))
	var y0 := int(floor(y))
	var x1 := mini(x0 + 1, image.get_width() - 1)
	var y1 := mini(y0 + 1, image.get_height() - 1)
	var tx := x - float(x0)
	var ty := y - float(y0)
	var c00 := image.get_pixel(x0, y0)
	var c10 := image.get_pixel(x1, y0)
	var c01 := image.get_pixel(x0, y1)
	var c11 := image.get_pixel(x1, y1)
	return c00.lerp(c10, tx).lerp(c01.lerp(c11, tx), ty)


func terrarium_height(color: Color) -> float:
	var r := color.r * 255.0
	var g := color.g * 255.0
	var b := color.b * 255.0
	return (r * 256.0 + g + b / 256.0) - 32768.0


func _http_get(url: String, headers: PackedStringArray = PackedStringArray(), as_text: bool = true) -> Dictionary:
	var err := http.request(url, headers)
	if err != OK:
		return {"ok": false, "code": 0, "body": PackedByteArray(), "text": "request error %s" % err}
	var args: Array = await http.request_completed
	var body: PackedByteArray = args[3]
	var text := body.get_string_from_utf8() if as_text else ""
	var code := int(args[1])
	var ok := int(args[0]) == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300
	return {"ok": ok, "code": code, "body": body, "text": text}


func _attr(parser: XMLParser, key: String) -> String:
	for i in parser.get_attribute_count():
		if parser.get_attribute_name(i) == key:
			return parser.get_attribute_value(i)
	return ""


func _num(v: float) -> String:
	return "%.7f" % v


func _cache_base(zip_code: String) -> String:
	return "user://ashen/%s_v3" % zip_code


func _read_cache(zip_code: String) -> Dictionary:
	var base := _cache_base(zip_code)
	var meta_path := base + "/meta.json"
	if not FileAccess.file_exists(meta_path):
		return {}
	var meta_text := FileAccess.get_file_as_string(meta_path)
	var meta: Variant = JSON.parse_string(meta_text)
	if typeof(meta) != TYPE_DICTIONARY:
		return {}
	if int(meta.get("map_half", 0)) != int(MAP_HALF):
		return {}
	var elev := Image.new()
	var sat := Image.new()
	var elev_path := ProjectSettings.globalize_path(base + "/elev.png")
	var sat_path := ProjectSettings.globalize_path(base + "/sat.jpg")
	var osm_path := base + "/map.osm"
	if elev.load(elev_path) != OK or sat.load(sat_path) != OK or not FileAccess.file_exists(osm_path):
		return {}
	origin_lat = float(meta.lat)
	origin_lon = float(meta.lon)
	meters_per_lat = float(meta.meters_per_lat)
	meters_per_lon = float(meta.meters_per_lon)
	return {
		"ok": true,
		"zip": zip_code,
		"place": meta.place,
		"state": meta.state,
		"lat": origin_lat,
		"lon": origin_lon,
		"meters_per_lat": meters_per_lat,
		"meters_per_lon": meters_per_lon,
		"elev_image": elev,
		"elev_bounds": meta.elev_bounds,
		"sat_image": sat,
		"sat_bounds": meta.sat_bounds,
		"osm_xml": FileAccess.get_file_as_string(osm_path),
		"cached": true,
	}


func _write_cache(zip_code: String, region: Dictionary) -> void:
	var base := _cache_base(zip_code)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base))
	var elev: Image = region.elev_image
	var sat: Image = region.sat_image
	elev.save_png(ProjectSettings.globalize_path(base + "/elev.png"))
	sat.save_jpg(ProjectSettings.globalize_path(base + "/sat.jpg"), 0.86)
	var osm_file := FileAccess.open(base + "/map.osm", FileAccess.WRITE)
	if osm_file:
		osm_file.store_string(region.osm_xml)
		osm_file.close()
	var meta := {
		"map_half": MAP_HALF,
		"lat": region.lat,
		"lon": region.lon,
		"place": region.place,
		"state": region.state,
		"meters_per_lat": region.meters_per_lat,
		"meters_per_lon": region.meters_per_lon,
		"elev_bounds": region.elev_bounds,
		"sat_bounds": region.sat_bounds,
	}
	var meta_file := FileAccess.open(base + "/meta.json", FileAccess.WRITE)
	if meta_file:
		meta_file.store_string(JSON.stringify(meta))
		meta_file.close()
