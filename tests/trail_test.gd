extends SceneTree
var checks=0
var failed=false
func check(ok: bool,label: String) -> void:
	if not ok: failed=true; push_error(label)
	else: checks+=1; print("PASS: ",label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game._local_game()
	var w=game.world
	w.set_physics_process(false)
	var b=w.bodies[w.players[1].body_id]
	var enemy_id=w._spawn_enemy(b.position+Vector3(0,0,-4),"brute")
	var e=w.enemies[enemy_id]
	w.trails[900]={"id":900,"position":e.position,"expires":100,"color":Color.RED,"powers":{"Ember":1}}
	var hp=e.health
	w._apply_trail_effects(e,1)
	check(is_equal_approx(hp-e.health,3),"Ember trail deals minor damage")
	w.trails[901]=w.trails[900].duplicate(true)
	hp=e.health
	w._apply_trail_effects(e,1)
	check(is_equal_approx(hp-e.health,3),"Overlapping patches do not multiply damage")
	w.trails[900].powers={"Venom":1}
	w.trails.erase(901)
	w._apply_trail_effects(e,0)
	check(e.poison_damage==1.5 and e.poison_until>w.clock,"Venom leaves weaker lingering poison")
	e.poison_damage=20
	w._apply_trail_effects(e,0)
	check(e.poison_damage==20,"Trail does not overwrite stronger fused poison")
	w.trails[900].powers={"Storm":1}
	hp=e.health
	w._apply_trail_effects(e,0)
	w._apply_trail_effects(e,0)
	check(is_equal_approx(hp-e.health,2),"Storm shocks are rate limited")
	w.trails[900].powers={"Gale":1}
	var before=e.position
	w._apply_trail_effects(e,1)
	check(e.position.distance_to(before)>0,"Gale gently pushes enemies")
	w.enemies.clear()
	w.trails.clear()
	for i in 20:
		w.trails[900+i]={"id":900+i,"position":b.position+Vector3(0,0,-i),"expires":100,"color":Color.CYAN,"powers":{"Frost":1}}
	w._set_input(1,Vector2.UP,Vector2.UP,false)
	for i in 40:w._simulate(1.0/60)
	check(b.velocity.length()>9.5,"Frost trail speeds up allies")
	w._set_input(1,Vector2.ZERO,Vector2.UP,false)
	var speed=b.velocity.length()
	w._simulate(1.0/60)
	check(speed-b.velocity.length()<0.5,"Frost gives sliding momentum")
	check(w._trail_powers(b.position+Vector3(0,2,0),b.radius).is_empty(),"Airborne slimes do not receive floor effects")
	w.clock=101
	check(w._trail_powers(b.position,b.radius).is_empty(),"Expired patches have no effects")
	w._restart()
	w.players[1].elements=["Ember","Frost"]
	w._set_input(1,Vector2.UP,Vector2.UP,false)
	w._simulate(0.1)
	check(w.trails.values()[0].powers=={"Ember":1,"Frost":1},"Solo trail carries every equipped element")
	check(w._snapshot().trails[0].powers.has("Frost"),"Trail effects included in authoritative snapshot")
	print("ALL ",checks," TRAIL CHECKS PASSED")
	quit(1 if failed else 0)
