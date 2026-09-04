extends Node3D

enum Foot { NONE, LEFT, RIGHT }
enum State {
	NO_CONTROL,
	BALL_DETECTED,
	APPROACHING,
	CONTACT_READY,
	CONTROLLED,
	DRIBBLING,
	PASS_REQUESTED,
	PASS_PREPARING,
	PASS_CONTACT,
	PASS_EXECUTED,
	RELEASED,
	SHOOT,
}

@export_group("Detection")
@export var detection_distance := 2.0
@export var detection_angle_deg := 90.0
@export var detection_height := 0.5
@export var max_ball_speed := 12.0

@export_group("Control envelope")
@export var control_distance := 0.9
@export var max_control_distance := 1.8
@export var control_height := 0.35
@export var speed_factor := 0.15

@export_group("Dribble target")
@export var control_forward_distance := 0.65
@export var control_side_distance := 0.20
@export var control_height_offset := 0.11
@export var close_forward_bias := 0.6
@export var prediction_time := 0.10

@export_group("Touch physics")
@export var touch_interval := 0.20
@export var min_touch_speed := 1.0
@export var max_touch_speed := 4.5
@export var touch_control_factor := 0.6
@export var player_velocity_influence := 0.7
@export var foot_offset := 0.20

@export_group("Reach")
@export var max_foot_reach := 1.3
@export var reach_fade := 0.25

const PassDataClass := preload("res://scenes/pass_data.gd")
const PassIntentClass := preload("res://scenes/pass_intent.gd")

@export_group("Pass")
@export var kick_cooldown_time := 0.3
@export var pass_prep_time := 0.20
@export var pass_follow_through := 0.15
@export var pass_max_height := 0.35
@export var pass_movement_multiplier := 0.5
@export var pass_target_node_path := ""

@export_group("Shoot (legacy Stage 5 stub, not Stage 6 scope)")
@export var shoot_power := 18.0
@export var shoot_elevation := 0.8

@export_group("Simulation")
@export var sim_rate := 100.0

@export_group("Visuals")
@export var ball_radius := 0.11
@export var debug_interactions := true
@export var debug_dribble_visuals := false
@export var debug_pass_visuals := false

var _state: int = State.NO_CONTROL
var _ball: CharacterBody3D
var _player: CharacterBody3D
var _foot_ik: Node3D
var _pass_controller: Node
var _pass_target: Node3D
var _pass_intent: Object
var _pass_data: Object
var _pass_timer := 0.0
var _active_foot: int = Foot.RIGHT
var _previous_foot: int = Foot.RIGHT
var _touch_cooldown := 0.0
var _kick_cooldown := 0.0
var _sim_accumulator := 0.0
var _desired_ball_pos := Vector3.ZERO
var _debug_sphere_desired: MeshInstance3D
var _debug_sphere_predicted: MeshInstance3D
var _debug_sphere_foot: MeshInstance3D
var _debug_sphere_forward: MeshInstance3D
var _debug_pass_arrow: MeshInstance3D
var _debug_pass_target_sphere: MeshInstance3D


func _ready() -> void:
	_player = get_parent() as CharacterBody3D
	if debug_interactions:
		print("[FI._ready] parent=", _player)
	call_deferred("_deferred_init")


func _deferred_init() -> void:
	_foot_ik = _player.get_node_or_null("IK")
	_pass_controller = _player.get_node_or_null("PassController")
	if pass_target_node_path != "":
		_pass_target = _player.get_node_or_null(pass_target_node_path)
	_find_ball()
	if debug_interactions:
		print("[FI._deferred_init] ball=", _ball, " ik=", _foot_ik, " pass=", _pass_controller, " target=", _pass_target)
	if _ball != null:
		_player.add_collision_exception_with(_ball)
		_ball.add_collision_exception_with(_player)


func _find_ball() -> void:
	var ball := get_tree().root.find_child("Ball", true, false)
	if ball is CharacterBody3D:
		_ball = ball as CharacterBody3D
	if debug_interactions and _ball == null:
		print("[FI._find_ball] NO BALL FOUND. root=", get_tree().root,
			" children=", get_tree().root.get_children().map(func(c): return c.name))


func _physics_process(delta: float) -> void:
	if _ball == null:
		_find_ball()
		return
	_kick_cooldown = maxf(_kick_cooldown - delta, 0.0)
	_handle_input()
	if _pass_controller != null and bool(_pass_controller.call("is_charging")):
		_pass_controller.call("update_charge", delta)
	_sim_accumulator += delta
	var sim_dt := 1.0 / sim_rate
	while _sim_accumulator >= sim_dt:
		_sim_step(sim_dt)
		_sim_accumulator -= sim_dt
	_update_foot_ik(delta)
	_update_debug()


func _sim_step(dt: float) -> void:
	var prev_state := _state
	_touch_cooldown = maxf(_touch_cooldown - dt, 0.0)
	_update_state(dt)
	_handle_dribble(dt)
	if debug_interactions and _state != prev_state:
		_debug_print()


func _update_state(dt: float) -> void:
	var in_range := _ball_in_range()
	var in_control := _ball_in_control_range()
	var ball_speed := _ball.velocity.length()
	var ball_too_fast := ball_speed > max_ball_speed
	match _state:
		State.NO_CONTROL:
			if in_range and not ball_too_fast:
				_state = State.BALL_DETECTED
		State.BALL_DETECTED:
			if not in_range:
				_state = State.NO_CONTROL
				_reset_ik()
			elif in_control:
				_state = State.CONTACT_READY
		State.APPROACHING:
			if not in_range:
				_state = State.RELEASED
				_reset_ik()
			elif in_control:
				_state = State.CONTACT_READY
		State.CONTACT_READY:
			if not in_control:
				_state = State.APPROACHING if in_range else State.RELEASED
			elif _can_touch():
				_state = State.CONTROLLED if _player.velocity.length() < 0.3 else State.DRIBBLING
		State.CONTROLLED:
			if not in_control or _ball_too_far():
				_state = State.RELEASED
				_reset_ik()
			elif _player.velocity.length() > 0.5:
				_state = State.DRIBBLING
		State.DRIBBLING:
			if not in_control or _ball_too_far():
				_state = State.RELEASED
				_reset_ik()
			elif _player.velocity.length() < 0.3:
				_state = State.CONTROLLED
		State.RELEASED:
			_state = State.NO_CONTROL
		State.PASS_REQUESTED:
			if _pass_intent == null:
				_state = State.RELEASED
			else:
				_select_pass_foot(_pass_intent.direction)
				_player.play_kick("Kick_Soccerball")
				_kick_cooldown = kick_cooldown_time
				_pass_timer = pass_prep_time
				_state = State.PASS_PREPARING
		State.PASS_PREPARING:
			_pass_timer -= dt
			if _pass_timer <= 0.0:
				_execute_pass_contact()
				_pass_timer = pass_follow_through
				_state = State.PASS_CONTACT
		State.PASS_CONTACT:
			_pass_timer -= dt
			if _pass_timer <= 0.0:
				_state = State.PASS_EXECUTED
		State.PASS_EXECUTED:
			_state = State.RELEASED
		State.SHOOT:
			_kick_cooldown = kick_cooldown_time
			_state = State.APPROACHING
	if _state == State.BALL_DETECTED and in_control:
		_state = State.CONTACT_READY
	if _state == State.BALL_DETECTED and not in_control and in_range:
		_state = State.APPROACHING


func _handle_dribble(dt: float) -> void:
	if _state != State.DRIBBLING and _state != State.CONTROLLED:
		return
	_desired_ball_pos = _compute_desired_ball_position()
	if not _can_touch():
		return
	_perform_touch()


func _perform_touch() -> void:
	if _ball == null:
		return
	_select_foot()
	var touch_dir := _compute_touch_direction()
	var touch_vel := _compute_touch_speed() * touch_dir
	var player_vel_h := _player.velocity
	player_vel_h.y = 0.0
	touch_vel += player_vel_h * player_velocity_influence
	var ball_vel_h := _ball.velocity
	ball_vel_h.y = 0.0
	var desired_delta_v := touch_vel - ball_vel_h
	var ball_mass: float = _ball.ball_mass if "ball_mass" in _ball else 0.43
	var impulse := desired_delta_v * ball_mass * touch_control_factor
	_ball.apply_touch(impulse)
	_touch_cooldown = touch_interval


func _compute_touch_direction() -> Vector3:
	var to_desired := _desired_ball_pos - _ball.global_position
	to_desired.y = 0.0
	if to_desired.length_squared() > 0.001:
		var dir := to_desired.normalized()
		var player_forward := _player.global_transform.basis.z
		player_forward.y = 0.0
		if player_forward.length_squared() > 0.0001:
			player_forward = player_forward.normalized()
		var close_bias: float = clampf(1.0 - get_ball_distance() / control_distance, 0.0, 1.0)
		return dir.lerp(player_forward, close_bias * close_forward_bias).normalized()
	return _player.global_transform.basis.z


func _compute_touch_speed() -> float:
	var sprint_spd: float = _player.sprint_speed if "sprint_speed" in _player else 5.5
	var speed_factor_val := _player.velocity.length() / sprint_spd
	var local_err := _player.to_local(_desired_ball_pos)
	var distance_err := Vector2(local_err.x, local_err.z).length()
	var norm_err := clampf(distance_err / control_distance, 0.0, 1.0)
	return lerpf(min_touch_speed, max_touch_speed, lerpf(speed_factor_val, norm_err, 0.5))


func _select_foot() -> void:
	if _ball == null:
		return
	var local_ball := _player.to_local(_ball.global_position)
	if _previous_foot != Foot.NONE and absf(local_ball.x) < 0.08:
		_active_foot = _previous_foot
		return
	var side_foot := Foot.LEFT if local_ball.x < 0.0 else Foot.RIGHT
	var dist_to_ball := get_ball_distance()
	var reach := _reach_weight()
	if reach <= 0.01 and _previous_foot != Foot.NONE:
		_active_foot = _previous_foot
		return
	_active_foot = side_foot


func _can_touch() -> bool:
	if _ball == null:
		return false
	if _touch_cooldown > 0.0:
		return false
	var dist := get_ball_distance()
	var effective_control := control_distance + _player.velocity.length() * speed_factor
	if dist > effective_control:
		return false
	if _ball.global_position.y - _player.global_position.y > control_height:
		return false
	return true


func _ball_too_far() -> bool:
	return get_ball_distance() > max_control_distance


func _ball_in_range() -> bool:
	if _ball == null:
		return false
	var dist := get_ball_distance()
	if dist > detection_distance:
		return false
	if _ball.global_position.y - _player.global_position.y > detection_height:
		return false
	return _ball_within_angle()


func _ball_within_angle() -> bool:
	if _ball == null:
		return false
	var local_ball := _player.to_local(_ball.global_position)
	var horiz := Vector2(local_ball.x, local_ball.z)
	var dist := horiz.length()
	if dist < 0.8:
		return true
	var angle_deg := rad_to_deg(horiz.angle_to(Vector2.DOWN))
	return absf(angle_deg) <= detection_angle_deg * 0.5


func _ball_in_control_range() -> bool:
	if _ball == null:
		return false
	var dist := get_ball_distance()
	var effective_control := control_distance + _player.velocity.length() * speed_factor
	if dist > effective_control:
		return false
	if _ball.global_position.y - _player.global_position.y > control_height:
		return false
	return true


func _compute_desired_ball_position() -> Vector3:
	if _ball == null:
		return Vector3.ZERO
	var forward := _player.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var side := _player.global_transform.basis.x
	if _active_foot == Foot.LEFT:
		side = -side
	var sprint_spd: float = _player.sprint_speed if "sprint_speed" in _player else 5.5
	var speed_ratio := clampf(_player.velocity.length() / maxf(sprint_spd, 1.0), 0.0, 1.0)
	var forward_dist := control_forward_distance + speed_ratio * 0.25
	return _player.global_position + forward * forward_dist + side * control_side_distance + Vector3.UP * control_height_offset


func _compute_predicted_ball_position() -> Vector3:
	if _ball == null:
		return Vector3.ZERO
	return _ball.global_position + _ball.velocity * prediction_time


func _reach_weight() -> float:
	if _ball == null:
		return 0.0
	var dist := get_ball_distance()
	if dist >= max_foot_reach:
		return 0.0
	return clampf(1.0 - (dist - (max_foot_reach - reach_fade)) / reach_fade, 0.0, 1.0)


func _update_foot_ik(_delta: float) -> void:
	if _foot_ik == null:
		return
	var ik_active := _state == State.CONTROLLED or _state == State.DRIBBLING or _state == State.CONTACT_READY
	ik_active = ik_active or _in_pass_state()
	if ik_active and _active_foot != Foot.NONE:
		var reach_weight := _reach_weight()
		var contact := _get_pass_contact_point() if _in_pass_state() else _get_ball_contact_point()
		_foot_ik.set_ball_ik(true, _foot_name(_active_foot), contact, reach_weight)
	else:
		_foot_ik.set_ball_ik(false, "", Vector3.ZERO)


func _get_ball_contact_point() -> Vector3:
	if _ball == null:
		return Vector3.ZERO
	var ball_pos := _compute_predicted_ball_position()
	var player_to_ball := (ball_pos - _player.global_position)
	player_to_ball.y = 0.0
	var len := player_to_ball.length()
	if len > 0.01:
		player_to_ball = player_to_ball / len
	else:
		player_to_ball = _player.global_transform.basis.z
	var side_dir := _player.global_transform.basis.x
	if _active_foot == Foot.LEFT:
		side_dir = -side_dir
	var contact := ball_pos - player_to_ball * ball_radius * 0.5 + side_dir * foot_offset * 0.3
	contact.y = ball_pos.y
	return contact


func _handle_input() -> void:
	if Input.is_action_just_pressed("football_pass"):
		_begin_pass_charge()
	if Input.is_action_just_released("football_pass"):
		_finish_pass_charge()
	if Input.is_action_just_pressed("football_shoot"):
		_do_shoot()
	if Input.is_action_just_pressed("football_cancel_pass"):
		_cancel_pass()


func _begin_pass_charge() -> void:
	if _pass_controller == null or not _pass_controller.has_method("begin_charge"):
		return
	if _kick_cooldown > 0.0 or not _ball_in_control_range():
		return
	if _state != State.CONTROLLED and _state != State.DRIBBLING:
		return
	_pass_controller.call("begin_charge")


func _finish_pass_charge() -> void:
	if _pass_controller == null or not bool(_pass_controller.call("is_charging")):
		return
	var power: float = _pass_controller.call("finish_charge")
	if power < float(_pass_controller.get("min_pass_power")) or _kick_cooldown > 0.0:
		return
	if _state != State.CONTROLLED and _state != State.DRIBBLING:
		return
	if not _ball_in_control_range():
		return
	if _ball.global_position.y - _player.global_position.y > pass_max_height:
		return
	_request_pass(power)


func _cancel_pass() -> void:
	if _pass_controller != null and bool(_pass_controller.call("is_charging")):
		_pass_controller.call("cancel_charge")
	if _state == State.PASS_REQUESTED or _state == State.PASS_PREPARING:
		_pass_intent = null
		_pass_timer = 0.0
		_state = State.CONTROLLED


func _request_pass(power: float) -> void:
	var intent := PassIntentClass.new()
	intent.power = power
	intent.pass_type = PassDataClass.PassType.GROUND
	var dir := _pass_direction()
	if _pass_target != null:
		var predicted := _pass_controller.call("predicted_target_position", _ball, _pass_target, power) as Vector3
		intent.target = _pass_target
		intent.target_position = _pass_target.global_position
		intent.predicted_target = predicted
		var to_target := predicted - _ball.global_position
		to_target.y = 0.0
		if to_target.length() > 0.01:
			dir = to_target.normalized()
	intent.direction = dir
	intent.requested = true
	_pass_intent = intent
	_state = State.PASS_REQUESTED


func _execute_pass_contact() -> void:
	if _ball == null or _pass_intent == null or _pass_controller == null:
		_state = State.RELEASED
		return
	_pass_data = _pass_controller.call("build_pass_data", _player, _ball, _pass_intent)
	if _pass_data == null:
		_state = State.RELEASED
		return
	if debug_interactions:
		print("PASS CONTACT -> impulse %.2f m/s toward (%+.2f, %+.2f) power=%.0f%% foot=%s"
			% [_pass_data.speed, _pass_data.direction.x, _pass_data.direction.z,
				_pass_data.power * 100.0, _foot_name(_active_foot)])
	_ball.apply_pass(_pass_data)
	_pass_intent = null


func _pass_direction() -> Vector3:
	var ix := Input.get_axis("turn_left", "turn_right")
	var iz := Input.get_axis("move_back", "move_forward")
	if absf(ix) < 0.01 and absf(iz) < 0.01:
		iz = 1.0
	var fwd := _player.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := _player.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var world := fwd * iz + right * ix
	return world.normalized()


func _select_pass_foot(pass_dir: Vector3) -> void:
	_select_foot()
	if _ball == null:
		return
	var side_hit := pass_dir.dot(_player.global_transform.basis.x)
	var local_ball := _player.to_local(_ball.global_position)
	if absf(local_ball.x) < 0.25 and absf(side_hit) > 0.4:
		_active_foot = Foot.RIGHT if side_hit < 0.0 else Foot.LEFT


func _do_shoot() -> void:
	if _ball == null or _kick_cooldown > 0.0 or not _ball_in_control_range():
		return
	_state = State.SHOOT
	_player.play_kick("Kick_Soccerball")
	var forward := _player.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	_ball.apply_shot(forward, shoot_power, shoot_elevation)
	_kick_cooldown = kick_cooldown_time


func _reset_ik() -> void:
	if _foot_ik != null:
		_foot_ik.set_ball_ik(false, "", Vector3.ZERO)


func _foot_name(f: int) -> String:
	return "left" if f == Foot.LEFT else "right"


func _get_pass_contact_point() -> Vector3:
	if _pass_controller == null or not _pass_controller.has_method("pass_contact_point"):
		return _get_ball_contact_point()
	return _pass_controller.call("pass_contact_point",
		_player, _ball, _active_foot == Foot.LEFT, ball_radius)


func _in_pass_state() -> bool:
	return _state == State.PASS_REQUESTED or _state == State.PASS_PREPARING \
		or _state == State.PASS_CONTACT or _state == State.PASS_EXECUTED


func has_ball() -> bool:
	return _state == State.CONTROLLED or _state == State.DRIBBLING or _in_pass_state()


func get_state() -> int:
	return _state


func get_movement_multiplier() -> float:
	if _in_pass_state():
		return pass_movement_multiplier
	return 1.0


func get_pass_intent():
	return _pass_intent


func is_charging_pass() -> bool:
	if _pass_controller == null:
		return false
	return bool(_pass_controller.call("is_charging"))


func get_pass_charge() -> float:
	if _pass_controller == null:
		return 0.0
	return float(_pass_controller.call("charge_power"))


func get_active_foot() -> String:
	return _foot_name(_active_foot)


func get_ball_distance() -> float:
	if _ball == null:
		return -1.0
	return _player.global_position.distance_to(_ball.global_position)


func get_ball_speed() -> float:
	if _ball != null:
		return _ball.velocity.length()
	return 0.0


func get_desired_ball_position() -> Vector3:
	_desired_ball_pos = _compute_desired_ball_position()
	return _desired_ball_pos


func get_predicted_ball_position() -> Vector3:
	return _compute_predicted_ball_position()


func get_foot_contact_position() -> Vector3:
	return _get_ball_contact_point()


func _update_debug() -> void:
	_update_pass_debug()
	if not debug_dribble_visuals and _debug_sphere_desired == null:
		return
	if debug_dribble_visuals and _debug_sphere_desired == null:
		_debug_sphere_desired = _make_debug_sphere("DesiredBallPos", Color(1.0, 1.0, 0.0))
		_debug_sphere_predicted = _make_debug_sphere("PredictedBall", Color(0.0, 1.0, 0.5))
		_debug_sphere_foot = _make_debug_sphere("FootContact", Color(1.0, 0.5, 0.0))
		_debug_sphere_forward = _make_debug_sphere("PlayerForward", Color(0.0, 1.0, 0.0))
	if not debug_dribble_visuals:
		if _debug_sphere_desired != null:
			_debug_sphere_desired.queue_free()
			_debug_sphere_predicted.queue_free()
			_debug_sphere_foot.queue_free()
			_debug_sphere_forward.queue_free()
			_debug_sphere_desired = null
			_debug_sphere_predicted = null
			_debug_sphere_foot = null
			_debug_sphere_forward = null
		return
	_desired_ball_pos = _compute_desired_ball_position()
	_debug_sphere_desired.global_position = _desired_ball_pos
	_debug_sphere_predicted.global_position = _compute_predicted_ball_position()
	_debug_sphere_foot.global_position = _get_ball_contact_point() if _active_foot != Foot.NONE else Vector3(0.0, -1000.0, 0.0)
	var player_forward := _player.global_transform.basis.z
	var forward_marker := _player.global_position + player_forward * 1.0
	forward_marker.y = _player.global_position.y + 0.2
	_debug_sphere_forward.global_position = forward_marker
	_update_pass_debug()


func _update_pass_debug() -> void:
	var show := debug_pass_visuals and (is_charging_pass() or _in_pass_state() or _pass_intent != null)
	if not show:
		if _debug_pass_arrow != null:
			_debug_pass_arrow.queue_free()
			_debug_pass_arrow = null
		if _debug_pass_target_sphere != null:
			_debug_pass_target_sphere.queue_free()
			_debug_pass_target_sphere = null
		return
	var power := get_pass_charge()
	var dir := _pass_direction()
	if _pass_intent != null:
		power = _pass_intent.power
		dir = _pass_intent.direction
	if _pass_controller == null:
		return
	var speed: float = _pass_controller.call("compute_speed", power)
	if _debug_pass_arrow == null:
		_debug_pass_arrow = MeshInstance3D.new()
		_debug_pass_arrow.name = "PassArrow"
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.06, 0.06, 1.0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.0, 1.0, 0.5)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material = mat
		_debug_pass_arrow.mesh = mesh
		add_child(_debug_pass_arrow)
	var length := clampf(speed * 0.2, 0.4, 6.0)
	var origin := _ball.global_position if _ball != null else _player.global_position
	_debug_pass_arrow.global_position = origin + Vector3.UP * 0.25 + dir * length * 0.5
	_debug_pass_arrow.scale = Vector3(1.0, 1.0, length)
	_debug_pass_arrow.global_rotation = Vector3.ZERO
	_debug_pass_arrow.look_at(origin + Vector3.UP * 0.25 + dir * length, Vector3.UP)
	if _pass_target != null and _pass_intent != null:
		if _debug_pass_target_sphere == null:
			_debug_pass_target_sphere = _make_debug_sphere("PassTargetPredicted", Color(1.0, 0.0, 1.0))
		_debug_pass_target_sphere.global_position = _pass_intent.predicted_target
	else:
		if _debug_pass_target_sphere != null:
			_debug_pass_target_sphere.queue_free()
			_debug_pass_target_sphere = null


func _make_debug_sphere(sphere_name: String, sphere_color: Color) -> MeshInstance3D:
	var sphere := MeshInstance3D.new()
	sphere.name = sphere_name
	var mesh := SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = sphere_color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	sphere.mesh = mesh
	add_child(sphere)
	return sphere


func _debug_print() -> void:
	var state_names := ["NO_CONTROL","BALL_DETECTED","APPROACHING","CONTACT_READY","CONTROLLED","DRIBBLING",
		"PASS_REQUESTED","PASS_PREPARING","PASS_CONTACT","PASS_EXECUTED","RELEASED","SHOOT"]
	var ball_h := _ball.global_position.y - _player.global_position.y if _ball != null else 0.0
	var reach := _reach_weight() if _state == State.CONTROLLED or _state == State.DRIBBLING else 0.0
	var pass_info := ""
	if _pass_controller != null and bool(_pass_controller.call("is_charging")):
		pass_info = " | CHARGE: %d%%" % int(float(_pass_controller.call("charge_power")) * 100.0)
	if _pass_intent != null:
		pass_info += " | PASS PWR: %d%% DIR: (%+.2f, %+.2f)" % [
			int(_pass_intent.power * 100.0), _pass_intent.direction.x, _pass_intent.direction.z]
	print("STATE: %s | FOOT: %s | DIST: %.2fm | BALL_H: %.2fm | BALL_V: %.2f | REACH: %.2f | TOUCH_CD: %.2f | HAS_BALL: %s%s" % [
		state_names[_state], _foot_name(_active_foot), get_ball_distance(), ball_h,
		get_ball_speed(), reach, _touch_cooldown, has_ball(), pass_info
	])
