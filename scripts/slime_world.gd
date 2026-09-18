extends Node3D
## Host-authoritative simulation. Local co-op uses the same simulation, without RPCs.
signal toast_requested(message: String)
signal local_stats_changed(health: float, max_health: float, member_count: int, power: float, enemies_left: int, floor_number: int, portal_open: bool)
signal roster_changed(roster: Array)
signal encounter_changed(info: Dictionary)

const COLORS = [Color("#72ef9b"), Color("#65d5ff"), Color("#ff8fd8"), Color("#ffd66d"), Color("#b79cff"), Color("#ff9875")]
const ELEMENTS = {"Ember": Color("#ff9454"), "Frost": Color("#75e1ff"), "Storm": Color("#c5a1ff")}
const terrain = preload("res://scripts/outdoor_level.gd")
const CameraRig = preload("res://scripts/exploration_camera.gd")
const ROOMS = ["TRAILHEAD", "WHISPERING GROVE", "SUNLIT RIDGE", "WARDEN SUMMIT"]
const CENTERS = [48.0, 12.0, -28.0, -68.0]
const PORTAL = Vector3(0, 8.4, -89)
var camera_rig: Node
var cleared = [true, false, false, false]
var party_level = 1
var party_xp = 0
var xp_claims: Dictionary = {}
var snapshot_frames: Array = []
var is_host = false
var local_coop = false
var local_peer_id = 1
var clock = 0.0
var stage = 0
var victory = false
var complete = false
var next_id = 1
var boss_id = 0
var snapshot_timer = 0.0
var input_timer = 0.0
var attack_step = 0
var checkpoint_pending = false
var players: Dictionary = {}
var bodies: Dictionary = {}
var enemies: Dictionary = {}
var trails: Dictionary = {}
var pickups: Dictionary = {}
var shots: Dictionary = {}
var hazards: Dictionary = {}
var visuals: Dictionary = {}
var room_labels: Array[Label3D] = []
var state: Dictionary = {}
var walls: Array[Rect2] = []
var gates: Array[Node3D] = []
var camera: Camera3D
var actors: Node3D
var portal: Node3D
var aim_marker: Node3D

func _ready() -> void:
	camera = $MainCamera
	actors = $Actors
	camera.position = Vector3(0, 24, 54)
	camera.look_at(Vector3(0, 0, 36))
	camera.make_current()
	_build_level()
	camera_rig = CameraRig.new()
	add_child(camera_rig)
	camera_rig.setup(self)
	multiplayer.peer_disconnected.connect(_leave)

func setup_host(player_name: String) -> void:
	is_host = true
	_start()
	_add_player(1, player_name)
	_apply(_snapshot())

func setup_client(player_name: String) -> void:
	local_peer_id = multiplayer.get_unique_id()
	register_player.rpc_id(1, player_name)

func setup_local_coop(first_name: String, second_name: String) -> void:
	is_host = true
	local_coop = true
	_start()
	_add_player(1, first_name)
	_add_player(2, second_name)
	_apply(_snapshot())

func _start() -> void:
	for room in 4:
		for i in 3:
			var key = ELEMENTS.keys()[i]
			var id = _id()
			pickups[id] = {"id": id, "position": terrain.ground(terrain.LANDMARKS[room] + Vector3(-5 + i * 5, 0, 5)),
				"element": key, "ready": 0.0, "room": room}
	for i in 3:
		var id = _id()
		var cache_pos = [Vector3(-34, 0, 30), Vector3(36, 0, -3), Vector3(-30, 0, -48)][i]
		pickups[id] = {"id": id, "position": terrain.ground(cache_pos),
			"element": ELEMENTS.keys()[i], "ready": 0.0, "room": -1}

func _id() -> int:
	var id = next_id
	next_id += 1
	return id

func _add_player(peer_id: int, player_name: String) -> void:
	if players.size() >= 6 or players.has(peer_id):
		return
	players[peer_id] = {"id": peer_id, "name": player_name.left(18), "color": COLORS[players.size() % 6],
		"body_id": 0, "score": 0, "element": "", "offer": 0.0, "last_input": clock,
		"move": Vector2.ZERO, "aim": Vector2.UP, "attack": false, "sprint": false, "shot": 0.0}
	_solo(peer_id, Vector3(-2 + players.size() * 1.7, 0, CENTERS[stage] + 8), 1.0)

func _solo(peer_id: int, pos: Vector3, ratio: float) -> void:
	pos.y = maxf(pos.y, terrain.elevation(pos))
	var id = _id()
	bodies[id] = {"id": id, "members": [peer_id], "position": pos, "radius": 0.7,
		"health": maxf(1, _member_health() * ratio), "max_health": _member_health(), "color": players[peer_id].color,
		"velocity": Vector3.ZERO, "sprinting": false, "vertical_speed": 0.0, "next_trail": 0.0, "invulnerable": clock + 1.5, "swing": 0.0, "facing": Vector2.UP}
	players[peer_id].body_id = id

@rpc("any_peer", "call_remote", "reliable")
func register_player(player_name: String) -> void:
	if is_host:
		_add_player(multiplayer.get_remote_sender_id(), player_name.strip_edges())

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func submit_input(move: Vector2, aim: Vector2, attack: bool, sprint: bool = false) -> void:
	if is_host and move.is_finite() and aim.is_finite():
		_set_input(multiplayer.get_remote_sender_id(), move, aim, attack, sprint)

@rpc("any_peer", "call_remote", "reliable")
func action(kind: String) -> void:
	if is_host:
		_action(multiplayer.get_remote_sender_id(), kind)

@rpc("authority", "call_remote", "reliable", 2)
func receive_snapshot(data: Dictionary) -> void:
	snapshot_frames.append({"time": Time.get_ticks_msec() / 1000.0, "bodies": data.bodies, "enemies": data.enemies})
	while snapshot_frames.size() > 8: snapshot_frames.pop_front()
	_apply(data)

@rpc("authority", "call_local", "reliable")
func announce(message: String) -> void:
	toast_requested.emit(message)

func _message(message: String) -> void:
	if local_coop:
		announce(message)
	else:
		announce.rpc(message)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo:
		return
	for kind in ["fuse", "split", "collect", "jump"]:
		if event.is_action_pressed(kind):
			if is_host:
				_action(local_peer_id, kind)
			else:
				action.rpc_id(1, kind)
		if local_coop and event.is_action_pressed("p2_" + kind):
			_action(2, kind)
	if is_host and event.is_action_pressed("restart_run"):
		_restart()

func _action(peer_id: int, kind: String) -> void:
	if not players.has(peer_id) or complete:
		return
	var p = players[peer_id]
	if not bodies.has(p.body_id):
		return
	var body = bodies[p.body_id]
	match kind:
		"jump":
			if body.position.y <= terrain.elevation(body.position) + 0.05:
				body.vertical_speed = 8.0
		"fuse":
			p.offer = clock + 3.0
		"split":
			if body.members.size() > 1:
				_split(body)
		"collect":
			if body.members.size() > 1:
				_message("Split first! Only solo slimes absorb power.")
				return
			for item in pickups.values():
				if item.ready <= clock and _distance(item, body) < 2.3:
					p.element = item.element
					if item.room == -1: _award_xp(35, "cache:%d" % item.id)
					item.ready = clock + 1.0
					_message("%s absorbed %s. Fuse to activate it!" % [p.name, p.element])
					break

func _set_input(peer_id: int, move: Vector2, aim: Vector2, attack: bool, sprint: bool = false) -> void:
	if players.has(peer_id):
		var p = players[peer_id]
		p.move = move.limit_length()
		p.aim = aim.normalized() if aim.length_squared() > 0.01 else Vector2.UP
		p.attack = attack
		p.sprint = sprint
		p.last_input = clock

func _read_inputs() -> void:
	var move = camera_rig.movement(Input.get_vector("move_left", "move_right", "move_up", "move_down"), 0)
	var aim = _mouse_aim()
	if is_host:
		_set_input(local_peer_id, move, aim, Input.is_action_pressed("attack"), Input.is_action_pressed("sprint"))
	else:
		submit_input.rpc_id(1, move, aim, Input.is_action_pressed("attack"), Input.is_action_pressed("sprint"))
	if local_coop and players.has(2):
		var move2 = camera_rig.movement(Input.get_vector("p2_move_left", "p2_move_right", "p2_move_up", "p2_move_down"), 1)
		var body = bodies[players[2].body_id]
		var target = _nearest(body.position, enemies)
		var aim2 = camera_rig.aim(1)
		if not target.is_empty() and target.position.distance_to(body.position) < 25:
			var d = target.position - body.position
			aim2 = Vector2(d.x, d.z).normalized()

		_set_input(2, move2, aim2, Input.is_action_pressed("p2_attack"), Input.is_action_pressed("p2_sprint"))

func _physics_process(delta: float) -> void:
	if not is_host and multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if players.is_empty() and is_host:
		return
	input_timer += delta
	if is_host or input_timer >= 0.033:
		input_timer = 0
		_read_inputs()
	if not is_host:
		return
	clock += delta
	if not complete:
		_simulate(delta)
	# Rendering follows every physics tick; network/HUD traffic remains at 10 Hz.
	state = _snapshot()
	snapshot_timer += delta
	if snapshot_timer >= 0.1:
		snapshot_timer = 0
		var data = state
		if not local_coop:
			receive_snapshot.rpc(data)
		_apply(data)

func _simulate(delta: float) -> void:
	for body in bodies.values():
		var move = Vector2.ZERO
		var moving_members = 0
		var sprinting_members = 0
		for member in body.members:
			var p = players[member]
			if clock - p.last_input > 0.3:
				continue
			move += p.move
			if p.move.length_squared() > 0.01:
				moving_members += 1
				if p.sprint: sprinting_members += 1
			body.facing = p.aim
			if p.attack and body.members.size() > 1 and clock >= p.shot:
				_attack(p, body)
		# Idle allies no longer halve speed; opposing active inputs still cancel.
		move /= float(maxi(1, moving_members))
		var sprinting = sprinting_members > 0 and move.length_squared() > 0.01
		body.sprinting = sprinting
		var speed = (9.0 if body.members.size() == 1 else 7.6) * (1.7 if sprinting else 1.0)
		var desired_velocity = Vector3(move.x, 0, move.y) * speed
		var acceleration = 80.0 if move.length_squared() < 0.01 else 60.0
		body.velocity = body.velocity.move_toward(desired_velocity, acceleration * delta)
		var before: Vector3 = body.position
		_move(body, body.velocity * delta)
		if is_equal_approx(body.position.x, before.x): body.velocity.x = 0.0
		if is_equal_approx(body.position.z, before.z): body.velocity.z = 0.0
		body.vertical_speed -= 22.0 * delta
		body.position.y += body.vertical_speed * delta
		var floor_y = terrain.elevation(body.position)
		if body.position.y <= floor_y:
			body.position.y = floor_y
			body.vertical_speed = 0.0
		if body.members.size() == 1 and clock >= body.next_trail and move.length() > 0.1 and body.position.y < floor_y + 0.1:
			body.next_trail = clock + 0.18
			var id = _id()
			trails[id] = {"id": id, "position": body.position, "color": body.color, "expires": clock + 7.0}
	while trails.size() > 180:
		trails.erase(trails.keys()[0])
	for id in trails.keys():
		if trails[id].expires < clock:
			trails.erase(id)
	_check_fusion()
	_update_shots(delta)
	_update_enemies(delta)
	_update_hazards(delta)
	_progress()

func _powers(body: Dictionary) -> Dictionary:
	var result = {}
	for id in body.members:
		var element = players[id].element
		if element != "":
			result[element] = result.get(element, 0) + 1
	return result

func _power_name(body: Dictionary) -> String:
	var p = _powers(body)
	if body.members.size() == 1:
		return "SOLO · %s dormant · slowing trail" % ("no power" if p.is_empty() else p.keys()[0])
	if p.size() >= 3:
		return "TEMPEST · burn + frost + chain"
	if p.has("Ember") and p.has("Frost"):
		return "FROSTFIRE · burning, slowing splash"
	if p.has("Ember") and p.has("Storm"):
		return "PLASMA · explosive chain lightning"
	if p.has("Frost") and p.has("Storm"):
		return "BLIZZARD · slowing chain lightning"
	if p.size() == 1:
		return "%s ×%d" % [p.keys()[0].to_upper(), p.values()[0]]
	return "FUSED · GEL FISTS"

func _attack(p: Dictionary, body: Dictionary) -> void:
	p.shot = clock + 0.65
	body.swing = clock + 0.22
	var powers = _powers(body)
	var damage = 14.0 + body.members.size() * 5.0
	var target = _nearest(body.position, enemies)
	if not target.is_empty() and _distance(body, target) <= body.radius + target.radius + 2.0:
		_hit(target.id, damage, powers)
	if not powers.is_empty():
		var id = _id()
		var aim = Vector3(p.aim.x, 0, p.aim.y)
		shots[id] = {"id": id, "position": body.position + aim * (body.radius + 0.35),
			"velocity": aim * 19, "damage": damage, "powers": powers,
			"expires": clock + 1.5, "color": ELEMENTS[powers.keys()[0]], "enemy": false}

func _hit(enemy_id: int, damage: float, powers: Dictionary) -> void:
	if not enemies.has(enemy_id):
		return
	var enemy = enemies[enemy_id]
	var level_multiplier = 1.0 + (party_level - 1) * 0.12
	var ember = powers.get("Ember", 0)
	var frost = powers.get("Frost", 0)
	var storm = powers.get("Storm", 0)
	# Elemental damage scales exactly linearly with matching carried powers.
	enemy.health -= (damage + 8 * (ember + frost + storm)) * level_multiplier
	enemy.flash = clock + 0.1
	if ember > 0:
		enemy.burn_until = clock + 3
		enemy.burn_damage = 6.0 * ember * level_multiplier
	if frost > 0:
		enemy.frost_until = clock + 2.0 * frost
	if storm > 0:
		var remaining = storm + 1
		for other in enemies.values():
			if other.id != enemy_id and _distance(enemy, other) < 7 and remaining > 0:
				other.health -= 14.0 * storm * level_multiplier
				other.flash = clock + 0.2
				if frost > 0:
					other.frost_until = clock + 2.0 * frost
				if ember > 0:
					other.burn_until = clock + 3
					other.burn_damage = 6.0 * ember * level_multiplier
				remaining -= 1
	if ember > 0 and powers.size() > 1:
		_effect(enemy.position, 3.0, Color("#ffc46c"), 0.22)
		for other in enemies.values():
			if other.id != enemy_id and _distance(enemy, other) < 3:
				other.health -= 12.0 * ember * level_multiplier
				if frost > 0:
					other.frost_until = clock + 2.0 * frost

func _update_shots(delta: float) -> void:
	for id in shots.keys():
		var s = shots[id]
		var next = s.position + s.velocity * delta
		next.y = terrain.elevation(next)
		if s.expires < clock or not _can_occupy(next, 0.2):
			shots.erase(id)
			continue
		s.position = next
		var targets = bodies if s.enemy else enemies
		for target in targets.values():
			if _distance(s, target) < target.radius + 0.3:
				if s.enemy:
					_hurt(target, 14)
				else:
					_hit(target.id, s.damage, s.powers)
				shots.erase(id)
				break

func _check_fusion() -> void:
	var ids = bodies.keys()
	for a in range(ids.size()):
		for b in range(a + 1, ids.size()):
			if not bodies.has(ids[a]) or not bodies.has(ids[b]):
				continue
			var first = bodies[ids[a]]
			var second = bodies[ids[b]]
			var members = first.members + second.members
			if members.size() > 6 or _distance(first, second) > first.radius + second.radius + 1.8:
				continue
			var consent = true
			for member in members:
				consent = consent and players[member].offer > clock
			var pos = (first.position + second.position) * 0.5
			var radius = 1.0 + members.size() * 0.13
			if not consent or not _can_occupy(pos, radius):
				continue
			var ratio = (first.health + second.health) / (first.max_health + second.max_health)
			first.members = members
			first.position = pos
			first.radius = radius
			first.velocity = (first.velocity + second.velocity) * 0.5
			first.max_health = _member_health() * members.size()
			first.health = first.max_health * ratio
			first.invulnerable = clock + 0.5
			for member in members:
				players[member].body_id = first.id
				players[member].offer = 0.0
			bodies.erase(second.id)
			_message("Limbs formed! " + _power_name(first))

func _split(body: Dictionary) -> void:
	var ratio = body.health / body.max_health
	var members = body.members.duplicate()
	bodies.erase(body.id)
	for i in members.size():
		var offset = Vector3(cos(TAU * i / members.size()), 0, sin(TAU * i / members.size())) * 1.7
		var pos = body.position + offset
		if not _can_occupy(pos, 0.7):
			pos = body.position
		_solo(members[i], pos, ratio)
		bodies[players[members[i]].body_id].velocity = body.velocity
	# No healing, recharge or replacement powers when splitting.

func _spawn_enemy(pos: Vector3, kind: String, reward_key: String = "") -> int:
	pos = terrain.ground(pos)
	var id = _id()
	var hp = 1400.0 if kind == "boss" else (110.0 if kind == "brute" else 65.0)
	enemies[id] = {"id": id, "position": pos, "kind": kind, "radius": 2.1 if kind == "boss" else 0.8,
		"health": hp, "max_health": hp, "reward_key": reward_key, "attack_at": clock + 2.0, "flash": 0.0,
		"burn_until": 0.0, "burn_damage": 0.0, "frost_until": 0.0, "slow": false, "enraged": false}
	return id

func _update_enemies(delta: float) -> void:
	for id in enemies.keys():
		if not enemies.has(id):
			continue
		var e = enemies[id]
		if e.burn_until > clock:
			e.health -= e.burn_damage * delta
		if e.health <= 0:
			if e.reward_key != "": _award_xp(250 if e.kind == "boss" else (45 if e.kind == "brute" else 25), e.reward_key)
			enemies.erase(id)
			for p in players.values():
				p.score += 1
			if id == boss_id:
				victory = true
				enemies.clear()
				hazards.clear()
				shots.clear()
				_message("The Moss Warden falls! Reach the heart gate together.")
			continue
		var target = _nearest(e.position, bodies)
		if target.is_empty():
			continue
		var slow = 1.0
		for trail in trails.values():
			if _distance(e, trail) < e.radius + 0.85:
				slow = 0.7 if e.kind == "boss" else 0.45
				break
		if e.frost_until > clock:
			slow = minf(slow, 0.7 if e.kind == "boss" else 0.45)
		e.slow = slow < 1.0
		var direction = (target.position - e.position).normalized()
		var speed = 1.45 if e.kind == "boss" else (2.5 if e.kind == "brute" else 3.1)
		if _distance(e, target) > e.radius + target.radius + 0.1:
			_move(e, direction * speed * slow * delta)
		if e.kind == "boss":
			_boss(e, target)
		elif clock >= e.attack_at and _distance(e, target) < e.radius + target.radius + 0.5:
			e.attack_at = clock + 1.0
			_hurt(target, 16 if e.kind == "brute" else 10)

func _boss(e: Dictionary, target: Dictionary) -> void:
	if e.health < e.max_health * 0.5 and not e.enraged:
		e.enraged = true
		_message("WARDEN ENRAGED · faster roots and wider slams!")
	if clock < e.attack_at:
		return
	e.attack_at = clock + (2.4 if e.enraged else 3.6)
	attack_step += 1
	match attack_step % 3:
		0:
			var id = _id()
			hazards[id] = {"id": id, "position": target.position, "radius": 4.0 if e.enraged else 3.2,
				"trigger": clock + 1.5, "expires": clock + 2.1, "kind": "slam", "fired": false}
		1:
			var id = _id()
			hazards[id] = {"id": id, "position": e.position, "radius": 3.0,
				"trigger": clock + 1.2, "expires": clock + 1.7, "kind": "volley", "fired": false}
		2:
			if enemies.size() < 7:
				for x in [-8, 8]:
					_spawn_enemy(Vector3(x, 0, -71), "crawler")
			var id = _id()
			hazards[id] = {"id": id, "position": e.position, "radius": 5.0,
				"trigger": clock + 1.6, "expires": clock + 2.1, "kind": "slam", "fired": false}

func _effect(pos: Vector3, radius: float, color: Color, duration: float) -> void:
	var id = _id()
	hazards[id] = {"id": id, "position": pos, "radius": radius, "trigger": clock,
		"expires": clock + duration, "kind": "effect", "fired": true, "color": color}

func _update_hazards(_delta: float) -> void:
	for id in hazards.keys():
		if not hazards.has(id):
			continue
		var h = hazards[id]
		if h.expires <= clock:
			hazards.erase(id)
			continue
		if not h.fired and clock >= h.trigger:
			h.fired = true
			if h.kind == "slam":
				for body in bodies.values():
					if _distance(h, body) < h.radius + body.radius and body.position.y < terrain.elevation(body.position) + 1.3:
						_hurt(body, 30)
			elif h.kind == "volley":
				for i in 12:
					var direction = Vector3(cos(TAU * i / 12), 0, sin(TAU * i / 12))
					var shot_id = _id()
					shots[shot_id] = {"id": shot_id, "position": h.position + direction * 2.5,
						"velocity": direction * 8, "expires": clock + 4.0, "enemy": true, "color": Color("#ff5e72")}

func _hurt(body: Dictionary, damage: float) -> void:
	if clock < body.invulnerable:
		return
	body.health -= damage
	body.invulnerable = clock + 0.5
	if body.health <= 0 and not checkpoint_pending:
		checkpoint_pending = true
		# Reset this encounter as a team; no lost progression or stranded solo fighter.
		call_deferred("_checkpoint")
		body.health = 1.0
		body.invulnerable = clock + 5

func _checkpoint() -> void:
	checkpoint_pending = false
	if bodies.is_empty():
		return
	_reset_party()
	_start_encounter()
	_message("Reformed at the last landmark. Your powers survived.")

func _reset_party() -> void:
	bodies.clear()
	trails.clear()
	shots.clear()
	hazards.clear()
	var i = 0
	for id in players:
		_solo(id, terrain.ground(terrain.LANDMARKS[stage] + Vector3(-2 + i * 1.8, 0, 8)), 1.0)
		players[id].offer = 0.0
		i += 1

func _restart() -> void:
	party_level = 1
	party_xp = 0
	xp_claims.clear()
	stage = 0
	cleared = [true, false, false, false]
	victory = false
	complete = false
	for p in players.values():
		p.element = ""
		p.score = 0
	_reset_party()
	_start_encounter()
	_message("A fresh descent begins.")

func _start_encounter() -> void:
	enemies.clear()
	attack_step = 0
	boss_id = 0
	if stage in [1, 2]:
		for i in (4 if stage == 1 else 6):
			_spawn_enemy(terrain.LANDMARKS[stage] + Vector3(-7 + (i % 3) * 7, 0, -3 - (i / 3) * 3),
				"brute" if stage == 2 and i % 2 == 0 else "crawler", "encounter:%d:%d" % [stage, i])
	elif stage == 3:
		boss_id = _spawn_enemy(terrain.LANDMARKS[3], "boss", "warden")

func _progress() -> void:
	if enemies.is_empty(): cleared[stage] = true
	if stage < 3 and cleared[stage]:
		for body in bodies.values():
			if body.members.size() >= 2 and body.position.distance_to(terrain.LANDMARKS[stage + 1]) < 11:
				stage += 1
				_award_xp(40, "landmark:%d" % stage)
				_start_encounter()
				_message(ROOMS[stage] + " · defend the landmark together!")
				return
	if victory:
		for body in bodies.values():
			if body.members.size() >= 2 and body.position.distance_to(PORTAL) < 4:
				complete = true
				_message("SUMMIT REACHED! Press R for another expedition.")
				break

func _leave(peer_id: int) -> void:
	if not is_host or not players.has(peer_id):
		return
	var body = bodies.get(players[peer_id].body_id, {})
	if not body.is_empty() and body.members.size() > 1:
		_split(body)
	if players.has(peer_id):
		bodies.erase(players[peer_id].body_id)
		players.erase(peer_id)

func _distance(a: Dictionary, b: Dictionary) -> float:
	return a.position.distance_to(b.position)

func _nearest(pos: Vector3, collection: Dictionary) -> Dictionary:
	var best = {}
	var distance = INF
	for value in collection.values():
		var d = pos.distance_squared_to(value.position)
		if d < distance:
			distance = d
			best = value
	return best

func _can_occupy(pos: Vector3, radius: float) -> bool:
	if absf(pos.x) + radius > 48 or pos.z - radius < -98 or pos.z + radius > 65:
		return false
	var point = Vector2(pos.x, pos.z)
	for rect in walls:
		var nearest = Vector2(clampf(point.x, rect.position.x, rect.end.x), clampf(point.y, rect.position.y, rect.end.y))
		if point.distance_to(nearest) < radius: return false
	return true

func _move(entity: Dictionary, amount: Vector3) -> void:
	var pos: Vector3 = entity.position
	var next = pos + Vector3(amount.x, 0, 0)
	if _can_occupy(next, entity.radius):
		pos.x = next.x
	next = pos + Vector3(0, 0, amount.z)
	if _can_occupy(next, entity.radius):
		pos.z = next.z
	if not entity.has("members"): pos.y = terrain.elevation(pos)
	entity.position = pos

func _snapshot() -> Dictionary:
	var roster = []
	for p in players.values():
		var body = bodies.get(p.body_id, {})
		roster.append({"id": p.id, "name": p.name, "color": p.color, "score": p.score, "element": p.element,
			"health": body.get("health", 0), "max_health": body.get("max_health", 70)})
	var body_array = []
	for b in bodies.values():
		var copy = b.duplicate(true)
		copy.power_name = _power_name(b)
		copy.powers = _powers(b)
		copy.offering = false
		for id in b.members:
			copy.offering = copy.offering or players[id].offer > clock
		body_array.append(copy)
	return {"clock": clock, "party_level": party_level, "party_xp": party_xp, "xp_needed": _xp_needed(), "stage": stage, "cleared": cleared, "victory": victory, "complete": complete, "players": roster,
		"bodies": body_array, "enemies": enemies.values().duplicate(true), "trails": trails.values().duplicate(true),
		"pickups": pickups.values().duplicate(true), "shots": shots.values().duplicate(true), "hazards": hazards.values().duplicate(true)}

func _apply(data: Dictionary) -> void:
	state = data
	var body = _local_body()
	if not body.is_empty():
		local_stats_changed.emit(body.health, body.max_health, body.members.size(), 0, data.enemies.size(), 1, data.victory)
	roster_changed.emit(data.players)
	var boss_health = 0.0
	var boss_max = 0.0
	for e in data.enemies:
		if e.kind == "boss":
			boss_health = e.health
			boss_max = e.max_health
	var objective = "Travel fused along the trail to " + ROOMS[mini(3, data.stage + 1)] + "."
	if data.stage == 0:
		objective = "Collect powers (F / L). Fuse near your ally (E + N). Follow the uphill trail."
	elif not data.enemies.is_empty():
		objective = "Defend this landmark · %d enemies remain." % data.enemies.size()
	if data.stage == 3 and not data.victory:
		objective = "Moss Warden · dodge red warnings; jump to evade ground slams."
	if data.victory: objective = "Reach the summit arch together."
	if data.complete: objective = "EXPEDITION COMPLETE · R: replay · Esc: menu"
	encounter_changed.emit({"title": ROOMS[data.stage], "objective": objective, "boss_health": boss_health,
		"boss_max": boss_max, "power": body.get("power_name", ""), "complete": data.complete, "party_level": data.party_level, "party_xp": data.party_xp, "xp_needed": data.xp_needed})

func _local_body() -> Dictionary:
	for body in state.get("bodies", []):
		if local_peer_id in body.members:
			return body
	return {}

func _mouse_aim() -> Vector2:
	return camera_rig.aim(0) if camera_rig != null else Vector2.UP

func _process(delta: float) -> void:
	if state.is_empty(): return
	_render_entities(delta)
	camera_rig.update(delta)
	camera = camera_rig.cameras[0]
	var body = _local_body()
	if not body.is_empty():
		aim_marker.position = terrain.ground(body.position + Vector3(_mouse_aim().x, 0, _mouse_aim().y) * 5) + Vector3(0, 0.06, 0)
		aim_marker.visible = body.members.size() > 1
	portal.visible = state.victory

# All visuals instantiate public CC0 assets; only their layout and transforms are authored.
var asset_cache: Dictionary = {}
var surface_cache: Dictionary = {}

func _style_asset(node: Node, nature: bool) -> void:
	# Engine material tuning of licensed models; no new textures or mesh artwork.
	var palette = {"grass": Color("718455"), "leafsDark": Color("3c5b48"),
		"leafs": Color("628553"), "leafsLight": Color("8f9d58"),
		"woodBarkDark": Color("564737"), "woodBark": Color("79624a"),
		"dirt": Color("88775f"), "stone": Color("737b78")}
	if node is MeshInstance3D:
		for i in node.mesh.get_surface_count():
			var original = node.mesh.surface_get_material(i)
			if original is StandardMaterial3D:
				var key = str(original.get_instance_id()) + str(nature)
				if not surface_cache.has(key):
					var mat = original.duplicate()
					mat.metallic = 0
					mat.roughness = 0.95
					if nature and palette.has(original.resource_name):
						mat.albedo_color = palette[original.resource_name]
					surface_cache[key] = mat
				node.set_surface_override_material(i, surface_cache[key])
	for child in node.get_children(): _style_asset(child, nature)

func _asset(parent: Node3D, path: String, pos: Vector3, size: Vector3) -> Node3D:
	if not asset_cache.has(path):
		asset_cache[path] = load("res://assets/" + path)
	var holder = Node3D.new()
	parent.add_child(holder)
	holder.position = pos
	var model = asset_cache[path].instantiate()
	holder.add_child(model)
	_style_asset(model, path.begins_with("nature/"))
	var bounds = _bounds(model, Transform3D.IDENTITY)
	var extent = bounds.size
	model.scale = Vector3.ONE * (size.y / maxf(0.001, extent.y)) if path.begins_with("quaternius/") else size / Vector3(maxf(0.001, extent.x), maxf(0.001, extent.y), maxf(0.001, extent.z))
	model.position = -Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z) * model.scale
	return holder

func _bounds(node: Node, transform: Transform3D) -> AABB:
	var result = AABB()
	if node is Node3D:
		transform = transform * node.transform
	if node is MeshInstance3D:
		result = transform * node.get_aabb()
	for child in node.get_children():
		var other = _bounds(child, transform)
		if other.size != Vector3.ZERO:
			result = other if result.size == Vector3.ZERO else result.merge(other)
	return result

func _decal(parent: Node3D, texture: String, radius: float, color: Color, height: float = 0.04) -> Sprite3D:
	var sprite = Sprite3D.new()
	sprite.texture = load("res://assets/particles/" + texture + ".png")
	sprite.pixel_size = radius * 2 / sprite.texture.get_width()
	sprite.rotation_degrees.x = -90
	sprite.position.y = height
	sprite.modulate = color
	sprite.shaded = false
	parent.add_child(sprite)
	return sprite

func _label3d(parent: Node3D, pos: Vector3, text: String, size: int = 32) -> Label3D:
	var label = Label3D.new()
	label.text = text
	label.font_size = size
	label.pixel_size = 0.012
	label.position = pos
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(label)
	return label

func _build_level() -> void:
	terrain.build(self)

func _animate(root: Node, action_name: String) -> void:
	var anim = root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim == null:
		return
	for name in anim.get_animation_list():
		if name.ends_with(action_name):
			if anim.current_animation != name or not anim.is_playing():
				anim.get_animation(name).loop_mode = Animation.LOOP_LINEAR
				anim.play(name, 0.12)
			return

func _render_entities(delta: float) -> void:
	var present = {}
	for kind in ["bodies", "enemies", "trails", "pickups", "shots", "hazards"]:
		for data in state[kind]:
			var key = kind + str(data.id)
			present[key] = true
			var signature = str(data.members.size()) if kind == "bodies" else ""
			if visuals.has(key) and visuals[key].get_meta("signature", "") != signature:
				visuals[key].queue_free()
				visuals.erase(key)
			if not visuals.has(key):
				var node = _make_visual(kind, data)
				node.set_meta("signature", signature)
				actors.add_child(node)
				node.position = data.position
				visuals[key] = node
			var visual: Node3D = visuals[key]
			var moving = visual.position.distance_to(data.position) > 0.025
			var render_pos = _sample_remote_position(kind, data)
			if not is_host and kind in ["bodies", "enemies"]:
				visual.position = render_pos
			else:
				visual.position = visual.position.lerp(render_pos, 1.0 - exp(-delta * 24))
			match kind:
				"bodies":
					var fused = data.members.size() > 1
					var face = data.facing
					visual.get_node("Model").rotation.y = lerp_angle(visual.get_node("Model").rotation.y, atan2(face.x, face.y), minf(1, delta * 8))
					visual.get_node("Name").text = ("FUSED  %d/%d" % [data.health, data.max_health]) if fused else "P%d" % data.members[0]
					visual.get_node("Offer").visible = data.offering
					visual.get_node("Power").text = ""
					_animate(visual, "Punch" if fused and data.swing > state.clock else ("Walk" if moving else "Idle"))
				"enemies":
					visual.get_node("Name").text = "SLOWED" if data.slow else ""
					_animate(visual, "Walk" if moving else "Idle")
				"pickups":
					visual.visible = data.ready <= state.clock
					visual.get_node("Crystal").rotation.y += delta * 1.7
				"trails":
					visual.scale = Vector3.ONE * clampf((data.expires - state.clock) / 2, 0.1, 1.0)
				"hazards":
					visual.get_child(0).modulate = Color("ffe18b") if data.fired else Color(1, 0.1, 0.15, 0.85)
	for key in visuals.keys():
		if not present.has(key):
			visuals[key].queue_free()
			visuals.erase(key)

func _make_visual(kind: String, data: Dictionary) -> Node3D:
	var root = Node3D.new()
	match kind:
		"bodies", "enemies":
			var is_body = kind == "bodies"
			var fused = is_body and data.members.size() > 1
			var boss = not is_body and data.kind == "boss"
			var model = "slime" if is_body else "crawler"
			if fused: model = "fusion"
			if boss or (not is_body and data.kind == "brute"): model = "warden"
			var height = 3.2 if fused else (5.0 if boss else 1.4)
			_asset(root, "quaternius/" + model + ".glb", Vector3.ZERO, Vector3(data.radius * 2, height, data.radius * 2)).name = "Model"
			_label3d(root, Vector3(0, height + 0.4, 0), "").name = "Name"
			if is_body:
				_label3d(root, Vector3(0, height + 1, 0), "", 22).name = "Power"
				_decal(root, "circle_02", data.radius + 0.3, data.color).name = "Offer"
				_decal(root, "circle_01", data.radius, Color(data.color, 0.5))
		"trails":
			_decal(root, "smoke_01", 1.05, Color(data.color, 0.7), 0.025 + (int(data.id) % 8) * 0.001)
		"shots":
			var shot = _decal(root, "spark_01", 0.5, data.color, 1)
			shot.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		"pickups":
			_asset(root, "kenney/column.glb", Vector3.ZERO, Vector3(1.2, 0.5, 1.2))
			_asset(root, "kenney/potion.glb", Vector3(0, 0.6, 0), Vector3(0.7, 0.9, 0.7)).name = "Crystal"
			_decal(root, "magic_01", 1.2, ELEMENTS[data.element])
			_label3d(root, Vector3(0, 2, 0), data.element, 30).modulate = ELEMENTS[data.element]
		"hazards":
			_decal(root, "circle_01", data.radius, Color(1, 0.1, 0.15, 0.8), 0.08)
	return root

func _member_health() -> float:
	return 70.0 + (party_level - 1) * 10.0

func _xp_needed() -> int:
	return 100 + (party_level - 1) * 50

func _award_xp(amount: int, claim: String) -> void:
	if not is_host or xp_claims.has(claim): return
	xp_claims[claim] = true
	if party_level >= 10: return
	party_xp += amount
	var previous_level = party_level
	while party_level < 10 and party_xp >= _xp_needed():
		party_xp -= _xp_needed()
		party_level += 1
	if party_level >= 10: party_xp = 0
	if party_level != previous_level:
		for body in bodies.values():
			var maximum = _member_health() * body.members.size()
			body.health = minf(maximum, body.health + maximum - body.max_health)
			body.max_health = maximum
		_message("PARTY LEVEL %d · +10 health per slime, +12%% fusion damage per level" % party_level)

func _sample_remote_position(kind: String, data: Dictionary) -> Vector3:
	if is_host or not kind in ["bodies", "enemies"] or snapshot_frames.size() < 2:
		return data.position
	var render_time = Time.get_ticks_msec() / 1000.0 - 0.12
	while snapshot_frames.size() > 2 and snapshot_frames[1].time <= render_time:
		snapshot_frames.pop_front()
	var first = snapshot_frames[0]
	var second = snapshot_frames[1]
	var a = {}
	var b = {}
	for entity in first[kind]:
		if entity.id == data.id: a = entity
	for entity in second[kind]:
		if entity.id == data.id: b = entity
	if a.is_empty() or b.is_empty(): return data.position
	var weight = clampf((render_time - first.time) / maxf(0.001, second.time - first.time), 0, 1)
	return a.position.lerp(b.position, weight)

func camera_anchor(body: Dictionary) -> Vector3:
	var visual = visuals.get("bodies" + str(body.id))
	return visual.position if is_instance_valid(visual) else body.position
