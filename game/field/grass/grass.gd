@tool
extends MultiMeshInstance3D

## Pitch-grass MultiMeshInstance helper — sets the player interaction
## uniforms on its material each frame so blades bend around the player.
## Wind is disabled; this is the only per-frame grass motion.

@export var player: Node3D = null

@export_range(0.1, 10.0) var object_radius := 1.2


func _update_interaction() -> void:
	if material_override is ShaderMaterial:
		var mat := material_override as ShaderMaterial
		# A far sentinel keeps blades unbent when there is no active player.
		var pos: Vector3 = Vector3(100000.0, 100000.0, 100000.0)
		if player != null and is_instance_valid(player) and is_inside_tree():
			pos = player.global_position
		mat.set_shader_parameter("object_position", pos)
		mat.set_shader_parameter("object_radius", object_radius)


func _process(_delta: float) -> void:
	_update_interaction()