class_name PassController
extends Node

const PassDataClass := preload("res://scenes/pass_data.gd")

const CURVE_POINTS := [
	Vector2(0.0, 0.0),
	Vector2(0.25, 0.08),
	Vector2(0.5, 0.35),
	Vector2(0.75, 0.7),
	Vector2(1.0, 1.0),
]

@export_group("Charge")
@export var charge_time := 1.0
@export var min_pass_power := 0.15

@export_group("Speed")
@export var pass_speed_min := 4.0
@export var pass_speed_max := 14.0
@export var power_curve: Curve

@export_group("Velocity")
@export var pass_velocity_influence := 0.4
@export var pass_prediction_time := 0.08

@export_group("Contact")
@export var pass_contact_lift := -0.03
@export var pass_contact_radius_fraction := 0.5

var _charging := false
var _charge_elapsed := 0.0


func _ready() -> void:
	if power_curve == null:
		power_curve = Curve.new()
		for p in CURVE_POINTS:
			power_curve.add_point(p)


func _curve_value(t: float) -> float:
	if power_curve == null:
		var x := clampf(t, 0.0, 1.0)
		for i in range(CURVE_POINTS.size() - 1):
			var a: Vector2 = CURVE_POINTS[i]
			var b: Vector2 = CURVE_POINTS[i + 1]
			if x <= b.x:
				return lerpf(a.y, b.y, (x - a.x) / maxf(b.x - a.x, 0.001))
		return 1.0
	return power_curve.sample(clampf(t, 0.0, 1.0))


# ── charge lifecycle ────────────────────────────────────────────────────────

func begin_charge() -> void:
	_charging = true
	_charge_elapsed = 0.0


func update_charge(delta: float) -> void:
	if _charging:
		_charge_elapsed += delta


func cancel_charge() -> void:
	_charging = false
	_charge_elapsed = 0.0


func finish_charge() -> float:
	_charging = false
	return charge_power()


func is_charging() -> bool:
	return _charging


func charge_power() -> float:
	return _curve_value(clampf(_charge_elapsed / maxf(charge_time, 0.001), 0.0, 1.0))


# ── pass computation ────────────────────────────────────────────────────────

func compute_speed(power: float) -> float:
	return lerpf(pass_speed_min, pass_speed_max, _curve_value(clampf(power, 0.0, 1.0)))


func predicted_target_position(ball: Node3D, target: Node3D, power: float) -> Vector3:
	if ball == null or target == null:
		return Vector3.ZERO
	var pos := target.global_position
	var vel := Vector3.ZERO
	if "velocity" in target:
		vel = target.velocity
	var dist := ball.global_position.distance_to(pos)
	var est_speed := maxf(compute_speed(power), pass_speed_min)
	var travel := dist / maxf(est_speed, 1.0)
	return pos + vel * travel


func build_pass_data(player: Node3D, ball: Node3D, intent) -> Variant:
	var data := PassDataClass.new()
	data.pass_type = intent.pass_type
	data.power = intent.power
	data.speed = compute_speed(intent.power)
	data.direction = intent.direction
	data.lift = 0.0
	data.spin = Vector3.ZERO
	data.player_velocity = player.velocity if player != null else Vector3.ZERO
	data.player_velocity_influence = pass_velocity_influence
	return data


func pass_contact_point(player: Node3D, ball: Node3D, is_left: bool, ball_radius: float) -> Vector3:
	if ball == null:
		return Vector3.ZERO
	var ball_pos: Vector3 = ball.global_position
	var ball_vel: Vector3 = ball.velocity if "velocity" in ball else Vector3.ZERO
	ball_pos += ball_vel * pass_prediction_time
	var to_ball: Vector3 = ball_pos - player.global_position
	to_ball.y = 0.0
	if to_ball.length() > 0.01:
		to_ball = to_ball.normalized()
	else:
		to_ball = player.global_transform.basis.z
	var side: Vector3 = player.global_transform.basis.x
	if is_left:
		side = -side
	var contact: Vector3 = ball_pos - to_ball * ball_radius * pass_contact_radius_fraction + side * 0.06
	contact.y = ball_pos.y + pass_contact_lift
	return contact