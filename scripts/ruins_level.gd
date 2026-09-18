extends RefCounted
## Second expedition map, assembled from the existing licensed Kenney assets.
const LANDMARKS = [Vector3(0, 0, 48), Vector3(22, 0, 12), Vector3(-20, 3, -28), Vector3(0, 6, -68)]
const EXIT = Vector3(0, 6, -89)
static func elevation(pos: Vector3) -> float:
	return clampf((4 - pos.z) * 0.15, 0, 3) + clampf((-38 - pos.z) * 0.15, 0, 3)
static func ground(pos: Vector3) -> Vector3:
	return Vector3(pos.x, elevation(pos), pos.z)
static func slope(z: float) -> float:
	return atan(0.15) if (z < 4 and z > -16) or (z < -38 and z > -58) else 0
static func trail_x(z: float) -> float:
	if z > 12: return lerpf(22, 0, clampf((z - 12) / 36, 0, 1))
	if z > -28: return lerpf(-20, 22, (z + 28) / 40)
	return lerpf(0, -20, clampf((z + 68) / 40, 0, 1))
static func build(w: Node3D) -> void:
	var root = w.get_node("GeneratedGeometry")
	for span in [Vector2(72,4),Vector2(4,-16),Vector2(-16,-38),Vector2(-38,-58),Vector2(-58,-102)]:
		var z = (span.x + span.y) / 2
		var rise = elevation(Vector3(0,0,span.y)) - elevation(Vector3(0,0,span.x))
		var tile = w._asset(root,"nature/ground_grass.glb",ground(Vector3(0,0,z)),Vector3(110,1,Vector2(span.x-span.y,rise).length()))
		tile.rotation.x = atan2(rise,span.x-span.y)
	for z in range(-92,60,4):
		var tile = w._asset(root,"nature/ground_pathOpen.glb",ground(Vector3(trail_x(z),0,z))+Vector3(0,0.03,0),Vector3(7,1,4/cos(slope(z))))
		tile.rotation.x = slope(z)
	# Rock ridges enclose the valley, keeping the central winding route open.
	for side in [-1,1]:
		for z in range(-100,73,12):
			var p = ground(Vector3(side * 58,0,z))
			w._asset(root,"nature/cliff_block_rock.glb",p,Vector3(20,15 + posmod(z,7),15))
	for i in LANDMARKS.size():
		var mark = LANDMARKS[i]
		for side in [-1,1]:
			for offset in [-7,0,7]:
				var p = ground(mark+Vector3(side*18,0,offset))
				w._asset(root,"kenney/column.glb",p,Vector3(2.2,4.5+i*1.2+abs(offset)*0.2,2.2))
				w.walls.append(Rect2(p.x-1.1,p.z-1.1,2.2,2.2))
				preload("res://scripts/outdoor_level.gd")._camera_blocker(root,p+Vector3(0,3,0),Vector3(2.2,6,2.2))
		w._asset(root,"nature/campfire_logs.glb",ground(mark+Vector3(6,0,6)),Vector3(2,0.8,2))
	var rng = RandomNumberGenerator.new()
	rng.seed = 29081
	for i in 65:
		var p = ground(Vector3(rng.randf_range(-46,46),0,rng.randf_range(-96,64)))
		var clear = absf(p.x-trail_x(p.z)) < 10 or (absf(absf(p.x)-24) < 10 and absf(p.z+8) < 10) or (p.x < -18 and p.x > -36 and absf(p.z-36) < 6)
		for mark in LANDMARKS:
			if Vector2(p.x-mark.x,p.z-mark.z).length() < 17: clear = true
		for cache_pos in [Vector3(-34,0,30),Vector3(36,0,-3),Vector3(-30,0,-48)]:
			if Vector2(p.x-cache_pos.x,p.z-cache_pos.z).length() < 6: clear = true
		if p.x > 24 and p.x < 43 and p.z < -22 and p.z > -49: clear = true
		for cache in [Vector3(32,0,26),Vector3(-34,0,-3),Vector3(-30,0,-70),Vector3(-36,0,22),Vector3(35,0,-3),Vector3(-35,0,-34),Vector3(-26,0,-76)]:
			if Vector2(p.x-cache.x,p.z-cache.z).length() < 5: clear = true
		if clear: continue
		var size = rng.randf_range(2,5)
		w._asset(root,"nature/rock_largeA.glb",p,Vector3(size,size*0.7,size)).rotation.y=rng.randf_range(0,TAU)
		w.walls.append(Rect2(p.x-size*0.4,p.z-size*0.4,size*0.8,size*0.8))
		preload("res://scripts/outdoor_level.gd")._camera_blocker(root,p+Vector3(0,size*0.35,0),Vector3(size*0.8,size*0.7,size*0.8))
	w._asset(root,"nature/tent_smallOpen.glb",Vector3(-7,0,53),Vector3(4,3,4))
	w._asset(root,"kenney/wall-opening.glb",ground(Vector3(22,0,20)),Vector3(10,7,2))
	w.portal=w._asset(root,"kenney/wall-opening.glb",EXIT,Vector3(8,8,2))
	w._decal(w.portal,"magic_01",3.5,Color("ffc878"))
	w.aim_marker=Node3D.new()
	w.add_child(w.aim_marker)
	w._decal(w.aim_marker,"circle_02",0.22,Color.WHITE)
