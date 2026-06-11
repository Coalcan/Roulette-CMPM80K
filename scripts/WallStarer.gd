extends Node

const ACCELERATION := 0.5
const ROTATION_SPEED := 20.0
const KILL_DISTANCE := 1.0
const IDLE_ANIM := "HumanArmature|Man_Idle"

@onready var player : CharacterBody3D = get_node_or_null("../../../Player")
@onready var body : CharacterBody3D = get_node_or_null("../..")
@onready var death_screen : CanvasLayer = get_node_or_null("../../../DeathScreen")

@export var spin_speed := 0.6        # radians per second (~10s per full revolution)
@export var spin_axis := Vector3.UP  # head-local axis to spin around; flip to FORWARD/RIGHT if it tilts

var _skel: Skeleton3D
var _head_idx := -1
var _head_base := Quaternion.IDENTITY
var _angle := 0.0
var SPEED := 0.0

var kill_mode := false

func _ready() -> void:
	var root := get_parent()
	if root == null:
		return
		
	var anim := root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim and anim.has_animation(IDLE_ANIM):
		anim.play(IDLE_ANIM)
		anim.seek(0.0, true)   # apply the pose right now...
		anim.pause()           # ...and hold it there (no breathing/sway)

	# Cache the head bone so we can spin it on top of that frozen pose.
	_skel = root.find_child("Skeleton3D", true, false) as Skeleton3D
	if _skel:
		_head_idx = _find_head_bone(_skel)
		if _head_idx != -1:
			_head_base = _skel.get_bone_pose_rotation(_head_idx)


func _process(delta: float) -> void:
	if _skel == null or _head_idx == -1:
		return
	if (kill_mode):
		_angle = fmod(_angle + spin_speed * delta * 5 * (SPEED + 1), TAU)
	else:
		_angle = fmod(_angle + spin_speed * delta, TAU)
	_skel.set_bone_pose_rotation(_head_idx, _head_base * Quaternion(spin_axis.normalized(), _angle))
	
	if char == null or player == null:
		return
	if kill_mode:
		var direction = player.position - body.position
		if direction.length() < KILL_DISTANCE:
			death_screen.visible = true
			kill_mode = false
			return
		SPEED += ACCELERATION * delta
		body.velocity.x = direction.normalized().x * SPEED
		body.velocity.z = direction.normalized().z * SPEED
		var target_yaw := atan2(direction.x, direction.z)
		body.rotation.y = lerp_angle(body.rotation.y, target_yaw, ROTATION_SPEED * delta)
		body.move_and_slide()

func _find_head_bone(skel: Skeleton3D) -> int:
	var exact := skel.find_bone("Head")
	if exact != -1:
		return exact
	for i in skel.get_bone_count():
		if skel.get_bone_name(i).to_lower().contains("head"):
			return i
	return -1


func _on_main_game_over() -> void:
	await get_tree().create_timer(5.0).timeout
	kill_mode = true
