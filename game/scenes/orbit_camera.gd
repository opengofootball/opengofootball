extends Camera3D

@export var target := Vector3.ZERO
@export var distance := 110.0
@export var min_distance := 2.5
@export var max_distance := 280.0
@export var sensitivity := 0.005
@export var elevation := 0.45

var _yaw := 0.7

func _ready() -> void:
	current = true
	_apply()

func _process(_delta: float) -> void:
	var p := get_tree().root.find_child("Player", true, false)
	if p is Node3D:
		target = (p as Node3D).global_position + Vector3(0.0, 1.2, 0.0)
	_apply()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_yaw -= event.relative.x * sensitivity
		elevation = clampf(elevation + event.relative.y * sensitivity, 0.05, 1.45)
		_apply()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = clampf(distance * 0.85, min_distance, max_distance)
			_apply()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = clampf(distance * 1.15, min_distance, max_distance)
			_apply()

func _apply() -> void:
	var ce := cos(elevation)
	var se := sin(elevation)
	global_position = target + Vector3(
		distance * ce * sin(_yaw),
		distance * se,
		distance * ce * cos(_yaw)
	)
	look_at(target)
