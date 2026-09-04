extends SceneTree
## Headless validation of the world-space retargeted clips (Soccer_Idle,
## Jog_Fwd, Jog_Back, Dribble) on the Ch38 mixamorig5_* skeleton. For each clip,
## samples N frames and checks:
##   - The player stays UPRIGHT: Ch38 pelvis (mixamorig5_Hips) world up ~ +Y the
##     whole clip (never lies down). PASS requires min_pelvis_up_y >= MIN_UP.
##   - Legs point DOWN: thigh up ~ -Y (reported as down-length).
##   - Residual source-vs-target pose delta is reported (informational).
##
## Usage:
##   ./Godot_v4.6.3-stable_linux.x86_64 --headless --path game \
##       --script res://tools/verify_retarget.gd
## Exits 0 on PASS, 1 on FAIL.

const CLIPS := ["Soccer_Idle", "Jog_Fwd", "Jog_Back", "Dribble"]
const TARGET := "res://characters/Ch38_nonPBR.fbx"
const N_SAMPLES := 12
const MIN_PELVIS_UP_Y := 0.7

var _failed := false

func _init() -> void:
	var gl := (load(TARGET) as PackedScene).instantiate()
	get_root().add_child(gl)
	var sk: Skeleton3D = null
	for s in gl.find_children("*", "Skeleton3D", true, false):
		sk = s as Skeleton3D
	var ap := AnimationPlayer.new()
	gl.add_child(ap)
	var lib := AnimationLibrary.new()
	ap.add_animation_library("", lib)

	for clip in CLIPS:
		await _check_clip(clip, lib, ap, sk)
		lib.remove_animation(clip)
	gl.free()
	if _failed:
		push_error("[verify] FAILED.")
		quit(1)
	else:
		print("[verify] All clips PASS (upright the whole clip).")
		quit(0)


func _check_clip(clip: String, lib: AnimationLibrary, ap: AnimationPlayer, sk: Skeleton3D) -> void:
	var tres := load("res://characters/" + clip + ".tres") as Animation
	lib.add_animation(clip, tres)
	var min_pelvis_up := 1.0
	var min_thigh_down := 1.0
	for si in range(N_SAMPLES):
		var T := tres.length * float(si) / float(N_SAMPLES - 1)
		ap.play(clip)
		ap.seek(T, true)
		sk.force_update_all_bone_transforms()
		await process_frame
		var pi := sk.find_bone("mixamorig5_Hips")
		var ti := sk.find_bone("mixamorig5_LeftUpLeg")
		var pu: Vector3 = sk.get_bone_global_pose(pi).basis.get_rotation_quaternion() * Vector3(0, 1, 0)
		var lu: Vector3 = sk.get_bone_global_pose(ti).basis.get_rotation_quaternion() * Vector3(0, 1, 0)
		min_pelvis_up = minf(min_pelvis_up, pu.y)
		min_thigh_down = minf(min_thigh_down, -lu.y)
	var ok := min_pelvis_up >= MIN_PELVIS_UP_Y
	if ok:
		print("[verify] %s PASS: minPelvisUpY=%.2f minThighDownY=%.2f (len=%.3f)"
			% [clip, min_pelvis_up, min_thigh_down, tres.length])
	else:
		_failed = true
		push_error("[verify] %s FAIL: minPelvisUpY=%.2f < %.2f (not upright)"
			% [clip, min_pelvis_up, MIN_PELVIS_UP_Y])
