extends RefCounted

const FLOOR_Y := 0.02

var lib
var root: Node3D
var body: StaticBody3D
var probe := Vector3(0, 1.5, -1.0)
var woodland := false
var seed_val := 0
var footprint := Vector2(8, 6)

func _init(materials) -> void:
	lib = materials


func build(kind: String, parent: Node3D, xform: Transform3D, size := Vector2(8, 6)) -> Dictionary:
	footprint = size
	seed_val = int(absf(xform.origin.x * 13.1 + xform.origin.z * 7.7)) + kind.length() * 101
	root = Node3D.new()
	root.name = kind
	root.transform = xform
	parent.add_child(root)
	body = StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)
	match kind:
		"farmhouse":
			_house(_style_farmhouse())
		"craftsman":
			_house(_style_craftsman())
		"colonial":
			_house(_style_colonial())
		"cottage":
			_house(_style_cottage())
		"ranch":
			_house(_style_ranch())
		"apartment":
			_house(_style_apartment())
		"warehouse":
			_industrial(false)
		"factory":
			_industrial(true)
		"shed":
			_shed()
		"garage":
			_garage()
		"barn":
			_barn()
		"chapel":
			_chapel()
		"store":
			_store()
		"gas":
			_gas()
		_:
			_shed()
	_yard(kind)
	_merge_meshes()
	return {"root": root, "probe": root.global_transform * probe}


func _merge_meshes() -> void:
	var groups := {}
	var order: Array = []
	var inv := root.global_transform.affine_inverse()
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or mi.material_override == null:
			continue
		var xf := inv * mi.global_transform
		for s in mi.mesh.get_surface_count():
			var fmt := -1
			if mi.mesh is ArrayMesh:
				fmt = (mi.mesh as ArrayMesh).surface_get_format(s)
			var key := "%d_%d" % [mi.material_override.get_instance_id(), fmt]
			if not groups.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				groups[key] = {"st": st, "mat": mi.material_override}
				order.append(key)
			groups[key].st.append_from(mi.mesh, s, xf)
		mi.get_parent().remove_child(mi)
		mi.queue_free()
	if order.is_empty():
		return
	var merged := ArrayMesh.new()
	for key in order:
		var group: Dictionary = groups[key]
		var st: SurfaceTool = group.st
		st.set_material(group.mat)
		st.commit(merged)
	var node := MeshInstance3D.new()
	node.name = "Merged"
	node.mesh = merged
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	node.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	root.add_child(node)


func _style_farmhouse() -> Dictionary:
	if woodland:
		return _wood_style("farmhouse")
	return {
		"w": 11.2, "d": 9.0, "stories": 1, "story_h": 3.05,
		"siding": lib.tinted("plaster", Color(0.78, 0.62, 0.42)),
		"trim": lib.tinted("plaster", Color(0.86, 0.74, 0.54)),
		"roof": lib.tinted("concrete", Color(0.55, 0.46, 0.36)),
		"foundation": lib.tinted("concrete", Color(0.48, 0.42, 0.34)),
		"floor": lib.tinted("wood", Color(0.55, 0.42, 0.28)),
		"interior": lib.tinted("plaster", Color(0.7, 0.58, 0.42)),
		"porch": 1.7, "chimney": false, "roof_kind": "flat",
		"stair": Rect2(0, 0, 0, 0),
	}


func _style_craftsman() -> Dictionary:
	if woodland:
		return _wood_style("craftsman")
	return {
		"w": 8.4, "d": 6.2, "stories": 1, "story_h": 2.7,
		"siding": lib.tinted("planks", Color(0.62, 0.52, 0.36)),
		"trim": lib.tinted("planks", Color(0.48, 0.38, 0.26)),
		"roof": lib.tinted("metal", Color(0.46, 0.3, 0.18)),
		"foundation": lib.tinted("concrete", Color(0.42, 0.38, 0.32)),
		"floor": lib.tinted("wood", Color(0.48, 0.36, 0.22)),
		"interior": lib.tinted("planks", Color(0.5, 0.4, 0.28)),
		"porch": 1.4, "chimney": false, "roof_kind": "gable",
		"stair": Rect2(0, 0, 0, 0),
	}


func _style_colonial() -> Dictionary:
	if woodland:
		return _wood_style("colonial")
	return {
		"w": 10.8, "d": 8.2, "stories": 1, "story_h": 3.1,
		"siding": lib.tinted("concrete", Color(0.62, 0.58, 0.5)),
		"trim": lib.tinted("concrete", Color(0.48, 0.44, 0.38)),
		"roof": lib.tinted("concrete", Color(0.5, 0.46, 0.4)),
		"foundation": lib.tinted("concrete", Color(0.4, 0.38, 0.34)),
		"floor": lib.tinted("concrete", Color(0.55, 0.5, 0.44)),
		"interior": lib.tinted("concrete", Color(0.58, 0.54, 0.46)),
		"porch": 0.0, "chimney": false, "roof_kind": "flat",
		"stair": Rect2(0, 0, 0, 0),
	}


func _style_cottage() -> Dictionary:
	return {
		"w": 12.4, "d": 3.6, "stories": 1, "story_h": 2.65,
		"siding": lib.tinted("metal", Color(0.7, 0.66, 0.52)),
		"trim": lib.tinted("metal", Color(0.42, 0.36, 0.28)),
		"roof": lib.tinted("metal", Color(0.55, 0.5, 0.4)),
		"foundation": lib.tinted("concrete", Color(0.4, 0.36, 0.3)),
		"floor": lib.tinted("wood", Color(0.46, 0.34, 0.22)),
		"interior": lib.tinted("planks", Color(0.58, 0.48, 0.34)),
		"porch": 0.9, "chimney": false, "roof_kind": "flat",
		"stair": Rect2(0, 0, 0, 0),
	}


func _style_ranch() -> Dictionary:
	if woodland:
		return _wood_style("ranch")
	return {
		"w": 14.5, "d": 7.4, "stories": 1, "story_h": 2.85,
		"siding": lib.tinted("plaster", Color(0.74, 0.58, 0.4)),
		"trim": lib.tinted("plaster", Color(0.84, 0.7, 0.5)),
		"roof": lib.tinted("concrete", Color(0.5, 0.42, 0.32)),
		"foundation": lib.tinted("concrete", Color(0.46, 0.4, 0.32)),
		"floor": lib.tinted("wood", Color(0.52, 0.4, 0.26)),
		"interior": lib.tinted("plaster", Color(0.68, 0.56, 0.4)),
		"porch": 2.0, "chimney": false, "roof_kind": "flat",
		"stair": Rect2(0, 0, 0, 0),
	}


func _style_apartment() -> Dictionary:
	return {
		"w": 16.0, "d": 11.0, "stories": 3, "story_h": 2.8,
		"siding": lib.tinted("plaster", Color(0.7, 0.56, 0.42)),
		"trim": lib.tinted("concrete", Color(0.5, 0.44, 0.36)),
		"roof": lib.tinted("concrete", Color(0.42, 0.36, 0.28)),
		"foundation": lib.tinted("concrete", Color(0.4, 0.36, 0.3)),
		"floor": lib.tinted("wood", Color(0.5, 0.38, 0.24)),
		"interior": lib.tinted("plaster", Color(0.64, 0.54, 0.4)),
		"porch": 0.0, "chimney": false, "roof_kind": "flat",
		"stair": Rect2(-1.45, -3.05, 2.9, 6.1),
	}


func _house(style: Dictionary) -> void:
	var w: float = style.w
	var d: float = style.d
	var stories: int = style.stories
	var sh: float = style.story_h
	var t := 0.18
	var x0 := -w * 0.5
	var x1 := w * 0.5
	var z0 := -d * 0.5
	var z1 := d * 0.5
	var top := sh * float(stories)
	_box(Vector3(0, FLOOR_Y - 0.12, 0), Vector3(w, 0.24, d), style.foundation, true)
	_ground_apron(w, d)
	for s in stories:
		var y0 := FLOOR_Y + sh * float(s)
		var y1 := FLOOR_Y + sh * float(s + 1)
		_story_shell(style, s, x0, x1, z0, z1, y0, y1, t)
		if s > 0:
			_upper_floor(style, y0, x0 + t, x1 - t, z0 + t, z1 - t, style.floor)
	_roof(style, x0, x1, z0, z1, top)
	if float(style.porch) > 0.3 and stories >= 1:
		_porch(style, x0, x1, z0)
	_corner_trim(x0, x1, z0, z1, top, style.trim)
	_house_dressing(style, x0, x1, z0, z1)
	if stories >= 2:
		_stairs_for(style, sh)
	_rooms(style, x0, x1, z0, z1, sh, t)
	_furnish_house(style, sh)
	for s in stories:
		_light(Vector3(-1.2, FLOOR_Y + sh * float(s) + sh - 0.45, -0.4), 5.6, 2.9)
		_light(Vector3(1.6, FLOOR_Y + sh * float(s) + sh * 0.55, 1.1), 5.0, 2.0)
	_interior_probe(w, top, d)
	probe = Vector3(0.8, 0.02, z0 + 2.6)


func _story_shell(style: Dictionary, story: int, x0: float, x1: float, z0: float, z1: float, y0: float, y1: float, t: float) -> void:
	var siding: Material = style.siding
	var south: Array = []
	var north: Array = []
	var west: Array = []
	var east: Array = []
	var inset_x0 := x0 + 0.9
	var inset_x1 := x1 - 0.9
	if story == 0:
		south.append({"a": -0.58, "b": 0.58, "low": y0, "high": y0 + 2.15})
	var win_w := 1.15
	var win_low := y0 + 0.92
	var win_high := min(y0 + 2.25, y1 - 0.25)
	for slot in _window_slots(inset_x0, inset_x1, win_w):
		if story == 0 and abs(slot) < 0.9:
			continue
		south.append({"a": slot - win_w * 0.5, "b": slot + win_w * 0.5, "low": win_low, "high": win_high})
		north.append({"a": slot - win_w * 0.5, "b": slot + win_w * 0.5, "low": win_low, "high": win_high})
	for slot_z in _window_slots(z0 + 0.9, z1 - 0.9, 1.05):
		west.append({"a": slot_z - 0.52, "b": slot_z + 0.52, "low": win_low, "high": win_high})
		east.append({"a": slot_z - 0.52, "b": slot_z + 0.52, "low": win_low, "high": win_high})
	_partition(true, z0 + t * 0.5, x0, x1, y0, y1, t, south, siding)
	_partition(true, z1 - t * 0.5, x0, x1, y0, y1, t, north, siding)
	_partition(false, x0 + t * 0.5, z0, z1, y0, y1, t, west, siding)
	_partition(false, x1 - t * 0.5, z0, z1, y0, y1, t, east, siding)
	for g in south:
		_opening_trim(true, z0 + t * 0.5, g, style.trim, g.high - g.low > 2.0)
		if style.has("shutter") and g.high - g.low < 2.0:
			_shutters(true, z0 - 0.02, g, style.shutter)
	for g in north:
		_opening_trim(true, z1 - t * 0.5, g, style.trim, false)
		if style.has("shutter"):
			_shutters(true, z1 + 0.02, g, style.shutter)
	for g in west:
		_opening_trim(false, x0 + t * 0.5, g, style.trim, false)
	for g in east:
		_opening_trim(false, x1 - t * 0.5, g, style.trim, false)
	if story == 0 and south.size() > 0:
		_door_panel(Vector3(0.62, y0 + 1.05, z0 - 0.08), 1.15, style.trim)


func _window_slots(a0: float, a1: float, width: float) -> Array:
	var span := a1 - a0
	if span < width + 0.4:
		return []
	if span < width * 2.4:
		return [(a0 + a1) * 0.5]
	return [a0 + span * 0.28, a0 + span * 0.72]


func _upper_floor(style: Dictionary, y: float, x0: float, x1: float, z0: float, z1: float, mat: Material) -> void:
	var stair: Rect2 = style.stair
	if style.stories < 2 or stair.size.x < 0.5:
		_box(Vector3((x0 + x1) * 0.5, y - 0.08, (z0 + z1) * 0.5), Vector3(x1 - x0, 0.16, z1 - z0), mat, true)
		return
	if style.stories >= 3:
		var land := 1.05
		_slab_hole(y - 0.08, x0, x1, z0, z1, 0.16, stair.position.x, stair.position.x + stair.size.x, stair.position.y + land, stair.position.y + stair.size.y - land, mat)
	else:
		_slab_hole(y - 0.08, x0, x1, z0, z1, 0.16, stair.position.x, stair.position.x + stair.size.x, stair.position.y, stair.position.y + stair.size.y, mat)


func _stairs_for(style: Dictionary, sh: float) -> void:
	var stair: Rect2 = style.stair
	if stair.size.x < 0.5:
		return
	var x0 := stair.position.x
	var z0 := stair.position.y
	var x1 := x0 + stair.size.x
	var z1 := z0 + stair.size.y
	var stories: int = style.stories
	var wall: Material = style.interior
	var wood: Material = style.floor
	if stories >= 3:
		_switchback(x0, x1, z0, z1, stories, sh, wood, wall)
	else:
		_partition(false, x0, z0, z1, FLOOR_Y, FLOOR_Y + sh * 2.0, 0.12, [], wall)
		_partition(false, x1, z0, z1, FLOOR_Y, FLOOR_Y + sh * 2.0, 0.12, [], wall)
		var exit_high := min(FLOOR_Y + sh + 2.15, FLOOR_Y + sh * 2.0 - 0.1)
		var exit := [{"a": x0 + 0.06, "b": x1 - 0.06, "low": FLOOR_Y + sh, "high": exit_high}]
		_partition(true, z1, x0, x1, FLOOR_Y, FLOOR_Y + sh * 2.0, 0.12, exit, wall)
		var entrance := [{"a": x0 + 0.06, "b": x1 - 0.06, "low": FLOOR_Y, "high": FLOOR_Y + 2.15}]
		_partition(true, z0, x0, x1, FLOOR_Y, FLOOR_Y + sh * 2.0, 0.12, entrance, wall)
		var cx := (x0 + x1) * 0.5
		var width := max(stair.size.x - 0.28, 0.9)
		_stairs_z(cx, width, z0 + 0.12, z1 + 0.2, FLOOR_Y, FLOOR_Y + sh, wood)


func _switchback(x0: float, x1: float, z0: float, z1: float, stories: int, sh: float, wood: Material, wall: Material) -> void:
	var land := 1.05
	var mid := (x0 + x1) * 0.5
	var south_gaps: Array = []
	var north_gaps: Array = []
	south_gaps.append({"a": x0 + 0.1, "b": x1 - 0.1, "low": FLOOR_Y, "high": FLOOR_Y + 2.15})
	for s in range(1, stories):
		var y := FLOOR_Y + sh * float(s)
		var gap := {"a": x0 + 0.1, "b": x1 - 0.1, "low": y, "high": min(y + 2.15, FLOOR_Y + sh * float(stories) - 0.15)}
		if s % 2 == 1:
			north_gaps.append(gap)
		else:
			south_gaps.append(gap)
	_partition(true, z0, x0, x1, FLOOR_Y, FLOOR_Y + sh * float(stories), 0.12, south_gaps, wall)
	_partition(true, z1, x0, x1, FLOOR_Y, FLOOR_Y + sh * float(stories), 0.12, north_gaps, wall)
	_partition(false, x0, z0, z1, FLOOR_Y, FLOOR_Y + sh * float(stories), 0.1, [], wall)
	_partition(false, x1, z0, z1, FLOOR_Y, FLOOR_Y + sh * float(stories), 0.1, [], wall)
	for s in range(stories - 1):
		var y0 := FLOOR_Y + sh * float(s)
		var y1 := FLOOR_Y + sh * float(s + 1)
		var left: bool = s % 2 == 0
		var lane0 := x0 + 0.16 if left else mid + 0.08
		var lane1 := mid - 0.08 if left else x1 - 0.16
		var from_z := z0 + land if left else z1 - land
		var to_z := z1 - land + 0.15 if left else z0 + land - 0.15
		_stairs_z((lane0 + lane1) * 0.5, max(lane1 - lane0, 0.8), from_z, to_z, y0, y1, wood)


func _rooms(style: Dictionary, x0: float, x1: float, z0: float, z1: float, sh: float, t: float) -> void:
	var stair: Rect2 = style.stair
	var wall: Material = style.interior
	var split_z := 0.15
	var right_limit := x1 - t
	if stair.size.x > 0.5:
		right_limit = stair.position.x - 0.05
	if right_limit - (x0 + t) > 2.4:
		var door := [{"a": -1.7, "b": -0.55, "low": FLOOR_Y, "high": FLOOR_Y + 2.15}]
		_partition(true, split_z, x0 + t, right_limit, FLOOR_Y, FLOOR_Y + sh - 0.16, 0.12, door, wall)
	if style.stories >= 2:
		var y := FLOOR_Y + sh
		var door2 := [{"a": z0 + 1.4, "b": z0 + 2.5, "low": y, "high": y + 2.1}]
		var east_limit := x1 - t
		if stair.size.x > 0.5:
			east_limit = stair.position.x - 0.05
		if east_limit > 0.8:
			_partition(false, 0.15, z0 + t, z1 - t, y, y + sh - 0.16, 0.12, door2, wall)


func _furnish_house(style: Dictionary, sh: float) -> void:
	var fabric: Material = lib.get_shared("fabric")
	var wood: Material = style.floor
	var stone: Material = style.foundation
	_box(Vector3(-2.4, 0.38, style.d * -0.5 + 2.0), Vector3(1.8, 0.55, 0.8), fabric, true)
	_box(Vector3(-2.3, 0.72, style.d * -0.5 + 2.0), Vector3(1.7, 0.18, 0.75), fabric, false)
	_box(Vector3(-2.2, 0.32, 0.9), Vector3(1.2, 0.08, 0.7), wood, true)
	_box(Vector3(-3.0, 0.85, style.d * 0.5 - 0.7), Vector3(0.7, 0.9, 2.2), stone, true)
	if style.stories >= 2:
		var y := FLOOR_Y + sh
		_box(Vector3(-2.2, y + 0.32, 1.4), Vector3(2.1, 0.45, 1.5), fabric, true)
		_box(Vector3(-2.2, y + 0.62, 1.4), Vector3(2.0, 0.18, 1.4), lib.tinted("plaster", Color(0.7, 0.68, 0.64)), false)
		_box(Vector3(-3.3, y + 0.4, style.d * 0.5 - 0.55), Vector3(0.55, 0.7, 1.1), wood, true)


func _roof(style: Dictionary, x0: float, x1: float, z0: float, z1: float, eave_y: float) -> void:
	var kind := str(style.roof_kind)
	var mat: Material = style.roof
	if kind == "flat":
		_box(Vector3(0, eave_y + 0.14, 0), Vector3(x1 - x0 + 0.4, 0.28, z1 - z0 + 0.4), mat, true)
		_box(Vector3(0, eave_y + 0.45, z0 - 0.05), Vector3(x1 - x0 + 0.5, 0.5, 0.16), style.trim, true)
		_box(Vector3(0, eave_y + 0.45, z1 + 0.05), Vector3(x1 - x0 + 0.5, 0.5, 0.16), style.trim, true)
		_box(Vector3(x0 - 0.05, eave_y + 0.45, 0), Vector3(0.16, 0.5, z1 - z0 + 0.5), style.trim, true)
		_box(Vector3(x1 + 0.05, eave_y + 0.45, 0), Vector3(0.16, 0.5, z1 - z0 + 0.5), style.trim, true)
		return
	var ridge := 2.15 if kind == "hip" else 2.45
	if kind == "hip":
		_hip_visual(x0, x1, z0, z1, eave_y, ridge, 0.35, mat)
	else:
		_gable_visual(x0, x1, z0, z1, eave_y, ridge, 0.38, mat)
	_attic_fill(x0, x1, z0, z1, eave_y, ridge, mat)
	if style.get("chimney", false):
		_box(Vector3(x0 + 1.6, eave_y + ridge * 0.72, z0 + 1.5), Vector3(0.7, ridge + 1.3, 0.7), lib.tinted("brick", Color(0.55, 0.4, 0.36)), true)
		_box(Vector3(x0 + 1.6, eave_y + ridge * 0.72 + (ridge + 1.3) * 0.5 + 0.08, z0 + 1.5), Vector3(0.86, 0.12, 0.86), lib.tinted("concrete", Color(0.3, 0.3, 0.3)), false)


func _porch(style: Dictionary, x0: float, x1: float, z0: float) -> void:
	var depth: float = style.porch
	var width := min(x1 - x0 - 0.4, 8.5)
	_box(Vector3(0, 0.05, z0 - depth * 0.5), Vector3(width, 0.1, depth), style.floor, true)
	_box(Vector3(0, 2.62, z0 - depth * 0.5), Vector3(width + 0.3, 0.1, depth + 0.25), style.roof, true)
	var posts := 4 if depth > 2.0 else 2
	for i in posts:
		var px := lerp(-width * 0.42, width * 0.42, float(i) / float(max(posts - 1, 1)))
		_box(Vector3(px, 1.32, z0 - depth + 0.14), Vector3(0.16, 2.5, 0.16), style.trim, true)
	_box(Vector3(0, -0.02, z0 - depth - 0.28), Vector3(1.5, 0.1, 0.42), style.foundation, true)


func _industrial(factory: bool) -> void:
	var w := 42.0 if factory else 34.0
	var d := 24.0 if factory else 20.0
	var h := 12.0 if factory else 9.2
	var x0 := -w * 0.5
	var x1 := w * 0.5
	var z0 := -d * 0.5
	var z1 := d * 0.5
	var metal: Material = lib.tinted("metal", Color(0.5, 0.36, 0.24) if not factory else Color(0.42, 0.32, 0.22))
	var concrete: Material = lib.tinted("concrete", Color(0.58, 0.52, 0.44))
	var dark: Material = lib.get_shared("darkmetal")
	_box(Vector3(0, -0.1, 0), Vector3(w, 0.2, d), concrete, true)
	_ground_apron(w, d)
	var dock_h := 4.4
	var south_gaps := [
		{"a": -9.2, "b": -5.2, "low": FLOOR_Y, "high": FLOOR_Y + dock_h},
		{"a": 2.4, "b": 6.6, "low": FLOOR_Y, "high": FLOOR_Y + dock_h},
	]
	var east_gaps := [{"a": -0.6, "b": 0.6, "low": FLOOR_Y, "high": FLOOR_Y + 2.2}]
	var high_gaps: Array = []
	if factory:
		high_gaps = [{"a": -6.0, "b": 6.0, "low": h - 2.4, "high": h - 0.6}]
		_partition(true, z0 + 0.1, x0, x1, 0.0, h, 0.16, south_gaps + high_gaps, metal)
		_partition(true, z1 - 0.1, x0, x1, 0.0, h, 0.16, high_gaps, metal)
	else:
		_partition(true, z0 + 0.1, x0, x1, 0.0, h, 0.16, south_gaps, metal)
		_partition(true, z1 - 0.1, x0, x1, 0.0, h, 0.16, [], metal)
	_partition(false, x0 + 0.1, z0, z1, 0.0, h, 0.16, [], metal)
	_partition(false, x1 - 0.1, z0, z1, 0.0, h, 0.16, east_gaps, metal)
	for g in south_gaps:
		_opening_trim(true, z0 + 0.1, g, concrete, true)
	_opening_trim(false, x1 - 0.1, east_gaps[0], concrete, true)
	_door_panel(Vector3(x1 + 0.1, FLOOR_Y + 1.1, 0.7), 1.2, lib.tinted("planks", Color(0.45, 0.32, 0.22)))
	_box(Vector3(0, h + 0.12, 0), Vector3(w + 0.4, 0.24, d + 0.4), metal, true)
	if factory:
		for i in 4:
			var zx := x0 + 4.0 + float(i) * (w - 6.0) / 3.0
			_gable_visual(zx - 3.2, zx + 3.2, z0, z1, h + 0.2, 1.6, 0.2, metal)
	var col_h := h - 0.3
	for gx in range(-1, 2):
		for gz in range(-1, 2):
			var px := float(gx) * 8.0
			var pz := float(gz) * 6.0
			if abs(pz - z0) < 3.0:
				continue
			_box(Vector3(px, col_h * 0.5, pz), Vector3(0.45, col_h, 0.45), concrete, true)
	_office_block(x1, z1, concrete, metal)
	var mezz_y := 4.2
	var mezz_z0 := z1 - 6.5
	_slab_hole(mezz_y, x0 + 0.4, x0 + 14.0, mezz_z0, z1 - 0.4, 0.18, x0 + 0.4, x0 + 0.5, mezz_z0, mezz_z0, concrete)
	_box(Vector3((x0 + 0.8 + x0 + 14.0) * 0.5, mezz_y + 0.5, mezz_z0), Vector3(13.0, 1.0, 0.08), metal, true)
	_stairs_x(x0 + 1.0, x0 + 7.2, mezz_z0 + 1.6, 1.3, FLOOR_Y, mezz_y + 0.1, concrete)
	for row in 3:
		var rz := -2.0 + float(row) * 3.2
		for col in 4:
			var rx := -8.0 + float(col) * 2.2
			_box(Vector3(rx, 1.3, rz), Vector3(0.12, 2.6, 1.6), dark, true)
			_box(Vector3(rx, 0.8, rz), Vector3(1.5, 0.06, 1.4), dark, true)
			_box(Vector3(rx, 1.7, rz), Vector3(1.5, 0.06, 1.4), dark, true)
	var rng := RandomNumberGenerator.new()
	rng.seed = 19 if factory else 7
	for i in 10:
		var cx := rng.randf_range(-6.0, 6.0)
		var cz := rng.randf_range(z0 + 3.5, 2.0)
		var cs := rng.randf_range(0.6, 1.3)
		_box(Vector3(cx, cs * 0.5, cz), Vector3(cs, cs * 0.8, cs), lib.tinted("planks", Color(0.55, 0.4, 0.24)), true)
	if factory:
		for m in 3:
			_box(Vector3(-6.0 + float(m) * 5.5, 1.1, 2.5), Vector3(3.2, 2.2, 1.6), dark, true)
			_box(Vector3(-6.0 + float(m) * 5.5, 2.5, 2.5), Vector3(1.2, 0.8, 1.2), lib.tinted("metal", Color(0.6, 0.55, 0.3)), true)
		_box(Vector3(x1 + 1.6, 8.0, z1 - 2.0), Vector3(1.4, 16.0, 1.4), concrete, true)
		_box(Vector3(x1 + 1.6, 16.3, z1 - 2.0), Vector3(1.8, 0.4, 1.8), dark, true)
	for i in 4:
		_light(Vector3(lerp(x0 + 4.0, x1 - 4.0, float(i) / 3.0), h - 1.3, 0.0), 14.0, 1.1)
	_light(Vector3(x0 + 8.0, mezz_y + 1.6, z1 - 3.0), 8.0, 0.6)
	_interior_probe(w, h, d)
	probe = Vector3(-4.0, 0.02, -2.0)


func _office_block(x1: float, z1: float, concrete: Material, metal: Material) -> void:
	var ox0 := x1 - 8.0
	var oz0 := z1 - 6.2
	var door := [{"a": oz0 + 2.2, "b": oz0 + 3.4, "low": FLOOR_Y, "high": FLOOR_Y + 2.15}]
	var window := [{"a": ox0 + 1.1, "b": ox0 + 2.8, "low": 1.0, "high": 2.2}]
	_partition(false, ox0, oz0, z1 - 0.3, FLOOR_Y, 3.3, 0.14, door, concrete)
	_partition(true, oz0, ox0, x1 - 0.3, FLOOR_Y, 3.3, 0.14, window, concrete)
	_box(Vector3((ox0 + x1) * 0.5, 3.38, (oz0 + z1) * 0.5), Vector3(x1 - ox0 - 0.4, 0.12, z1 - oz0 - 0.5), concrete, true)
	_opening_trim(false, ox0, door[0], metal, true)
	_glass_for(true, oz0, window[0])
	_box(Vector3(ox0 + 2.2, 0.75, oz0 + 1.2), Vector3(1.6, 0.08, 0.7), lib.tinted("wood", Color(0.45, 0.32, 0.2)), true)
	_light(Vector3((ox0 + x1) * 0.5 - 0.5, 2.8, (oz0 + z1) * 0.5), 6.0, 0.5)


func _shed() -> void:
	var w := 4.4
	var d := 3.4
	var h := 2.55
	var wood: Material = lib.tinted("planks", Color(0.58, 0.5, 0.38))
	var roof: Material = lib.tinted("metal", Color(0.48, 0.32, 0.2))
	_box(Vector3(0, -0.08, 0), Vector3(w, 0.16, d), lib.get_shared("concrete"), true)
	var door := [{"a": -0.55, "b": 0.55, "low": FLOOR_Y, "high": 2.05}]
	_partition(true, -d * 0.5 + 0.08, -w * 0.5, w * 0.5, 0.0, h, 0.12, door, wood)
	_partition(true, d * 0.5 - 0.08, -w * 0.5, w * 0.5, 0.0, h, 0.12, [{"a": -0.4, "b": 0.4, "low": 1.15, "high": 1.85}], wood)
	_partition(false, -w * 0.5 + 0.08, -d * 0.5, d * 0.5, 0.0, h, 0.12, [], wood)
	_partition(false, w * 0.5 - 0.08, -d * 0.5, d * 0.5, 0.0, h, 0.12, [], wood)
	_gable_visual(-w * 0.5, w * 0.5, -d * 0.5, d * 0.5, h, 0.7, 0.15, roof)
	_attic_fill(-w * 0.5, w * 0.5, -d * 0.5, d * 0.5, h, 0.7, roof)
	_box(Vector3(-1.2, 1.0, d * 0.5 - 0.4), Vector3(0.5, 0.08, 1.2), wood, true)
	_box(Vector3(0.8, 0.35, 0.4), Vector3(0.7, 0.7, 0.7), lib.tinted("planks", Color(0.4, 0.28, 0.16)), true)
	_door_panel(Vector3(0.62, 1.02, -d * 0.5 - 0.02), 0.9, lib.tinted("planks", Color(0.35, 0.24, 0.16)))
	_light(Vector3(0, h - 0.4, 0), 4.5, 0.35)
	probe = Vector3(0, 1.3, 0)


func _garage() -> void:
	var w := 7.2
	var d := 6.6
	var h := 3.05
	var siding: Material = lib.tinted("concrete", Color(0.64, 0.58, 0.48))
	var concrete: Material = lib.get_shared("concrete")
	_box(Vector3(0, -0.08, 0), Vector3(w, 0.16, d), concrete, true)
	var bay := [{"a": -2.3, "b": 1.2, "low": FLOOR_Y, "high": 2.45}]
	_partition(true, -d * 0.5 + 0.1, -w * 0.5, w * 0.5, 0.0, h, 0.16, bay, siding)
	_partition(true, d * 0.5 - 0.1, -w * 0.5, w * 0.5, 0.0, h, 0.16, [], siding)
	var side_door := [{"a": -0.5, "b": 0.55, "low": FLOOR_Y, "high": 2.1}]
	_partition(false, -w * 0.5 + 0.1, -d * 0.5, d * 0.5, 0.0, h, 0.16, side_door, siding)
	_partition(false, w * 0.5 - 0.1, -d * 0.5, d * 0.5, 0.0, h, 0.16, [], siding)
	_box(Vector3(0, h + 0.1, 0), Vector3(w + 0.3, 0.2, d + 0.3), lib.tinted("roof", Color(0.3, 0.3, 0.32)), true)
	_box(Vector3(2.4, 0.9, 1.6), Vector3(0.7, 0.9, 1.8), lib.tinted("wood", Color(0.5, 0.36, 0.22)), true)
	_light(Vector3(0, h - 0.35, 0), 6.0, 0.45)
	probe = Vector3(0.8, 1.4, 0.2)


func _barn() -> void:
	var w := 16.0
	var d := 11.0
	var h := 5.2
	var wood: Material = lib.tinted("planks", Color(0.6, 0.52, 0.38))
	var dark: Material = lib.tinted("planks", Color(0.4, 0.32, 0.22))
	_box(Vector3(0, -0.1, 0), Vector3(w, 0.2, d), lib.tinted("dirt", Color(0.7, 0.6, 0.45)), true)
	var bay := [{"a": -2.3, "b": 2.3, "low": FLOOR_Y, "high": 3.8}]
	_partition(true, -d * 0.5 + 0.12, -w * 0.5, w * 0.5, 0.0, h, 0.18, bay, wood)
	_partition(true, d * 0.5 - 0.12, -w * 0.5, w * 0.5, 0.0, h, 0.18, [], wood)
	_partition(false, -w * 0.5 + 0.12, -d * 0.5, d * 0.5, 0.0, h, 0.18, [], wood)
	_partition(false, w * 0.5 - 0.12, -d * 0.5, d * 0.5, 0.0, h, 0.18, [], wood)
	for x in [-4.5, 0.0, 4.5]:
		_box(Vector3(x, h * 0.45, 0), Vector3(0.28, h * 0.9, 0.28), dark, true)
	_slab_hole(3.05, -w * 0.5 + 0.4, w * 0.5 - 0.4, 0.4, d * 0.5 - 0.4, 0.16, -w * 0.5, -w * 0.5 + 0.2, 0.4, 0.5, dark)
	_box(Vector3(0, 3.55, 0.55), Vector3(w - 1.2, 1.0, 0.1), dark, true)
	_stairs_x(-6.2, -2.4, 2.2, 1.2, FLOOR_Y, 3.15, dark)
	_gable_visual(-w * 0.5, w * 0.5, -d * 0.5, d * 0.5, h, 2.8, 0.4, lib.tinted("metal", Color(0.46, 0.3, 0.18)))
	_attic_fill(-w * 0.5, w * 0.5, -d * 0.5, d * 0.5, h, 2.8, dark)
	for i in 5:
		_box(Vector3(-2.0 + float(i % 3) * 1.6, 0.4, 2.5 + float(i / 3) * 1.4), Vector3(1.2, 0.8, 0.8), lib.tinted("plaster", Color(0.72, 0.62, 0.28)), true)
	_light(Vector3(0, h - 0.8, -1.0), 9.0, 0.45)
	probe = Vector3(0, 1.5, -1.0)


func _chapel() -> void:
	var w := 11.0
	var d := 16.0
	var h := 6.0
	var stone: Material = lib.tinted("plaster", Color(0.76, 0.62, 0.44))
	var trim: Material = lib.tinted("plaster", Color(0.84, 0.72, 0.52))
	_box(Vector3(0, -0.1, 0), Vector3(w, 0.2, d), lib.get_shared("concrete"), true)
	var door := [{"a": -0.7, "b": 0.7, "low": FLOOR_Y, "high": 2.6}]
	_partition(true, -d * 0.5 + 0.16, -w * 0.5, w * 0.5, 0.0, h, 0.28, door, stone)
	_partition(true, d * 0.5 - 0.16, -w * 0.5, w * 0.5, 0.0, h, 0.28, [], stone)
	var glass_gaps := [{"a": -1.5, "b": 1.5, "low": 1.6, "high": 4.4}]
	_partition(false, -w * 0.5 + 0.16, -d * 0.5, d * 0.5, 0.0, h, 0.28, glass_gaps, stone)
	_partition(false, w * 0.5 - 0.16, -d * 0.5, d * 0.5, 0.0, h, 0.28, glass_gaps, stone)
	_glass_for(false, -w * 0.5 + 0.16, glass_gaps[0])
	_glass_for(false, w * 0.5 - 0.16, glass_gaps[0])
	_gable_visual(-w * 0.5, w * 0.5, -d * 0.5, d * 0.5, h, 3.4, 0.3, lib.tinted("roof", Color(0.25, 0.27, 0.3)))
	_attic_fill(-w * 0.5, w * 0.5, -d * 0.5, d * 0.5, h, 3.4, stone)
	_box(Vector3(0, 2.2, -d * 0.5 - 0.5), Vector3(2.2, 4.4, 2.2), stone, true)
	_box(Vector3(0, 5.6, -d * 0.5 - 0.5), Vector3(1.5, 3.2, 1.5), stone, true)
	_pyramid(Vector3(0, 8.4, -d * 0.5 - 0.5), 1.8, 2.2, trim)
	for i in 6:
		var z := -3.0 + float(i) * 1.5
		_box(Vector3(-2.3, 0.45, z), Vector3(2.2, 0.5, 0.55), lib.tinted("planks", Color(0.4, 0.26, 0.16)), true)
		_box(Vector3(2.3, 0.45, z), Vector3(2.2, 0.5, 0.55), lib.tinted("planks", Color(0.4, 0.26, 0.16)), true)
	_light(Vector3(0, h - 1.0, 0), 10.0, 0.55)
	probe = Vector3(0, 1.5, -2.0)


func _store() -> void:
	var w := 12.0
	var d := 9.0
	var h := 4.0
	var brick: Material = lib.tinted("plaster", Color(0.72, 0.56, 0.4))
	var concrete: Material = lib.get_shared("concrete")
	_box(Vector3(0, -0.08, 0), Vector3(w, 0.16, d), concrete, true)
	var front := [
		{"a": -4.6, "b": -0.8, "low": 0.6, "high": 3.1},
		{"a": 0.8, "b": 4.6, "low": 0.6, "high": 3.1},
		{"a": -0.55, "b": 0.55, "low": FLOOR_Y, "high": 2.2},
	]
	_partition(true, -d * 0.5 + 0.12, -w * 0.5, w * 0.5, 0.0, h, 0.18, front, brick)
	_partition(true, d * 0.5 - 0.12, -w * 0.5, w * 0.5, 0.0, h, 0.18, [], brick)
	_partition(false, -w * 0.5 + 0.12, -d * 0.5, d * 0.5, 0.0, h, 0.18, [], brick)
	_partition(false, w * 0.5 - 0.12, -d * 0.5, d * 0.5, 0.0, h, 0.18, [], brick)
	_glass_for(true, -d * 0.5 + 0.12, front[0])
	_glass_for(true, -d * 0.5 + 0.12, front[1])
	_box(Vector3(0, h + 0.1, 0), Vector3(w + 0.2, 0.2, d + 0.2), lib.tinted("concrete", Color(0.45, 0.45, 0.45)), true)
	_box(Vector3(0, 0.95, d * 0.5 - 1.4), Vector3(4.5, 0.12, 0.8), lib.tinted("wood", Color(0.45, 0.3, 0.18)), true)
	for side in [-1.0, 1.0]:
		for i in 3:
			_box(Vector3(side * 3.6, 1.0, -1.5 + float(i) * 1.6), Vector3(0.8, 1.8, 0.45), lib.tinted("metal", Color(0.7, 0.7, 0.72)), true)
	_door_panel(Vector3(0.65, 1.1, -d * 0.5), 1.05, lib.tinted("planks", Color(0.4, 0.28, 0.18)))
	_light(Vector3(-2.5, h - 0.4, 0), 7.0, 0.7)
	_light(Vector3(2.5, h - 0.4, 0), 7.0, 0.7)
	probe = Vector3(0, 1.5, -1.0)


func _gas() -> void:
	_store_small()
	var canopy: Material = lib.tinted("metal", Color(0.72, 0.52, 0.24))
	var white: Material = lib.tinted("plaster", Color(0.8, 0.7, 0.52))
	_box(Vector3(0, 4.3, -8.2), Vector3(10.5, 0.18, 7.5), canopy, true)
	for p in [Vector2(-4.2, -6.2), Vector2(4.2, -6.2), Vector2(-4.2, -10.0), Vector2(4.2, -10.0)]:
		_box(Vector3(p.x, 2.15, p.y), Vector3(0.28, 4.3, 0.28), white, true)
	_box(Vector3(-1.6, 0.9, -8.0), Vector3(0.7, 1.5, 0.45), lib.get_shared("darkmetal"), true)
	_box(Vector3(1.6, 0.9, -8.0), Vector3(0.7, 1.5, 0.45), lib.get_shared("darkmetal"), true)
	probe = Vector3(0, 1.4, -1.2)


func _store_small() -> void:
	var w := 8.0
	var d := 6.5
	var h := 3.5
	var siding: Material = lib.tinted("plaster", Color(0.82, 0.8, 0.74))
	_box(Vector3(0, -0.08, 0), Vector3(w, 0.16, d), lib.get_shared("concrete"), true)
	var front := [
		{"a": -2.6, "b": -0.7, "low": 0.7, "high": 2.6},
		{"a": 0.7, "b": 2.6, "low": 0.7, "high": 2.6},
		{"a": -0.5, "b": 0.5, "low": FLOOR_Y, "high": 2.15},
	]
	_partition(true, -d * 0.5 + 0.1, -w * 0.5, w * 0.5, 0.0, h, 0.16, front, siding)
	_partition(true, d * 0.5 - 0.1, -w * 0.5, w * 0.5, 0.0, h, 0.16, [], siding)
	_partition(false, -w * 0.5 + 0.1, -d * 0.5, d * 0.5, 0.0, h, 0.16, [], siding)
	_partition(false, w * 0.5 - 0.1, -d * 0.5, d * 0.5, 0.0, h, 0.16, [], siding)
	_glass_for(true, -d * 0.5 + 0.1, front[0])
	_glass_for(true, -d * 0.5 + 0.1, front[1])
	_box(Vector3(0, h + 0.1, 0), Vector3(w + 0.3, 0.18, d + 0.3), lib.tinted("concrete", Color(0.4, 0.4, 0.42)), true)
	_box(Vector3(0, 0.9, d * 0.5 - 1.1), Vector3(2.4, 0.1, 0.6), lib.tinted("wood", Color(0.4, 0.28, 0.16)), true)
	_light(Vector3(0, h - 0.35, 0), 6.0, 0.55)


func _partition(along_x: bool, fixed: float, a0: float, a1: float, y0: float, y1: float, thick: float, gaps: Array, mat: Material) -> void:
	if a1 < a0:
		var swap := a0
		a0 = a1
		a1 = swap
	var cursor := a0
	var ordered := gaps.duplicate()
	ordered.sort_custom(func(u, v): return float(u.a) < float(v.a))
	for g in ordered:
		var gs: float = clampf(float(g.a), a0, a1)
		var ge: float = clampf(float(g.b), a0, a1)
		if gs > cursor + 0.04:
			_span(along_x, fixed, cursor, gs, y0, y1, thick, mat, true)
		if ge > gs + 0.02:
			if float(g.low) - y0 > 0.04:
				_span(along_x, fixed, gs, ge, y0, float(g.low), thick, mat, true)
			if y1 - float(g.high) > 0.04:
				_span(along_x, fixed, gs, ge, float(g.high), y1, thick, mat, true)
			if float(g.high) - float(g.low) < 2.45 and float(g.low) > y0 + 0.35:
				_glass_for(along_x, fixed, g)
		cursor = max(cursor, ge)
	if a1 > cursor + 0.04:
		_span(along_x, fixed, cursor, a1, y0, y1, thick, mat, true)


func _span(along_x: bool, fixed: float, a0: float, a1: float, y0: float, y1: float, thick: float, mat: Material, collide: bool) -> void:
	var mid_a := (a0 + a1) * 0.5
	var mid_y := (y0 + y1) * 0.5
	var length := a1 - a0
	var height := y1 - y0
	if along_x:
		_box(Vector3(mid_a, mid_y, fixed), Vector3(length, height, thick), mat, collide)
	else:
		_box(Vector3(fixed, mid_y, mid_a), Vector3(thick, height, length), mat, collide)


func _glass_for(along_x: bool, fixed: float, g: Dictionary) -> void:
	if float(g.high) - float(g.low) > 2.35:
		return
	var mid_a := (float(g.a) + float(g.b)) * 0.5
	var mid_y := (float(g.low) + float(g.high)) * 0.5
	var length := max(float(g.b) - float(g.a) - 0.08, 0.2)
	var height := max(float(g.high) - float(g.low) - 0.08, 0.2)
	var mat: Material = lib.get_shared("glass")
	if along_x:
		_box(Vector3(mid_a, mid_y, fixed), Vector3(length, height, 0.03), mat, false)
	else:
		_box(Vector3(fixed, mid_y, mid_a), Vector3(0.03, height, length), mat, false)


func _opening_trim(along_x: bool, fixed: float, g: Dictionary, mat: Material, is_door: bool) -> void:
	var a0 := float(g.a)
	var a1 := float(g.b)
	var low := float(g.low)
	var high := float(g.high)
	var face := 0.07
	var depth := 0.12
	if along_x:
		_box(Vector3((a0 + a1) * 0.5, high + face * 0.5, fixed), Vector3(a1 - a0 + face * 2.0, face, depth), mat, false)
		if not is_door:
			_box(Vector3((a0 + a1) * 0.5, low - face * 0.5, fixed), Vector3(a1 - a0 + face * 2.0, face, depth), mat, false)
		_box(Vector3(a0 - face * 0.5, (low + high) * 0.5, fixed), Vector3(face, high - low, depth), mat, false)
		_box(Vector3(a1 + face * 0.5, (low + high) * 0.5, fixed), Vector3(face, high - low, depth), mat, false)
	else:
		_box(Vector3(fixed, high + face * 0.5, (a0 + a1) * 0.5), Vector3(depth, face, a1 - a0 + face * 2.0), mat, false)
		if not is_door:
			_box(Vector3(fixed, low - face * 0.5, (a0 + a1) * 0.5), Vector3(depth, face, a1 - a0 + face * 2.0), mat, false)
		_box(Vector3(fixed, (low + high) * 0.5, a0 - face * 0.5), Vector3(depth, high - low, face), mat, false)
		_box(Vector3(fixed, (low + high) * 0.5, a1 + face * 0.5), Vector3(depth, high - low, face), mat, false)


func _door_panel(at: Vector3, yaw: float, mat: Material) -> void:
	var mesh_node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.92, 2.05, 0.05)
	mesh_node.mesh = mesh
	mesh_node.material_override = mat
	mesh_node.position = at
	mesh_node.rotation.y = yaw
	root.add_child(mesh_node)


func _slab_hole(y: float, x0: float, x1: float, z0: float, z1: float, thick: float, hx0: float, hx1: float, hz0: float, hz1: float, mat: Material) -> void:
	if hx1 <= hx0 or hz1 <= hz0:
		_box(Vector3((x0 + x1) * 0.5, y, (z0 + z1) * 0.5), Vector3(x1 - x0, thick, z1 - z0), mat, true)
		return
	if hx0 > x0 + 0.05:
		_box(Vector3((x0 + hx0) * 0.5, y, (z0 + z1) * 0.5), Vector3(hx0 - x0, thick, z1 - z0), mat, true)
	if x1 > hx1 + 0.05:
		_box(Vector3((hx1 + x1) * 0.5, y, (z0 + z1) * 0.5), Vector3(x1 - hx1, thick, z1 - z0), mat, true)
	if hz0 > z0 + 0.05:
		_box(Vector3((hx0 + hx1) * 0.5, y, (z0 + hz0) * 0.5), Vector3(hx1 - hx0, thick, hz0 - z0), mat, true)
	if z1 > hz1 + 0.05:
		_box(Vector3((hx0 + hx1) * 0.5, y, (hz1 + z1) * 0.5), Vector3(hx1 - hx0, thick, z1 - hz1), mat, true)


func _rails(stair: Rect2, y: float, mat: Material) -> void:
	var x0 := stair.position.x
	var z0 := stair.position.y
	var x1 := x0 + stair.size.x
	var z1 := z0 + stair.size.y
	_box(Vector3((x0 + x1) * 0.5, y + 0.5, z0), Vector3(x1 - x0, 1.0, 0.06), mat, true)
	_box(Vector3(x0, y + 0.5, (z0 + z1) * 0.5), Vector3(0.06, 1.0, z1 - z0), mat, true)
	_box(Vector3(x1, y + 0.5, (z0 + z1) * 0.5), Vector3(0.06, 1.0, z1 - z0), mat, true)


func _stairs_z(x_center: float, width: float, z0: float, z1: float, y0: float, y1: float, mat: Material) -> void:
	var run := abs(z1 - z0)
	var rise := y1 - y0
	if run < 0.4 or rise < 0.2:
		return
	var steps := clampi(int(round(rise / 0.17)), 8, 22)
	var step_h: float = rise / float(steps)
	var step_d: float = run / float(steps)
	var dir := signf(z1 - z0)
	for i in steps:
		var z: float = z0 + dir * step_d * (float(i) + 0.5)
		var y := y0 + step_h * (float(i) + 0.5)
		_box(Vector3(x_center, y, z), Vector3(width, step_h, step_d), mat, false)
	_ramp(x_center, width, z0, z1, y0, y1, true)


func _stairs_x(x0: float, x1: float, z_center: float, width: float, y0: float, y1: float, mat: Material) -> void:
	var run := abs(x1 - x0)
	var rise := y1 - y0
	if run < 0.4 or rise < 0.2:
		return
	var steps := clampi(int(round(rise / 0.17)), 8, 24)
	var step_h: float = rise / float(steps)
	var step_d: float = run / float(steps)
	var dir := signf(x1 - x0)
	for i in steps:
		var x: float = x0 + dir * step_d * (float(i) + 0.5)
		var y := y0 + step_h * (float(i) + 0.5)
		_box(Vector3(x, y, z_center), Vector3(step_d, step_h, width), mat, false)
	_ramp(z_center, width, x0, x1, y0, y1, false)


func _ramp(center: float, width: float, a0: float, a1: float, y0: float, y1: float, along_z: bool) -> void:
	var shape := ConvexPolygonShape3D.new()
	var half := width * 0.5
	var thick := 0.35
	var p: PackedVector3Array = []
	if along_z:
		p = PackedVector3Array([
			Vector3(center - half, y0, a0), Vector3(center + half, y0, a0),
			Vector3(center - half, y1, a1), Vector3(center + half, y1, a1),
			Vector3(center - half, y0 - thick, a0), Vector3(center + half, y0 - thick, a0),
			Vector3(center - half, y1 - thick, a1), Vector3(center + half, y1 - thick, a1),
		])
	else:
		p = PackedVector3Array([
			Vector3(a0, y0, center - half), Vector3(a0, y0, center + half),
			Vector3(a1, y1, center - half), Vector3(a1, y1, center + half),
			Vector3(a0, y0 - thick, center - half), Vector3(a0, y0 - thick, center + half),
			Vector3(a1, y1 - thick, center - half), Vector3(a1, y1 - thick, center + half),
		])
	shape.points = p
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)


func _gable_visual(x0: float, x1: float, z0: float, z1: float, eave_y: float, ridge: float, overhang: float, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mid_z := (z0 + z1) * 0.5
	var s00 := Vector3(x0 - overhang, eave_y, z0 - overhang)
	var s10 := Vector3(x1 + overhang, eave_y, z0 - overhang)
	var n00 := Vector3(x0 - overhang, eave_y, z1 + overhang)
	var n10 := Vector3(x1 + overhang, eave_y, z1 + overhang)
	var r0 := Vector3(x0 - overhang, eave_y + ridge, mid_z)
	var r1 := Vector3(x1 + overhang, eave_y + ridge, mid_z)
	_tri(st, s00, r0, r1)
	_tri(st, s00, r1, s10)
	_tri(st, n10, r1, r0)
	_tri(st, n10, r0, n00)
	_tri(st, s00, n00, r0)
	_tri(st, s10, r1, n10)
	var mesh := st.commit()
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	root.add_child(node)


func _hip_visual(x0: float, x1: float, z0: float, z1: float, eave_y: float, ridge: float, overhang: float, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inset := min((x1 - x0) * 0.28, (z1 - z0) * 0.45)
	var mid_z := (z0 + z1) * 0.5
	var r0 := Vector3(x0 + inset, eave_y + ridge, mid_z)
	var r1 := Vector3(x1 - inset, eave_y + ridge, mid_z)
	var s00 := Vector3(x0 - overhang, eave_y, z0 - overhang)
	var s10 := Vector3(x1 + overhang, eave_y, z0 - overhang)
	var n00 := Vector3(x0 - overhang, eave_y, z1 + overhang)
	var n10 := Vector3(x1 + overhang, eave_y, z1 + overhang)
	_tri(st, s00, r0, r1)
	_tri(st, s00, r1, s10)
	_tri(st, n10, r1, r0)
	_tri(st, n10, r0, n00)
	_tri(st, s00, n00, r0)
	_tri(st, n10, s10, r1)
	var mesh := st.commit()
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	root.add_child(node)


func _attic_fill(x0: float, x1: float, z0: float, z1: float, eave_y: float, ridge: float, mat: Material) -> void:
	var layers := 4
	for i in layers:
		var t0 := float(i) / float(layers)
		var t1 := float(i + 1) / float(layers)
		var y := eave_y + ridge * (t0 + t1) * 0.5
		var height := ridge / float(layers) + 0.05
		var depth := (z1 - z0) * (1.0 - t0)
		_box(Vector3(0, y, (z0 + z1) * 0.5), Vector3(x1 - x0, height, max(depth, 0.4)), mat, true)


func _pyramid(at: Vector3, width: float, height: float, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var apex := at + Vector3(0, height, 0)
	var h := width * 0.5
	var b00 := at + Vector3(-h, 0, -h)
	var b10 := at + Vector3(h, 0, -h)
	var b11 := at + Vector3(h, 0, h)
	var b01 := at + Vector3(-h, 0, h)
	_tri(st, b00, b10, apex)
	_tri(st, b10, b11, apex)
	_tri(st, b11, b01, apex)
	_tri(st, b01, b00, apex)
	var node := MeshInstance3D.new()
	node.mesh = st.commit()
	node.material_override = mat
	root.add_child(node)


func _corner_trim(x0: float, x1: float, z0: float, z1: float, top: float, mat: Material) -> void:
	for corner in [Vector3(x0, top * 0.5, z0), Vector3(x1, top * 0.5, z0), Vector3(x0, top * 0.5, z1), Vector3(x1, top * 0.5, z1)]:
		_box(corner, Vector3(0.12, top, 0.12), mat, false)


func _yard(kind: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var hx := maxf(footprint.x * 0.5, 2.0)
	var hz := maxf(footprint.y * 0.5, 1.8)
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var rust: Material = lib.tinted("metal", Color(0.48, 0.3, 0.16))
	var wood: Material = lib.tinted("planks", Color(0.52, 0.42, 0.28))
	var faded: Material = lib.tinted("metal", Color(0.62, 0.56, 0.42))
	var yard_x := side * (hx + rng.randf_range(1.4, 2.4))
	_barrel(Vector3(yard_x, 0.43, rng.randf_range(-hz * 0.6, hz * 0.4)), rust)
	if rng.randf() < 0.6:
		_barrel(Vector3(yard_x + side * 0.7, 0.43, rng.randf_range(-hz * 0.6, hz * 0.4)), faded)
	for i in rng.randi_range(1, 3):
		var s := rng.randf_range(0.42, 0.75)
		_box(Vector3(yard_x + side * rng.randf_range(0.2, 1.4), s * 0.36, hz * 0.3 + float(i) * 0.8), Vector3(s, s * 0.72, s * 0.85), wood, true)
	var sheet := MeshInstance3D.new()
	var panel := BoxMesh.new()
	panel.size = Vector3(1.5, 0.85, 0.04)
	sheet.mesh = panel
	sheet.material_override = faded
	sheet.position = Vector3(-yard_x, 0.5, hz + rng.randf_range(0.6, 1.4))
	sheet.rotation_degrees = Vector3(0, rng.randf_range(-25.0, 25.0), 68.0)
	root.add_child(sheet)
	if not woodland and kind in ["farmhouse", "ranch", "craftsman", "shed", "gas", "store"]:
		var tank_at := Vector3(-yard_x, 1.7, -hz + rng.randf_range(0.4, 1.2))
		_cyl(tank_at, 0.55, 0.55, 1.15, lib.tinted("metal", Color(0.55, 0.5, 0.4)), false)
		for leg in 3:
			var ang := TAU * float(leg) / 3.0
			_box(tank_at + Vector3(cos(ang) * 0.32, -0.7, sin(ang) * 0.32), Vector3(0.08, 1.3, 0.08), lib.get_shared("darkmetal"), false)
	if woodland and kind in ["farmhouse", "ranch", "craftsman", "colonial", "barn"]:
		_woodpile(Vector3(-yard_x, 0.0, -hz * 0.4), rng)
	if rng.randf() < 0.55:
		var car_z := -hz - rng.randf_range(3.5, 6.0)
		_wreck(Vector3(side * rng.randf_range(hx * 0.3, hx + 2.0), 0.0, car_z), rng.randf_range(-0.5, 0.5) + (PI * 0.5 if rng.randf() < 0.4 else 0.0), rng)
	if woodland and kind in ["farmhouse", "ranch", "craftsman", "colonial", "cottage"]:
		_yard_fence(hx, hz, rng)


func _barrel(at: Vector3, mat: Material) -> void:
	_cyl(at, 0.28, 0.3, 0.86, mat, true)
	_cyl(at + Vector3(0, 0.2, 0), 0.305, 0.305, 0.04, lib.get_shared("darkmetal"), false)
	_cyl(at + Vector3(0, -0.2, 0), 0.305, 0.305, 0.04, lib.get_shared("darkmetal"), false)


func _cyl(at: Vector3, top: float, bottom: float, height: float, mat: Material, collide: bool, rot := Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 12
	node.mesh = mesh
	node.material_override = mat
	node.position = at
	node.rotation = rot
	root.add_child(node)
	if collide:
		var col := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = maxf(top, bottom)
		shape.height = height
		col.shape = shape
		col.position = at
		col.rotation = rot
		body.add_child(col)
	return node


func _wreck(at: Vector3, yaw: float, rng: RandomNumberGenerator) -> void:
	var paints := [Color(0.42, 0.5, 0.48), Color(0.62, 0.52, 0.3), Color(0.52, 0.3, 0.24), Color(0.6, 0.6, 0.56), Color(0.32, 0.36, 0.42)]
	var paint: Material = lib.tinted("metal", paints[rng.randi() % paints.size()])
	var rust: Material = lib.tinted("metal", Color(0.42, 0.26, 0.14))
	var dark: Material = lib.get_shared("darkmetal")
	var car := Node3D.new()
	car.position = at
	car.rotation.y = yaw
	car.rotation.z = rng.randf_range(-0.04, 0.04)
	root.add_child(car)
	var old_root := root
	root = car
	_box(Vector3(0, 0.52, 0), Vector3(4.6, 0.5, 1.82), paint, false)
	_box(Vector3(1.55, 0.82, 0), Vector3(1.5, 0.14, 1.74), paint, false)
	_box(Vector3(-1.75, 0.82, 0), Vector3(1.1, 0.14, 1.74), rust, false)
	_box(Vector3(-0.15, 1.08, 0), Vector3(1.9, 0.5, 1.6), paint, false)
	_box(Vector3(-0.15, 1.34, 0), Vector3(1.7, 0.06, 1.5), rust, false)
	_box(Vector3(0.82, 1.06, 0), Vector3(0.06, 0.42, 1.48), dark, false)
	_box(Vector3(-1.12, 1.06, 0), Vector3(0.06, 0.4, 1.44), dark, false)
	_box(Vector3(-0.15, 1.06, 0.81), Vector3(1.7, 0.36, 0.03), dark, false)
	_box(Vector3(-0.15, 1.06, -0.81), Vector3(1.7, 0.36, 0.03), dark, false)
	_box(Vector3(2.32, 0.5, 0), Vector3(0.08, 0.22, 1.7), lib.tinted("metal", Color(0.7, 0.68, 0.62)), false)
	_box(Vector3(-2.32, 0.5, 0), Vector3(0.08, 0.2, 1.7), lib.tinted("metal", Color(0.7, 0.68, 0.62)), false)
	for wx in [1.45, -1.45]:
		for wz in [0.86, -0.86]:
			if rng.randf() < 0.25:
				continue
			_cyl(Vector3(wx, 0.24, wz), 0.34, 0.34, 0.24, dark, false, Vector3(PI * 0.5, 0, 0))
	root = old_root
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(4.6, 1.3, 1.82)
	col.shape = shape
	col.position = at + Vector3(0, 0.65, 0)
	col.rotation.y = yaw
	body.add_child(col)


func _woodpile(at: Vector3, rng: RandomNumberGenerator) -> void:
	var log_mat: Material = lib.tinted("bark", Color(0.5, 0.4, 0.3))
	for row in 3:
		for i in 4 - row:
			var z := at.z + (float(i) - float(3 - row) * 0.5) * 0.24
			_cyl(Vector3(at.x, 0.12 + float(row) * 0.21, z), 0.11, 0.11, rng.randf_range(1.0, 1.2), log_mat, false, Vector3(0, 0, PI * 0.5))
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.2, 0.7, 1.0)
	col.shape = shape
	col.position = at + Vector3(0, 0.35, 0)
	body.add_child(col)


func _yard_fence(hx: float, hz: float, rng: RandomNumberGenerator) -> void:
	var wood: Material = lib.tinted("planks", Color(0.56, 0.5, 0.4))
	var x0 := -hx - 4.0
	var x1 := hx + 4.0
	var z_front := -hz - 9.0
	var z_back := hz + 5.0
	_fence_line(Vector3(x0, 0, z_front), Vector3(-1.4, 0, z_front), wood, rng)
	_fence_line(Vector3(1.4, 0, z_front), Vector3(x1, 0, z_front), wood, rng)
	_fence_line(Vector3(x0, 0, z_front), Vector3(x0, 0, z_back), wood, rng)
	_fence_line(Vector3(x1, 0, z_front), Vector3(x1, 0, z_back), wood, rng)


func _fence_line(a: Vector3, b: Vector3, mat: Material, rng: RandomNumberGenerator) -> void:
	var length := a.distance_to(b)
	if length < 0.5:
		return
	var dir := (b - a) / length
	var count := maxi(int(ceil(length / 2.6)), 1)
	var seg := length / float(count)
	var along_x := absf(dir.x) > absf(dir.z)
	for i in count + 1:
		var p := a + dir * seg * float(i)
		var lean := rng.randf_range(-0.06, 0.06)
		var post := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.12, 1.25, 0.12)
		post.mesh = mesh
		post.material_override = mat
		post.position = p + Vector3(0, 0.6, 0)
		post.rotation = Vector3(lean, 0, -lean)
		root.add_child(post)
	for i in count:
		if rng.randf() < 0.12:
			continue
		var mid := a + dir * seg * (float(i) + 0.5)
		for h in [0.55, 0.98]:
			if h > 0.9 and rng.randf() < 0.15:
				continue
			var size := Vector3(seg, 0.09, 0.05) if along_x else Vector3(0.05, 0.09, seg)
			_box(mid + Vector3(0, h + rng.randf_range(-0.03, 0.03), 0), size, mat, h < 0.6)


func _lean_to(x1: float, z0: float, z1: float, roof: Material, post: Material) -> void:
	var depth := minf(z1 - z0 - 1.0, 5.0)
	if depth < 2.0:
		return
	var out := 2.6
	var zc := (z0 + z1) * 0.5
	var slab := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(out + 0.4, 0.06, depth + 0.3)
	slab.mesh = mesh
	slab.material_override = roof
	slab.position = Vector3(x1 + out * 0.5, 2.2, zc)
	slab.rotation.z = -0.18
	root.add_child(slab)
	for z in [zc - depth * 0.5, zc + depth * 0.5]:
		_box(Vector3(x1 + out - 0.1, 0.98, z), Vector3(0.14, 1.95, 0.14), post, true)
	_box(Vector3(x1 + 0.9, 0.38, zc), Vector3(0.8, 0.76, 1.6), lib.tinted("planks", Color(0.44, 0.34, 0.24)), true)


func _house_dressing(style: Dictionary, x0: float, x1: float, z0: float, z1: float) -> void:
	if not woodland:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val + 31
	if rng.randf() < 0.7:
		_lean_to(x1, z0, z1, lib.tinted("metal", Color(0.46, 0.34, 0.24)), style.trim)


func _shutters(along_x: bool, fixed: float, g: Dictionary, mat: Material) -> void:
	var a0 := float(g.a)
	var a1 := float(g.b)
	var low := float(g.low)
	var high := float(g.high)
	var w := 0.42
	var out := -0.07 if fixed < 0.0 else 0.07
	if along_x:
		_box(Vector3(a0 - 0.12 - w * 0.5, (low + high) * 0.5, fixed + out), Vector3(w, high - low, 0.04), mat, false)
		_box(Vector3(a1 + 0.12 + w * 0.5, (low + high) * 0.5, fixed + out), Vector3(w, high - low, 0.04), mat, false)
		_box(Vector3((a0 + a1) * 0.5, low - 0.08, fixed + out * 1.6), Vector3(a1 - a0 + 0.3, 0.06, 0.2), mat, false)
	else:
		_box(Vector3(fixed + out, (low + high) * 0.5, a0 - 0.12 - w * 0.5), Vector3(0.04, high - low, w), mat, false)
		_box(Vector3(fixed + out, (low + high) * 0.5, a1 + 0.12 + w * 0.5), Vector3(0.04, high - low, w), mat, false)


func _wood_style(kind: String) -> Dictionary:
	var shutter := [Color(0.3, 0.36, 0.3), Color(0.42, 0.24, 0.2), Color(0.28, 0.3, 0.36), Color(0.36, 0.3, 0.22)]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val + 7
	var shut: Material = lib.tinted("planks", shutter[rng.randi() % shutter.size()])
	match kind:
		"farmhouse":
			return {
				"w": 11.2, "d": 9.0, "stories": 2, "story_h": 2.9,
				"siding": lib.tinted("planks", Color(0.78, 0.74, 0.64)),
				"trim": lib.tinted("planks", Color(0.52, 0.46, 0.36)),
				"roof": lib.tinted("metal", Color(0.46, 0.34, 0.24)),
				"foundation": lib.tinted("concrete", Color(0.44, 0.42, 0.38)),
				"floor": lib.tinted("wood", Color(0.52, 0.4, 0.28)),
				"interior": lib.tinted("plaster", Color(0.66, 0.6, 0.5)),
				"porch": 2.15, "chimney": true, "roof_kind": "gable",
				"stair": Rect2(2.35, -3.55, 2.85, 4.7), "shutter": shut,
			}
		"craftsman":
			return {
				"w": 10.4, "d": 8.6, "stories": 2, "story_h": 2.8,
				"siding": lib.tinted("planks", Color(0.5, 0.5, 0.4)),
				"trim": lib.tinted("planks", Color(0.7, 0.64, 0.5)),
				"roof": lib.tinted("roof", Color(0.36, 0.32, 0.28)),
				"foundation": lib.tinted("brick", Color(0.56, 0.44, 0.36)),
				"floor": lib.tinted("wood", Color(0.48, 0.36, 0.24)),
				"interior": lib.tinted("plaster", Color(0.62, 0.56, 0.44)),
				"porch": 2.6, "chimney": true, "roof_kind": "gable",
				"stair": Rect2(1.9, -3.2, 2.7, 4.5), "shutter": shut,
			}
		"colonial":
			return {
				"w": 10.8, "d": 8.2, "stories": 2, "story_h": 3.0,
				"siding": lib.tinted("brick", Color(0.6, 0.44, 0.36)),
				"trim": lib.tinted("plaster", Color(0.72, 0.68, 0.6)),
				"roof": lib.tinted("roof", Color(0.3, 0.29, 0.28)),
				"foundation": lib.tinted("concrete", Color(0.42, 0.4, 0.36)),
				"floor": lib.tinted("wood", Color(0.52, 0.38, 0.26)),
				"interior": lib.tinted("plaster", Color(0.66, 0.62, 0.54)),
				"porch": 1.15, "chimney": true, "roof_kind": "hip",
				"stair": Rect2(2.15, -3.05, 2.55, 4.35), "shutter": shut,
			}
	return {
		"w": 14.5, "d": 7.4, "stories": 1, "story_h": 2.85,
		"siding": lib.tinted("planks", Color(0.64, 0.58, 0.46)),
		"trim": lib.tinted("planks", Color(0.46, 0.38, 0.28)),
		"roof": lib.tinted("metal", Color(0.4, 0.36, 0.3)),
		"foundation": lib.tinted("concrete", Color(0.44, 0.42, 0.38)),
		"floor": lib.tinted("wood", Color(0.52, 0.4, 0.26)),
		"interior": lib.tinted("plaster", Color(0.64, 0.58, 0.46)),
		"porch": 1.8, "chimney": false, "roof_kind": "gable",
		"stair": Rect2(0, 0, 0, 0), "shutter": shut,
	}


func _ground_apron(w: float, d: float) -> void:
	var dirt: Material = lib.tinted("dirt", Color(0.48, 0.4, 0.28))
	_box(Vector3(0, -0.08, 0), Vector3(w + 2.4, 0.06, d + 2.4), dirt, false)


func _interior_probe(w: float, h: float, d: float) -> void:
	if w < 3.0 or h < 2.2 or d < 3.0:
		return
	var probe_node := ReflectionProbe.new()
	probe_node.name = "InteriorProbe"
	probe_node.position = Vector3(0, h * 0.42, 0)
	probe_node.size = Vector3(maxf(w - 0.55, 1.0), maxf(h - 0.35, 1.0), maxf(d - 0.55, 1.0))
	probe_node.interior = true
	probe_node.box_projection = true
	probe_node.intensity = 0.62
	probe_node.max_distance = maxf(w, d) + 2.0
	probe_node.enable_shadows = false
	probe_node.update_mode = ReflectionProbe.UPDATE_ONCE
	probe_node.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	probe_node.ambient_color = Color(0.32, 0.28, 0.24)
	probe_node.ambient_color_energy = 0.35
	root.add_child(probe_node)


func _light(at: Vector3, range: float, energy: float) -> void:
	var lamp := OmniLight3D.new()
	lamp.position = at
	lamp.light_color = Color(1.0, 0.78, 0.55)
	lamp.light_energy = energy
	lamp.omni_range = range
	lamp.shadow_enabled = false
	lamp.light_specular = 0.18
	lamp.light_volumetric_fog_energy = 0.8
	lamp.distance_fade_enabled = true
	lamp.distance_fade_begin = 32.0
	lamp.distance_fade_length = 10.0
	root.add_child(lamp)
	_box(at + Vector3(0, 0.08, 0), Vector3(0.35, 0.06, 0.35), lib.get_shared("emit"), false)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length() < 0.0001:
		return
	n = n.normalized()
	st.set_normal(n)
	st.add_vertex(a)
	st.set_normal(n)
	st.add_vertex(b)
	st.set_normal(n)
	st.add_vertex(c)


func _box(center: Vector3, size: Vector3, mat: Material, collide: bool) -> void:
	if size.x < 0.03 or size.y < 0.03 or size.z < 0.03:
		return
	var mesh_node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_node.mesh = mesh
	mesh_node.position = center
	mesh_node.material_override = mat
	root.add_child(mesh_node)
	if collide:
		var shape_node := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		shape_node.shape = shape
		shape_node.position = center
		body.add_child(shape_node)
		var dims := [size.x, size.y, size.z]
		dims.sort()
		if float(dims[1]) >= 1.2 and float(dims[0]) >= 0.08:
			var occ := BoxOccluder3D.new()
			occ.size = size - Vector3(0.04, 0.04, 0.04)
			var occ_node := OccluderInstance3D.new()
			occ_node.occluder = occ
			occ_node.position = center
			root.add_child(occ_node)
