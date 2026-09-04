extends Node3D

enum State { NONE, APPROACH, CONTROL, DRIBBLE, PASS, SHOOT }

@export var detection_distance := 2.0
@export var detection_angle_deg := 90.0
@export var max_ball_height := 0.5
@export var control_distance := 1.0
@export var max_foot_reach := 1.3
@export var reach_fade := 0.25
@export var dribble_forward_offset := 0.6
@export var dribble_side_offset := 0.15
@export var pass_power := 8.0
@export var pass_height := 0.0
@export var shoot_power := 18.0
@export var shoot_elevation := 0.8
@export var ball_radius := 0.11
@export var debug_interactions := false

var _state: int = State.NONE
var _ball: CharacterBody3D
var _player: CharacterBody3D
var _foot_ik: Node3D
var _active_foot := "right"
var _kick_cooldown := 0.0
var _ball_initial_y := 0.0


func _ready() -> void:
	_player = get_parent() as CharacterBody3D
	call_deferred("_deferred_init")


func _deferred_init() -> void:
	_foot_ik = _player.get_node_or_null("IK")
	_find_ball()
	if _ball != null:
		_player.add_collision_exception_with(_ball)
		_ball.add_collision_exception_with(_player)


func _find_ball() -> void:
	var ball := get_tree().root.find_child("Ball", true, false)
	if ball is CharacterBody3D:
		_ball = ball as CharacterBody3D
		_ball_initial_y = _ball.global_position.y


func _physics_process(delta: float) -> void:
	if _ball == null:
		_find_ball()
		return
	if _kick_cooldown > 0.0:
		_kick_cooldown -= delta
	_update_state(delta)
	_update_foot_ik(delta)
	_handle_input(delta)
	if debug_interactions:
		_debug_print()


func _update_state(delta: float) -> void:
	match _state:
		State.NONE:
			if _ball_in_range():
				_state = State.APPROACH
		State.APPROACH:
			if not _ball_in_range():
				_state = State.NONE
				_reset_ik()
			elif _ball_in_control_range():
				_state = State.CONTROL
				_select_foot()
		State.CONTROL:
			if not _ball_in_control_range():
				_state = State.APPROACH
			elif _player.velocity.length() > 0.5:
				_state = State.DRIBBLE
		State.DRIBBLE:
			if _player.velocity.length() < 0.3:
				_state = State.CONTROL
			elif not _ball_in_control_range():
				_state = State.APPROACH
			else:
				_update_dribble(delta)
		State.PASS:
			_kick_cooldown = 0.3
			_state = State.APPROACH
		State.SHOOT:
			_kick_cooldown = 0.3
			_state = State.APPROACH


func _ball_in_range() -> bool:
	if _ball == null:
		return false
	var dist := _player.global_position.distance_to(_ball.global_position)
	if dist > detection_distance:
		return false
	if _ball.global_position.y - _player.global_position.y > max_ball_height:
		return false
	if not _ball_within_angle():
		return false
	return true


func _ball_within_angle() -> bool:
	if _ball == null:
		return false
	var local_ball := _player.to_local(_ball.global_position)
	var horiz := Vector2(local_ball.x, local_ball.z)
	var dist := horiz.length()
	if dist < 0.8:
		return true
	var angle_deg := rad_to_deg(horiz.angle_to(Vector2.UP))
	return absf(angle_deg) <= detection_angle_deg * 0.5


func _ball_in_control_range() -> bool:
	if _ball == null:
		return false
	var dist := _player.global_position.distance_to(_ball.global_position)
	if dist > control_distance:
		return false
	if _ball.global_position.y - _player.global_position.y > max_ball_height:
		return false
	return true


func _select_foot() -> void:
	if _ball == null:
		return
	var local_ball := _player.to_local(_ball.global_position)
	_active_foot = "left" if local_ball.x < 0.0 else "right"


func _update_dribble(_delta: float) -> void:
	if _ball == null:
		return
	var forward := -_player.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var side := _player.global_transform.basis.x
	if _active_foot == "left":
		side = -side
	var target_pos := _player.global_position + forward * dribble_forward_offset + side * dribble_side_offset
	target_pos.y = _ball.global_position.y
	var to_target := target_pos - _ball.global_position
	to_target.y = 0.0
	var correction := to_target * 8.0
	_ball.velocity.x = _player.velocity.x + correction.x
	_ball.velocity.z = _player.velocity.z + correction.z


func _handle_input(_delta: float) -> void:
	if Input.is_action_just_pressed("football_pass"):
		_do_pass()
	elif Input.is_action_just_pressed("football_shoot"):
		_do_shoot()


func _do_pass() -> void:
	if _ball == null or _kick_cooldown > 0.0 or not _ball_in_control_range():
		return
	_state = State.PASS
	_player.play_kick("Kick_Soccerball")
	var forward := -_player.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var direction := forward
	if _ball.global_position.distance_to(_player.global_position) > 0.5:
		direction = (_ball.global_position - _player.global_position).normalized()
		direction.y = 0.0
		direction = direction.normalized()
	var impulse := direction * pass_power
	impulse.y = pass_height
	_ball.apply_shot(direction, pass_power, pass_height)
	_kick_cooldown = 0.3


func _do_shoot() -> void:
	if _ball == null or _kick_cooldown > 0.0 or not _ball_in_control_range():
		return
	_state = State.SHOOT
	_player.play_kick("Kick_Soccerball")
	var forward := -_player.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var direction := forward
	if _ball.global_position.distance_to(_player.global_position) > 0.5:
		direction = (_ball.global_position - _player.global_position).normalized()
		direction.y = 0.0
		direction = direction.normalized()
	_ball.apply_shot(direction, shoot_power, shoot_elevation)
	_kick_cooldown = 0.3


func _update_foot_ik(_delta: float) -> void:
	if _foot_ik == null:
		return
	if _state == State.CONTROL or _state == State.DRIBBLE:
		var reach_weight := _reach_weight()
		_foot_ik.set_ball_ik(true, _active_foot, _get_ball_contact_point(), reach_weight)
	else:
		_foot_ik.set_ball_ik(false, "", Vector3.ZERO)


func _reach_weight() -> float:
	if _ball == null:
		return 0.0
	var dist := _player.global_position.distance_to(_ball.global_position)
	if dist >= max_foot_reach:
		return 0.0
	return clampf(1.0 - (dist - (max_foot_reach - reach_fade)) / reach_fade, 0.0, 1.0)


func _get_ball_contact_point() -> Vector3:
	if _ball == null:
		return Vector3.ZERO
	var ball_pos := _ball.global_position
	var player_to_ball := (ball_pos - _player.global_position)
	player_to_ball.y = 0.0
	player_to_ball = player_to_ball.normalized()
	var foot_offset := 0.12
	if _active_foot == "left":
		foot_offset = -0.12
	var forward := -_player.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var contact := ball_pos - player_to_ball * ball_radius * 0.5
	contact.x += forward.x * 0.02
	contact.z += forward.z * 0.02
	contact.x += foot_offset * 0.3
	contact.y = ball_pos.y
	return contact


func _reset_ik() -> void:
	if _foot_ik != null:
		_foot_ik.set_ball_ik(false, "", Vector3.ZERO)


func has_ball() -> bool:
	return _state == State.CONTROL or _state == State.DRIBBLE


func get_state() -> int:
	return _state


func get_active_foot() -> String:
	return _active_foot


func get_ball_distance() -> float:
	if _ball == null:
		return -1.0
	return _player.global_position.distance_to(_ball.global_position)


func get_ball_speed() -> float:
	if _ball != null:
		return _ball.velocity.length()
	return 0.0


func _debug_print() -> void:
	var state_names := ["NONE", "APPROACH", "CONTROL", "DRIBBLE", "PASS", "SHOOT"]
	var ball_h := _ball.global_position.y - _player.global_position.y if _ball != null else 0.0
	var reach := _reach_weight() if _state == State.CONTROL or _state == State.DRIBBLE else 0.0
	print("STATE: %s | FOOT: %s | DIST: %.2fm | BALL_H: %.2fm | REACH: %.2f | DETECTED: %s | HAS_BALL: %s" % [
		state_names[_state], _active_foot, get_ball_distance(), ball_h, reach,
		_ball_in_range(), has_ball()
	])
