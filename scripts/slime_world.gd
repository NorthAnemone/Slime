extends Node3D

signal toast_requested(message: String)
signal local_stats_changed(health: float, max_health: float, member_count: int, power: float, enemies_left: int, floor_number: int, portal_open: bool)
signal roster_changed(roster: Array)

const MAX_FUSION := 6
const WORLD_HALF := Vector2(36.0, 24.0)
const SERVER_PEER_ID := 1
const SNAPSHOT_INTERVAL := 0.066
const INPUT_INTERVAL := 0.033
const PLAYER_COLORS := [
	Color("72ef9b"), Color("65d5ff"), Color("ff8fd8"),
	Color("ffd66d"), Color("b79cff"), Color("ff9875")
]

var is_host := false
var local_coop := false
var local_peer_id := 1
var local_second_peer_id := 2
var local_player_name := "Gloob"
var next_entity_id := 1
var floor_number := 1
var portal_open := false
var snapshot_clock := 0.0
var input_clock := 0.0

var players := {}
var bodies := {}
var enemies := {}
var bullets := {}
var cores := {}

var latest_bodies: Array = []
var latest_enemies: Array = []
var latest_bullets: Array = []
var latest_cores: Array = []
var latest_players: Array = []

var body_visuals := {}
var enemy_visuals := {}
var bullet_visuals := {}
var core_visuals := {}

var camera: Camera3D
var portal_visual: Node3D
var aim_marker: MeshInstance3D
var walls: Array[Rect2] = [
	Rect2(-36, -24, 72, 1), Rect2(-36, 23, 72, 1),
	Rect2(-36, -24, 1, 48), Rect2(35, -24, 1, 48),
	Rect2(-22, -23, 1.2, 11), Rect2(-22, -7, 1.2, 13), Rect2(-22, 11, 1.2, 12),
	Rect2(-8, -17, 1.2, 17), Rect2(-8, 5, 1.2, 18),
	Rect2(7, -23, 1.2, 12), Rect2(7, -6, 1.2, 16), Rect2(7, 15, 1.2, 8),
	Rect2(21, -15, 1.2, 15), Rect2(21, 5, 1.2, 18),
	Rect2(-31, -10, 9, 1.2), Rect2(-21, 2, 8, 1.2),
	Rect2(-7, -4, 9, 1.2), Rect2(8, 10, 8, 1.2), Rect2(22, 0, 13, 1.2)
]


func _ready() -> void:
	camera = get_node_or_null("MainCamera") as Camera3D
	if camera:
		camera.make_current()
		camera.look_at(Vector3.ZERO, Vector3.UP)
	_build_dungeon()
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func setup_host(player_name: String) -> void:
	is_host = true
	local_peer_id = SERVER_PEER_ID
	local_player_name = player_name
	_add_player(local_peer_id, player_name)
	_reset_floor()


func setup_client(player_name: String) -> void:
	is_host = false
	local_peer_id = multiplayer.get_unique_id()
	local_player_name = player_name
	register_player.rpc_id(SERVER_PEER_ID, player_name)


func setup_local_coop(first_name: String, second_name: String) -> void:
	is_host = true
	local_coop = true
	local_peer_id = 1
	local_second_peer_id = 2
	local_player_name = first_name
	_add_player(local_peer_id, first_name)
	_add_player(local_second_peer_id, second_name)
	_reset_floor()
	bodies[players[local_peer_id].body_id].position = Vector3(-2.0, 0, 0)
	bodies[players[local_second_peer_id].body_id].position = Vector3(2.0, 0, 0)
	_apply_snapshot(_make_snapshot())


func _physics_process(delta: float) -> void:
	if not local_coop and not multiplayer.has_multiplayer_peer():
		return
	input_clock += delta
	if input_clock >= INPUT_INTERVAL:
		input_clock = 0.0
		_send_local_input()

	if is_host:
		_update_host_simulation(delta)
		snapshot_clock += delta
		if snapshot_clock >= SNAPSHOT_INTERVAL:
			snapshot_clock = 0.0
			var state := _make_snapshot()
			if not local_coop:
				receive_snapshot.rpc(state)
			_apply_snapshot(state)


func _process(delta: float) -> void:
	_sync_visuals(delta)
	_update_camera(delta)
	_update_aim_marker()
	if portal_visual:
		portal_visual.rotate_y(delta * 0.8)
		portal_visual.visible = portal_open


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("fuse"):
		if is_host:
			_offer_fusion_for(local_peer_id)
		else:
			offer_fusion.rpc_id(SERVER_PEER_ID)
	if event.is_action_pressed("split"):
		if is_host:
			_split_for(local_peer_id)
		else:
			request_split.rpc_id(SERVER_PEER_ID)
	if local_coop and event.is_action_pressed("p2_fuse"):
		_offer_fusion_for(local_second_peer_id)
	if local_coop and event.is_action_pressed("p2_split"):
		_split_for(local_second_peer_id)


@rpc("any_peer", "call_remote", "reliable")
func register_player(player_name: String) -> void:
	if not is_host:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id <= 0 or players.has(peer_id):
		return
	_add_player(peer_id, player_name.strip_edges().substr(0, 18))
	_broadcast_message("%s oozed into the dungeon." % players[peer_id].name)


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func submit_input(move_input: Vector2, aim_input: Vector2, attacking: bool) -> void:
	if not is_host:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if players.has(peer_id):
		players[peer_id].input = {
			"move": move_input.limit_length(1.0),
			"aim": aim_input.normalized() if aim_input.length_squared() > 0.01 else Vector2.RIGHT,
			"attack": attacking
		}


@rpc("any_peer", "call_remote", "reliable")
func offer_fusion() -> void:
	if is_host:
		_offer_fusion_for(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func request_split() -> void:
	if is_host:
		_split_for(multiplayer.get_remote_sender_id())


@rpc("authority", "call_remote", "unreliable_ordered", 2)
func receive_snapshot(state: Dictionary) -> void:
	_apply_snapshot(state)


@rpc("authority", "call_local", "reliable")
func announce(message: String) -> void:
	toast_requested.emit(message)


func _broadcast_message(message: String) -> void:
	if local_coop:
		toast_requested.emit(message)
	else:
		announce.rpc(message)


func _notify_peer(peer_id: int, message: String) -> void:
	if local_coop or peer_id == local_peer_id:
		toast_requested.emit(message)
	else:
		announce.rpc_id(peer_id, message)


func _send_local_input() -> void:
	var movement := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var aim := _get_aim_direction()
	var attacking := Input.is_action_pressed("attack")
	if is_host:
		if players.has(local_peer_id):
			players[local_peer_id].input = {"move": movement, "aim": aim, "attack": attacking}
		if local_coop and players.has(local_second_peer_id):
			var second_movement := Input.get_vector("p2_move_left", "p2_move_right", "p2_move_up", "p2_move_down")
			var second_body_id: int = players[local_second_peer_id].body_id
			players[local_second_peer_id].input = {
				"move": second_movement,
				"aim": _get_auto_aim_direction(second_body_id),
				"attack": Input.is_action_pressed("p2_attack")
			}
	else:
		submit_input.rpc_id(SERVER_PEER_ID, movement, aim, attacking)


func _get_auto_aim_direction(body_id: int) -> Vector2:
	if not bodies.has(body_id):
		return Vector2.LEFT
	var origin: Vector3 = bodies[body_id].position
	var closest_position := origin + Vector3.LEFT
	var closest_distance := INF
	for enemy in enemies.values():
		var current_distance: float = origin.distance_squared_to(enemy.position)
		if current_distance < closest_distance:
			closest_distance = current_distance
			closest_position = enemy.position
	return Vector2(closest_position.x - origin.x, closest_position.z - origin.z).normalized()


func _get_aim_direction() -> Vector2:
	if not camera:
		return Vector2.RIGHT
	var mouse := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var direction := camera.project_ray_normal(mouse)
	if abs(direction.y) < 0.001:
		return Vector2.RIGHT
	var distance_to_floor := -origin.y / direction.y
	var floor_point := origin + direction * distance_to_floor
	var body := _find_latest_local_body()
	if body.is_empty():
		return Vector2.RIGHT
	var body_position: Vector3 = body.position
	return Vector2(floor_point.x - body_position.x, floor_point.z - body_position.z).normalized()


func _add_player(peer_id: int, player_name: String) -> void:
	var safe_name := player_name if not player_name.is_empty() else "Slime"
	var color: Color = PLAYER_COLORS[players.size() % PLAYER_COLORS.size()]
	players[peer_id] = {
		"id": peer_id,
		"name": safe_name,
		"color": color,
		"body_id": 0,
		"score": 0,
		"kills": 0,
		"merge_until": 0,
		"next_shot": 0,
		"input": {"move": Vector2.ZERO, "aim": Vector2.RIGHT, "attack": false}
	}
	_create_solo_body(peer_id, _random_open_point(1.0))


func _create_solo_body(peer_id: int, position: Vector3) -> Dictionary:
	var body_id := _uid()
	var body := {
		"id": body_id,
		"members": [peer_id],
		"position": position,
		"health": 100.0,
		"max_health": 100.0,
		"radius": 0.9,
		"speed": 7.2,
		"damage": 22.0,
		"color": players[peer_id].color,
		"invulnerable_until": Time.get_ticks_msec() + 1500,
		"hit_until": 0
	}
	bodies[body_id] = body
	players[peer_id].body_id = body_id
	return body


func _recalculate_body(body: Dictionary, health_ratio := -1.0) -> void:
	if health_ratio < 0.0:
		health_ratio = body.health / maxf(1.0, body.max_health)
	var count: int = body.members.size()
	body.radius = 0.9 + (count - 1) * 0.28
	body.max_health = 100.0 + (count - 1) * 85.0
	body.health = clampf(body.max_health * health_ratio, 1.0, body.max_health)
	body.speed = maxf(4.7, 7.2 - (count - 1) * 0.38)
	body.damage = 22.0 + (count - 1) * 15.0
	body.color = _blend_member_colors(body.members)


func _blend_member_colors(members: Array) -> Color:
	var total := Color(0, 0, 0, 1)
	for member_id in members:
		if players.has(member_id):
			total.r += players[member_id].color.r
			total.g += players[member_id].color.g
			total.b += players[member_id].color.b
	var divisor := maxf(1.0, float(members.size()))
	return Color(total.r / divisor, total.g / divisor, total.b / divisor, 1)


func _offer_fusion_for(peer_id: int) -> void:
	if not players.has(peer_id):
		return
	players[peer_id].merge_until = Time.get_ticks_msec() + 2400
	var control_hint := "E" if peer_id == local_peer_id else "N"
	_notify_peer(peer_id, "%s offered fusion. The other slime must also use its fuse key." % control_hint)


func _split_for(peer_id: int) -> void:
	if not players.has(peer_id):
		return
	var body_id: int = players[peer_id].body_id
	if bodies.has(body_id) and bodies[body_id].members.size() > 1:
		_split_body(body_id, "%s released the fusion." % players[peer_id].name)


func _merge_bodies(first_id: int, second_id: int) -> void:
	if not bodies.has(first_id) or not bodies.has(second_id) or first_id == second_id:
		return
	var first: Dictionary = bodies[first_id]
	var second: Dictionary = bodies[second_id]
	if first.members.size() + second.members.size() > MAX_FUSION:
		return
	var total_count: float = first.members.size() + second.members.size()
	var ratio := (first.health + second.health) / (first.max_health + second.max_health)
	first.position = (first.position * first.members.size() + second.position * second.members.size()) / total_count
	first.members.append_array(second.members)
	for member_id in second.members:
		players[member_id].body_id = first_id
	for member_id in first.members:
		players[member_id].merge_until = 0
	_recalculate_body(first, ratio)
	first.invulnerable_until = Time.get_ticks_msec() + 800
	bodies.erase(second_id)
	_broadcast_message("Fusion complete: %d minds, one slime!" % first.members.size())


func _split_body(body_id: int, message: String) -> void:
	if not bodies.has(body_id):
		return
	var old_body: Dictionary = bodies[body_id]
	var members: Array = old_body.members.duplicate()
	var origin: Vector3 = old_body.position
	bodies.erase(body_id)
	for index in members.size():
		var angle := TAU * float(index) / members.size()
		var proposed := origin + Vector3(cos(angle), 0, sin(angle)) * (1.8 + members.size() * 0.15)
		if not _can_occupy(proposed, 0.9):
			proposed = _random_open_point(1.0)
		_create_solo_body(members[index], proposed)
	_broadcast_message(message)


func _update_host_simulation(delta: float) -> void:
	var now := Time.get_ticks_msec()
	_update_bodies(delta, now)
	_update_bullets(delta, now)
	_update_enemies(delta, now)
	_update_cores()
	_check_fusions(now)
	_check_portal()


func _update_bodies(delta: float, now: int) -> void:
	for body_id in bodies.keys():
		if not bodies.has(body_id):
			continue
		var body: Dictionary = bodies[body_id]
		var movement := Vector2.ZERO
		var contributors := 0
		for member_id in body.members:
			if not players.has(member_id):
				continue
			var player: Dictionary = players[member_id]
			movement += player.input.move
			contributors += 1
			if player.input.attack and now >= player.next_shot:
				_fire_bullet(player, body, now)
		if contributors > 0 and movement.length_squared() > 0.01:
			movement = movement.normalized()
			_move_entity(body, Vector3(movement.x, 0, movement.y) * body.speed * delta)


func _check_fusions(now: int) -> void:
	var ids: Array = bodies.keys()
	for first_index in ids.size():
		for second_index in range(first_index + 1, ids.size()):
			var first_id: int = ids[first_index]
			var second_id: int = ids[second_index]
			if not bodies.has(first_id) or not bodies.has(second_id):
				continue
			var first: Dictionary = bodies[first_id]
			var second: Dictionary = bodies[second_id]
			var first_ready := _body_has_offer(first, now)
			var second_ready := _body_has_offer(second, now)
			var merge_distance: float = first.radius + second.radius + 1.7
			if first_ready and second_ready and first.position.distance_to(second.position) <= merge_distance:
				_merge_bodies(first_id, second_id)


func _body_has_offer(body: Dictionary, now: int) -> bool:
	for member_id in body.members:
		if players.has(member_id) and players[member_id].merge_until > now:
			return true
	return false


func _fire_bullet(player: Dictionary, body: Dictionary, now: int) -> void:
	var cooldown := maxi(240, 480 - body.members.size() * 38)
	player.next_shot = now + cooldown
	var aim: Vector2 = player.input.aim
	var direction := Vector3(aim.x, 0, aim.y).normalized()
	var bullet_id := _uid()
	bullets[bullet_id] = {
		"id": bullet_id,
		"owner_id": player.id,
		"position": body.position + direction * (body.radius + 0.35) + Vector3.UP * 0.35,
		"velocity": direction * 17.0,
		"radius": 0.2 + minf(0.16, body.members.size() * 0.025),
		"damage": body.damage,
		"color": player.color,
		"expires": now + 1300
	}


func _update_bullets(delta: float, now: int) -> void:
	for bullet_id in bullets.keys():
		if not bullets.has(bullet_id):
			continue
		var bullet: Dictionary = bullets[bullet_id]
		bullet.position += bullet.velocity * delta
		if now >= bullet.expires or not _can_occupy(bullet.position, bullet.radius):
			bullets.erase(bullet_id)
			continue
		for enemy_id in enemies.keys():
			if not enemies.has(enemy_id):
				continue
			var enemy: Dictionary = enemies[enemy_id]
			if bullet.position.distance_to(enemy.position) <= bullet.radius + enemy.radius:
				enemy.health -= bullet.damage
				enemy.hit_until = now + 100
				bullets.erase(bullet_id)
				if enemy.health <= 0.0:
					_defeat_enemy(enemy_id, bullet.owner_id)
				break


func _spawn_enemy(brute := false) -> void:
	var enemy_id := _uid()
	var radius := 1.05 if brute else 0.68
	enemies[enemy_id] = {
		"id": enemy_id,
		"kind": "brute" if brute else "crawler",
		"position": _random_open_point(radius),
		"radius": radius,
		"health": 115.0 if brute else 48.0,
		"max_health": 115.0 if brute else 48.0,
		"speed": 2.3 if brute else 3.5,
		"damage": 22.0 if brute else 11.0,
		"next_attack": 0,
		"hit_until": 0
	}


func _update_enemies(delta: float, now: int) -> void:
	for enemy_id in enemies.keys():
		if not enemies.has(enemy_id):
			continue
		var enemy: Dictionary = enemies[enemy_id]
		var target: Dictionary = {}
		var closest := INF
		for body in bodies.values():
			var distance := enemy.position.distance_to(body.position)
			if distance < closest:
				closest = distance
				target = body
		if target.is_empty():
			continue
		if closest < 15.0:
			var direction: Vector3 = (target.position - enemy.position).normalized()
			_move_entity(enemy, Vector3(direction.x, 0, direction.z) * enemy.speed * delta)
		if closest <= enemy.radius + target.radius + 0.18 and now >= enemy.next_attack:
			enemy.next_attack = now + (1000 if enemy.kind == "brute" else 720)
			_hurt_body(target.id, enemy.damage, now)


func _hurt_body(body_id: int, damage: float, now: int) -> void:
	if not bodies.has(body_id):
		return
	var body: Dictionary = bodies[body_id]
	if now < body.invulnerable_until:
		return
	body.health -= damage
	body.hit_until = now + 140
	body.invulnerable_until = now + 420
	if body.health > 0.0:
		return
	if body.members.size() > 1:
		_split_body(body_id, "The fusion burst! Reform and regroup.")
	else:
		body.position = _random_open_point(body.radius)
		body.health = body.max_health
		body.invulnerable_until = now + 2200
		_notify_peer(body.members[0], "You reformed deeper in the dungeon.")


func _defeat_enemy(enemy_id: int, owner_id: int) -> void:
	if not enemies.has(enemy_id):
		return
	var enemy: Dictionary = enemies[enemy_id]
	var core_id := _uid()
	cores[core_id] = {
		"id": core_id,
		"position": enemy.position,
		"value": 3 if enemy.kind == "brute" else 1
	}
	enemies.erase(enemy_id)
	if players.has(owner_id):
		players[owner_id].kills += 1
	if enemies.is_empty():
		portal_open = true
		_broadcast_message("The heart gate is open. Reach the green portal!")


func _update_cores() -> void:
	for core_id in cores.keys():
		if not cores.has(core_id):
			continue
		var core: Dictionary = cores[core_id]
		for body in bodies.values():
			if core.position.distance_to(body.position) <= body.radius + 0.55:
				for member_id in body.members:
					if players.has(member_id):
						players[member_id].score += core.value
				body.health = minf(body.max_health, body.health + core.value * 4.0)
				cores.erase(core_id)
				break


func _check_portal() -> void:
	if not portal_open:
		return
	var portal_position := Vector3(32, 0, 0)
	for body in bodies.values():
		if body.position.distance_to(portal_position) <= body.radius + 1.6:
			floor_number += 1
			_reset_floor()
			_broadcast_message("Floor %d writhes awake." % floor_number)
			return


func _reset_floor() -> void:
	enemies.clear()
	bullets.clear()
	cores.clear()
	portal_open = false
	var enemy_count := mini(34, 10 + floor_number * 2)
	for index in enemy_count:
		_spawn_enemy(index % 5 == 0)
	for body in bodies.values():
		body.position = _random_open_point(body.radius)
		body.health = body.max_health
		body.invulnerable_until = Time.get_ticks_msec() + 1800


func _on_peer_disconnected(peer_id: int) -> void:
	if not is_host or not players.has(peer_id):
		return
	var player: Dictionary = players[peer_id]
	var body_id: int = player.body_id
	players.erase(peer_id)
	if bodies.has(body_id):
		var body: Dictionary = bodies[body_id]
		body.members.erase(peer_id)
		if body.members.is_empty():
			bodies.erase(body_id)
		else:
			_recalculate_body(body)
	_broadcast_message("%s dissolved away." % player.name)


func _move_entity(entity: Dictionary, displacement: Vector3) -> void:
	var next := entity.position
	next.x += displacement.x
	if _can_occupy(next, entity.radius):
		entity.position.x = next.x
	next = entity.position
	next.z += displacement.z
	if _can_occupy(next, entity.radius):
		entity.position.z = next.z


func _can_occupy(position: Vector3, radius: float) -> bool:
	if absf(position.x) + radius > WORLD_HALF.x or absf(position.z) + radius > WORLD_HALF.y:
		return false
	var point := Vector2(position.x, position.z)
	for wall in walls:
		var nearest := Vector2(
			clampf(point.x, wall.position.x, wall.end.x),
			clampf(point.y, wall.position.y, wall.end.y)
		)
		if point.distance_to(nearest) < radius:
			return false
	return true


func _random_open_point(radius: float) -> Vector3:
	for attempt in 100:
		var point := Vector3(randf_range(-33, 33), 0, randf_range(-21, 21))
		if _can_occupy(point, radius):
			return point
	return Vector3(-32, 0, -19)


func _uid() -> int:
	var result := next_entity_id
	next_entity_id += 1
	return result


func _make_snapshot() -> Dictionary:
	var player_array: Array = []
	for player in players.values():
		player_array.append({
			"id": player.id, "name": player.name, "color": player.color,
			"body_id": player.body_id, "score": player.score, "kills": player.kills
		})
	var body_array: Array = []
	for body in bodies.values():
		body_array.append({
			"id": body.id, "members": body.members, "position": body.position,
			"health": body.health, "max_health": body.max_health, "radius": body.radius,
			"damage": body.damage, "color": body.color, "hit_until": body.hit_until
		})
	var enemy_array: Array = []
	for enemy in enemies.values():
		enemy_array.append({
			"id": enemy.id, "kind": enemy.kind, "position": enemy.position,
			"radius": enemy.radius, "health": enemy.health,
			"max_health": enemy.max_health, "hit_until": enemy.hit_until
		})
	var bullet_array: Array = []
	for bullet in bullets.values():
		bullet_array.append({
			"id": bullet.id, "position": bullet.position,
			"radius": bullet.radius, "color": bullet.color
		})
	var core_array: Array = []
	for core in cores.values():
		core_array.append({"id": core.id, "position": core.position, "value": core.value})
	return {
		"players": player_array, "bodies": body_array, "enemies": enemy_array,
		"bullets": bullet_array, "cores": core_array,
		"floor": floor_number, "portal_open": portal_open
	}


func _apply_snapshot(state: Dictionary) -> void:
	latest_players = state.players
	latest_bodies = state.bodies
	latest_enemies = state.enemies
	latest_bullets = state.bullets
	latest_cores = state.cores
	floor_number = state.floor
	portal_open = state.portal_open
	var local_body := _find_latest_local_body()
	if not local_body.is_empty():
		local_stats_changed.emit(
			local_body.health, local_body.max_health, local_body.members.size(),
			local_body.damage, latest_enemies.size(), floor_number, portal_open
		)
	var roster := latest_players.duplicate()
	roster.sort_custom(func(a, b): return a.score > b.score)
	roster_changed.emit(roster)


func _find_latest_local_body() -> Dictionary:
	for body in latest_bodies:
		if local_peer_id in body.members:
			return body
	return {}


func _build_dungeon() -> void:
	var geometry_parent := get_node_or_null("GeneratedGeometry") as Node3D
	if geometry_parent == null:
		geometry_parent = self
	for wall in walls:
		var wall_mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(wall.size.x, 2.8, wall.size.y)
		wall_mesh.mesh = box
		wall_mesh.position = Vector3(wall.position.x + wall.size.x / 2.0, 1.4, wall.position.y + wall.size.y / 2.0)
		wall_mesh.material_override = _material(Color("2c3b42"), 0.82)
		geometry_parent.add_child(wall_mesh)

	for x in range(-32, 33, 4):
		for z in range(-20, 21, 4):
			if (x * 7 + z * 11) % 5 != 0:
				continue
			var tile := MeshInstance3D.new()
			var tile_mesh := BoxMesh.new()
			tile_mesh.size = Vector3(0.12, 0.02, 0.8)
			tile.mesh = tile_mesh
			tile.position = Vector3(x, -0.1, z)
			tile.rotation.y = (x + z) * 0.13
			tile.material_override = _material(Color(0.25, 0.48, 0.38, 0.2), 1.0)
			geometry_parent.add_child(tile)

	portal_visual = _create_portal()
	portal_visual.position = Vector3(32, 0.1, 0)
	portal_visual.visible = false
	add_child(portal_visual)

	aim_marker = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.23
	ring.outer_radius = 0.3
	ring.rings = 12
	ring.ring_segments = 20
	aim_marker.mesh = ring
	aim_marker.material_override = _material(Color("d9ffe5"), 0.45)
	add_child(aim_marker)


func _create_portal() -> Node3D:
	var root := Node3D.new()
	for index in 2:
		var ring_mesh := MeshInstance3D.new()
		var ring := TorusMesh.new()
		ring.inner_radius = 1.05 + index * 0.16
		ring.outer_radius = 1.2 + index * 0.16
		ring.rings = 18
		ring.ring_segments = 32
		ring_mesh.mesh = ring
		ring_mesh.rotation_degrees.x = 90
		ring_mesh.position.y = 1.35
		ring_mesh.material_override = _material(Color("72ef9b") if index == 0 else Color("b7ffca"), 0.28)
		root.add_child(ring_mesh)
	var glow := OmniLight3D.new()
	glow.light_color = Color("72ef9b")
	glow.light_energy = 3.0
	glow.omni_range = 7.0
	glow.position.y = 1.2
	root.add_child(glow)
	return root


func _sync_visuals(delta: float) -> void:
	_sync_collection(latest_bodies, body_visuals, _create_body_visual)
	_sync_collection(latest_enemies, enemy_visuals, _create_enemy_visual)
	_sync_collection(latest_bullets, bullet_visuals, _create_bullet_visual)
	_sync_collection(latest_cores, core_visuals, _create_core_visual)

	for body in latest_bodies:
		var visual: Node3D = body_visuals[body.id]
		visual.position = visual.position.lerp(body.position, minf(1.0, delta * 16.0))
		var scale_factor: float = body.radius / 0.9
		visual.scale = visual.scale.lerp(Vector3(scale_factor, scale_factor, scale_factor), minf(1.0, delta * 9.0))
		var mesh: MeshInstance3D = visual.get_node("Body")
		mesh.material_override.albedo_color = Color.WHITE if body.hit_until > Time.get_ticks_msec() else body.color
		var eye_count := mini(3, body.members.size())
		for index in 3:
			visual.get_node("Eye%d" % index).visible = index < eye_count

	for enemy in latest_enemies:
		var visual: Node3D = enemy_visuals[enemy.id]
		visual.position = visual.position.lerp(enemy.position, minf(1.0, delta * 14.0))
		var mesh: MeshInstance3D = visual.get_node("Body")
		mesh.material_override.albedo_color = Color.WHITE if enemy.hit_until > Time.get_ticks_msec() else (Color("ce657b") if enemy.kind == "brute" else Color("8a6fe8"))
		var bar: MeshInstance3D = visual.get_node("Health/Fill")
		bar.scale.x = maxf(0.001, enemy.health / enemy.max_health)

	for bullet in latest_bullets:
		var visual: Node3D = bullet_visuals[bullet.id]
		visual.position = visual.position.lerp(bullet.position, minf(1.0, delta * 25.0))
		visual.scale = Vector3.ONE * bullet.radius / 0.22

	for core in latest_cores:
		var visual: Node3D = core_visuals[core.id]
		visual.position = core.position + Vector3.UP * (0.55 + sin(Time.get_ticks_msec() * 0.004 + core.id) * 0.15)
		visual.rotate_y(delta * 2.5)


func _sync_collection(entries: Array, visuals: Dictionary, factory: Callable) -> void:
	var present := {}
	for entry in entries:
		present[entry.id] = true
		if not visuals.has(entry.id):
			var visual: Node3D = factory.call(entry)
			visual.position = entry.position
			visuals[entry.id] = visual
			add_child(visual)
	for entity_id in visuals.keys():
		if not present.has(entity_id):
			visuals[entity_id].queue_free()
			visuals.erase(entity_id)


func _create_body_visual(body: Dictionary) -> Node3D:
	var root := Node3D.new()
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Body"
	var sphere := SphereMesh.new()
	sphere.radius = 0.9
	sphere.height = 1.5
	sphere.radial_segments = 24
	sphere.rings = 12
	mesh_instance.mesh = sphere
	mesh_instance.position.y = 0.65
	mesh_instance.scale = Vector3(1.0, 0.86, 1.0)
	mesh_instance.material_override = _material(body.color, 0.28)
	root.add_child(mesh_instance)
	for index in 3:
		var eye := MeshInstance3D.new()
		eye.name = "Eye%d" % index
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.1
		eye_mesh.height = 0.2
		eye.mesh = eye_mesh
		eye.position = Vector3((index - 1) * 0.28, 0.78, -0.76)
		eye.material_override = _material(Color("122019"), 0.6)
		eye.visible = index < mini(3, body.members.size())
		root.add_child(eye)
	return root


func _create_enemy_visual(enemy: Dictionary) -> Node3D:
	var root := Node3D.new()
	var body_mesh := MeshInstance3D.new()
	body_mesh.name = "Body"
	if enemy.kind == "brute":
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.8
		capsule.height = 1.8
		body_mesh.mesh = capsule
	else:
		var sphere := SphereMesh.new()
		sphere.radius = 0.68
		sphere.height = 1.2
		body_mesh.mesh = sphere
	body_mesh.position.y = enemy.radius * 0.8
	body_mesh.material_override = _material(Color("ce657b") if enemy.kind == "brute" else Color("8a6fe8"), 0.62)
	root.add_child(body_mesh)

	for side in [-1, 1]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.09
		eye_mesh.height = 0.18
		eye.mesh = eye_mesh
		eye.position = Vector3(side * enemy.radius * 0.3, enemy.radius * 0.9, -enemy.radius * 0.78)
		eye.material_override = _material(Color("110d18"), 0.7)
		root.add_child(eye)

	var health := Node3D.new()
	health.name = "Health"
	health.position = Vector3(0, enemy.radius * 2.0 + 0.35, 0)
	root.add_child(health)
	var backing := MeshInstance3D.new()
	var backing_mesh := BoxMesh.new()
	backing_mesh.size = Vector3(1.3, 0.12, 0.05)
	backing.mesh = backing_mesh
	backing.material_override = _material(Color("21131a"), 1.0)
	health.add_child(backing)
	var fill := MeshInstance3D.new()
	fill.name = "Fill"
	var fill_mesh := BoxMesh.new()
	fill_mesh.size = Vector3(1.22, 0.08, 0.06)
	fill.mesh = fill_mesh
	fill.position.z = -0.04
	fill.material_override = _material(Color("ff718e"), 0.75)
	health.add_child(fill)
	return root


func _create_bullet_visual(bullet: Dictionary) -> Node3D:
	var root := Node3D.new()
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.22
	sphere.height = 0.44
	mesh.mesh = sphere
	mesh.material_override = _material(bullet.color, 0.2)
	root.add_child(mesh)
	var light := OmniLight3D.new()
	light.light_color = bullet.color
	light.light_energy = 1.0
	light.omni_range = 2.0
	root.add_child(light)
	return root


func _create_core_visual(_core: Dictionary) -> Node3D:
	var root := Node3D.new()
	var mesh := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(0.38, 0.62, 0.38)
	mesh.mesh = prism
	mesh.material_override = _material(Color("ffd66d"), 0.22)
	root.add_child(mesh)
	var light := OmniLight3D.new()
	light.light_color = Color("ffd66d")
	light.light_energy = 1.2
	light.omni_range = 2.5
	root.add_child(light)
	return root


func _update_camera(delta: float) -> void:
	var body := _find_latest_local_body()
	if body.is_empty():
		return
	var target: Vector3 = body.position
	var spread := 0.0
	if local_coop:
		for candidate in latest_bodies:
			if local_second_peer_id in candidate.members:
				if candidate.id != body.id:
					spread = body.position.distance_to(candidate.position)
					target = (body.position + candidate.position) * 0.5
				break
	var desired := target + Vector3(0, 15.5 + spread * 0.42, 12.5 + spread * 0.22)
	camera.position = camera.position.lerp(desired, minf(1.0, delta * 6.5))
	camera.look_at(target + Vector3.UP * 0.35)


func _update_aim_marker() -> void:
	var body := _find_latest_local_body()
	if body.is_empty():
		aim_marker.visible = false
		return
	aim_marker.visible = true
	var aim := _get_aim_direction()
	aim_marker.position = body.position + Vector3(aim.x, 0.08, aim.y) * (body.radius + 1.0)


func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material
