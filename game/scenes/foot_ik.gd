extends Node3D

@export var influence := 0.5
@export var foot_offset := 0.03
@export var lerp_speed := 10.0
@export var max_slope_deg := 15.0
@export var ray_up := 0.8
@export var ray_down := 1.2

const LEFT_ROOT := "mixamorig5_LeftUpLeg"
const LEFT_MID := "mixamorig5_LeftLeg"
const LEFT_END := "mixamorig5_LeftFoot"
const RIGHT_ROOT := "mixamorig5_RightUpLeg"
const RIGHT_MID := "mixamorig5_RightLeg"
const RIGHT_END := "mixamorig5_RightFoot"

var _player: CharacterBody3D
var _skeleton: Skeleton3D
var _left_ik: TwoBoneIK3D
var _right_ik: TwoBoneIK3D
var _left_target: Node3D
var _right_target: Node3D
var _left_pole: Node3D
var _right_pole: Node3D
var _left_ray: RayCast3D
var _right_ray: RayCast3D
var _left_foot_idx := -1
var _right_foot_idx := -1

var _ball_ik_active := false
var _ball_ik_foot := ""
var _ball_ik_target := Vector3.ZERO


func _ready() -> void:
	_player = get_parent() as CharacterBody3D
	_left_target = $LeftFootTarget
	_right_target = $RightFootTarget
	_left_pole = $LeftFootPole
	_right_pole = $RightFootPole
	var ground := get_parent().get_node_or_null("GroundDetection")
	if ground != null:
		_left_ray = ground.get_node_or_null("LeftFootRay") as RayCast3D
		_right_ray = ground.get_node_or_null("RightFootRay") as RayCast3D
	set_physics_process(false)
	call_deferred("_bind")


func _bind() -> void:
	if _player == null:
		return
	for node in _player.find_children("*", "Skeleton3D", true, false):
		_skeleton = node as Skeleton3D
		break
	if _skeleton == null:
		push_warning("Foot IK: no Skeleton3D under Player.")
		return
	_left_foot_idx = _skeleton.find_bone(LEFT_END)
	_right_foot_idx = _skeleton.find_bone(RIGHT_END)
	if _left_foot_idx < 0 or _right_foot_idx < 0:
		push_warning("Foot IK: missing Ch38 foot bones.")
		return
	if _left_ray != null:
		_left_ray.add_exception(_player)
		_left_ray.enabled = true
	if _right_ray != null:
		_right_ray.add_exception(_player)
		_right_ray.enabled = true
	_left_ik = _make_leg_ik("LeftLegIK", LEFT_ROOT, LEFT_MID, LEFT_END, _left_target, _left_pole)
	_right_ik = _make_leg_ik("RightLegIK", RIGHT_ROOT, RIGHT_MID, RIGHT_END, _right_target, _right_pole)
	set_physics_process(true)


func _make_leg_ik(ik_name: String, root_bone: String, mid_bone: String, end_bone: String, target: Node3D, pole: Node3D) -> TwoBoneIK3D:
	var ik := TwoBoneIK3D.new()
	ik.name = ik_name
	ik.influence = influence
	_skeleton.add_child(ik)
	ik.setting_count = 1
	ik.set_root_bone_name(0, root_bone)
	ik.set_middle_bone_name(0, mid_bone)
	ik.set_end_bone_name(0, end_bone)
	ik.set_target_node(0, ik.get_path_to(target))
	ik.set_pole_node(0, ik.get_path_to(pole))
	return ik


func _physics_process(delta: float) -> void:
	if _skeleton == null:
		return
	if _ball_ik_active:
		if _ball_ik_foot == "left":
			_solve_ball_foot(_left_target, _left_pole, delta)
			_solve_foot(_right_ray, _right_target, _right_foot_idx, delta)
		else:
			_solve_ball_foot(_right_target, _right_pole, delta)
			_solve_foot(_left_ray, _left_target, _left_foot_idx, delta)
	else:
		_solve_foot(_left_ray, _left_target, _left_foot_idx, delta)
		_solve_foot(_right_ray, _right_target, _right_foot_idx, delta)


func _solve_foot(ray: RayCast3D, target: Node3D, foot_idx: int, delta: float) -> void:
	if ray == null or target == null or foot_idx < 0:
		return
	var foot_pos: Vector3 = _skeleton.global_transform * _skeleton.get_bone_global_pose(foot_idx).origin
	ray.global_position = Vector3(foot_pos.x, _player.global_position.y + ray_up, foot_pos.z)
	ray.target_position = Vector3(0.0, -ray_down, 0.0)
	ray.force_raycast_update()
	if not ray.is_colliding():
		return
	var hit: Vector3 = ray.get_collision_point() + Vector3.UP * foot_offset
	var normal: Vector3 = ray.get_collision_normal()
	var weight := clampf(lerp_speed * delta, 0.0, 1.0)
	var desired := target.global_transform
	desired.origin = hit
	desired.basis = _clamped_foot_basis(normal, _player.global_transform.basis.z)
	target.global_transform = target.global_transform.interpolate_with(desired, weight)


func _solve_ball_foot(target: Node3D, pole: Node3D, delta: float) -> void:
	if target == null:
		return
	var weight := clampf(lerp_speed * delta, 0.0, 1.0)
	var desired := target.global_transform
	desired.origin = _ball_ik_target
	target.global_transform = target.global_transform.interpolate_with(desired, weight)
	if pole != null:
		var to_ball := (_ball_ik_target - _player.global_position).normalized()
		var pole_pos := _ball_ik_target + to_ball * 0.3 + Vector3.UP * 0.4
		var pole_desired := pole.global_transform
		pole_desired.origin = pole_pos
		pole.global_transform = pole.global_transform.interpolate_with(pole_desired, weight)


func set_ball_ik(active: bool, foot: String, target: Vector3) -> void:
	_ball_ik_active = active
	_ball_ik_foot = foot
	_ball_ik_target = target


func _clamped_foot_basis(normal: Vector3, forward: Vector3) -> Basis:
	var n := normal.normalized()
	var max_rad := deg_to_rad(max_slope_deg)
	var angle := Vector3.UP.angle_to(n)
	if angle > max_rad:
		var axis := Vector3.UP.cross(n)
		if axis.length_squared() < 0.0001:
			n = Vector3.UP
		else:
			n = Vector3.UP.rotated(axis.normalized(), max_rad)
	var fwd := forward.slide(n)
	if fwd.length_squared() < 0.0001:
		fwd = Vector3(0.0, 0.0, 1.0).slide(n)
	fwd = fwd.normalized()
	var x := n.cross(fwd)
	if x.length_squared() < 0.0001:
		return Basis.IDENTITY
	x = x.normalized()
	var z := x.cross(n).normalized()
	return Basis(x, n, z).orthonormalized()
