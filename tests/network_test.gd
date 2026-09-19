extends SceneTree
var game
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	if "--server" in OS.get_cmdline_user_args():
		game._host_game()
		game.world._award_xp(250, "network_test")
		game.world.coins = 87
		game.world.damage_upgrades = 1
		game.world.shop_stock["0:1"] = true
		game.world.players[1].elements = ["Ember", "Storm"]
		game.world.players[1].element = "Ember + Storm"
		await create_timer(4).timeout
		if game.world.players.size() != 2:
			push_error("Server did not register client")
			quit(1)
			return
		print("NETWORK HOST PASS: two registered players")
		game.world.complete = true
		game.world._next_map()
		await create_timer(2).timeout
	else:
		game._join_game()
		await create_timer(3).timeout
		if not is_instance_valid(game.world) or game.world.state.get("players", []).size() != 2:
			push_error("Client did not receive authoritative state")
			quit(1)
			return
		if game.world.state.party_level != 3 or game.world.state.players[0].elements.size() != 2 or game.world.state.players[0].capacity != 2:
			push_error("Shared level was not replicated")
			quit(1)
			return
		if game.world.state.coins != 87 or game.world.state.damage_upgrades != 1 or not game.world.state.shop_stock.get("0:1",false):
			push_error("Economy was not replicated")
			quit(1)
			return
		game.world.action.rpc_id(1, "fuse")
		await create_timer(1.5).timeout
		if game.world._local_body().is_empty() or game.world.map_index != 1 or game.world.state.pickups.size() != 6:
			push_error("Map transition was not replicated")
			quit(1)
			return
		print("NETWORK CLIENT PASS: authoritative snapshot, inventories and second-map transition")
	game.world.queue_free()
	await process_frame
	quit(0)
