extends SceneTree
var checks = 0
var failed = false
func check(ok: bool, label: String) -> void:
	if not ok:
		failed = true
		push_error(label)
		quit(1)
		assert(ok)
	checks += 1
	print("PASS: ",label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game._local_game()
	var w=game.world
	w.set_physics_process(false)
	w._apply(w._snapshot())
	w._process(0.016)
	var rig=w.camera_rig
	var drag=InputEventMouseButton.new()
	drag.button_index=MOUSE_BUTTON_RIGHT
	drag.pressed=true
	Input.parse_input_event(drag)
	await process_frame
	var mouse=InputEventMouseMotion.new()
	mouse.relative=Vector2(50,40)
	rig._input(mouse)
	check(rig.yaw[0] < 0 and rig.pitch[0] < -0.42,"Mouse controls yaw and pitch")
	var wheel=InputEventMouseButton.new()
	wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed=true
	rig._input(wheel)
	check(rig.zoom[0] == 1,"Mouse wheel zoom works")
	Input.action_release("jump")
	var key=InputEventKey.new()
	key.physical_keycode=KEY_K
	key.pressed=true
	Input.parse_input_event(key)
	await process_frame
	rig.update(0.1)
	check(rig.pitch[1] < -0.42,"Player two can tilt camera with K")
	key.pressed=false
	Input.parse_input_event(key)
	var reset=InputEventKey.new()
	reset.physical_keycode=KEY_HOME
	reset.pressed=true
	rig._input(reset)
	check(rig.zoom[0] == 0 and rig.pitch[0] == -0.42,"Home restores default view")
	w._next_map()
	check(w.map_index == 0,"Cannot skip first map before completing it")
	w._award_xp(250,"test")
	w.players[1].elements=["Ember","Frost"]
	w.complete=true
	w._next_map()
	check(w.map_index == 1 and w.stage == 0 and not w.complete,"Completed first map unlocks Amber Ruins")
	check(w.party_level == 3 and w.players[1].elements == ["Ember","Frost"],"Map travel retains levels and inventories")
	check(w.pickups.size() == 23,"Second map provides five powers at each landmark and three caches")
	var route_clear=true
	for z in range(-90,57):
		if not w._can_occupy(w.terrain.ground(Vector3(w.terrain.trail_x(z),0,z)),1.8):route_clear=false
	check(route_clear,"Ruins route is clear for largest fusion")
	w.enemies.clear()
	var a=w._spawn_enemy(Vector3(0,0,43),"brute")
	var b=w._spawn_enemy(Vector3(1,0,43),"brute")
	w._hit(a,0,{"Venom":1,"Storm":1})
	check(w.enemies[a].poison_until > w.clock and w.enemies[b].poison_until > w.clock,"Plague Arc spreads poison through lightning")
	var hp=w.enemies[b].health
	w._update_enemies(0.1)
	check(w.enemies[b].health < hp,"Poison deals damage over time")
	w._hit(a,0,{"Venom":1,"Frost":1})
	check(w.enemies[a].poison_until == w.clock+6 and w.enemies[a].frost_until > w.clock,"Deep Chill extends poison and slows")
	var before=w.enemies[b].position
	w._hit(b,0,{"Gale":2})
	check(w.enemies[b].position.distance_to(before) > 1,"Gale pushes enemies away")
	w.stage=3
	w._start_encounter()
	check(is_equal_approx(w.enemies[w.boss_id].max_health,1960),"Amber Warden has scaled health")
	w.victory=true
	w.enemies.clear()
	w._reset_party()
	w._action(1,"fuse")
	w._action(2,"fuse")
	w._check_fusion()
	w.bodies.values()[0].position=w.PORTAL
	w._progress()
	check(w.complete,"Second map exit completes expedition")
	w._restart()
	check(w.map_index == 0 and w.party_level == 1 and w.pickups.size() == 15,"Restart returns to first map with a fresh expedition")
	print("ALL ",checks," RUINS AND CAMERA CHECKS PASSED")
	quit(1 if failed else 0)
