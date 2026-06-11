extends CharacterBody3D

const SPEED := 12
const GRAVITY := 9.8
const ROTATION_SPEED := 10.0

const ANIM_IDLE := "HumanArmature|Man_Idle"
const ANIM_RUN := "HumanArmature|Man_Run"
const ANIM_SIT := "HumanArmature|Man_Sitting"   # preferred sitting clip (if the model has it)
const RUN_SPEED := 1.5   # run animation playback multiplier (1.0 = normal)

# sitting (press E near a chair)
const PROMPT_RANGE := 6.0    # how close to a prompt you must be to see it
const SIT_RANGE := 5.0		# how close to a chair's sit point you must be to sit
const SIT_PITCH := -0.6   # camera tilt while seated, so the view looks down at the table
const STAND_BACK := 1.5   # how far you step away from the table when standing up
const PROMPT_HEIGHT := 2.8  # how high above the chair the "press E" popup floats
# Seated camera: an over-the-head view so you can see your own body/hands and the table.
const SIT_VIEW_HEIGHT := 4.0  # camera height above the seated body origin
const SIT_VIEW_BACK := 2.0    # how far the camera sits back from the head, to keep your body in frame

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
@onready var sit_prompt: Node3D = get_node_or_null("../SitPrompt")  # "press E" popup (sibling in Main)
@onready var seat_hud: Control = get_node_or_null("../SeatHUD/Panel")  # top-left controls list while seated
@onready var gun_hud: Control = get_node_or_null("../GunHUD/Panel")  # output while holding gun
@onready var gamble_hud: Control = get_node_or_null("../GambleHUD/Panel") # top-right controls list while seated
@onready var gun_hud_text: Label = get_node_or_null("../GunHUD/Panel/Label") # text for output while holding gun
@onready var gun_purchase_prompt: Node3D = get_node_or_null("../GunPedestal/GunPurchasePrompt") # purchase prompt for new gun
@onready var gun: Node3D = get_node_or_null("../Gun") # the revolver on the table

signal player_died # signal that player died for other scripts
signal purchase_gun # signal to purchase new gun
signal gun_shoot # signal that player shot gun (for gamble)

var current_anim := ""
var zoom_target := 1.0         # 1.0 = third person, 0.0 = first person
var zoom := 1.0
var cam_yaw := PI              # start looking +Z (behind the character)
var cam_pitch := -0.35         # start tilted slightly down

var is_sitting := false        # true while seated in a chair
var sit_anim := ""             # resolved sitting animation name ("" if the model has none)

# --- Seated arm pose (degrees, layered on the frozen sitting pose) -------------
# These are starting guesses. Tune them live: run, sit, then in the Remote scene
# tree pick Player and adjust these until the forearms rest on the table. If an
# arm bends the wrong way, flip a sign or move the angle to a different axis.
@export var arm_pose_enabled := true
@export var left_upperarm_deg := Vector3(0, 0, -20)
@export var left_lowerarm_deg := Vector3(20, 70, -10)
# Right arm bones mirror the left (Y and Z negated). X is nudged down from 20 to
# lift the right hand back up out of the table surface.
@export var right_upperarm_deg := Vector3(0, 0, 10)
@export var right_lowerarm_deg := Vector3(50, -65, 20)
# Right arm raised with the gun at the temple (snapped to on pickup). Starts equal
# to the table pose; raise these toward the head by tuning live.
@export var right_upperarm_head_deg := Vector3(30, 0, 0)
@export var right_lowerarm_head_deg := Vector3(-10, -80, -120)
# Right wrist (MiddleHand.R). Table pose is neutral; tweak the head one so the gun
# points naturally at the temple.
@export var right_hand_deg := Vector3(0, 0, 0)
@export var right_hand_head_deg := Vector3(0, 0, -30)
@export var debug_hold_at_head := false   # freeze the arm at the head pose to tune the angles

# --- Gun grip (where the revolver sits in the right hand) ----------------------
@export var gun_grip_position := Vector3.ZERO
@export var gun_grip_rotation_deg := Vector3.ZERO
@export var gun_grip_scale := 0.01   # gun is scaled to this in-hand (its table scale is restored on drop)
@export var muzzle_offset := Vector3(0, 0, -0.5)   # where the smoke puff spawns, relative to the right hand

const HAND_BONE := "MiddleHand.R"
const ARM_BONES := ["UpperArm.L", "LowerArm.L", "UpperArm.R", "LowerArm.R", "MiddleHand.R"]

var skeleton: Skeleton3D
var bone_sim: PhysicalBoneSimulator3D   # ragdoll simulator (Godot 4.4+); inactive until death
var arm_bone_idx := {}         # bone name -> index
var arm_base := {}             # bone name -> sitting-pose rotation captured on sit
var hand_holder: Node3D        # follows the right hand bone; the gun parents here when held
var gun_home: Transform3D      # the gun's resting transform on the table
var has_gun := false
var muzzle_smoke: CPUParticles3D   # puff emitted when the gun actually fires

# --- Russian-roulette sequence -------------------------------------------------
var LIVE := 1
var CHAMBERS := 6
var RAISE_TIME := 0.5   # seconds to bring the gun up to the temple (and back down)
var HOLD_TIME := 0.5    # suspense pause at the temple before the trigger resolves

var gambleUnlocked := false # becomes true when cash >= 8
var WAGER := 0 # amount of money gambled
var GAMBLE_CHOICE := false # false = miss, true = hit

enum GunSeq { IDLE, RAISING, HOLD, LOWERING, DEAD }
var gun_seq := GunSeq.IDLE
var raise_amount := 0.0   # 0 = arm resting on table, 1 = gun at head
var seq_timer := 0.0
var loaded_chamber := -1  # which chamber holds the live round
var current_chamber := 0  # chamber currently under the hammer

var game_over := false







func _ready() -> void:
	randomize()
	_resolve_sit_anim()
	for anim_name in [ANIM_IDLE, ANIM_RUN, sit_anim]:
		if anim_name != "" and anim_player and anim_player.has_animation(anim_name):
			anim_player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	_play_anim(ANIM_IDLE)
	_setup_skeleton()
	if gun:
		gun_home = gun.global_transform


# Cache the arm bones and attach a holder node to the right hand bone (the gun
# parents under it when picked up, so it follows the hand automatically).
func _setup_skeleton() -> void:
	skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return
	# The PhysicalBoneSimulator3D is created "active", which makes it override the
	# animation every frame (breaks walking). Keep it off until we ragdoll on death.
	bone_sim = skeleton.find_child("PhysicalBoneSimulator3D", true, false) as PhysicalBoneSimulator3D
	if bone_sim:
		bone_sim.active = false
	for b in ARM_BONES:
		arm_bone_idx[b] = skeleton.find_bone(b)
	if skeleton.find_bone(HAND_BONE) != -1:
		var attach := BoneAttachment3D.new()
		attach.bone_name = HAND_BONE
		skeleton.add_child(attach)
		hand_holder = Node3D.new()
		attach.add_child(hand_holder)
	# Muzzle smoke lives on the Player (not the hand) so the puff stays put in the
	# world when fired instead of riding the death animation.
	muzzle_smoke = _make_muzzle_smoke()
	add_child(muzzle_smoke)


# A one-shot grey smoke burst (CPUParticles3D works on every renderer, including
# Compatibility). Tune the spawn point with muzzle_offset; sizes are below.
func _make_muzzle_smoke() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 40
	p.lifetime = 1.0
	p.explosiveness = 0.95
	p.direction = Vector3(0, 1, 0)
	p.spread = 55.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.8
	p.gravity = Vector3(0, 0.4, 0)
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.5
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.5))
	grow.add_point(Vector2(1, 1.3))
	p.scale_amount_curve = grow
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.9, 0.9, 0.9, 0.9))
	ramp.set_color(1, Color(0.7, 0.7, 0.7, 0.0))
	p.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2(0.6, 0.6)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	quad.material = mat
	p.mesh = quad
	return p


func _emit_muzzle_smoke() -> void:
	if muzzle_smoke == null:
		push_warning("muzzle_smoke is null - particle creation failed")
		return
	if hand_holder == null:
		return
	# orthonormalized() keeps the hand's position + rotation but strips the bone's
	# (large) scale, so muzzle_offset stays in world units instead of being flung away.
	muzzle_smoke.global_position = hand_holder.global_transform.orthonormalized() * muzzle_offset
	muzzle_smoke.restart()
	muzzle_smoke.emitting = true
	print("muzzle smoke fired at ", muzzle_smoke.global_position)


func _first_in_group(group: String) -> Node3D:
	var nodes := get_tree().get_nodes_in_group(group)
	return nodes[0] as Node3D if nodes.size() > 0 else null


# Use the built-in sitting clip if it exists; otherwise fall back to any animation
# whose name mentions "sit". Leaves sit_anim as "" if the model has none.
func _resolve_sit_anim() -> void:
	if not anim_player:
		return
	if anim_player.has_animation(ANIM_SIT):
		sit_anim = ANIM_SIT
		return
	for anim_name in anim_player.get_animation_list():
		if anim_name.to_lower().contains("sit"):
			sit_anim = anim_name
			return


func _unhandled_input(event: InputEvent) -> void:
	if not game_over:
		if event.is_action_pressed("interact"):
			_interact_event()
			return
		if event.is_action_pressed("pickup_gun"):
			_try_pickup_gun()
			return
		if event.is_action_pressed("spin_barrel"):
			_spin_barrel()
			return
		if event.is_action_pressed("shoot"):
			_shoot()
			return
		if event.is_action_pressed("gamble_hit") and gambleUnlocked:
			_change_gamble_choice(true)
			return
		if event.is_action_pressed("gamble_miss") and gambleUnlocked:
			_change_gamble_choice(false)
			return
		if event.is_action_pressed("gamble_clear") and gambleUnlocked:
			_change_gamble_wager(-1)
			return
		if event is InputEventKey and gambleUnlocked:
			if event.pressed:
				var key = event.as_text_key_label()
				if key.is_valid_int():
					_change_gamble_wager(key.to_int())
					return
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				# Locked to first person while seated: ignore zoom.
				if not is_sitting:
					zoom_target = clampf(zoom_target - ZOOM_STEP, 0.0, 1.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				if not is_sitting:
					zoom_target = clampf(zoom_target + ZOOM_STEP, 0.0, 1.0)
			MOUSE_BUTTON_RIGHT:
				# JUUUUST LIKE ROBLOX
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			cam_yaw -= event.relative.x * MOUSE_SENS
			cam_pitch -= event.relative.y * MOUSE_SENS
			cam_pitch = clampf(cam_pitch, PITCH_MIN, PITCH_MAX)

func _interact_event() -> void:
	if is_sitting:
		_stand_up()
	else:
		var target := _nearest_sit_point()
		if target != null:
			_sit_down(target)
			return
	
	if global_position.distance_to(gun_purchase_prompt.global_position) < PROMPT_RANGE:
		purchase_gun.emit()

func _sit_down(target : Node3D) -> void:
	is_sitting = true
	velocity = Vector3.ZERO
	global_position = target.global_position
	# Face the table (the room/table centre is the world origin in the X/Z plane).
	var to_centre := Vector2(-global_position.x, -global_position.z)
	if to_centre.length() < 0.001:
		to_centre = Vector2(0, -1)
	to_centre = to_centre.normalized()
	# The model's forward is +Z; the camera's forward is -Z, hence the sign flip.
	model.rotation.y = atan2(to_centre.x, to_centre.y)
	cam_yaw = atan2(-to_centre.x, -to_centre.y)
	cam_pitch = SIT_PITCH
	# Snap straight into first person and lock it there.
	zoom_target = 0.0
	zoom = 0.0
	# Freeze the sitting pose on a frame so we can lay the arms on the table on top.
	if anim_player and sit_anim != "":
		current_anim = sit_anim
		anim_player.play(sit_anim)
		anim_player.seek(0.2, true)
		anim_player.pause()
	_capture_arm_base()
	if seat_hud:
		seat_hud.visible = true
		if gamble_hud and gambleUnlocked:
			gamble_hud.visible = true


# Remember the sitting-pose rotation of each arm bone so the table pose can be
# applied as an offset on top of it.
func _capture_arm_base() -> void:
	arm_base.clear()
	if skeleton == null:
		return
	for b in ARM_BONES:
		var idx: int = arm_bone_idx.get(b, -1)
		if idx != -1:
			arm_base[b] = skeleton.get_bone_pose_rotation(idx)


func _apply_seated_arms() -> void:
	if not arm_pose_enabled or skeleton == null:
		return
	if gun_seq == GunSeq.DEAD:
		return   # hands off — let the death animation play
	var t := 1.0 if debug_hold_at_head else raise_amount
	# Left arm stays on the table; the right arm blends up to the head pose as we raise.
	_set_arm_pose("UpperArm.L", left_upperarm_deg)
	_set_arm_pose("LowerArm.L", left_lowerarm_deg)
	_set_arm_pose("UpperArm.R", right_upperarm_deg.lerp(right_upperarm_head_deg, t))
	_set_arm_pose("LowerArm.R", right_lowerarm_deg.lerp(right_lowerarm_head_deg, t))
	_set_arm_pose("MiddleHand.R", right_hand_deg.lerp(right_hand_head_deg, t))


func _set_arm_pose(bone_name: String, deg: Vector3) -> void:
	var idx: int = arm_bone_idx.get(bone_name, -1)
	if idx == -1:
		return
	var base: Quaternion = arm_base.get(bone_name, Quaternion.IDENTITY)
	var offset := Quaternion.from_euler(Vector3(deg_to_rad(deg.x), deg_to_rad(deg.y), deg_to_rad(deg.z)))
	skeleton.set_bone_pose_rotation(idx, base * offset)


# --- Russian-roulette loop: pick up (F) -> spin (R) -> trigger (Space) ----------
func _try_pickup_gun() -> void:
	if not is_sitting or has_gun or gun == null or hand_holder == null:
		return
	gun.reparent(hand_holder, false)
	var grip_basis := Basis.from_euler(Vector3(
		deg_to_rad(gun_grip_rotation_deg.x),
		deg_to_rad(gun_grip_rotation_deg.y),
		deg_to_rad(gun_grip_rotation_deg.z)))
	grip_basis = grip_basis.scaled(Vector3.ONE * gun_grip_scale)
	gun.transform = Transform3D(grip_basis, gun_grip_position)
	has_gun = true
	# Load one live round into a random chamber.
	loaded_chamber = randi() % CHAMBERS
	current_chamber = randi() % CHAMBERS
	gun_seq = GunSeq.IDLE
	raise_amount = 1.0   # snap the arm straight up to the head, gun at the temple
	if gun_hud and gun_hud_text:
		gun_hud_text.text = "Picked up the revolver. [R] spin the cylinder, [Space] pull the trigger."
		gun_hud.visible = true

func _change_gamble_choice(choice : bool) -> void:
	if not is_sitting:
		return
	GAMBLE_CHOICE = choice
	if gun_hud and gun_hud_text:
		if choice:
			gun_hud_text.text = "You believe the next bullet is live."
		else:
			gun_hud_text.text = "You believe the next bullet is blank."

func _change_gamble_wager(amount : int) -> void:
	if not is_sitting:
		return
	if amount == -1:
		WAGER = 0
		if gun_hud and gun_hud_text:
			gun_hud_text.text = "You second guess your wager, and back out."
	else:
		WAGER += amount
		if gun_hud and gun_hud_text:
			gun_hud_text.text = "You increase your wager to " + String.num_int64(WAGER) + " dollars."

func _spin_barrel() -> void:
	if not has_gun or gun_seq != GunSeq.IDLE:
		return
	current_chamber = randi() % CHAMBERS
	if gun_hud and gun_hud_text:
		gun_hud_text.text = "You give the cylinder a spin... it rattles to a stop."


func _shoot() -> void:
	if not has_gun or gun_seq != GunSeq.IDLE:
		return
	gun_seq = GunSeq.HOLD
	seq_timer = HOLD_TIME


# Counts down the suspense hold, then fires. Called every frame while seated.
func _update_gun_sequence(delta: float) -> void:
	if gun_seq == GunSeq.HOLD:
		seq_timer -= delta
		if seq_timer <= 0.0:
			_fire()


func _fire() -> void:
	var is_live := current_chamber == loaded_chamber
	current_chamber = (current_chamber + 1) % CHAMBERS  # cylinder advances one notch
	gun_shoot.emit(WAGER, GAMBLE_CHOICE, is_live)
	if is_live:
		if gun_hud and gun_hud_text:
			if WAGER == 0:
				gun_hud_text.text = "*BANG* - the live round fires."
			else:
				if GAMBLE_CHOICE:
					gun_hud_text.text = "*BANG* - you were correct."
				else:
					gun_hud_text.text = "*BANG* - you were incorrect."
		_emit_muzzle_smoke()   # puff of smoke on a real shot
		_die()
	else:
		if gun_hud and gun_hud_text:
			if WAGER == 0:
				gun_hud_text.text = "*click* - empty chamber."
			else:
				if GAMBLE_CHOICE:
					gun_hud_text.text = "*click* - you were incorrect."
				else:
					gun_hud_text.text = "*click* - you were correct."
		# TODO: play the empty-click sound here (add an AudioStreamPlayer3D and .play()).
		gun_seq = GunSeq.IDLE   # stay at the head, ready to spin/shoot again
	WAGER = 0


func _die() -> void:
	player_died.emit()
	gun_seq = GunSeq.DEAD
	# NOTE: physics ragdoll doesn't work on this model — its skeleton carries a large
	# baked scale (same reason gun_grip_scale is 0.01), and Godot can't simulate
	# PhysicalBone3D under a scaled skeleton (the body tears apart / collapses). So we
	# play the death clip instead. The PhysicalBoneSimulator3D is kept inactive in
	# _setup_skeleton so it doesn't override the normal animations.
	if anim_player and anim_player.has_animation("HumanArmature|Man_Death"):
		current_anim = "HumanArmature|Man_Death"
		anim_player.play("HumanArmature|Man_Death")
	await get_tree().create_timer(3.0).timeout
	if gun_seq == GunSeq.DEAD:   # still dead (didn't manually stand up)
		raise_amount = 0.0
		_stand_up()   # reset: drop gun, get up, back to idle


func _shoot_state_reset() -> void:
	gun_seq = GunSeq.IDLE
	raise_amount = 0.0
	seq_timer = 0.0


func _stand_up() -> void:
	is_sitting = false
	_shoot_state_reset()
	if seat_hud:
		seat_hud.visible = false
	if gun_hud and not game_over:
		gun_hud.visible = false
	if gamble_hud and gambleUnlocked:
		gamble_hud.visible = false
	# Put the gun back on the table before getting up.
	if has_gun and gun:
		gun.reparent(get_parent(), false)
		gun.global_transform = gun_home
		has_gun = false
	# Step away from the table (outward from centre) and drop back to the floor.
	var outward := Vector2(global_position.x, global_position.z)
	if outward.length() < 0.001:
		outward = Vector2(0, 1)
	outward = outward.normalized() * STAND_BACK
	global_position = Vector3(global_position.x + outward.x, 0.0, global_position.z + outward.y)
	zoom_target = 1.0
	current_anim = ""          # force the locomotion animation to replay next frame (also unpauses it)
	_play_anim(ANIM_IDLE)


# Nearest chair sit point within SIT_RANGE, or null if there isn't one close enough.
func _nearest_sit_point() -> Node3D:
	var best: Node3D = null
	var best_dist := SIT_RANGE
	for node in get_tree().get_nodes_in_group("sit_points"):
		if node is Node3D:
			var d := global_position.distance_to(node.global_position)
			if d < best_dist:
				best_dist = d
				best = node
	return best


func _physics_process(delta: float) -> void:
	if is_sitting:
		# Stay put in the chair; run the roulette sequence, pose the arms, keep the camera live.
		velocity = Vector3.ZERO
		_update_gun_sequence(delta)
		_apply_seated_arms()
		_update_camera(delta)
		_update_prompts()
		return

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
	_update_prompts()

func _update_prompts() -> void:
	_update_sit_prompt()
	_update_gun_purchase_prompt()

# Float the "press E" popup above the nearest chair when one is in range,
# and hide it while seated or when no chair is close.
func _update_sit_prompt() -> void:
	if sit_prompt == null:
		return
	if is_sitting:
		sit_prompt.visible = false
		return
	var target := _nearest_sit_point()
	if target != null:
		sit_prompt.global_position = target.global_position + Vector3(0, PROMPT_HEIGHT, 0)
		sit_prompt.visible = true
	else:
		sit_prompt.visible = false

func _update_gun_purchase_prompt() -> void:
	if gun_purchase_prompt == null:
		return
	if global_position.distance_to(gun_purchase_prompt.global_position) < PROMPT_RANGE:
		gun_purchase_prompt.visible = true
	else:
		gun_purchase_prompt.visible = false


func _update_camera(delta: float) -> void:
	# While seated: keep the body visible and frame it (and the table) from just
	# above and behind the head, looking down. Lets you see your hands at the table.
	if is_sitting:
		var sit_pivot := global_position + Vector3(0, SIT_VIEW_HEIGHT, 0)
		var sit_basis := Basis.from_euler(Vector3(cam_pitch, cam_yaw, 0))
		var forward := -sit_basis.z
		camera.global_position = sit_pivot - forward * SIT_VIEW_BACK
		camera.global_rotation = Vector3(cam_pitch, cam_yaw, 0)
		model.visible = true
		return

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
	# solution: once distance <= 0.5, point cam_yaw toward the model's facing so FP tracks where you're walking
	model.visible = distance > 0.5


func _play_anim(anim_name: String, speed := 1.0) -> void:
	if not anim_player or current_anim == anim_name:
		return
	if not anim_player.has_animation(anim_name):
		return
	current_anim = anim_name
	anim_player.play(anim_name, -1, speed)


func _on_update_gun_values(rate, chance) -> void:
	RAISE_TIME = rate/2
	HOLD_TIME = rate/2
	LIVE = chance[0]
	CHAMBERS = chance[1]


func _on_unlock_gamble() -> void:
	gambleUnlocked = true
	game_over = true
	if gun_hud and gun_hud_text:
		await get_tree().create_timer(1.5).timeout
		gun_hud_text.text = "You have unlocked the ability to gamble."
		await get_tree().create_timer(3.0).timeout
		gun_hud_text.text = "Be wary, going into debt has consequences..."
		await get_tree().create_timer(3.0).timeout
		gun_hud.visible = false
		game_over = false


func _on_game_over() -> void:
	game_over = true
	_stand_up()
	if gun_hud and gun_hud_text:
		await get_tree().create_timer(0.5).timeout
		gun_hud_text.text = "You gambled too much, and are now in debt."
		await get_tree().create_timer(3.0).timeout
		gun_hud_text.text = "Unfortuantely for you, the house always wins."
		await get_tree().create_timer(3.0).timeout
		gun_hud.visible = false
