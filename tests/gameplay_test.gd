extends SceneTree
var checks = 0
var game
var w
func check(condition: bool, message: String) -> void:
	if not condition:
		push_error("FAIL: " + message)
		quit(1)
		assert(condition, message)
	checks += 1
	print("PASS: ", message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game._local_game()
	w = game.world
	w.set_physics_process(false)
	check(w.players.size() == 2 and w.bodies.size() == 2, "Local Dungeon creates two offline players")
	check(w.multiplayer.multiplayer_peer is OfflineMultiplayerPeer, "No server required")
	check(InputMap.action_get_events("p2_move_up")[0].physical_keycode == KEY_UP, "Arrow key binding")
	var b1 = w.bodies[w.players[1].body_id]
	var b2 = w.bodies[w.players[2].body_id]
	w._set_input(1, Vector2.LEFT, Vector2.UP, true)
	w._set_input(2, Vector2.RIGHT, Vector2.UP, true)
	var x1 = b1.position.x
	var x2 = b2.position.x
	w._simulate(0.1)
	check(b1.position.x < x1 and b2.position.x > x2, "Both keyboard players move independently")
	check(w.shots.is_empty() and w.trails.size() == 2, "Solo slimes leave trails and cannot shoot")
	var enemy_id = w._spawn_enemy(b1.position + Vector3(0, 0, -4), "crawler")
	var e = w.enemies[enemy_id]
	w.trails[999] = {"id": 999, "position": e.position, "color": Color.GREEN, "expires": 10.0}
	var before = e.position
	w._update_enemies(0.1)
	check(e.slow and e.position.distance_to(before) < 0.19, "Solo trail slows enemies without damaging them")
	check(e.health == e.max_health, "Trail does no damage")
	w.enemies.clear()
	var ember = w.pickups.values()[0]
	b1.position = ember.position
	w._action(1, "collect")
	check(w.players[1].element == "Ember", "Solo collects Ember")
	w.clock = 2.0
	b2.position = ember.position + Vector3(1, 0, 0)
	w._action(2, "collect")
	w._action(1, "fuse")
	w._check_fusion()
	check(w.bodies.size() == 2, "Fusion requires both players' consent")
	w._action(2, "fuse")
	w._check_fusion()
	check(w.bodies.size() == 1, "Consenting nearby slimes fuse")
	var fused = w.bodies.values()[0]
	check(w._powers(fused).get("Ember") == 2, "Matching powers stack to Ember x2")
	var frost = w.pickups.values()[1]
	fused.position = frost.position
	w._action(1, "collect")
	check(w.players[1].element == "Ember", "Fused body cannot collect power")
	var eid = w._spawn_enemy(fused.position + Vector3(0, 0, -3), "brute")
	w._hit(eid, 0, {"Ember": 2})
	check(w.enemies[eid].health == 134 and w.enemies[eid].burn_damage == 12, "Matching powers double elemental hit and burn")
	fused.health = 70
	w._split(fused)
	check(w.bodies.size() == 2, "Split restores solo bodies")
	check(w.bodies.values()[0].health == 35 and w.players[1].element == "Ember", "Split preserves health ratio and power")
	w.bodies[w.players[2].body_id].position = frost.position
	w._action(2, "collect")
	w.bodies[w.players[1].body_id].position = frost.position
	w._action(1, "fuse")
	w._action(2, "fuse")
	w._check_fusion()
	fused = w.bodies.values()[0]
	check(w._power_name(fused).begins_with("FROSTFIRE"), "Mixed powers form Frostfire")
	w._hit(eid, 0, w._powers(fused))
	check(w.enemies[eid].burn_until > w.clock and w.enemies[eid].frost_until > w.clock, "Frostfire applies burn and slow")
	w.enemies.clear()
	fused.position = w.terrain.LANDMARKS[1]
	w._progress()
	check(w.stage == 1 and w.enemies.size() == 4, "Entering grove starts encounter without teleport")
	check(fused.position == w.terrain.LANDMARKS[1], "Landmark transition preserves player position")
	w.stage = 2
	w._reset_party()
	w._start_encounter()
	check(w.enemies.size() == 6, "Second combat chamber has six enemies")
	w.stage = 3
	w._reset_party()
	w._start_encounter()
	var boss = w.enemies[w.boss_id]
	check(boss.health == 1800, "Final chamber spawns boss")
	w.clock = boss.attack_at
	w._boss(boss, w.bodies.values()[0])
	check(w.hazards.size() == 1 and not w.hazards.values()[0].fired, "Boss telegraphs volley")
	w.clock += 1.3
	w._update_hazards(0)
	check(w.shots.size() == 12, "Telegraphed volley fires twelve projectiles")
	boss.health = 600
	w._boss(boss, w.bodies.values()[0])
	check(boss.enraged, "Boss enters second phase at half health")
	boss.health = 0
	w._update_enemies(0)
	check(w.victory and w.enemies.is_empty(), "Boss death opens victory gate and clears enemies")
	w.bodies[w.players[1].body_id].position = w.PORTAL
	w.bodies[w.players[2].body_id].position = w.PORTAL
	w._action(1, "fuse")
	w._action(2, "fuse")
	w._check_fusion()
	w._progress()
	check(w.complete, "Fused team reaching gate completes level")
	w._apply(w._snapshot())
	w._process(0.016)
	check(w.visuals.size() > 0, "Imported 3D assets instantiate")
	w._restart()
	check(w.stage == 0 and not w.complete and w.bodies.size() == 2, "Replay resets run")
	w._apply(w._snapshot())
	w._process(0.1)
	check(w.camera_rig.split, "Separate local slimes have two third-person views")
	check(w._can_occupy(Vector3(0, 0, 25), 0.7), "Old room gates no longer block exploration")
	check(is_equal_approx(w.terrain.elevation(Vector3(0, 0, -68)), 8.4), "Summit is elevated above trailhead")
	w.camera_rig.orbit_yaw[0] = PI / 2
	check(w.camera_rig.movement(Vector2.UP, 0).distance_to(Vector2.LEFT) < 0.001, "Movement is camera-relative")
	w.camera_rig.orbit_yaw[0] = 0
	var jumper = w.bodies[w.players[1].body_id]
	w._action(1, "jump")
	w._simulate(0.1)
	check(jumper.position.y > w.terrain.elevation(jumper.position), "Jump lifts slime off terrain")
	for i in 60: w._simulate(1.0 / 60)
	check(is_equal_approx(jumper.position.y, w.terrain.elevation(jumper.position)), "Jump lands on terrain")
	w._action(1, "fuse")
	w._action(2, "fuse")
	w._check_fusion()
	w._apply(w._snapshot())
	w._process(0.1)
	check(not w.camera_rig.split, "Fusion merges local views and remains third-person")
	check(w.camera_rig.distance[0] > 7, "Fusion smoothly pulls camera back")
	var route_clear = true
	for z in range(-90, 57):
		if not w._can_occupy(w.terrain.ground(Vector3(w.terrain.trail_x(z), 0, z)), 1.8): route_clear = false
	check(route_clear, "Entire marked route is passable by the largest fused slime")
	check(w.pickups.size() == 15, "Twelve landmark powers plus three exploration caches")
	var jumping_fusion = w.bodies.values()[0]
	jumping_fusion.invulnerable = 0
	jumping_fusion.position.y = w.terrain.elevation(jumping_fusion.position) + 2
	var hp_before = jumping_fusion.health
	w.hazards[90000] = {"id": 90000, "position": w.terrain.ground(jumping_fusion.position), "radius": 4,
		"trigger": w.clock, "expires": w.clock + 2, "kind": "slam", "fired": false}
	w._update_hazards(0)
	check(jumping_fusion.health == hp_before, "Jump evades ground slam")
	jumping_fusion.position.y = w.terrain.elevation(jumping_fusion.position)
	w.hazards[90000].fired = false
	w._update_hazards(0)
	check(jumping_fusion.health == hp_before - 30, "Same slam hits a grounded slime")
	await process_frame
	print("ALL ", checks, " GAMEPLAY CHECKS PASSED")
	quit(0)
