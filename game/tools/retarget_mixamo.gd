extends SceneTree
## Headless world-space retarget of Mixamo/UFL clips onto the Ch38 character
## (`mixamorig5_*` skeleton). No Blender required: Godot's native FBX importer
## reads each source, this script remaps the animation rotation tracks bone-name
## by bone-name onto Ch38's mixamorig5_* bones, drops the root position track
## (locomotion is code-driven), and commits each result as a standalone .tres
## Animation.
##
## The retarget is rest-frame agnostic: it reads each source clip's world-space
## bone poses while it plays, forms deltas vs the source's own rest, and applies
## them onto Ch38's upright standing frame. This lets us consume sources with
## DIFFERENT rig conventions:
##   - "mixamorig5_*" sources (Ch38 Mixamo pack) -> identity
##   - "mixamorig_*" sources  (X Bot)  -> prefix-swapped to mixamorig5_*
##   - short-name sources     (Dribble)-> explicit short -> mixamorig5_* map
##
## Ch38's skeleton sits at the scene ROOT (node named "Skeleton3D"), so emitted
## track paths are "Skeleton3D:mixamorig5_<bone>".
##
## Usage (Linux headless):
##   ./Godot_v4.6.3-stable_linux.x86_64 --headless --path game \
##       --script res://tools/retarget_mixamo.gd

# Ch38 scene is the retarget target (also the playable rig).
const CHARACTER_PATH := "res://characters/Ch38_nonPBR.fbx"

const SAMPLE_TIME_STEP := 1.0 / 30.0

# FBX source -> output clip. `src` is the imported FBX scene; out is the
# committed .tres filename and the animation name.
const JOBS := {
	"res://characters/mixamo/Soccer Idle.fbx": {
		"out": "res://characters/Soccer_Idle.tres", "name": "Soccer_Idle",
	},
	"res://characters/mixamo/Offensive Idle.fbx": {
		"out": "res://characters/Offensive_Idle.tres", "name": "Offensive_Idle",
	},
	"res://characters/mixamo/Jog Forward.fbx": {
		"out": "res://characters/Jog_Fwd.tres", "name": "Jog_Fwd",
	},
	"res://characters/mixamo/Jog Backward.fbx": {
		"out": "res://characters/Jog_Back.tres", "name": "Jog_Back",
	},
	"res://characters/mixamo/Jog Strafe Left.fbx": {
		"out": "res://characters/Jog_Strafe_Left.tres", "name": "Jog_Strafe_Left",
	},
	"res://characters/mixamo/Jog Strafe Right.fbx": {
		"out": "res://characters/Jog_Strafe_Right.tres", "name": "Jog_Strafe_Right",
	},
	"res://characters/mixamo/Jog Forward Diagonal.fbx": {
		"out": "res://characters/Jog_Fwd_Diag.tres", "name": "Jog_Fwd_Diag",
	},
	"res://characters/mixamo/Jog Backward Diagonal.fbx": {
		"out": "res://characters/Jog_Back_Diag.tres", "name": "Jog_Back_Diag",
	},
	"res://characters/mixamo/Strike Foward Jog.fbx": {
		"out": "res://characters/Strike_Fwd_Jog.tres", "name": "Strike_Fwd_Jog",
	},
	"res://characters/mixamo/Dribble.fbx": {
		"out": "res://characters/Dribble.tres", "name": "Dribble",
	},
	"res://characters/mixamo/Chip.fbx": {
		"out": "res://characters/Chip.tres", "name": "Chip",
	},
	"res://characters/mixamo/Header.fbx": {
		"out": "res://characters/Header.tres", "name": "Header",
	},
	"res://characters/mixamo/Header Soccerball.fbx": {
		"out": "res://characters/Header_Soccerball.tres", "name": "Header_Soccerball",
	},
	"res://characters/mixamo/Soccer Header.fbx": {
		"out": "res://characters/Soccer_Header.tres", "name": "Soccer_Header",
	},
	"res://characters/mixamo/Kick Soccerball.fbx": {
		"out": "res://characters/Kick_Soccerball.tres", "name": "Kick_Soccerball",
	},
	"res://characters/mixamo/Soccer Pass.fbx": {
		"out": "res://characters/Soccer_Pass.tres", "name": "Soccer_Pass",
	},
	"res://characters/mixamo/Soccer Penalty Kick.fbx": {
		"out": "res://characters/Soccer_Penalty_Kick.tres", "name": "Soccer_Penalty_Kick",
	},
	"res://characters/mixamo/Soccer Tackle.fbx": {
		"out": "res://characters/Soccer_Tackle.tres", "name": "Soccer_Tackle",
	},
	"res://characters/mixamo/Receive.fbx": {
		"out": "res://characters/Receive.tres", "name": "Receive",
	},
	"res://characters/mixamo/Receive Soccerball.fbx": {
		"out": "res://characters/Receive_Soccerball.tres", "name": "Receive_Soccerball",
	},
	"res://characters/mixamo/Stall Soccerball.fbx": {
		"out": "res://characters/Stall_Soccerball.tres", "name": "Stall_Soccerball",
	},
	"res://characters/mixamo/Throw In.fbx": {
		"out": "res://characters/Throw_In.tres", "name": "Throw_In",
	},
	"res://characters/mixamo/Kneeing Soccerball.fbx": {
		"out": "res://characters/Kneeing_Soccerball.tres", "name": "Kneeing_Soccerball",
	},
	"res://characters/mixamo/Fallen Idle.fbx": {
		"out": "res://characters/Fallen_Idle.tres", "name": "Fallen_Idle",
	},
	"res://characters/mixamo/Standing Up.fbx": {
		"out": "res://characters/Standing_Up.tres", "name": "Standing_Up",
	},
}

# Short-name bone -> Ch38 mixamorig5_* bone (core body). Finger bones handled by
# a numeric shim below (short "_NN_l" -> "mixamorig5_LeftHand<Finger>N").
const SHORT_TO_MIX5 := {
	"pelvis": "mixamorig5_Hips",
	"spine_01": "mixamorig5_Spine",
	"spine_02": "mixamorig5_Spine1",
	"spine_03": "mixamorig5_Spine2",
	"neck_01": "mixamorig5_Neck",
	"Head": "mixamorig5_Head",
	"clavicle_r": "mixamorig5_RightShoulder",
	"upperarm_r": "mixamorig5_RightArm",
	"lowerarm_r": "mixamorig5_RightForeArm",
	"hand_r": "mixamorig5_RightHand",
	"clavicle_l": "mixamorig5_LeftShoulder",
	"upperarm_l": "mixamorig5_LeftArm",
	"lowerarm_l": "mixamorig5_LeftForeArm",
	"hand_l": "mixamorig5_LeftHand",
	"thigh_r": "mixamorig5_RightUpLeg",
	"calf_r": "mixamorig5_RightLeg",
	"foot_r": "mixamorig5_RightFoot",
	"ball_r": "mixamorig5_RightToeBase",
	"ball_leaf_r": "mixamorig5_RightToe_End",
	"thigh_l": "mixamorig5_LeftUpLeg",
	"calf_l": "mixamorig5_LeftLeg",
	"foot_l": "mixamorig5_LeftFoot",
	"ball_l": "mixamorig5_LeftToeBase",
	"ball_leaf_l": "mixamorig5_LeftToe_End",
}

# Short finger root names -> Ch38 mixamorig5 finger stem (no leaf in Mixamo-5).
const SHORT_FINGER_TO_MIX5 := {
	"thumb": "Thumb", "index": "Index", "middle": "Middle",
	"ring": "Ring", "pinky": "Pinky",
}

var _target_bones: Dictionary = {}
var _super_rest_world: Dictionary = {}
var _super_parent_rest_world: Dictionary = {}
var _super_parent: Dictionary = {}
var _super_order: Array[String] = []


func _init() -> void:
	if not _load_target_skeleton():
		push_error("Retarget aborted: cannot load character skeleton.")
		quit(1)
		return
	var failed := 0
	for src in JOBS:
		if not await _retarget(src, JOBS[src].out, JOBS[src].name):
			failed += 1
	if failed > 0:
		push_error("Retarget finished with %d job(s) failed." % failed)
		quit(1)
	else:
		print("[retarget] All clips retargeted successfully.")
		quit(0)


func _load_target_skeleton() -> bool:
	if not ResourceLoader.exists(CHARACTER_PATH):
		push_error("Missing character skeleton: %s" % CHARACTER_PATH)
		return false
	var packed := load(CHARACTER_PATH) as PackedScene
	if packed == null:
		push_error("Failed to load character scene: %s" % CHARACTER_PATH)
		return false
	var root := packed.instantiate()
	for sk in root.find_children("*", "Skeleton3D", true, false):
		var s := sk as Skeleton3D
		for i in s.get_bone_count():
			var bname: String = s.get_bone_name(i)
			_target_bones[bname] = true
			_super_rest_world[bname] = s.get_bone_global_rest(i).basis.get_rotation_quaternion()
			var pid := s.get_bone_parent(i)
			if pid < 0:
				_super_parent_rest_world[bname] = Quaternion.IDENTITY
				_super_parent[bname] = ""
			else:
				_super_parent_rest_world[bname] = s.get_bone_global_rest(pid).basis.get_rotation_quaternion()
				_super_parent[bname] = String(s.get_bone_name(pid))
			_super_order.append(bname)
	root.free()
	return _target_bones.size() > 0


# Source bone name -> Ch38 mixamorig5_* target bone. Returns "" if unmappable.
# Handles three source conventions by probing the *source* name:
#   "mixamorig5_*" -> identity (Ch38 Mixamo pack).
#   "mixamorig_*"  -> prefix-swap to "mixamorig5_" (X Bot rigs).
#   short names    -> SHORT_TO_MIX5 / finger shim (Dribble/UFL rigs).
func _map_bone(source_bone: String) -> String:
	var bone := source_bone.replace(":", "_")
	if bone.begins_with("mixamorig5_"):
		if _target_bones.has(bone):
			return bone
		return ""
	if bone.begins_with("mixamorig_"):
		var candidate := "mixamorig5_" + bone.trim_prefix("mixamorig_")
		if _target_bones.has(candidate):
			return candidate
		return ""
	if bone in SHORT_TO_MIX5:
		var named := String(SHORT_TO_MIX5[bone])
		if _target_bones.has(named):
			return named
		return ""
	var side := ""
	if bone.ends_with("_l"):
		side = "l"
	elif bone.ends_with("_r"):
		side = "r"
	if side == "":
		return ""
	var stem := bone.trim_suffix("_" + side)
	var parts := stem.split("_")
	if parts.size() < 2:
		return ""
	var root := parts[0]
	var num_str := parts[1]
	if root.ends_with("_leaf"):
		root = root.trim_suffix("_leaf")
		num_str = "4"
	if root not in SHORT_FINGER_TO_MIX5:
		return ""
	var n := num_str.to_int()
	if n < 1 or n > 4:
		return ""
	var mix5 := "mixamorig5_" + ("Left" if side == "l" else "Right") + "Hand" \
		+ String(SHORT_FINGER_TO_MIX5[root]) + str(n)
	if _target_bones.has(mix5):
		return mix5
	return ""


func _retarget(src_path: String, out_path: String, anim_name: String) -> bool:
	if not ResourceLoader.exists(src_path):
		push_warning("Skipping, source missing: %s" % src_path)
		return false
	var packed := load(src_path) as PackedScene
	if packed == null:
		push_warning("Skipping, not a scene: %s" % src_path)
		return false
	var root := packed.instantiate()
	get_root().add_child(root)
	await process_frame

	var src_ap: AnimationPlayer = null
	var src_sk: Skeleton3D = null
	var src_anim: Animation = null
	var src_anim_key: String = ""
	for child in root.find_children("*", "Skeleton3D", true, false):
		src_sk = child as Skeleton3D
		break
	for child in root.find_children("*", "AnimationPlayer", true, false):
		var a := child as AnimationPlayer
		for lib_name in a.get_animation_library_list():
			var lib := a.get_animation_library(lib_name)
			for an in lib.get_animation_list():
				src_anim = lib.get_animation(an)
				src_anim_key = an
				src_ap = a
				break
			if src_anim != null:
				break
		if src_anim != null:
			break
	if src_anim == null or src_sk == null or src_ap == null:
		root.free()
		push_warning("Skipping, no animation/skeleton in %s" % src_path)
		return false

	# --- Build the source-side bone table ---
	var src_bones: Dictionary = {}
	var src_index_of: Dictionary = {}
	for i in src_sk.get_bone_count():
		src_index_of[String(src_sk.get_bone_name(i))] = i
	for t in src_anim.get_track_count():
		if src_anim.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		var path := src_anim.track_get_path(t)
		if path.get_subname_count() == 0:
			continue
		var src_bone: String = path.get_subname(0)
		var target := _map_bone(src_bone)
		if target == "" or not _target_bones.has(target):
			continue
		if not src_index_of.has(src_bone):
			continue
		var si: int = src_index_of[src_bone]
		src_bones[src_bone] = {
			"target": target,
			"src_index": si,
			"src_rest": src_sk.get_bone_global_rest(si).basis.get_rotation_quaternion(),
		}

	if src_bones.is_empty():
		root.free()
		push_warning("Skipping, no mappable bones in %s" % src_path)
		return false

	# --- Collect sampling times (union of all rotation key times) ---
	var times: Array[float] = []
	for t in src_anim.get_track_count():
		if src_anim.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		for i in src_anim.track_get_key_count(t):
			var tm: float = src_anim.track_get_key_time(t, i)
			if not times.has(tm):
				times.append(tm)
	times.sort()
	if not times.has(0.0):
		times.push_front(0.0)
	if not times.has(src_anim.length):
		times.append(src_anim.length)

	# --- World-space retarget per sampling time ---
	var values: Dictionary = {}
	for sb in src_bones:
		values[String(src_bones[sb].target)] = []

	src_ap.play(src_anim_key)
	for tm in times:
		src_ap.seek(tm)
		src_sk.force_update_all_bone_transforms()
		await process_frame
		var deltas: Dictionary = {}
		for sb in src_bones:
			var target: String = src_bones[sb].target
			var si: int = src_bones[sb].src_index
			var quat: Quaternion
			if si < 0 or si >= src_sk.get_bone_count():
				quat = src_bones[sb].src_rest
			else:
				quat = src_sk.get_bone_global_pose(si).basis.get_rotation_quaternion()
			var src_rest: Quaternion = src_bones[sb].src_rest
			deltas[target] = src_rest.inverse() * quat
		var anim_world: Dictionary = {}
		var last_q: Dictionary = {}
		for short in _super_order:
			if not _target_bones.has(short):
				continue
			var parent_world: Quaternion
			if _super_parent[short] == "":
				parent_world = Quaternion.IDENTITY
			else:
				parent_world = anim_world[_super_parent[short]]
			var target_world: Quaternion
			if deltas.has(short):
				target_world = _super_rest_world[short] * deltas[short]
			else:
				target_world = parent_world * (_super_parent_rest_world[short].inverse() * _super_rest_world[short]) * Quaternion.IDENTITY
			var local: Quaternion = parent_world.inverse() * target_world
			anim_world[short] = parent_world * local
			if deltas.has(short):
				if last_q.has(short):
					var prev: Quaternion = last_q[short]
					if prev.dot(local) < 0.0:
						local = -local
				last_q[short] = local
				values[short].append([tm, local])

	# --- Emit tracks in bone order ---
	var out := Animation.new()
	out.loop_mode = Animation.LOOP_LINEAR
	out.length = src_anim.length
	var mapped: Array[String] = []
	var skipped: Array[String] = []
	for short in values:
		var vals: Array = values[short]
		if vals.is_empty():
			continue
		var nt := out.add_track(Animation.TYPE_ROTATION_3D)
		# Ch38's skeleton is the scene root, so the path is just the skeleton node.
		out.track_set_path(nt, NodePath("Skeleton3D:" + short))
		for kv in vals:
			out.rotation_track_insert_key(nt, kv[0], kv[1])
		out.track_set_interpolation_type(nt, Animation.INTERPOLATION_LINEAR)
		mapped.append(short)
	for t in src_anim.get_track_count():
		if src_anim.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			var path := src_anim.track_get_path(t)
			var sb := ""
			if path.get_subname_count() > 0:
				sb = path.get_subname(0)
			var target := _map_bone(sb)
			if target == "" and sb != "":
				skipped.append("unmapped:%s" % sb)

	var ok := ResourceSaver.save(out, out_path)
	if ok != OK:
		root.free()
		push_error("Failed to save %s (errcode %d)" % [out_path, ok])
		return false
	root.free()
	print("[retarget] %s -> %s (tracks=%d, samples=%d, length=%.3f)" % [
		src_path, out_path, mapped.size(), times.size(), out.length])
	_print_breakdown(mapped, skipped)
	return true


func _print_breakdown(mapped: Array[String], skipped: Array[String]) -> void:
	print("  mapped bones (%d): %s" % [mapped.size(), ", ".join(mapped)])
	if skipped.size() > 0:
		print("  dropped tracks (%d): %s" % [skipped.size(), ", ".join(skipped)])
