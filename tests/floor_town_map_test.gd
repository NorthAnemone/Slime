extends SceneTree
var failed := false
var checks := 0
func check(ok: bool, label: String) -> void:
	if ok: checks += 1; print("PASS: ",label)
	else: failed = true; push_error(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game._local_game()
	var w = game.world
	w.set_physics_process(false)
	check(InputMap.has_action("city_teleport") and InputMap.has_action("toggle_map") and InputMap.has_action("track_player"),"City, map and ally-tracker controls are bound")
	check(w._town_locations().size()==2,"Authored floor includes two side towns")
	var body = w.bodies[w.players[1].body_id]
	w.coins = 20
	body.health = 10
	body.position = w._town_locations()[0]+Vector3(0,0,1)
	w._action(1,"collect")
	check(w.coins==8 and body.health==body.max_health,"Town hospital heals the party for 12 coins")
	body.position = w._town_locations()[0]+Vector3(-4,0,1)
	w._action(1,"collect")
	check(w.side_quests.has("0") and w.side_quests["0"].status=="active","Bounty board starts a regional side quest")
	var quest = w.side_quests["0"]
	for i in quest.target:
		var enemy = {"id":9000+i,"position":body.position,"kind":"crawler","reward_key":"quest%d"%i,"region":quest.region}
		w._drop_coins(enemy)
	check(w.side_quests["0"].status=="complete" and w.coins>=quest.reward,"Bounty completion awards shared coins")
	body.position = Vector3(40,0,-70)
	w.enemies.clear()
	w._action(1,"city_teleport")
	check(body.position.distance_to(w.terrain.ground(w.terrain.LANDMARKS[0]+Vector3(0,0,7)))<0.1,"City crystal returns a player to the floor hub")
	w.complete = true
	w._next_map()
	w.complete = true
	w._next_map()
	check(w.map_index==2 and w.floor_name() in ["VERDANT EXPANSE","GOLDEN BADLANDS","MISTWOOD HEIGHTS"],"Floor 3 selects a procedural theme")
	check(w.map_bounds().size.x>=160 and w.map_bounds().size.y>=250,"Procedural floor is substantially larger")
	check(w._town_locations().size()==3,"Procedural floor generates three seeded towns")
	check(w._shop_locations().size()==4 and w.shop_labels.size()==12,"Every generated town plus the main city has a shop")
	check(w.rock_surfaces.size()>80,"Random trees and rocks expose climbable mesh surfaces")
	var same = load("res://scripts/procedural_floor.gd").new()
	same.configure(3)
	check(same.LANDMARKS==w.terrain.LANDMARKS and same.TOWNS==w.terrain.TOWNS,"Floor generation is deterministic for multiplayer")
	w.enemies.clear()
	w.stage = 3
	w._start_encounter()
	check(w.portal.position.distance_to(w.PORTAL)<0.1 and w.boss_id!=0,"Every floor has a boss route and ascent gate")
	game.player_map.toggle_map()
	game.player_map.toggle_tracking()
	check(game.player_map.expanded and game.player_map.tracking,"Minimap expands and teammate compass toggles")
	print("ALL %d FLOOR, TOWN AND MAP CHECKS PASSED" % checks)
	game.free()
	quit(1 if failed else 0)
