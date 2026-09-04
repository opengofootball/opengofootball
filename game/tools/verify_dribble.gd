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
	player.global_position = Vector3(0.0, 0.05, 0.0)
	player.rotation = Vector3.ZERO
	player.velocity = Vector3.ZERO
	ball.global_position = Vector3(0.0, 0.11, 1.8)
	ball.velocity = Vector3.ZERO
	Input.action_press("move_forward")

	var ever_dribbling := false
	var had_ball := false
	for i in STEPS:
		player.call("_physics_process", JOG_DT)
		_simulate_ball(ball, JOG_DT)
		fi.call("_physics_process", JOG_DT)
		player.global_position.y = 0.05
		player.velocity.y = 0.0
		var st: int = fi.call("get_state")
		ever_dribbling = ever_dribbling or st >= fi.State.DRIBBLING
		had_ball = had_ball or bool(fi.call("has_ball"))

	var dist: float = fi.call("get_ball_distance")
	var local: Vector3 = (player as Node3D).to_local(ball.global_position)
	print("[verify_dribble] phase1 steps=%d state=%d dist=%.2f local=(%.2f, %.2f, %.2f) ever_dribbling=%s had_ball=%s"
		% [STEPS, fi.call("get_state"), dist, local.x, local.y, local.z, ever_dribbling, had_ball])
	if not ever_dribbling:
		_fail("never reached DRIBBLING while running at the ball")
	if not had_ball:
		_fail("has_ball() never true")
	if dist < 0.0 or dist > fi.max_control_distance:
		_fail("ball escaped: dist=%.2f > max_control_distance=%.1f" % [dist, fi.max_control_distance])
	if local.z <= 0.2:
		_fail("ball not carried in front (local.z=%.2f, behind/side)" % local.z)

	fi.call("_request_pass", 0.5)
	var recaptured := false
	print("[verify_dribble] phase2 kick -> ball_speed=", ball.velocity.length())
	for i in 900:
		player.call("_physics_process", JOG_DT)
		_simulate_ball(ball, JOG_DT)
		fi.call("_physics_process", JOG_DT)
		player.global_position.y = 0.05
		player.velocity.y = 0.0
		if bool(fi.call("has_ball")):
			recaptured = true
		if i % 60 == 0:
			var st2: int = fi.call("get_state")
			var d2: float = fi.call("get_ball_distance")
			var l2: Vector3 = (player as Node3D).to_local(ball.global_position)
			print("[verify_dribble] t=%.1fs st=%d dist=%.2f ball_speed=%.2f local=(%.2f, %.2f, %.2f)"
				% [(i + 1) * JOG_DT, st2, d2, ball.velocity.length(), l2.x, l2.y, l2.z])
	var dist2: float = fi.call("get_ball_distance")
	var local2: Vector3 = (player as Node3D).to_local(ball.global_position)
	if dist2 < 0.0 or dist2 > fi.max_control_distance:
		_fail("after kick ball escaped: dist=%.2f" % dist2)
	if not recaptured:
		_fail("after kick the player never recaptured the ball (has_ball stayed false)")
	elif local2.z <= 0.2:
		_fail("after kick ball not carried in front (local.z=%.2f, behind/side)" % local2.z)
	else:
		print("[verify_dribble] phase2 recaptured dist=%.2f local=(%.2f, %.2f, %.2f)"
			% [dist2, local2.x, local2.y, local2.z])
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