extends Node3D

const ROTATION_SPEED := PI/3

func _process(delta: float) -> void:
	rotation.y += ROTATION_SPEED * delta
