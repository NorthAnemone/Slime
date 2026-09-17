extends Node3D
## Host-authoritative simulation. Local co-op uses the same simulation, without RPCs.
signal toast_requested(message: String)
signal local_stats_changed(health: float, max_health: float, member_count: int, power: float, enemies_left: int, floor_number: int, portal_open: bool)
signal roster_changed(roster: Array)
signal encounter_changed(info: Dictionary)

const COLORS = [Color("#72ef9b"), Color("#65d5ff"), Color("#ff8fd8"), Color("#ffd66d"), Color("#b79cff"), Color("#ff9875")]
const ELEMENTS = {"Ember": Color("#ff9454"), "Frost": Color("#75e1ff"), "Storm": Color("#c5a1ff")}
const ROOMS = ["THE NURSERY", "ROOT GALLERY", "CRUCIBLE HALL", "MOSS WARDEN"]
const CENTERS = [36.0, 12.0, -12.0, -36.0]
const PORTAL = Vector3(0, 0, -43)
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
			pickups[id] = {"id": id, "position": Vector3(-6 + i * 6, 0, CENTERS[room] + 5),
				"element": key, "ready": 0.0, "room": room}

func _id() -> int:
	var id = next_id
	next_id += 1
	return id

func _add_player(peer_id: int, player_name: String) -> void:
	if players.size() >= 6 or players.has(peer_id):
		return
	players[peer_id] = {"id": peer_id, "name": player_name.left(18), "color": COLORS[players.size() % 6],
		"body_id": 0, "score": 0, "element": "", "offer": 0.0, "last_input": clock,
		"move": Vector2.ZERO, "aim": Vector2.UP, "attack": false, "shot": 0.0}
	_solo(peer_id, Vector3(-2 + players.size() * 1.7, 0, CENTERS[stage] + 8), 1.0)

func _solo(peer_id: int, pos: Vector3, ratio: float) -> void:
	var id = _id()
	bodies[id] = {"id": id, "members": [peer_id], "position": pos, "radius": 0.7,
		"health": maxf(1, 70 * ratio), "max_health": 70.0, "color": players[peer_id].color,
		"next_trail": 0.0, "invulnerable": clock + 1.5, "swing": 0.0, "facing": Vector2.UP}
	players[peer_id].body_id = id

@rpc("any_peer", "call_remote", "reliable")
func register_player(player_name: String) -> void:
	if is_host:
		_add_player(multiplayer.get_remote_sender_id(), player_name.strip_edges())

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func submit_input(move: Vector2, aim: Vector2, attack: bool) -> void:
	if is_host and move.is_finite() and aim.is_finite():
		_set_input(multiplayer.get_remote_sender_id(), move, aim, attack)

@rpc("any_peer", "call_remote", "reliable")
func action(kind: String) -> void:
	if is_host:
		_action(multiplayer.get_remote_sender_id(), kind)

@rpc("authority", "call_remote", "reliable", 2)
func receive_snapshot(data: Dictionary) -> void:
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
	for kind in ["fuse", "split", "collect"]:
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
				if item.room == stage and item.ready <= clock and _distance(item, body) < 2.3:
					p.element = item.element
					item.ready = clock + 1.0
					_message("%s absorbed %s. Fuse to activate it!" % [p.name, p.element])
					break

func _set_input(peer_id: int, move: Vector2, aim: Vector2, attack: bool) -> void:
	if players.has(peer_id):
		var p = players[peer_id]
		p.move = move.limit_length()
		p.aim = aim.normalized() if aim.length_squared() > 0.01 else Vector2.UP
		p.attack = attack
		p.last_input = clock

func _read_inputs() -> void:
	var move = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var aim = _mouse_aim()
	if is_host:
		_set_input(local_peer_id, move, aim, Input.is_action_pressed("attack"))
	else:
		submit_input.rpc_id(1, move, aim, Input.is_action_pressed("attack"))
	if local_coop and players.has(2):
		var move2 = Input.get_vector("p2_move_left", "p2_move_right", "p2_move_up", "p2_move_down")
		var body = bodies[players[2].body_id]
		var target = _nearest(body.position, enemies)
		var aim2 = Vector2.UP
		if not target.is_empty():
			var d = target.position - body.position
			aim2 = Vector2(d.x, d.z).normalized()
		elif move2.length() > 0.1:
			aim2 = move2
		_set_input(2, move2, aim2, Input.is_action_pressed("p2_attack"))

func _physics_process(delta: float) -> void:
	if not is_host and multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if players.is_empty() and is_host:
		return
	input_timer += delta
	if input_timer >= 0.033:
		input_timer = 0
		_read_inputs()
	if not is_host:
		return
	clock += delta
	if not complete:
		_simulate(delta)
	snapshot_timer += delta
	if snapshot_timer >= 0.1:
		snapshot_timer = 0
		var data = _snapshot()
		if not local_coop:
			receive_snapshot.rpc(data)
		_apply(data)

func _simulate(delta: float) -> void:
	for body in bodies.values():
		var move = Vector2.ZERO
		for member in body.members:
			var p = players[member]
			if clock - p.last_input > 0.3:
				continue
			move += p.move
			body.facing = p.aim
			if p.attack and body.members.size() > 1 and clock >= p.shot:
				_attack(p, body)
		# Average, do not normalize: disagreeing/idle members reduce shared speed.
		move /= float(body.members.size())
		var speed = 7.2 if body.members.size() == 1 else 5.7
		_move(body, Vector3(move.x, 0, move.y) * speed * delta)
		if body.members.size() == 1 and clock >= body.next_trail and move.length() > 0.1:
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
	var ember = powers.get("Ember", 0)
	var frost = powers.get("Frost", 0)
	var storm = powers.get("Storm", 0)
	# Elemental damage scales exactly linearly with matching carried powers.
	enemy.health -= damage + 8 * (ember + frost + storm)
	enemy.flash = clock + 0.1
	if ember > 0:
		enemy.burn_until = clock + 3
		enemy.burn_damage = 6.0 * ember
	if frost > 0:
		enemy.frost_until = clock + 2.0 * frost
	if storm > 0:
		var remaining = storm + 1
		for other in enemies.values():
			if other.id != enemy_id and _distance(enemy, other) < 7 and remaining > 0:
				other.health -= 14.0 * storm
				other.flash = clock + 0.2
				if frost > 0:
					other.frost_until = clock + 2.0 * frost
				if ember > 0:
					other.burn_until = clock + 3
					other.burn_damage = 6.0 * ember
				remaining -= 1
	if ember > 0 and powers.size() > 1:
		_effect(enemy.position, 3.0, Color("#ffc46c"), 0.22)
		for other in enemies.values():
			if other.id != enemy_id and _distance(enemy, other) < 3:
				other.health -= 12.0 * ember
				if frost > 0:
					other.frost_until = clock + 2.0 * frost

func _update_shots(delta: float) -> void:
	for id in shots.keys():
		var s = shots[id]
		var next = s.position + s.velocity * delta
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
			first.max_health = 70.0 * members.size()
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
	# No healing, recharge or replacement powers when splitting.

func _spawn_enemy(pos: Vector3, kind: String) -> int:
	var id = _id()
	var hp = 1400.0 if kind == "boss" else (110.0 if kind == "brute" else 65.0)
	enemies[id] = {"id": id, "position": pos, "kind": kind, "radius": 2.1 if kind == "boss" else 0.8,
		"health": hp, "max_health": hp, "attack_at": clock + 2.0, "flash": 0.0,
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
					_spawn_enemy(Vector3(x, 0, -38), "crawler")
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
					if _distance(h, body) < h.radius + body.radius:
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
	_message("Reformed at this chamber's checkpoint. Your powers survived.")

func _reset_party() -> void:
	bodies.clear()
	trails.clear()
	shots.clear()
	hazards.clear()
	var i = 0
	for id in players:
		_solo(id, Vector3(-2 + i * 1.8, 0, CENTERS[stage] + 8), 1.0)
		players[id].offer = 0.0
		i += 1

func _restart() -> void:
	stage = 0
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
			_spawn_enemy(Vector3(-9 + (i % 3) * 9, 0, CENTERS[stage] - 3 - (i / 3) * 3),
				"brute" if stage == 2 and i % 2 == 0 else "crawler")
	elif stage == 3:
		boss_id = _spawn_enemy(Vector3(0, 0, -39), "boss")

func _progress() -> void:
	if stage < 3 and enemies.is_empty():
		var exit_z = CENTERS[stage] - 10
		for body in bodies.values():
			if body.members.size() >= 2 and body.position.z < exit_z:
				stage += 1
				_reset_party()
				_start_encounter()
				_message(ROOMS[stage] + " · split, prepare your powers, then fuse!")
				return
	if victory:
		for body in bodies.values():
			if body.members.size() >= 2 and body.position.distance_to(PORTAL) < 3:
				complete = true
				_message("CRUCIBLE CLEARED! Press R to play again.")
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
	var rects = walls.duplicate()
	# Confine all actors to the active chamber. Crossing the exit triggers next stage.
	rects.append(Rect2(-20, CENTERS[stage] + 11.8, 40, 1))
	if not enemies.is_empty():
		rects.append(Rect2(-20, CENTERS[stage] - 12, 40, 1))
	var point = Vector2(pos.x, pos.z)
	if absf(pos.x) + radius > 19.5 or absf(pos.z) + radius > 47.5:
		return false
	for rect in rects:
		var nearest = Vector2(clampf(point.x, rect.position.x, rect.end.x), clampf(point.y, rect.position.y, rect.end.y))
		if point.distance_to(nearest) < radius:
			return false
	return true

func _move(entity: Dictionary, amount: Vector3) -> void:
	var pos: Vector3 = entity.position
	var next = pos + Vector3(amount.x, 0, 0)
	if _can_occupy(next, entity.radius):
		pos.x = next.x
	next = pos + Vector3(0, 0, amount.z)
	if _can_occupy(next, entity.radius):
		pos.z = next.z
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
	return {"clock": clock, "stage": stage, "victory": victory, "complete": complete, "players": roster,
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
	var objective = "Fuse and go north through the arch."
	if data.stage == 0:
		objective = "Solo: collect a power (F / L). Fuse (E + N), then go north."
	elif not data.enemies.is_empty():
		objective = "Defeat %d enemies to unlock the north arch." % data.enemies.size()
	if data.stage == 3:
		objective = "Dodge red warnings. Slow the Warden with solo trails; fuse to strike."
	if data.victory:
		objective = "Warden defeated! Fuse and enter the heart gate."
	if data.complete:
		objective = "LEVEL COMPLETE · R: replay   Esc: menu"
	encounter_changed.emit({"title": ROOMS[data.stage], "objective": objective, "boss_health": boss_health,
		"boss_max": boss_max, "power": body.get("power_name", ""), "complete": data.complete})

func _local_body() -> Dictionary:
	for body in state.get("bodies", []):
		if local_peer_id in body.members:
			return body
	return {}

func _mouse_aim() -> Vector2:
	var body = _local_body()
	if body.is_empty():
		return Vector2.UP
	var mouse = get_viewport().get_mouse_position()
	var origin = camera.project_ray_origin(mouse)
	var ray = camera.project_ray_normal(mouse)
	if absf(ray.y) < 0.001:
		return Vector2.UP
	var pos = origin + ray * (-origin.y / ray.y)
	return Vector2(pos.x - body.position.x, pos.z - body.position.z).normalized()

func _process(delta: float) -> void:
	if state.is_empty():
		return
	_render_entities(delta)
	var body = _local_body()
	if not body.is_empty():
		var center: Vector3 = body.position
		var separation = 0.0
		if local_coop:
			for other in state.bodies:
				if 2 in other.members and other.id != body.id:
					center = (center + other.position) / 2
					separation = body.position.distance_to(other.position)
		center.z -= 4.5
		var zoom = 1.0 + separation / 27.0
		camera.position = camera.position.lerp(center + Vector3(0, 19, 16) * zoom, minf(1, delta * 7))
		camera.look_at(center)
		aim_marker.position = body.position + Vector3(_mouse_aim().x, 0.12, _mouse_aim().y) * 2.0
		aim_marker.visible = body.members.size() > 1
	for i in gates.size():
		gates[i].visible = i == state.stage and not state.enemies.is_empty()
	portal.visible = state.victory
	for i in room_labels.size():
		room_labels[i].visible = i == state.stage

# Visuals are instances of public CC0 models/textures. No generated artwork.
var asset_cache: Dictionary = {}

func _asset(parent: Node3D, path: String, pos: Vector3, size: Vector3) -> Node3D:
	if not asset_cache.has(path):
		asset_cache[path] = load("res://assets/" + path)
	var holder = Node3D.new()
	parent.add_child(holder)
	holder.position = pos
	var model = asset_cache[path].instantiate()
	holder.add_child(model)
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
	var geometry = $GeneratedGeometry
	for z in [-48, 48]:
		walls.append(Rect2(-20, z, 40, 0.7))
	for x in [-20, 20]:
		walls.append(Rect2(x, -48, 0.7, 96))
	for z in [24, 0, -24]:
		walls.append(Rect2(-20, z, 15, 0.9))
		walls.append(Rect2(5, z, 15, 0.9))
	for rect in walls:
		var along_x = rect.size.x > rect.size.y
		var length = rect.size.x if along_x else rect.size.y
		var count = int(ceil(length / 3))
		for i in count:
			var pos = Vector3(rect.position.x, 0, rect.position.y)
			pos += Vector3((i + 0.5) * length / count, 0, 0) if along_x else Vector3(0, 0, (i + 0.5) * length / count)
			_asset(geometry, "kenney/wall.glb", pos, Vector3(length / count, 2.6, 0.7) if along_x else Vector3(0.7, 2.6, length / count))
	for room in 4:
		var z = CENTERS[room]
		for x in range(-18, 19, 3):
			for zz in range(-10, 12, 3):
				_asset(geometry, "kenney/floor-detail.glb" if (x + zz) % 3 == 0 else "kenney/floor.glb", Vector3(x, -0.3, z + zz), Vector3(3, 0.3, 3))
		for x in [-17, 17]:
			for dz in [-8, 8]:
				_asset(geometry, "kenney/column.glb", Vector3(x, 0, z + dz), Vector3(1.5, 3.3, 1.5))
				walls.append(Rect2(x - 0.75, z + dz - 0.75, 1.5, 1.5))
				var light = OmniLight3D.new()
				geometry.add_child(light)
				light.position = Vector3(x, 3, z + dz)
				light.light_color = Color("83ffba") if room % 2 == 0 else Color("ffd18b")
				light.light_energy = 0.6
				light.omni_range = 9
			_asset(geometry, "kenney/banner.glb", Vector3(x, 0, z), Vector3(1.4, 3, 0.8))
		room_labels.append(_label3d(geometry, Vector3(0, 4.4, z - 10), ROOMS[room], 44))
		if room < 3:
			_asset(geometry, "kenney/wall-opening.glb", Vector3(0, 0, z - 12), Vector3(10, 4, 1))
			var gate = _asset(geometry, "kenney/gate.glb", Vector3(0, 0, z - 12), Vector3(9, 3.8, 0.5))
			gates.append(gate)
	portal = _asset(geometry, "kenney/wall-opening.glb", PORTAL, Vector3(6, 5, 1))
	_decal(portal, "magic_01", 3, Color("7bffc1"))
	_label3d(portal, Vector3(0, 5.5, 0), "HEART GATE")
	aim_marker = Node3D.new()
	add_child(aim_marker)
	_decal(aim_marker, "circle_02", 0.25, Color.WHITE)

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
			visual.position = visual.position.lerp(data.position, minf(1, delta * 18))
			match kind:
				"bodies":
					var fused = data.members.size() > 1
					var face = data.facing
					visual.get_node("Model").rotation.y = lerp_angle(visual.get_node("Model").rotation.y, atan2(face.x, face.y), minf(1, delta * 8))
					visual.get_node("Name").text = ("FUSED  %d/%d" % [data.health, data.max_health]) if fused else "P%d" % data.members[0]
					visual.get_node("Offer").visible = data.offering
					visual.get_node("Power").text = data.power_name if fused else ""
					_animate(visual, "Punch" if fused and data.swing > state.clock else ("Walk" if moving else "Idle"))
				"enemies":
					visual.get_node("Name").text = "%s  %d/%d%s" % ["WARDEN" if data.kind == "boss" else data.kind.to_upper(), maxf(0, data.health), data.max_health, " SLOWED" if data.slow else ""]
					_animate(visual, "Walk" if moving else "Idle")
				"pickups":
					visual.visible = data.room == state.stage and data.ready <= state.clock
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
			_label3d(root, Vector3(0, 2, 0), data.element + "\nSOLO: F / L", 30).modulate = ELEMENTS[data.element]
		"hazards":
			_decal(root, "circle_01", data.radius, Color(1, 0.1, 0.15, 0.8), 0.08)
	return root
