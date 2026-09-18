extends SceneTree
var checks = 0
func check(ok: bool, label: String) -> void:
	if not ok:
		push_error(label)
		quit(1)
		assert(ok)
	checks += 1
	print("PASS: ", label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game._local_game()
	var w = game.world
	w.set_physics_process(false)
	for level in [1,2,3,5,6,8,9,10]:
		w.party_level = level
		check(w._power_capacity() == 1 + floori(level / 3.0), "Capacity at level %d" % level)
	w.party_level = 3
	var b = w.bodies[w.players[1].body_id]
	var items = w.pickups.values()
	for i in [0,1]:
		b.position = items[i].position
		w._action(1, "collect")
	check(w.players[1].elements == ["Ember","Frost"], "Empty slots collect distinct powers")
	b.position = items[2].position
	w._action(1,"collect")
	check(w.players[1].elements == ["Frost","Storm"], "Full inventory replaces oldest power")
	items[2].ready = 0
	items[2].claimed = false # Fixture supplies a second Storm find to verify stacking.
	w._action(1,"collect")
	check(w.players[1].elements == ["Storm","Storm"], "Same power can occupy both slots")
	w.bodies[w.players[2].body_id].position = b.position + Vector3.RIGHT
	w._action(1,"fuse")
	w._action(2,"fuse")
	w._check_fusion()
	check(w._powers(w.bodies.values()[0]).get("Storm") == 2, "Fusion stacks all inventory slots")
	w._split(w.bodies.values()[0])
	check(w.players[1].elements.size() == 2, "Split retains inventory")
	w._restart()
	b = w.bodies[w.players[1].body_id]
	var baseline = b.position.y
	w._action(1,"jump")
	var full_height = 0.0
	for i in 70:
		w._simulate(1.0/120)
		full_height = maxf(full_height, b.position.y-baseline)
	w._reset_party()
	b = w.bodies[w.players[1].body_id]
	w._action(1,"jump")
	w._action(1,"jump_release")
	var short_height = 0.0
	for i in 70:
		w._simulate(1.0/120)
		short_height = maxf(short_height, b.position.y-baseline)
	check(full_height > short_height * 2 and full_height > 2, "Held jump rises higher than tapped jump")
	b.position.y = baseline + 0.08
	b.vertical_speed = -8
	b.coyote = 0
	w._action(1,"jump")
	w._simulate(1.0/60)
	check(b.vertical_speed > 0, "Buffered jump launches on landing")
	var speed = b.vertical_speed
	w._action(1,"jump")
	check(b.vertical_speed == speed, "Airborne presses do not double jump")
	w._apply(w._snapshot())
	w._process(0.016)
	var shot = w._make_visual("shots", {"enemy":false,"color":Color.BLUE,"velocity":Vector3.FORWARD})
	check(shot.get_child_count() == 5, "Projectile has halo, core and three trailing sprites")
	shot.free()
	var model = load("res://assets/quaternius/fusion.glb").instantiate()
	check(model.find_child("AnimationPlayer",true,false).has_animation("Armature|Slime_Attack"), "New fused slime imports its attack animation")
	model.free()
	print("ALL ",checks," POWER AND JUMP CHECKS PASSED")
	quit()
