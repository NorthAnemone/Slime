extends SceneTree
var game
var output_dir = OS.get_environment("SLIME_SCREENSHOT_DIR")
func _initialize() -> void:
	call_deferred("run")
func snap(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output_dir.path_join(path))
func run() -> void:
	if output_dir.is_empty(): output_dir = "user://screenshots"
	DirAccess.make_dir_recursive_absolute(output_dir)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await create_timer(0.5).timeout
	await snap("slime-menu.png")
	game._local_game()
	await create_timer(1).timeout
	await snap("slime-local.png")
	var w = game.world
	w.stage = 3
	w._reset_party()
	w._award_xp(250, "visual_check")
	w.players[1].elements = ["Ember", "Storm"]
	w.players[1].element = "Ember + Storm"
	w.players[2].elements = ["Frost", "Ember"]
	w.players[2].element = "Frost + Ember"
	w._action(1, "fuse")
	w._action(2, "fuse")
	w._check_fusion()
	w._start_encounter()
	await create_timer(2).timeout
	await snap("slime-boss.png")
	w.players[1].aim = Vector2(0.8, -0.6)
	w._attack(w.players[1], w.bodies.values()[0])
	await create_timer(0.25).timeout
	await snap("slime-projectile.png")
	game.queue_free()
	await process_frame
	quit()
