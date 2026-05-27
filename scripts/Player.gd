extends CharacterBody3D

const SPEED := 6.0
const GRAVITY := 9.8
const ROTATION_SPEED := 10.0

const ANIM_IDLE := "HumanArmature|Man_Idle"
const ANIM_RUN := "HumanArmature|Man_Run"
const RUN_SPEED := 1.5   # run animation playback multiplier (1.0 = normal)

# camera degrees of freedom, right click and scroll wheel input min/max
const PIVOT_HEIGHT := 4      # point the camera orbits around (head height)
const TP_DISTANCE := 7.0       # orbit distance at full third person
const MOUSE_SENS := 0.005      # right-drag look sensitivity
const PITCH_MIN := -1.4        # how far you can look up/down (radians)
const PITCH_MAX := 1.4
const ZOOM_STEP := 0.15        # how much each scroll notch changes zoom
const ZOOM_LERP := 10.0        # zoom smoothing

@onready var model: Node3D = $Male_Casual
@onready var anim_player: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
@onready var camera: Camera3D = $Camera3D

var current_anim := ""
var zoom_target := 1.0         # 1.0 = third person, 0.0 = first person
var zoom := 1.0
var cam_yaw := PI              # start looking +Z (behind the character)
var cam_pitch := -0.35         # start tilted slightly down







func _ready() -> void:
	for anim_name in [ANIM_IDLE, ANIM_RUN]:
		if anim_player and anim_player.has_animation(anim_name):
			anim_player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	_play_anim(ANIM_IDLE)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				zoom_target = clampf(zoom_target - ZOOM_STEP, 0.0, 1.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				zoom_target = clampf(zoom_target + ZOOM_STEP, 0.0, 1.0)
			MOUSE_BUTTON_RIGHT:
				# JUUUUST LIKE ROBLOX
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			cam_yaw -= event.relative.x * MOUSE_SENS
			cam_pitch -= event.relative.y * MOUSE_SENS
			cam_pitch = clampf(cam_pitch, PITCH_MIN, PITCH_MAX)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	# This camera shit is driving me insane
	# Walk direction coorelation to camera direction
	var input_x := Input.get_axis("move_left", "move_right")
	var input_y := Input.get_axis("move_back", "move_forward")
	var cam_basis := Basis(Vector3.UP, cam_yaw)
	var forward := -cam_basis.z
	var right := cam_basis.x
	forward.y = 0.0
	right.y = 0.0
	var direction := (forward.normalized() * input_y + right.normalized() * input_x).normalized()

	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
		var target_yaw := atan2(direction.x, direction.z)
		model.rotation.y = lerp_angle(model.rotation.y, target_yaw, ROTATION_SPEED * delta)
		_play_anim(ANIM_RUN, RUN_SPEED)
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
		_play_anim(ANIM_IDLE)

	move_and_slide()
	_update_camera(delta)


func _update_camera(delta: float) -> void:
	zoom = lerpf(zoom, zoom_target, ZOOM_LERP * delta)
	var distance := TP_DISTANCE * zoom
	var pivot := global_position + Vector3(0, PIVOT_HEIGHT, 0)
	var cam_basis := Basis.from_euler(Vector3(cam_pitch, cam_yaw, 0))
	# Place the camera behind the pivot along its local +Z, then aim it at the pivot.
	camera.global_position = pivot + cam_basis.z * distance
	camera.global_rotation = Vector3(cam_pitch, cam_yaw, 0)
	# Hide the model when we're basically inside its head.
	# ADD: once distance <= 0.5 shift the camera to follow the players direction instead of right click controls
	# tryna make it feel like roblox
	model.visible = distance > 0.5


func _play_anim(anim_name: String, speed := 1.0) -> void:
	if not anim_player or current_anim == anim_name:
		return
	if not anim_player.has_animation(anim_name):
		return
	current_anim = anim_name
	anim_player.play(anim_name, -1, speed)
