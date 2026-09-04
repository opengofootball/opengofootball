const PassDataClass := preload("res://scenes/pass_data.gd")

var direction := Vector3.FORWARD
var target: Node3D = null
var target_position := Vector3.ZERO
var predicted_target := Vector3.ZERO
var power := 0.0
var pass_type := PassDataClass.PassType.GROUND
var requested := false