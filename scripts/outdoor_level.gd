extends RefCounted
## Authored placement of unmodified CC0 models; no procedural art meshes.
const LANDMARKS = [Vector3(0, 0, 48), Vector3(-18, 3.6, 12), Vector3(20, 5.04, -28), Vector3(0, 8.4, -68)]
const EXIT = Vector3(0, 8.4, -89)

static func elevation(pos: Vector3) -> float:
	return clampf((26.0 - pos.z) * 0.18, 0, 3.6) + clampf((-22.0 - pos.z) * 0.24, 0, 4.8)

static func slope(z: float) -> float:
	if z < 26 and z > 6: return atan(0.18)
	if z < -22 and z > -42: return atan(0.24)
	return 0

static func ground(pos: Vector3) -> Vector3:
	return Vector3(pos.x, elevation(pos), pos.z)

static func trail_x(z: float) -> float:
	if z > 12: return lerpf(-18, 0, clampf((z - 12) / 36, 0, 1))
	if z > -28: return lerpf(20, -18, (z + 28) / 40)
	return lerpf(0, 20, clampf((z + 68) / 40, 0, 1))

static func build(w: Node3D) -> void:
	var root = w.get_node("GeneratedGeometry")
	# Each sloped surface is an existing grass model, positioned and rotated.
	for span in [Vector2(72, 26), Vector2(26, 6), Vector2(6, -22), Vector2(-22, -42), Vector2(-42, -102)]:
		var z = (span.x + span.y) / 2
		var rise = elevation(Vector3(0, 0, span.y)) - elevation(Vector3(0, 0, span.x))
		var length = Vector2(span.x - span.y, rise).length()
		var tile = w._asset(root, "nature/ground_grass.glb", ground(Vector3(0, 0, z)), Vector3(110, 1, length))
		tile.rotation.x = atan2(rise, span.x - span.y)
	for z in range(-92, 60, 4):
		var path = w._asset(root, "nature/ground_pathOpen.glb", ground(Vector3(trail_x(z), 0, z)) + Vector3(0, 0.025, 0), Vector3(6.5, 1, 4.0 / cos(slope(z))))
		path.rotation.x = slope(z)
	# Natural boundary and distant skyline; the playable route stays unobstructed.
	for i in 30:
		var angle = TAU * i / 30
		var p = Vector3(cos(angle) * 82, -5, -12 + sin(angle) * 125)
		w._asset(root, "nature/rock_largeA.glb" if i % 2 == 0 else "nature/rock_largeB.glb", p, Vector3(30, 25 + (i % 5) * 8, 34)).rotation.y = angle
	var rng = RandomNumberGenerator.new()
	rng.seed = 84519
	for i in 225:
		var p = Vector3(rng.randf_range(-51, 51), 0, rng.randf_range(-98, 65))
		var clear = absf(p.x - trail_x(p.z)) < 7
		for mark in LANDMARKS:
			if Vector2(p.x - mark.x, p.z - mark.z).length() < 13: clear = true
		for cache_pos in [Vector3(-34, 0, 30), Vector3(36, 0, -3), Vector3(-30, 0, -48)]:
			if Vector2(p.x - cache_pos.x, p.z - cache_pos.z).length() < 5: clear = true
		if p.x > 24 and p.x < 43 and p.z < -22 and p.z > -49: clear = true
		for cache in [Vector3(32,0,26),Vector3(-34,0,-3),Vector3(-30,0,-70),Vector3(-36,0,22),Vector3(35,0,-3),Vector3(-35,0,-34),Vector3(-26,0,-76)]:
			if Vector2(p.x-cache.x,p.z-cache.z).length() < 5: clear = true
		for location in w._shop_locations():
			if p.distance_to(location) < 8: clear = true
		if clear: continue
		var height = rng.randf_range(7, 14)
		var tree = w._asset(root, "nature/tree_pineTallA.glb" if i % 3 else "nature/tree_pineRoundA.glb", ground(p), Vector3(height * 0.48, height, height * 0.48))
		tree.rotation.y = rng.randf_range(0, TAU)
		w.walls.append(Rect2(p.x - 0.4, p.z - 0.4, 0.8, 0.8))
		_camera_blocker(root, ground(p) + Vector3(0, 4, 0), Vector3(0.85, 8, 0.85))
	for i in 135:
		var p = ground(Vector3(rng.randf_range(-43, 43), 0, rng.randf_range(-95, 60)))
		if absf(p.x - trail_x(p.z)) < 5: continue
		var model = "plant_bush" if i % 3 == 0 else ("flower_yellowA" if i % 3 == 1 else "grass")
		var size = 1.3 if model == "plant_bush" else 0.7
		w._asset(root, "nature/" + model + ".glb", p, Vector3(size, size, size)).rotation.y = rng.randf_range(0, TAU)
	# Distinct landmarks and optional side-route power caches.
	for i in LANDMARKS.size():
		var p = LANDMARKS[i]
		for side in [-1, 1]:
			var rock_pos = ground(p + Vector3(side * 12, 0, -3))
			var rock = w._asset(root, "nature/rock_largeB.glb", rock_pos, Vector3(7, 5 + i * 2, 7))
			w._register_rock(rock)
		if i > 0:
			w._asset(root, "kenney/column.glb", ground(p + Vector3(-5, 0, -4)), Vector3(2, 6 + i, 2))
			w._asset(root, "kenney/column.glb", ground(p + Vector3(5, 0, -4)), Vector3(2, 5 + i, 2))
		w._asset(root, "nature/campfire_logs.glb", ground(p + Vector3(5, 0, 4)), Vector3(1.6, 0.7, 1.6))
	w._asset(root, "nature/tent_smallOpen.glb", ground(Vector3(-7, 0, 53)), Vector3(4, 3, 4)).rotation.y = -0.5
	w._asset(root, "nature/log_large.glb", ground(Vector3(5, 0, 53)), Vector3(3, 0.8, 1))
	w.portal = w._asset(root, "kenney/wall-opening.glb", EXIT, Vector3(8, 8, 2))
	w._decal(w.portal, "magic_01", 3.5, Color("7bffc1"))
	w.aim_marker = Node3D.new()
	w.add_child(w.aim_marker)
	w._decal(w.aim_marker, "circle_02", 0.22, Color.WHITE)

static func _camera_blocker(root: Node3D, pos: Vector3, size: Vector3) -> void:
	var body = StaticBody3D.new()
	root.add_child(body)
	body.position = pos
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
