extends RefCounted

enum PassType {
	GROUND,
	LOB,
	THROUGH,
	CROSS,
	SHOT,
}

var direction := Vector3.FORWARD
var speed := 0.0
var power := 0.0
var lift := 0.0
var spin := Vector3.ZERO
var pass_type := PassType.GROUND
var player_velocity := Vector3.ZERO
var player_velocity_influence := 0.4


func velocity() -> Vector3:
	var dir := direction
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	var vel := dir * speed
	var pv := player_velocity
	pv.y = 0.0
	vel += pv * player_velocity_influence
	vel.y = lift
	return vel