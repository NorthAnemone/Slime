extends SceneTree
var failed=false
var checks=0
func check(ok: bool,label: String) -> void:
	if not ok:failed=true;push_error(label)
	else:checks+=1;print("PASS: ",label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game._local_game()
	var w=game.world
	w.set_physics_process(false)
	check(w.pickups.size()==5,"Only five powers in the Wilds")
	var b=w.bodies[w.players[1].body_id]
	var item=w.pickups.values()[0]
	b.position=item.position
	w._action(1,"collect")
	w._action(1,"collect")
	check(item.claimed and w.players[1].elements.size()==1,"Power pickup is consumed once")
	w._reset_party()
	check(item.claimed,"Defeat does not replenish powers")
	b=w.bodies[w.players[1].body_id]
	b.position=Vector3(-32.6,0,36)
	w._set_input(1,Vector2.ZERO,Vector2.UP,false,false,true)
	for i in 15:w._simulate(1.0/60)
	check(b.position.y>0.5 and b.stamina<100,"Solo climb gains height and spends stamina")
	b.stamina=0
	var y=b.position.y
	for i in 30:w._simulate(1.0/60)
	check(b.position.y<y,"Empty stamina stops climbing")
	w._set_input(1,Vector2.ZERO,Vector2.UP,false)
	for i in 60:w._simulate(1.0/60)
	check(b.stamina>10,"Resting recovers shared stamina")
	w._reset_party()
	w.players[1].elements.clear()
	w.players[1].element=""
	w._action(1,"fuse")
	w._action(2,"fuse")
	w._check_fusion()
	b=w.bodies.values()[0]
	var e=w._spawn_enemy(b.position+Vector3(0,0,-2),"brute")
	var hp=w.enemies[e].health
	w._attack(w.players[1],b)
	check(w.enemies[e].health<hp and w.shots.is_empty(),"Unpowered sword deals melee damage only")
	w.players[1].weapon="Bow"
	w._attack(w.players[1],b)
	check(w.shots.size()==1 and w.shots.values()[0].powers.is_empty(),"Unpowered bow fires physical arrows")
	w.shots.clear()
	w.players[1].weapon="Magic"
	w._attack(w.players[1],b)
	check(w.shots.is_empty(),"Magic requires an element")
	w.players[1].elements=["Ember"]
	w._attack(w.players[1],b)
	check(w.shots.values()[0].powers.has("Ember"),"Magic applies equipped powers")
	w.complete=true
	w._next_map()
	check(w.pickups.size()==6,"Ruins have six scattered power finds")
	b=w.bodies[w.players[1].body_id]
	b.position=w.plates[0]
	w._action(1,"collect")
	b.position=w.plates[1]
	w._action(1,"collect")
	check(w.clues_found==3 and not w.puzzle_open,"Reading both clues alone does not solve lock")
	for i in 3:
		b.position=w.terrain.ground(Vector3(-5+i*5,0,-15))
		while w.rune_states[i]!=i:w._action(1,"collect")
	b.position=w.terrain.ground(Vector3(w.terrain.trail_x(-20),0,-20))
	w._action(1,"collect")
	check(not w.puzzle_open,"Final lock requires fusion")
	w.bodies[w.players[2].body_id].position=b.position+Vector3.RIGHT
	w._action(1,"fuse")
	w._action(2,"fuse")
	w._check_fusion()
	w._action(1,"collect")
	check(w.puzzle_open,"Correct rune sequence plus fusion opens lock")
	check(w.platforms.any(func(s):return s.top-s.bottom>=9),"Map includes a nine-metre climbable terrace")
	print("ALL ",checks," COMBAT CLIMB AND RUNE CHECKS PASSED")
	quit(1 if failed else 0)
