extends SceneTree
var checks = 0
func check(ok: bool, label: String) -> void:
	assert(ok, label)
	checks += 1
	print("PASS: ", label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game._local_game()
	var w = game.world
	w.set_physics_process(false)
	var b = w.bodies[w.players[1].body_id]
	check(InputMap.action_get_events("sprint")[0].physical_keycode == KEY_SHIFT and InputMap.action_get_events("p2_sprint")[0].physical_keycode == KEY_CTRL, "Both sprint keys bound")
	w._set_input(1, Vector2.UP, Vector2.UP, false)
	for i in 20: w._simulate(1.0 / 60)
	check(is_equal_approx(b.velocity.length(), 9), "Solo walk reaches 9 units per second")
	w._set_input(1, Vector2.UP, Vector2.UP, false, true)
	for i in 20: w._simulate(1.0 / 60)
	check(is_equal_approx(b.velocity.length(), 15.3), "Sprint reaches 1.7 times walking speed")
	w._set_input(1, Vector2.ZERO, Vector2.UP, false)
	for i in 15: w._simulate(1.0 / 60)
	check(b.velocity.length() < 0.001, "Release brakes to a complete stop")
	w._reset_party()
	w._action(1, "fuse")
	w._action(2, "fuse")
	w._check_fusion()
	b = w.bodies.values()[0]
	w._set_input(1, Vector2.UP, Vector2.UP, false, true)
	for i in 20: w._simulate(1.0 / 60)
	check(is_equal_approx(b.velocity.length(), 12.92), "Idle partner does not halve fused sprint speed")
	w._award_xp(100, "test_reward")
	check(w.party_level == 2 and w.party_xp == 0 and b.max_health == 160, "Level up adds health per fused member")
	w._award_xp(100, "test_reward")
	check(w.party_xp == 0, "Claim cannot award XP twice")
	var eid = w._spawn_enemy(b.position + Vector3(0,0,-5), "brute")
	var hp = w.enemies[eid].health
	w._hit(eid, 20, {})
	check(is_equal_approx(hp - w.enemies[eid].health, 22.4), "Level adds 12 percent fusion damage")
	w._split(b)
	check(w.bodies.values()[0].max_health == 80, "Split preserves level health bonus")
	w._reset_party()
	check(w.party_level == 2, "Death reset retains progression")
	w._apply(w._snapshot())
	w._process(0.016)
	check(game.level_label.text.begins_with("PARTY LEVEL 2"), "HUD shows shared level")
	b = w._local_body()
	var cam = w.camera_rig.cameras[0]
	var anchor = w.camera_anchor(b) + Vector3.UP * w.camera_rig.eye_height[0]
	check((-cam.global_basis.z).dot((anchor-cam.position).normalized()) > 0.9999, "Camera aims at visible model anchor")
	w.is_host = false
	var now = Time.get_ticks_msec() / 1000.0
	w.snapshot_frames = [{"time":now-0.22,"bodies":[{"id":1,"position":Vector3.ZERO}],"enemies":[]},{"time":now-0.02,"bodies":[{"id":1,"position":Vector3(10,0,0)}],"enemies":[]}]
	check(absf(w._sample_remote_position("bodies", {"id":1,"position":Vector3(10,0,0)}).x - 5) < 0.2, "Remote rendering interpolates buffered snapshots")
	w.is_host = true
	w._award_xp(100000, "cap")
	check(w.party_level == 10 and w.party_xp == 0, "Levels cap at ten")
	w._restart()
	check(w.party_level == 1 and w.xp_claims.is_empty(), "New expedition resets levels and reward claims")
	print("ALL ", checks, " MOVEMENT AND LEVEL CHECKS PASSED")
	quit()
