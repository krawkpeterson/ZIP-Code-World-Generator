extends Control

var builder
var player: Node3D
var map_view: TextureRect
var kind_label: Label
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Segoe UI", "Arial"])
	var compass := Control.new()
	compass.name = "Compass"
	compass.position = Vector2(28, 0)
	compass.custom_minimum_size = Vector2(128, 128)
	compass.size = Vector2(128, 128)
	compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	compass.draw.connect(_draw_compass)
	add_child(compass)
	set_meta("compass", compass)
	map_view = TextureRect.new()
	map_view.position = Vector2(8, 136)
	map_view.custom_minimum_size = Vector2(168, 168)
	map_view.size = Vector2(168, 168)
	map_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map_view.stretch_mode = TextureRect.STRETCH_SCALE
	map_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(map_view)
	var frame := ReferenceRect.new()
	frame.position = map_view.position
	frame.size = map_view.size
	frame.border_color = Color(0.85, 0.78, 0.62, 0.85)
	frame.border_width = 2.0
	frame.editor_only = false
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	var north := Label.new()
	north.text = "N"
	north.position = map_view.position + Vector2(76, 2)
	north.add_theme_font_override("font", _font)
	north.add_theme_font_size_override("font_size", 13)
	north.add_theme_color_override("font_color", Color(0.95, 0.9, 0.78))
	north.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(north)
	kind_label = Label.new()
	kind_label.position = Vector2(8, 308)
	kind_label.custom_minimum_size = Vector2(168, 20)
	kind_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kind_label.add_theme_font_override("font", _font)
	kind_label.add_theme_font_size_override("font_size", 13)
	kind_label.add_theme_color_override("font_color", Color(0.9, 0.86, 0.74))
	kind_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(kind_label)
	var overlay := Control.new()
	overlay.position = map_view.position
	overlay.size = map_view.size
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_player)
	add_child(overlay)
	set_meta("overlay", overlay)


func bind(world, body: Node3D) -> void:
	builder = world
	player = body
	if builder != null and builder.map_tex != null:
		map_view.texture = builder.map_tex
	var compass: Control = get_meta("compass")
	compass.queue_redraw()


func _process(_delta: float) -> void:
	if builder == null or player == null:
		return
	var compass: Control = get_meta("compass")
	var overlay: Control = get_meta("overlay")
	compass.queue_redraw()
	overlay.queue_redraw()
	if kind_label:
		kind_label.text = builder.terrain_label(player.global_position.x, player.global_position.z)


func _heading() -> float:
	var forward := -player.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.001:
		return 0.0
	forward = forward.normalized()
	return atan2(forward.x, -forward.z)


func _draw_compass() -> void:
	var compass: Control = get_meta("compass")
	var center := compass.size * 0.5
	var radius := 52.0
	compass.draw_circle(center, radius, Color(0.08, 0.07, 0.05, 0.72))
	compass.draw_arc(center, radius, 0.0, TAU, 48, Color(0.82, 0.74, 0.58, 0.9), 2.0)
	var heading := _heading() if player != null else 0.0
	var marks := ["N", "E", "S", "W"]
	for i in marks.size():
		var ang := -heading + float(i) * TAU / 4.0 - PI * 0.5
		var dir := Vector2(cos(ang), sin(ang))
		var at := center + dir * (radius - 16.0)
		var col := Color(0.95, 0.55, 0.28) if marks[i] == "N" else Color(0.9, 0.86, 0.74)
		compass.draw_string(_font, at + Vector2(-6, 5), marks[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col)
		compass.draw_line(center + dir * (radius - 8.0), center + dir * (radius - 2.0), col, 2.0)
	var tip := center + Vector2(0, -radius + 4.0)
	compass.draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-5, 8), tip + Vector2(5, 8)]), Color(0.95, 0.9, 0.78))


func _draw_player() -> void:
	var overlay: Control = get_meta("overlay")
	if builder == null or player == null:
		return
	var span := 800.0
	if builder != null:
		span = float(builder.PLAY_HALF) * 2.0
	var u := (player.global_position.x + span * 0.5) / span
	var v := (player.global_position.z + span * 0.5) / span
	var at := Vector2(u, v) * overlay.size
	var heading := _heading()
	var tip := at + Vector2(sin(heading), -cos(heading)) * 8.0
	var left := at + Vector2(sin(heading + 2.4), -cos(heading + 2.4)) * 5.0
	var right := at + Vector2(sin(heading - 2.4), -cos(heading - 2.4)) * 5.0
	overlay.draw_colored_polygon(PackedVector2Array([tip, left, right]), Color(0.95, 0.92, 0.84))
