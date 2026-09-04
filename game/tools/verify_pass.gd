extends SceneTree

const MAIN := "res://scenes/Main.tscn"
const JOG_DT := 1.0 / 60.0

var _failed := false
var _player: CharacterBody3D
var _ball: CharacterBody3D
var _fi: Object
var _fi_pass: Object


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
	_player = get_root().find_child("Player", true, false)
	_ball = get_root().find_child("Ball", true, false)
	if not (_player is CharacterBody3D) or not (_ball is CharacterBody3D):
		_fail("Player/Ball missing: player=%s ball=%s" % [_player, _ball])
		main.free()
		_done()
		return
	_fi = _player.get_node_or_null("FootballInteraction")
	if _fi == null:
		_fail("Player has no FootballInteraction")
		main.free()
		_done()
		return
	_fi.call("_deferred_init")
	_fi_pass = _fi.get("_pass_controller")
	if _fi_pass == null:
		_fail("PassController not resolved on FootballInteraction")
		main.free()
		_done()
		return
	Input.action_release("move_forward")
	Input.action_release("turn_left")
	Input.action_release("dribble")

	_reset_scene()

	# ── phase 1: dribble into possession ────────────────────────────────────
	var had_ball := _drive_until_ball(700, true)
	var st_first: int = _fi.call("get_state")
	print("[verify_pass] phase1 state=%d had_ball=%s dist=%.2f"
		% [st_first, had_ball, _fi.call("get_ball_distance")])
	if not had_ball or (st_first != _fi.State.DRIBBLING and st_first != _fi.State.CONTROLLED):
		_fail("did not reach possession (state=%d)" % st_first)

	# ── phase 2: short-charge forward pass ──────────────────────────────────
	_fi.call("_begin_pass_charge")
	for i in 22:
		_physics_all(JOG_DT)
	var power_short: float = _fi.call("get_pass_charge")
	var expect_short: float = _fi_pass.call("compute_speed", power_short)
	_fi.call("_finish_pass_charge")
	var r1 := _run_pass_until_done()
	_assert_pass(r1, "short forward", expect_short, Vector2(0.0, 1.0))
	await _recapture(1200)

	# ── phase 3: full-charge forward pass ───────────────────────────────────
	_fi.call("_begin_pass_charge")
	for i in 120:
		_physics_all(JOG_DT)
	var power_full: float = _fi.call("get_pass_charge")
	var expect_full: float = _fi_pass.call("compute_speed", power_full)
	_fi.call("_finish_pass_charge")
	var r2 := _run_pass_until_done()
	_assert_pass(r2, "full forward", expect_full, Vector2(0.0, 1.0))
	if power_full <= power_short:
		_fail("power scaling broken: full=%.2f <= short=%.2f" % [power_full, power_short])
	if expect_full <= expect_short:
		_fail("speed scaling broken: full=%.2f <= short=%.2f" % [expect_full, expect_short])
	await _recapture(1200)

	# ── phase 4: left-directed pass (hold A at release only) ────────────────
	_fi.call("_begin_pass_charge")
	for i in 60:
		_physics_all(JOG_DT)
	Input.action_press("turn_left")
	_fi.call("_finish_pass_charge")
	Input.action_release("turn_left")
	var r3 := _run_pass_until_done()
	if not r3.saw_contact:
		_fail("left pass never reached contact")
	else:
		var ldir: Vector3 = _fi.get("_pass_data").direction
		if ldir.normalized().x >= -0.05:
			_fail("left pass not left: dir=(%.2f, %.2f)" % [ldir.x, ldir.z])
		else:
			print("[verify_pass] left pass dir=(%.2f, %.2f) ok" % [ldir.x, ldir.z])
	_redo_possession("phase4->5")

	# ── phase 5: cancel during prep ─────────────────────────────────────────
	print("[verify_pass] phase5 pre-begin state=%d dist=%.2f cd=%.2f"
		% [_fi.call("get_state"), _fi.call("get_ball_distance"), _fi.get("_kick_cooldown")])
	_fi.call("_begin_pass_charge")
	for i in 60:
		_physics_all(JOG_DT)
	print("[verify_pass] phase5 mid-charge state=%d charging=%s power=%.2f"
		% [_fi.call("get_state"), _fi.call("is_charging_pass"), _fi.call("get_pass_charge")])
	_fi.call("_finish_pass_charge")
	var st_finished: int = _fi.call("get_state")
	if st_finished != _fi.State.PASS_REQUESTED:
		_fail("after finish state=%d, expected PASS_REQUESTED" % st_finished)
	_fi.call("_cancel_pass")
	var st5b: int = _fi.call("get_state")
	var intent: Object = _fi.get("_pass_intent")
	if intent != null:
		_fail("cancel left stale pass_intent")
	if st5b != _fi.State.CONTROLLED and st5b != _fi.State.DRIBBLING:
		_fail("cancel state=%d, expected CONTROLLED/DRIBBLING" % st5b)
	print("[verify_pass] phase5 cancel ok state=%d" % st5b)
	_redo_possession("phase5->6")

	# ── phase 6: reject too-far at release ──────────────────────────────────
	_fi.call("_begin_pass_charge")
	for i in 60:
		_physics_all(JOG_DT)
	_ball.global_position.z += 6.0
	for i in 2:
		_physics_all(JOG_DT)
	_fi.call("_finish_pass_charge")
	if _fi.get("_pass_intent") != null:
		_fail("too-far pass created a pass_intent")
	print("[verify_pass] phase6 too-far reject ok (intent=None)")

	main.free()
	_done()


# ── helpers ──────────────────────────────────────────────────────────────────

func _reset_scene() -> void:
	_player.global_position = Vector3(0.0, 0.05, 0.0)
	_player.rotation = Vector3.ZERO
	_player.velocity = Vector3.ZERO
	_ball.global_position = Vector3(0.0, 0.11, 1.8)
	_ball.velocity = Vector3.ZERO


func _redo_possession(label: String) -> void:
	_reset_scene()
	if not _drive_until_ball(700, true):
		_fail("%s: could not re-establish possession" % label)


func _physics_all(dt: float) -> void:
	_player.call("_physics_process", dt)
	_simulate_ball(_ball, dt)
	_fi.call("_physics_process", dt)
	_player.global_position.y = 0.05
	_player.velocity.y = 0.0


func _drive_until_ball(max_steps: int, forward: bool) -> bool:
	Input.action_press("move_forward" if forward else "move_back")
	for i in max_steps:
		if bool(_fi.call("has_ball")):
			return true
		_physics_all(JOG_DT)
	return bool(_fi.call("has_ball"))


func _run_pass_until_done() -> Dictionary:
	var r := {
		"saw_states": {},
		"saw_contact": false,
		"ball_vel_contact": Vector3.ZERO,
		"saw_executed": false,
		"min_mult": 1.0,
	}
	for i in 90:
		var st: int = _fi.call("get_state")
		r["saw_states"][st] = true
		r["min_mult"] = minf(r["min_mult"], float(_fi.call("get_movement_multiplier")))
		if st == _fi.State.PASS_CONTACT and not r.saw_contact:
			r.saw_contact = true
			r["ball_vel_contact"] = _ball.velocity
		if st == _fi.State.PASS_EXECUTED:
			r.saw_executed = true
		_physics_all(JOG_DT)
		var s2: int = _fi.call("get_state")
		if s2 == _fi.State.APPROACHING or s2 == _fi.State.NO_CONTROL or s2 == _fi.State.BALL_DETECTED:
			break
	return r


func _assert_pass(r: Dictionary, label: String, expect_speed: float, expect_dir: Vector2) -> void:
	var states: Dictionary = r["saw_states"]
	var ok_requested: bool = states.has(_fi.State.PASS_REQUESTED)
	var ok_prepare: bool = states.has(_fi.State.PASS_PREPARING)
	if not r.saw_contact:
		_fail("%s: never reached PASS_CONTACT (states=%s)" % [label, states.keys()])
	if not ok_requested or not ok_prepare:
		_fail("%s: missing pass states req=%s prep=%s (contact=%s)" % [label, ok_requested, ok_prepare, r.saw_contact])
	if r["min_mult"] > 0.51:
		_fail("%s: pass movement multiplier not applied (min=%.2f)" % [label, r["min_mult"]])
	var vel: Vector3 = r["ball_vel_contact"]
	var hor := Vector2(vel.x, vel.z)
	var hor_speed := hor.length()
	var dir := (hor / hor_speed) if hor_speed > 0.01 else Vector2.ZERO
	if hor_speed < expect_speed * 0.7 or hor_speed > expect_speed * 1.4:
		_fail("%s: impulse speed %.2f not near expected %.2f" % [label, hor_speed, expect_speed])
	if absf(vel.y) > 0.2:
		_fail("%s: not a ground pass, vertical lift %.2f" % [label, vel.y])
	if dir.distance_to(expect_dir) > 0.35:
		_fail("%s: direction off: dir=(%.2f, %.2f) expected (%.2f, %.2f)" % [label, dir.x, dir.y, expect_dir.x, expect_dir.y])
	print("[verify_pass] %s PASS: exp_speed=%.1f got_speed=%.1f dir=(%.2f, %.2f) lift=%.2f"
		% [label, expect_speed, hor_speed, dir.x, dir.y, vel.y])


func _recapture(max_steps: int) -> bool:
	for i in max_steps:
		if bool(_fi.call("has_ball")):
			return true
		_physics_all(JOG_DT)
	return bool(_fi.call("has_ball"))


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
		push_error("[verify_pass] FAILED.")
		quit(1)
	else:
		print("[verify_pass] PASS.")
		quit(0)


func _fail(msg: String) -> void:
	_failed = true
	push_error("[verify_pass] %s" % msg)