extends CharacterBody3D

@export var character_path := "res://characters/Ch38_nonPBR.fbx"
@export var turf_y := 0.0
@export var jog_speed := 3.5
@export var sprint_speed := 5.5
@export var turn_speed := 2.4
@export var control_turn_speed := 1.2
@export var anim_blend := 0.2

# Ball-contact / foot-reach (PES/UFL model: no per-bone colliders).
@export var contact_radius := 0.12
@export var foot_ray_length := 0.35
@export var debug_physics := false

const ANIM_IDLE := "Offensive_Idle"
const ANIM_JOG_FWD := "Jog_Fwd"
const ANIM_JOG_BACK := "Jog_Back"
const ANIM_DRIBBLE := "Dribble"

# Ch38 retargeted clips (committed by game/tools/retarget_mixamo.gd). Track
# paths are "Skeleton3D:mixamorig5_<bone>" (Ch38's skeleton is the scene root).
const MIXAMO_CLIPS := {
	"Soccer_Idle": "res://characters/Soccer_Idle.tres",
	"Offensive_Idle": "res://characters/Offensive_Idle.tres",
	"Jog_Fwd": "res://characters/Jog_Fwd.tres",
	"Jog_Back": "res://characters/Jog_Back.tres",
	"Jog_Strafe_Left": "res://characters/Jog_Strafe_Left.tres",
	"Jog_Strafe_Right": "res://characters/Jog_Strafe_Right.tres",
	"Jog_Fwd_Diag": "res://characters/Jog_Fwd_Diag.tres",
	"Jog_Back_Diag": "res://characters/Jog_Back_Diag.tres",
	"Strike_Fwd_Jog": "res://characters/Strike_Fwd_Jog.tres",
	"Dribble": "res://characters/Dribble.tres",
	"Chip": "res://characters/Chip.tres",
	"Header": "res://characters/Header.tres",
	"Header_Soccerball": "res://characters/Header_Soccerball.tres",
	"Soccer_Header": "res://characters/Soccer_Header.tres",
	"Kick_Soccerball": "res://characters/Kick_Soccerball.tres",
	"Soccer_Pass": "res://characters/Soccer_Pass.tres",
	"Soccer_Penalty_Kick": "res://characters/Soccer_Penalty_Kick.tres",
	"Soccer_Tackle": "res://characters/Soccer_Tackle.tres",
	"Receive": "res://characters/Receive.tres",
	"Receive_Soccerball": "res://characters/Receive_Soccerball.tres",
	"Stall_Soccerball": "res://characters/Stall_Soccerball.tres",
	"Throw_In": "res://characters/Throw_In.tres",
	"Kneeing_Soccerball": "res://characters/Kneeing_Soccerball.tres",
	"Fallen_Idle": "res://characters/Fallen_Idle.tres",
	"Standing_Up": "res://characters/Standing_Up.tres",
}

var _character: Node3D
var _ap: AnimationPlayer
var _anim := ""
var _interaction: Node  # FootballInteraction, resolved after _ready
var _kick_anim_timer := 0.0

func _ready() -> void:
	_ensure_input_actions()
	if _character == null:
		_load_character()
	if _character != null:
		_attach_animations()
	_interaction = get_node_or_null("FootballInteraction")

func _physics_process(delta: float) -> void:
	if _kick_anim_timer > 0.0:
		_kick_anim_timer -= delta
	if not is_on_floor():
		velocity.y -= float(ProjectSettings.get_setting("physics/3d/default_gravity")) * delta
	else:
		velocity.y = 0.0

	var controlling := false
	if _interaction != null and _interaction.has_method("has_ball"):
		controlling = _interaction.call("has_ball")
	var turn := Input.get_axis("turn_left", "turn_right")
	if absf(turn) > 0.001:
		var ts := control_turn_speed if controlling else turn_speed
		rotate_y(-turn * ts * delta)

	var move := Input.get_axis("move_back", "move_forward")
	var dribble := Input.is_action_pressed("dribble")
	var speed_multiplier := 1.0
	if _interaction != null and _interaction.has_method("get_movement_multiplier"):
		speed_multiplier = float(_interaction.call("get_movement_multiplier"))
	var forward := global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() > 0.0001:
		forward = forward.normalized()
	else:
		forward = Vector3(0.0, 0.0, 1.0)
	var speed := (sprint_speed if dribble else jog_speed) * speed_multiplier
	velocity.x = forward.x * move * speed
	velocity.z = forward.z * move * speed
	move_and_slide()
	_update_anim(move, dribble)
	_debug_dump()

func _update_anim(move: float, dribble: bool) -> void:
	if _kick_anim_timer > 0.0:
		return
	var next := ANIM_IDLE
	if dribble and move > 0.01:
		next = ANIM_JOG_FWD
	elif absf(move) > 0.01:
		next = ANIM_JOG_BACK if move < 0.0 else ANIM_JOG_FWD
	_play(next)

func _play(anim_name: String) -> void:
	if _ap == null or _anim == anim_name:
		return
	if not _ap.has_animation(anim_name):
		return
	_ap.play(anim_name, anim_blend)
	_anim = anim_name


func play_kick(anim_name: String) -> void:
	if _ap == null:
		return
	if not _ap.has_animation(anim_name):
		return
	_ap.play(anim_name, 0.05)
	_anim = anim_name
	_kick_anim_timer = 0.5

func _load_character() -> void:
	if not ResourceLoader.exists(character_path):
		push_warning("Character %s not found — copy it into game/characters/." % character_path)
		return
	var packed := load(character_path) as PackedScene
	if packed == null:
		push_warning("Failed to load character scene %s." % character_path)
		return
	_character = packed.instantiate()
	add_child(_character)
	_ground_character()

# Build a self-contained AnimationPlayer under the character and load every
# Mixamo .tres clip (Skeleton3D:mixamorig5_* tracks resolve relative to it).
func _attach_animations() -> void:
	if _character == null:
		return
	_ap = AnimationPlayer.new()
	_ap.name = "Ch38AnimationPlayer"
	_character.add_child(_ap)
	var lib := AnimationLibrary.new()
	_ap.add_animation_library("", lib)
	for clip_name in MIXAMO_CLIPS:
		_add_mixamo_clip(String(clip_name), String(MIXAMO_CLIPS[clip_name]))
	_play(ANIM_IDLE)

func _add_mixamo_clip(anim_name: String, tres_path: String) -> void:
	if _ap == null:
		return
	if not ResourceLoader.exists(tres_path):
		push_warning("Clip %s missing — run game/tools/retarget_mixamo.gd." % tres_path)
		return
	var anim := load(tres_path) as Animation
	if anim == null:
		push_warning("Failed to load clip %s." % tres_path)
		return
	var lib := _ap.get_animation_library("") as AnimationLibrary
	if lib == null:
		return
	lib.add_animation(anim_name, anim)
	print("Loaded clip: ", anim_name, " (", tres_path, ")")

func _ground_character() -> void:
	turf_y = _field_surface_y()
	var feet := _local_bbox_min_y()
	_character.position.y = -feet
	global_position.y = turf_y + 0.05
	print("Character grounded: turf Y=%.2f, feet offset=%.2f -> mesh.y=%.2f" % [turf_y, feet, _character.position.y])

func _field_surface_y() -> float:
	var field := _find_football_field()
	if field != null and "surface_y" in field:
		return float(field.surface_y)
	return 0.0

func _find_football_field() -> Node:
	var root := get_tree().root
	return root.find_child("FootballField", true, false)

func _local_bbox_min_y() -> float:
	if _character == null:
		return 0.0
	var min_y := 0.0
	var first := true
	for node in _character.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var local_y: float = mi.global_transform.origin.y - global_transform.origin.y + mi.get_aabb().position.y
		if first or local_y < min_y:
			min_y = local_y
			first = false
	return min_y

# ── ball contact / foot reach (PES/UFL model) ──────────────────────────────

func get_ball_contact() -> Area3D:
	return get_node_or_null("BallContact") as Area3D


func ball_in_reach() -> bool:
	if not is_inside_tree():
		return false
	var area := get_ball_contact()
	if area == null:
		return false
	return area.get_overlapping_bodies().size() > 0 or area.get_overlapping_areas().size() > 0


func get_foot_pos(side: String) -> Vector3:
	var bone_name := "mixamorig5_LeftFoot" if side == "left" else "mixamorig5_RightFoot"
	var bone_pos: Variant = _find_foot_bone_global(bone_name)
	if bone_pos != null:
		return bone_pos
	var area := get_ball_contact()
	if area != null:
		return area.global_position
	return global_position


func _find_foot_bone_global(bone_name: String) -> Variant:
	if _character == null:
		return null
	for skeleton in _character.find_children("*", "Skeleton3D", true, false):
		var sk := skeleton as Skeleton3D
		if sk == null:
			continue
		var idx := sk.find_bone(bone_name)
		if idx >= 0:
			return sk.global_transform * sk.get_bone_global_pose(idx).origin
	return null


func _debug_dump() -> void:
	if not debug_physics:
		return
	var area := get_ball_contact()
	print("[debug] Player capsule_radius=0.35 capsule_height=1.8",
		" contact=", area.global_position if area else "(none)",
		" ball_in_reach=", ball_in_reach(),
		" left_foot=", get_foot_pos("left"))

func _ensure_input_actions() -> void:
	_add_key("move_forward", KEY_W)
	_add_key("move_back", KEY_S)
	_add_key("turn_left", KEY_A)
	_add_key("turn_right", KEY_D)
	_add_key("dribble", KEY_E)
	_add_key("football_pass", KEY_Q)
	_add_key("football_shoot", KEY_F)
	_add_key("football_cancel_pass", KEY_ESCAPE)

func _add_key(action: String, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == keycode:
			return
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action, ev)
