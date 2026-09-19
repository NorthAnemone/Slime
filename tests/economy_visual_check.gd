extends SceneTree
var output_dir = OS.get_environment("SLIME_SCREENSHOT_DIR")
func _initialize() -> void: call_deferred("run")
func snap(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output_dir.path_join(name+".png"))
func run() -> void:
	if output_dir.is_empty(): output_dir = "user://screenshots"
	DirAccess.make_dir_recursive_absolute(output_dir)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game._local_game()
	var w = game.world
	w.set_physics_process(false)
	w.enemies.clear()
	w.coins = 120
	w._action(1,"fuse")
	w._action(2,"fuse")
	w._check_fusion()
	w.players[1].weapon = "Sword"
	w.players[2].weapon = "Bow"
	var body = w.bodies.values()[0]
	body.position = w._shop_locations()[0]+Vector3(0,0,5)
	w._apply(w._snapshot())
	await create_timer(1).timeout
	await snap("shop-two-weapons")
	for id in range(3,7):
		w._add_player(id,"Player %d" % id)
		w.bodies.erase(w.players[id].body_id)
		w.players[id].body_id = body.id
		body.members.append(id)
		w.players[id].weapon = "Bow" if id%2==0 else "Sword"
	w._apply(w._snapshot())
	await create_timer(1).timeout
	await snap("six-hands")
	for id in range(3,7):
		body.members.erase(id)
		w.players.erase(id)
	w.complete = true
	w._next_map()
	w.set_physics_process(false)
	w.enemies.clear()
	w._apply(w._snapshot())
	await create_timer(1).timeout
	await snap("ruins-shops")
	w.complete = true
	w._next_map()
	w.set_physics_process(false)
	w.enemies.clear()
	w._apply(w._snapshot())
	game.player_map.toggle_map()
	await create_timer(1).timeout
	await snap("procedural-floor-map")
	game.free()
	quit()
