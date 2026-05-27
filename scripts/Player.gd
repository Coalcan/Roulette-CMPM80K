extends CharacterBody3D

const SPEED := 4.0
const GRAVITY := 9.8
const ROTATION_SPEED := 10.0

const ANIM_IDLE := "HumanArmature|Man_Idle"
const ANIM_RUN := "HumanArmature|Man_Run"

@onready var model: Node3D = $Male_Casual
@onready var anim_player: AnimationPlayer = model.find_child("AnimationPlayer", true, false)

var current_anim := ""


func _ready() -> void:
	_play_anim(ANIM_IDLE)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := Vector3(input_dir.x, 0, input_dir.y).normalized()

	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
		var target_yaw := atan2(direction.x, direction.z)
		model.rotation.y = lerp_angle(model.rotation.y, target_yaw, ROTATION_SPEED * delta)
		_play_anim(ANIM_RUN)
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
		_play_anim(ANIM_IDLE)

	move_and_slide()


func _play_anim(anim_name: String) -> void:
	if not anim_player or current_anim == anim_name:
		return
	if not anim_player.has_animation(anim_name):
		return
	current_anim = anim_name
	anim_player.play(anim_name)
