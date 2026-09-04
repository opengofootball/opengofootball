extends SceneTree

const MAIN := "res://scenes/Main.tscn"
const JOG_DT := 1.0 / 60.0
const STEPS := 600

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(MAIN) as PackedScene
	if packed == null:
		_fail("cannot load %s" % MAIN)
		_done()
		return
	var main := packed.instantiate()
	get_root().add_child(main)
	await process_frame
	var player := get_root().find_child("Player", true, false)
	var ball := get_root().find_child("Ball", true, false)
	if not (player is CharacterBody3D) or not (ball is CharacterBody3D):
		_fail("Player/Ball missing: player=%s ball=%s" % [player, ball])
		main.free()
		_done()
		return
	var fi := player.get_node_or_null("FootballInteraction")
	if fi == null:
		_fail("Player has no FootballInteraction")
		main.free()
		_done()
		return
	fi.call("_deferred_init")
	Input.action_press("move_forward")

	var ever_dribbling := false
	var had_ball := false
	for i in STEPS:
		player.call("_physics_process", JOG_DT)
		_simulate_ball(ball, JOG_DT)
		fi.call("_physics_process", JOG_DT)
		var st: int = fi.call("get_state")
		ever_dribbling = ever_dribbling or st >= fi.State.DRIBBLING
		had_ball = had_ball or bool(fi.call("has_ball"))

	var dist: float = fi.call("get_ball_distance")
	var local: Vector3 = (player as Node3D).to_local(ball.global_position)
	print("[verify_dribble] steps=%d state=%d dist=%.2f local=(%.2f, %.2f, %.2f) ever_dribbling=%s had_ball=%s"
		% [STEPS, fi.call("get_state"), dist, local.x, local.y, local.z, ever_dribbling, had_ball])
	if not ever_dribbling:
		_fail("never reached DRIBBLING while running at the ball")
	if not had_ball:
		_fail("has_ball() never true")
	if dist < 0.0 or dist > fi.max_control_distance:
		_fail("ball escaped: dist=%.2f > max_control_distance=%.1f" % [dist, fi.max_control_distance])
	if local.z <= 0.2:
		_fail("ball not carried in front (local.z=%.2f, behind/side)" % local.z)
	main.free()
	_done()


func _simulate_ball(ball: Node3D, dt: float) -> void:
	var vel: Vector3 = ball.velocity
	var h := Vector2(vel.x, vel.z)
	var speed := h.length()
	if speed > 0.0:
		h = h / speed * maxf(speed - 3.0 * dt, 0.0)
	vel.x = h.x
	vel.z = h.y
	vel.y = 0.0
	ball.velocity = vel
	ball.global_position += vel * dt
	ball.global_position.y = 0.11


func _done() -> void:
	if _failed:
		push_error("[verify_dribble] FAILED.")
		quit(1)
	else:
		print("[verify_dribble] PASS.")
		quit(0)


func _fail(msg: String) -> void:
	_failed = true
	push_error("[verify_dribble] %s" % msg)