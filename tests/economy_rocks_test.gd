extends SceneTree
var failed = false
var checks = 0
func check(ok: bool, message: String) -> void:
	if not ok: failed = true; push_error(message)
	else: checks += 1; print("PASS: ",message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game._local_game()
	var w = game.world
	w.set_physics_process(false)
	check(w.enemies.size() >= 12,"Random enemies populate the map")
	check(w.shop_labels.size() == 9,"Three shops each display three offers")
	var b = w.bodies[w.players[1].body_id]
	var pos = Vector3.ZERO
	var top = -INF
	for surface in w.rock_surfaces:
		var candidate = surface.bounds.get_center()
		var candidate_top = w._rock_height(candidate)
		candidate.y = candidate_top
		if candidate_top > w.terrain.elevation(candidate)+1 and w._can_occupy(candidate,0.7):
			pos = candidate
			top = candidate_top
			break
	check(top > w.terrain.elevation(pos)+1,"Rock surface sampled from model triangles")
	pos.y = top
	check(w._can_occupy(pos,0.7),"Rock top is not an infinite wall")
	check(abs(w._floor_height(pos)-top)<0.01,"Player can stand on rock surface")
	pos.y = w.terrain.elevation(pos)
	check(not w._can_occupy(pos,0.7),"Solid rock still blocks entry below its top")
	w.enemies.clear()
	var id = w._spawn_enemy(b.position,"crawler","test:coin")
	w.enemies[id].health = 0
	w._update_enemies(0)
	check(w.loot.size()==1 and w.coins==0,"Enemy death leaves a collectible coin drop")
	w._collect_coins()
	check(w.coins==6 and w.loot.is_empty(),"Nearby slime collects into shared wallet")
	id = w._spawn_enemy(b.position,"crawler","test:coin")
	w.enemies[id].health = 0
	w._update_enemies(0)
	check(w.loot.is_empty(),"Retrying an enemy cannot duplicate its reward")
	var shop = w._shop_locations()[0]
	b.position = shop+Vector3(-3,0,0)
	b.health = 10
	w._action(1,"collect")
	check(w.coins==6 and b.health==10,"Insufficient funds do not buy healing")
	w.coins = 200
	w._action(1,"collect")
	check(w.coins==180 and b.health==b.max_health,"Healing purchase spends exactly 20 coins")
	b.position = shop
	w._action(1,"collect")
	w._action(1,"collect")
	check(w.coins==120 and w.damage_upgrades==1,"Upgrade stock prevents duplicate purchases")
	b.position = shop+Vector3(3,0,0)
	w._action(1,"collect")
	check(w.coins==75 and w.players[1].elements==["Ember"],"Solo power purchase uses inventory slot")
	w.stage = 1
	w._start_encounter()
	w.region_kills[1] = 3
	w._progress()
	check(not w.cleared[1],"Landmark remains locked below kill target")
	w.region_kills[1] = 4
	w._progress()
	check(w.cleared[1] and not w.enemies.is_empty(),"Kill quota unlocks progression with enemies still alive")
	w.stage = 0
	w._reset_party()
	w._action(1,"fuse")
	w._action(2,"fuse")
	w._check_fusion()
	w.players[1].weapon = "Sword"
	w.players[2].weapon = "Bow"
	var data = w._snapshot().bodies[0]
	check(data.equipment[0].weapon=="Sword" and data.equipment[1].weapon=="Bow","Snapshot preserves independent weapon choices")
	for member in range(3,7):
		w._add_player(member,"Test")
		data.members.append(member)
	var visual = w._make_visual("bodies",data)
	root.add_child(visual)
	check(visual.get_node("Weapons").get_child_count()==6,"Six fused members have six weapon attachments")
	var arm = visual.get_node("Weapons").get_child(5).get_node("ExtraArm")
	check(arm.mesh.get_faces().size()>0,"Extra members reuse actual arm geometry")
	visual.free()
	w.complete = true
	w._next_map()
	check(w.coins==75 and w.damage_upgrades==1 and w.shop_stock.is_empty(),"Map travel retains wallet and upgrades; refreshes shops")
	w._restart()
	check(w.coins==0 and w.damage_upgrades==0 and w.coin_claims.is_empty(),"New expedition resets economy")
	print("CHECKS: ",checks)
	game.free()
	quit(1 if failed else 0)
