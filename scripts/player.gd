extends CharacterBody3D

const EYE_HEIGHT := 1.62
const CROUCH_HEIGHT := 1.08
const WALK_SPEED := 4.15
const SPRINT_SPEED := 7.4
const CROUCH_SPEED := 2.15
const JUMP_VELOCITY := 4.75
const MOUSE_SENS := 0.00215

var camera: Camera3D
var flashlight: SpotLight3D
var pitch := -0.06
var bob := 0.0
var flashlight_on := false
var crouching := false
var _step_player: AudioStreamPlayer3D
var _soft_step: AudioStreamWAV
var _hard_step: AudioStreamWAV
var _step_timer := 0.0
var _fall_speed := 0.0
var _land_dip := 0.0
var _bob_side := 0.0

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(50.0)
	safe_margin = 0.08
	var shape := CapsuleShape3D.new()
	shape.radius = 0.28
	shape.height = 1.7
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0, 0.86, 0)
	add_child(col)
	camera = Camera3D.new()
	camera.position = Vector3(0, EYE_HEIGHT, 0)
	camera.fov = 68.0
	camera.near = 0.12
	camera.far = 28000.0
	var attrs := CameraAttributesPractical.new()
	attrs.auto_exposure_enabled = false
	attrs.exposure_sensitivity = 100.0
	camera.attributes = attrs
	add_child(camera)
	flashlight = SpotLight3D.new()
	flashlight.position = Vector3(0.18, -0.12, -0.08)
	flashlight.rotation_degrees = Vector3(-8, 0, 0)
	flashlight.light_color = Color(1.0, 0.86, 0.68)
	flashlight.light_energy = 3.6
	flashlight.spot_range = 24.0
	flashlight.spot_angle = 22.0
	flashlight.spot_attenuation = 1.2
	flashlight.light_volumetric_fog_energy = 1.8
	flashlight.shadow_enabled = true
	flashlight.shadow_bias = 0.04
	flashlight.visible = false
	camera.add_child(flashlight)
	camera.rotation.x = pitch
	_soft_step = _step_wav(false)
	_hard_step = _step_wav(true)
	_step_player = AudioStreamPlayer3D.new()
	_step_player.stream = _soft_step
	_step_player.unit_size = 1.5
	_step_player.max_distance = 16.0
	_step_player.volume_db = -6.0
	_step_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(_step_player)


func _unhandled_input(event: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * MOUSE_SENS)
		pitch = clampf(pitch - event.relative.y * MOUSE_SENS, -1.35, 1.35)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F:
			flashlight_on = not flashlight_on
			flashlight.visible = flashlight_on


func _physics_process(delta: float) -> void:
	var gravity: float = 17.5
	var on_floor := is_on_floor()
	if not on_floor:
		velocity.y -= gravity * delta
		_fall_speed = maxf(_fall_speed, -velocity.y)
	else:
		if _fall_speed > 4.8:
			_land_dip = clampf(_fall_speed * 0.012, 0.03, 0.09)
		_fall_speed = 0.0
		if velocity.y < 0.0:
			velocity.y = -0.35
	crouching = Input.is_key_pressed(KEY_CTRL)
	var wish := Vector3.ZERO
	var forward := -global_transform.basis.z
	var right := global_transform.basis.x
	forward.y = 0.0
	right.y = 0.0
	forward = forward.normalized()
	right = right.normalized()
	if Input.is_key_pressed(KEY_W):
		wish += forward
	if Input.is_key_pressed(KEY_S):
		wish -= forward
	if Input.is_key_pressed(KEY_D):
		wish += right
	if Input.is_key_pressed(KEY_A):
		wish -= right
	var speed := WALK_SPEED
	if crouching:
		speed = CROUCH_SPEED
	elif Input.is_key_pressed(KEY_SHIFT):
		speed = SPRINT_SPEED
	var target := Vector3.ZERO
	if wish.length() > 0.01:
		wish = wish.normalized()
		target = wish * speed
	var rate := 28.0 if on_floor else 8.0
	if target.length() < 0.1:
		rate = 22.0 if on_floor else 4.0
	velocity.x = move_toward(velocity.x, target.x, rate * delta)
	velocity.z = move_toward(velocity.z, target.z, rate * delta)
	if Input.is_key_pressed(KEY_SPACE) and on_floor and not crouching:
		velocity.y = JUMP_VELOCITY
	move_and_slide()
	var target_eye := CROUCH_HEIGHT if crouching else EYE_HEIGHT
	var horizontal := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and horizontal > 0.45:
		bob += delta * horizontal * 1.65
		target_eye += sin(bob) * 0.028
		_bob_side = cos(bob * 0.5) * 0.016
		_step_timer -= delta
		var interval := 0.52 if speed < 6.0 else 0.36
		if crouching:
			interval = 0.68
		if _step_timer <= 0.0:
			_step_timer = interval * clampf(WALK_SPEED / maxf(horizontal, 0.5), 0.75, 1.35)
			_play_step()
	else:
		_bob_side = 0.0
		_step_timer = 0.12
	_land_dip = move_toward(_land_dip, 0.0, delta * 0.28)
	target_eye -= _land_dip
	var blend := 1.0 - exp(-delta * 12.0)
	camera.position.y = lerpf(camera.position.y, target_eye, blend)
	camera.position.x = lerpf(camera.position.x, _bob_side, blend)
	var roll := 0.0
	if wish.length() > 0.1:
		roll = -right.dot(wish.normalized()) * 0.012
	camera.rotation.z = lerpf(camera.rotation.z, roll, blend)
	camera.rotation.x = lerpf(camera.rotation.x, pitch, 1.0 - exp(-delta * 22.0))


func _play_step() -> void:
	if _step_player == null:
		return
	var hard := false
	var space := get_world_3d().direct_space_state
	if space:
		var from := global_position + Vector3(0, 0.4, 0)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -1.4, 0), 1))
		if not hit.is_empty():
			var body: Object = hit.collider
			var label := str(body)
			if body is Node:
				label = str((body as Node).name)
			hard = label.to_lower().contains("road")
	_step_player.stream = _hard_step if hard else _soft_step
	_step_player.pitch_scale = randf_range(0.92, 1.08)
	_step_player.play()


func _step_wav(hard: bool) -> AudioStreamWAV:
	var rate := 22050
	var seconds := 0.09 if hard else 0.14
	var count := int(seconds * float(rate))
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var hold := 0.0
	for i in count:
		var t := float(i) / float(rate)
		var env := exp(-t * (38.0 if hard else 18.0))
		var n := rng.randf_range(-1.0, 1.0)
		hold = lerpf(hold, n, 0.35 if hard else 0.12)
		var body := sin(TAU * (180.0 if hard else 70.0) * t) * (0.35 if hard else 0.55)
		var s := (hold * 0.7 + body) * env
		bytes.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 26000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = bytes
	return stream
