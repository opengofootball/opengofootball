extends CharacterBody3D

@export var ball_radius := 0.11
@export var ball_mass := 0.43
@export var gravity := 9.81
@export var bounce_coefficient := 0.5
@export var ground_friction := 3.0
@export var air_drag := 0.1
@export var rolling_friction := 1.5
@export var min_speed := 0.05

var _spin := Vector3.ZERO


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1


func _physics_process(delta: float) -> void:
	velocity.y -= gravity * delta
	move_and_slide()
	if is_on_floor():
		velocity.y = 0.0
		_apply_ground_friction(delta)
		if velocity.length() < min_speed:
			velocity = Vector3.ZERO
	else:
		_apply_air_drag(delta)
	_spin *= (1.0 - ground_friction * delta) if is_on_floor() else (1.0 - air_drag * delta)


func _apply_ground_friction(delta: float) -> void:
	var h_speed := Vector2(velocity.x, velocity.z)
	var speed := h_speed.length()
	if speed < min_speed:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var friction_force := ground_friction * delta
	if friction_force > 1.0:
		friction_force = 1.0
	var factor := 1.0 - friction_force
	velocity.x *= factor
	velocity.z *= factor


func _apply_air_drag(delta: float) -> void:
	velocity.x *= (1.0 - air_drag * delta)
	velocity.z *= (1.0 - air_drag * delta)


func apply_touch(impulse: Vector3, spin_impulse := Vector3.ZERO) -> void:
	velocity += impulse / ball_mass
	_spin += spin_impulse


func apply_shot(direction: Vector3, power: float, elevation := 0.0, spin_impulse := Vector3.ZERO) -> void:
	var vel := direction.normalized() * power
	vel.y = elevation
	velocity = vel
	_spin = spin_impulse


func get_speed() -> float:
	return velocity.length()


func is_grounded() -> bool:
	return is_on_floor()
