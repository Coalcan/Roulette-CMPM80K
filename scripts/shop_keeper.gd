extends Node3D

const ANIM_IDLE := "HumanArmature|Man_Idle"
const ANIM_CLAPPING := "HumanArmature|Man_Clapping"

@onready var anim_player: AnimationPlayer = find_child("AnimationPlayer", true, false)

var current_anim := ""

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	anim_player.get_animation(ANIM_IDLE).loop_mode = Animation.LOOP_LINEAR
	_play_anim(ANIM_IDLE)
	
func _play_anim(anim_name: String, speed := 1.0) -> void:
	if not anim_player or current_anim == anim_name:
		return
	if not anim_player.has_animation(anim_name):
		return
	current_anim = anim_name
	anim_player.play(anim_name, -1, speed)


func _on_player_died() -> void:
	_play_anim(ANIM_CLAPPING)
	await get_tree().create_timer(1.75).timeout
	_play_anim(ANIM_IDLE)
