extends SceneTree
var game
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	if "--server" in OS.get_cmdline_user_args():
		game._host_game()
		await create_timer(4).timeout
		if game.world.players.size() != 2:
			push_error("Server did not register client")
			quit(1)
			return
		print("NETWORK HOST PASS: two registered players")
		await create_timer(2).timeout
	else:
		game._join_game()
		await create_timer(3).timeout
		if not is_instance_valid(game.world) or game.world.state.get("players", []).size() != 2:
			push_error("Client did not receive authoritative state")
			quit(1)
			return
		game.world.action.rpc_id(1, "fuse")
		await create_timer(1.5).timeout
		if game.world._local_body().is_empty() or not game.world._local_body().offering:
			push_error("Reliable client action was not replicated")
			quit(1)
			return
		print("NETWORK CLIENT PASS: authoritative snapshot and reliable fusion offer")
	game.world.queue_free()
	await process_frame
	quit(0)
