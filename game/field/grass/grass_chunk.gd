@tool
extends Node3D

## One pitch-grass chunk as in karl/godot-grass (Unlicense):
##   - `Grass` uses the shared baked MultiMesh (.tres) for this cell
##   - detailed <-> simple Mesh LOD swapped by camera distance
##   - `Impostor` plane faded in at distance
##   - `Ground` is a dark base plane so the cell never shows black holes
##   - `Grass` carries the `grass.gd` helper that pushes the player
##     `object_position` so blades bend around the player (wind disabled).

@export var lod_switch := 10.0
@export var impostor_fade_in_start := 5.0
@export var impostor_fade_in_end := 10.0
@export var grass_fade_out_start := 10.0
@export var grass_fade_out_end := 20.0

# Texture-only test mode: when false, hide the 3D blades entirely and show
# only the flat impostor plane (solid green fill) — no LOD/fade logic.
@export var blades_enabled := true

const DETAILED_TRES := preload("res://field/grass/grass_multimesh_detailed.tres")
const SIMPLE_TRES := preload("res://field/grass/grass_multimesh_simple.tres")


func _process(_delta: float) -> void:
	var camera_pos := _camera_position()
	if camera_pos == null:
		return

	# Texture-only: blades hidden, impostor is the flat ground.
	if not blades_enabled:
		if $Grass.visible:
			$Grass.visible = false
		$Impostor.visible = true
		$Impostor.set_instance_shader_parameter("alpha", 1.0)
		return

	var camera_distance := global_position.distance_to(camera_pos)

	if camera_distance < lod_switch:
		if $Grass.multimesh != DETAILED_TRES:
			$Grass.multimesh = DETAILED_TRES
	else:
		if $Grass.multimesh != SIMPLE_TRES:
			$Grass.multimesh = SIMPLE_TRES

	var start_to_mid := smoothstep(impostor_fade_in_start, impostor_fade_in_end, camera_distance)
	var mid_to_end := smoothstep(grass_fade_out_start, grass_fade_out_end, camera_distance)

	$Grass.visible = mid_to_end < 1.0
	$Impostor.visible = start_to_mid >= 0.0

	$Impostor.set_instance_shader_parameter("alpha", start_to_mid)
	$Grass.set_instance_shader_parameter("alpha", 1.0 - mid_to_end)


func _camera_position() -> Vector3:
	if Engine.is_editor_hint():
		var ed := EditorInterface.get_editor_viewport_3d()
		if ed != null and ed.get_camera_3d() != null:
			return ed.get_camera_3d().global_position
		return Vector3.ZERO
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector3.ZERO
	return cam.global_position