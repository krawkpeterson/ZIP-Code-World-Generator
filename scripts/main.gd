extends Node

var menu: Control
var hud: CanvasLayer
var pause_layer: Control
var status_label: Label
var progress_bar: ProgressBar
var zip_edit: LineEdit
var generate_button: Button
var place_label: Label
var detail_label: Label
var nav: Control
var builder: Node
var player: CharacterBody3D
var playing := false
var generating := false
var shooting := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_menu()
	_build_hud()
	_build_pause()
	var cli := _cli()
	if cli.zip != "":
		zip_edit.text = cli.zip
		await _start_generation(cli.shot)


func _unhandled_input(event: InputEvent) -> void:
	if not playing or shooting:
		return
	if event is InputEventMouseButton and event.pressed and not get_tree().paused:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_set_paused(not get_tree().paused)
		elif event.keycode == KEY_F3:
			detail_label.visible = not detail_label.visible
		elif event.keycode == KEY_F and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			pass


func _process(_delta: float) -> void:
	if not playing or player == null or builder == null or not detail_label.visible:
		return
	var ll: Vector2 = builder.latlon_at(player.global_position.x, player.global_position.z)
	var elev: float = builder.sample_height(player.global_position.x, player.global_position.z) + builder.origin_elev
	detail_label.text = "Lat %s   Lon %s   Ground %sm" % [_coord(ll.x, true), _coord(ll.y, false), snapped(elev, 0.1)]


func set_status(text: String, ratio: float) -> void:
	if status_label:
		status_label.text = text
	if progress_bar:
		progress_bar.value = clampf(ratio, 0.0, 1.0) * 100.0
	print(text)


func _start_generation(shot: bool = false) -> void:
	if generating:
		return
	var zip_code := zip_edit.text.strip_edges()
	if zip_code.length() != 5 or not zip_code.is_valid_int():
		status_label.text = "Enter a five-digit US ZIP code."
		return
	generating = true
	generate_button.disabled = true
	zip_edit.editable = false
	progress_bar.visible = true
	if builder:
		builder.queue_free()
		builder = null
	builder = preload("res://scripts/world_builder.gd").new()
	builder.name = "WorldBuilder"
	builder.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(builder)
	var result: Dictionary = await builder.generate(zip_code, self)
	generating = false
	if not result.get("ok", false):
		status_label.text = str(result.get("error", "The map could not be built."))
		generate_button.disabled = false
		zip_edit.editable = true
		if shot:
			get_tree().quit(1)
		return
	_enter_world(shot)


func _enter_world(shot: bool) -> void:
	player = preload("res://scripts/player.gd").new()
	player.name = "Player"
	player.position = builder.spawn
	builder.world_root.add_child(player)
	if builder.spawn_dir.length() > 0.2:
		player.look_at(player.global_position + builder.spawn_dir, Vector3.UP)
	place_label.text = builder.place_label
	menu.visible = false
	menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if zip_edit:
		zip_edit.release_focus()
	get_viewport().gui_release_focus()
	hud.visible = true
	playing = true
	if nav:
		nav.bind(builder, player)
	if shot:
		await _capture_shots()
		get_tree().quit(0)
		return
	if DisplayServer.get_name() == "headless":
		print("HEADLESS OK ", builder.stats)
		get_tree().quit(0)
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _capture_shots() -> void:
	shooting = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.set_physics_process(false)
	player.collision_layer = 0
	player.collision_mask = 0
	var saved_density: float = float(builder.environment.fog_density)
	var saved_vfog: float = float(builder.environment.volumetric_fog_density)
	builder.environment.fog_density = 0.00012
	builder.environment.volumetric_fog_density = 0.0
	var ground_y: float = float(builder.sample_height(0.0, 0.0))
	player.global_position = Vector3(40.0, ground_y + 180.0, 90.0)
	player.rotation = Vector3.ZERO
	player.camera.look_at(Vector3(0.0, ground_y, 0.0), Vector3.UP)
	await get_tree().create_timer(1.2).timeout
	await _save_shot("res://shot_aerial.png")
	builder.environment.fog_density = saved_density
	builder.environment.volumetric_fog_density = saved_vfog
	player.global_position = builder.spawn + Vector3(0, 0.4, 0)
	player.rotation = Vector3.ZERO
	if builder.spawn_dir.length() > 0.2:
		player.look_at(player.global_position + builder.spawn_dir, Vector3.UP)
	player.camera.rotation = Vector3(0.12, 0, 0)
	await get_tree().create_timer(0.8).timeout
	await _save_shot("res://shot_street.png")
	await _measure("street")
	var side := Vector3(builder.spawn_dir.z, 0.0, -builder.spawn_dir.x)
	if side.length() < 0.2:
		side = Vector3(1.0, 0.0, 0.0)
	side = side.normalized()
	var verge: Vector3 = builder.spawn + side * 3.4
	verge.y = float(builder.sample_height(verge.x, verge.z)) + 0.08
	player.global_position = verge
	player.rotation = Vector3.ZERO
	player.look_at(verge + side * 6.0, Vector3.UP)
	player.camera.rotation = Vector3(0.38, 0.0, 0.0)
	await get_tree().create_timer(0.7).timeout
	await _save_shot("res://shot_verge.png")
	var eye: float = float(builder.sample_height(0.0, 0.0)) + 1.7
	player.global_position = Vector3(0.0, eye, 0.0)
	player.rotation = Vector3(0.0, -PI * 0.5, 0.0)
	player.camera.rotation = Vector3(-0.06, 0.0, 0.0)
	await get_tree().create_timer(0.6).timeout
	await _save_shot("res://shot_horizon.png")
	await _measure("town")
	var interior: Vector3 = builder.probes.get("house", builder.probes.get("industrial", builder.spawn))
	player.global_position = interior
	player.rotation = Vector3(0.0, 0.55, 0.0)
	player.camera.rotation = Vector3(-0.04, 0.0, 0.0)
	await get_tree().create_timer(0.6).timeout
	await _save_shot("res://shot_interior.png")
	var space := player.get_world_3d().direct_space_state
	var from := Vector3(0, builder.max_h + 40.0, 0)
	var to := Vector3(0, builder.min_h - 40.0, 0)
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))
	print("Center ray ", hit, " terrain ", builder.sample_height(0, 0))


func _measure(tag: String) -> void:
	for i in 30:
		await get_tree().process_frame
	var start := Time.get_ticks_usec()
	var frames := 120
	for i in frames:
		await get_tree().process_frame
	var ms := float(Time.get_ticks_usec() - start) / 1000.0 / float(frames)
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	for i in 20:
		await get_tree().process_frame
	print("TIMING %s  gpu %.2f ms  render_cpu %.2f ms  process %.2f ms  physics %.2f ms" % [tag, RenderingServer.viewport_get_measured_render_time_gpu(vp), RenderingServer.viewport_get_measured_render_time_cpu(vp), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])
	var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var objects := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	print("PERF %s  %.2f ms  %.0f fps  draws %d  objects %d  prims %d  nodes %d" % [tag, ms, 1000.0 / ms, draws, objects, prims, get_tree().get_node_count()])


func _save_shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var full := ProjectSettings.globalize_path(path)
	image.save_png(full)
	print("Saved ", full)


func _set_paused(paused: bool) -> void:
	get_tree().paused = paused
	pause_layer.visible = paused
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED


func _build_menu() -> void:
	menu = Control.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(menu)
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := ShaderMaterial.new()
	bg.shader = preload("res://shaders/menu_bg.gdshader")
	backdrop.material = bg
	menu.add_child(backdrop)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(560, 0)
	column.add_theme_constant_override("separation", 14)
	center.add_child(column)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Segoe UI", "Arial"])
	var eyebrow := Label.new()
	eyebrow.text = "SURVIVAL HORROR"
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eyebrow.add_theme_font_override("font", font)
	eyebrow.add_theme_font_size_override("font_size", 14)
	eyebrow.add_theme_color_override("font_color", Color(0.72, 0.58, 0.42))
	column.add_child(eyebrow)
	var title := Label.new()
	title.text = "ASHEN COUNTY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", font)
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(0.93, 0.9, 0.84))
	column.add_child(title)
	var copy := Label.new()
	copy.text = "Type a United States ZIP code. The ground, water, and roads are built from that place. Houses, warehouses, and factories are there to be walked through."
	copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	copy.add_theme_font_override("font", font)
	copy.add_theme_font_size_override("font_size", 18)
	copy.add_theme_color_override("font_color", Color(0.78, 0.74, 0.68))
	column.add_child(copy)
	zip_edit = LineEdit.new()
	zip_edit.placeholder_text = "ZIP code, such as 01002"
	zip_edit.max_length = 5
	zip_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	zip_edit.custom_minimum_size = Vector2(0, 52)
	zip_edit.add_theme_font_override("font", font)
	zip_edit.add_theme_font_size_override("font_size", 28)
	zip_edit.text_submitted.connect(func(_t): _start_generation(false))
	column.add_child(zip_edit)
	generate_button = Button.new()
	generate_button.text = "Generate this place"
	generate_button.custom_minimum_size = Vector2(0, 52)
	generate_button.add_theme_font_override("font", font)
	generate_button.add_theme_font_size_override("font_size", 20)
	generate_button.pressed.connect(func(): _start_generation(false))
	column.add_child(generate_button)
	progress_bar = ProgressBar.new()
	progress_bar.min_value = 0
	progress_bar.max_value = 100
	progress_bar.value = 0
	progress_bar.show_percentage = false
	progress_bar.custom_minimum_size = Vector2(0, 8)
	progress_bar.visible = false
	column.add_child(progress_bar)
	status_label = Label.new()
	status_label.text = "The first visit to a ZIP code needs an internet connection. Later visits reuse the saved map."
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_override("font", font)
	status_label.add_theme_font_size_override("font_size", 15)
	status_label.add_theme_color_override("font_color", Color(0.68, 0.66, 0.6))
	column.add_child(status_label)
	var credits := Label.new()
	credits.text = "Elevation tiles from the public terrain dataset. Imagery: U.S. Geological Survey. Map data © OpenStreetMap contributors. Ground textures: Poly Haven, CC0. Foliage cards authored for this project."
	credits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	credits.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	credits.add_theme_font_override("font", font)
	credits.add_theme_font_size_override("font_size", 12)
	credits.add_theme_color_override("font_color", Color(0.5, 0.48, 0.44))
	column.add_child(credits)
	_style_field(zip_edit)
	_style_button(generate_button)


func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.visible = false
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(hud)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(root)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Segoe UI", "Arial"])
	place_label = Label.new()
	place_label.position = Vector2(28, 22)
	place_label.add_theme_font_override("font", font)
	place_label.add_theme_font_size_override("font_size", 20)
	place_label.add_theme_color_override("font_color", Color(0.92, 0.9, 0.84))
	root.add_child(place_label)
	detail_label = Label.new()
	detail_label.position = Vector2(28, 50)
	detail_label.visible = false
	detail_label.add_theme_font_override("font", font)
	detail_label.add_theme_font_size_override("font_size", 14)
	detail_label.add_theme_color_override("font_color", Color(0.8, 0.78, 0.7))
	root.add_child(detail_label)
	var help := Label.new()
	help.text = "WASD move    Shift sprint    Space jump    F flashlight    F3 coordinates    Esc pause"
	help.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	help.offset_left = 28
	help.offset_top = -42
	help.offset_right = 900
	help.offset_bottom = -16
	help.add_theme_font_override("font", font)
	help.add_theme_font_size_override("font_size", 14)
	help.add_theme_color_override("font_color", Color(0.85, 0.82, 0.74, 0.85))
	root.add_child(help)
	var cross := ColorRect.new()
	cross.color = Color(0.95, 0.93, 0.88, 0.8)
	cross.anchor_left = 0.5
	cross.anchor_top = 0.5
	cross.anchor_right = 0.5
	cross.anchor_bottom = 0.5
	cross.offset_left = -1.5
	cross.offset_top = -1.5
	cross.offset_right = 1.5
	cross.offset_bottom = 1.5
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cross)
	nav = preload("res://scripts/nav_hud.gd").new()
	nav.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	nav.offset_left = -196.0
	nav.offset_top = 16.0
	nav.offset_right = -16.0
	nav.offset_bottom = 360.0
	nav.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(nav)


func _build_pause() -> void:
	pause_layer = Control.new()
	pause_layer.visible = false
	pause_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(pause_layer)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.025, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_layer.add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(320, 0)
	column.add_theme_constant_override("separation", 12)
	center.add_child(column)
	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	column.add_child(title)
	var resume := Button.new()
	resume.text = "Resume"
	resume.custom_minimum_size = Vector2(0, 46)
	resume.pressed.connect(func(): _set_paused(false))
	column.add_child(resume)
	var back := Button.new()
	back.text = "New ZIP code"
	back.custom_minimum_size = Vector2(0, 46)
	back.pressed.connect(func():
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().reload_current_scene()
	)
	column.add_child(back)
	_style_button(resume)
	_style_button(back)


func _style_field(field: LineEdit) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.08, 0.075, 0.07, 0.92)
	normal.border_color = Color(0.62, 0.5, 0.36)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(2)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	field.add_theme_stylebox_override("normal", normal)
	var focus := normal.duplicate()
	focus.border_color = Color(0.86, 0.72, 0.5)
	field.add_theme_stylebox_override("focus", focus)
	field.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88))
	field.add_theme_color_override("font_placeholder_color", Color(0.55, 0.5, 0.44))


func _style_button(button: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.36, 0.2, 0.12, 0.95)
	normal.set_corner_radius_all(2)
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	var hover := normal.duplicate()
	hover.bg_color = Color(0.5, 0.28, 0.16, 0.98)
	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.24, 0.13, 0.08)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", pressed)
	button.add_theme_color_override("font_color", Color(0.96, 0.93, 0.88))
	button.add_theme_color_override("font_hover_color", Color(1, 0.97, 0.92))


func _cli() -> Dictionary:
	var args := OS.get_cmdline_user_args()
	var zip_code := ""
	var shot := false
	var i := 0
	while i < args.size():
		if args[i] == "--zip" and i + 1 < args.size():
			zip_code = str(args[i + 1])
			i += 2
		elif args[i] == "--shot":
			shot = true
			i += 1
		else:
			i += 1
	return {"zip": zip_code, "shot": shot}


func _coord(value: float, latitude: bool) -> String:
	var hemi := "N" if value >= 0.0 else "S"
	if not latitude:
		hemi = "E" if value >= 0.0 else "W"
	return "%.5f°%s" % [absf(value), hemi]
