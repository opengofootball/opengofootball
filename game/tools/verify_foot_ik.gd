extends SceneTree

const PLAYER := "res://scenes/player.tscn"
const CHARACTER := "res://characters/Ch38_nonPBR.fbx"
const LEG_BONES := [
	"mixamorig5_LeftUpLeg", "mixamorig5_LeftLeg", "mixamorig5_LeftFoot",
	"mixamorig5_RightUpLeg", "mixamorig5_RightLeg", "mixamorig5_RightFoot",
]

var _failed := false


func _init() -> void:
	await _run()
	if _failed:
		push_error("[verify_foot_ik] FAILED.")
		quit(1)
	else:
		print("[verify_foot_ik] PASS.")
		quit(0)


func _run() -> void:
	var packed := load(CHARACTER) as PackedScene
	if packed == null:
		_fail("cannot load %s" % CHARACTER)
		return
	var ch := packed.instantiate()
	get_root().add_child(ch)
	await process_frame
	var sk: Skeleton3D = null
	for node in ch.find_children("*", "Skeleton3D", true, false):
		sk = node as Skeleton3D
		break
	if sk == null:
		_fail("Ch38 has no Skeleton3D")
		ch.free()
		return
	for bone in LEG_BONES:
		if sk.find_bone(bone) < 0:
			_fail("missing bone %s" % bone)
	ch.free()

	var player_packed := load(PLAYER) as PackedScene
	if player_packed == null:
		_fail("cannot load %s" % PLAYER)
		return
	var player := player_packed.instantiate()
	get_root().add_child(player)
	await process_frame
	await process_frame
	await process_frame
	var iks: Array = player.find_children("*", "TwoBoneIK3D", true, false)
	if iks.size() < 2:
		_fail("expected 2 TwoBoneIK3D, got %d" % iks.size())
	else:
		print("[verify_foot_ik] TwoBoneIK3D count=%d" % iks.size())
	var ik_node := player.get_node_or_null("IK")
	if ik_node == null:
		_fail("missing IK node")
	var rays := player.find_children("*", "RayCast3D", true, false)
	var foot_rays := 0
	for r in rays:
		if String(r.name).ends_with("FootRay") and r.name != "FootRay":
			foot_rays += 1
	if foot_rays < 2:
		_fail("expected Left/RightFootRay, found %d" % foot_rays)
	player.free()


func _fail(msg: String) -> void:
	_failed = true
	push_error("[verify_foot_ik] %s" % msg)
