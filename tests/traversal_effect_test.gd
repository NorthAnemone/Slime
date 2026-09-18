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
	var b=w.bodies[w.players[1].body_id]
	b.position=Vector3(-30,2,36)
	b.vertical_speed=-2
	for i in 30:w._simulate(1.0/60)
	check(is_equal_approx(b.position.y,1),"Jumpable platform supports landing")
	w._action(1,"jump")
	check(b.vertical_speed>0,"Can jump again from a platform")
	check(not w._can_occupy(Vector3(-30,0,36),0.7),"Cannot walk through solid platform sides")
	w.complete=true
	w._next_map()
	var plate=w.plates[0]
	check(w._can_occupy(plate,0.7) and not w._can_occupy(plate,1.26),"Low passage accepts solo and blocks fusion")
	var first=w.bodies[w.players[1].body_id]
	var second=w.bodies[w.players[2].body_id]
	first.position=w.plates[0]
	w._update_puzzle(1)
	check(not w.puzzle_open,"One slime cannot solve both seals")
	second.position=w.plates[1]
	w._update_puzzle(1)
	check(not w.puzzle_open,"Standing on old seals no longer solves puzzle")
	w._reset_party()
	w._action(1,"fuse")
	w._action(2,"fuse")
	w._check_fusion()
	var fused=w.bodies.values()[0]
	check(fused.transition.kind=="merge" and fused.transition.sources.size()==2,"Fusion stores both animation origins")
	w._apply(w._snapshot())
	w._process(0.016)
	check(w.visuals["bodies"+str(fused.id)].has_meta("morph_start"),"Merge animation starts on rendered body")
	w._split(fused)
	check(w.bodies.values()[0].transition.kind=="split","Split stores shared starting position")
	var shot=w._make_visual("shots",{"enemy":true,"color":Color.RED,"velocity":Vector3.FORWARD})
	var opaque=shot.has_node("SolidCore")
	for sprite in shot.get_children():
		if not sprite is Sprite3D:continue
		if sprite.alpha_cut != SpriteBase3D.ALPHA_CUT_DISCARD or sprite.modulate.a != 1:opaque=false
	check(opaque,"Every projectile sprite uses opaque alpha-cut pixels")
	shot.free()
	var enemy_id=w._spawn_enemy(Vector3(0,0,40),"skeleton")
	var enemy=w.enemies[enemy_id]
	var target=w.bodies.values()[0]
	w.clock=enemy.attack_at
	w._skeleton_attack(enemy,target)
	check(enemy.cast_at>w.clock and w.shots.is_empty(),"Skeleton warns before shooting")
	w.clock=enemy.cast_at
	w._skeleton_attack(enemy,target)
	check(w.shots.size()==1,"Skeleton releases aimed projectile after warning")
	check(w.enemies[enemy_id].health>100,"Second-map enemies have increased health")
	await process_frame
	print("ALL ",checks," TRAVERSAL AND EFFECT CHECKS PASSED")
	quit(1 if failed else 0)
