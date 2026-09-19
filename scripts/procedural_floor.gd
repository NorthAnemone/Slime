extends RefCounted
## Deterministic Aincrad-style floors assembled entirely from the bundled CC0 models.

var floor_number := 3
var floor_seed := 0
var theme := 0
var LANDMARKS: Array[Vector3] = []
var EXIT := Vector3.ZERO
var TOWNS: Array[Vector3] = []

func configure(number: int) -> void:
	floor_number = number
	floor_seed = 73013 + number * 7919
	theme = posmod(number - 3, 3)
	var rng = RandomNumberGenerator.new()
	rng.seed = floor_seed
	LANDMARKS = [Vector3(0,0,104)]
	for z in [45.0,-25.0,-98.0]:
		LANDMARKS.append(Vector3(rng.randf_range(-30,30),elevation(Vector3(0,0,z)),z))
	TOWNS.clear()
	for z in [70.0,5.0,-62.0]:
		var side = -1 if rng.randi()%2 == 0 else 1
		TOWNS.append(ground(Vector3(trail_x(z)+side*rng.randf_range(20,31),0,z+rng.randf_range(-5,5))))
	EXIT = ground(Vector3(LANDMARKS[3].x,0,-124))

func theme_name() -> String:
	return ["VERDANT EXPANSE","GOLDEN BADLANDS","MISTWOOD HEIGHTS"][theme]

func room_names() -> Array:
	return ["FLOOR %d CITY" % floor_number,"OUTER WILDS","HIGH CROSSING","FLOOR BOSS SANCTUM"]

func elevation(pos: Vector3) -> float:
	var base = clampf((76.0-pos.z)*0.028,0,5.8)
	var wave = sin((pos.x+floor_seed%17)*0.045)*1.0 + sin((pos.z-floor_seed%23)*0.035)*0.8
	return maxf(0,base+wave+1.4)

func ground(pos: Vector3) -> Vector3:
	return Vector3(pos.x,elevation(pos),pos.z)

func slope(_z: float) -> float:
	return 0.0

func trail_x(z: float) -> float:
	if z > LANDMARKS[1].z: return lerpf(LANDMARKS[1].x,0,clampf((z-LANDMARKS[1].z)/(LANDMARKS[0].z-LANDMARKS[1].z),0,1))
	if z > LANDMARKS[2].z: return lerpf(LANDMARKS[2].x,LANDMARKS[1].x,clampf((z-LANDMARKS[2].z)/(LANDMARKS[1].z-LANDMARKS[2].z),0,1))
	return lerpf(LANDMARKS[3].x,LANDMARKS[2].x,clampf((z-LANDMARKS[3].z)/(LANDMARKS[2].z-LANDMARKS[3].z),0,1))

func bounds() -> Rect2:
	return Rect2(-82,-136,164,260)

func build(w: Node3D) -> void:
	var root = w.get_node("GeneratedGeometry")
	var ground_model = "nature/ground_grass.glb"
	for z in range(-132,121,16):
		for x in range(-80,81,16):
			w._asset(root,ground_model,ground(Vector3(x,0,z)),Vector3(16,0.7,16))
	for z in range(-120,109,5):
		w._asset(root,"nature/ground_pathOpen.glb",ground(Vector3(trail_x(z),0,z))+Vector3(0,0.05,0),Vector3(8,0.8,5))
	# Visible outer cliffs explain the simulation boundary without placing blocker
	# boxes on the random rocks inside the playable region.
	for z in range(-132,125,14):
		for x in [-84,84]:
			w._asset(root,"nature/cliff_block_rock.glb",ground(Vector3(x,0,z)),Vector3(13,14+(abs(z)%5),13))
	for x in range(-77,78,14):
		for z in [-139,128]:
			w._asset(root,"nature/cliff_block_rock.glb",ground(Vector3(x,0,z)),Vector3(13,14+(abs(x)%5),13))
	_build_city(w,root)
	for i in TOWNS.size(): _build_town(w,root,TOWNS[i],i)
	var rng = RandomNumberGenerator.new()
	rng.seed = floor_seed
	for i in 155:
		var p = ground(Vector3(rng.randf_range(-74,74),0,rng.randf_range(-126,114)))
		if absf(p.x-trail_x(p.z)) < 8 or p.z > 87: continue
		var near_town = false
		for town in TOWNS:
			if p.distance_to(town) < 13: near_town = true
		if near_town: continue
		var near_landmark = false
		for mark in LANDMARKS:
			if p.distance_to(ground(mark)) < 15: near_landmark = true
		if near_landmark: continue
		if i % 3 == 0:
			var size = rng.randf_range(2.5,7.0)
			var rock = w._asset(root,"nature/rock_largeA.glb" if i%2 else "nature/rock_largeB.glb",p,Vector3(size,size*rng.randf_range(0.65,1.2),size))
			rock.rotation.y = rng.randf_range(0,TAU)
			w._register_rock(rock)
		else:
			var height = rng.randf_range(7,17)
			var tree = w._asset(root,"nature/tree_pineTallA.glb" if i%4 else "nature/tree_pineRoundA.glb",p,Vector3(height*0.48,height,height*0.48))
			tree.rotation.y = rng.randf_range(0,TAU)
			w._register_rock(tree)
	for mark in LANDMARKS:
		w._asset(root,"nature/campfire_logs.glb",ground(mark+Vector3(5,0,5)),Vector3(1.7,0.7,1.7))
	w.portal = w._asset(root,"kenney/wall-opening.glb",EXIT,Vector3(10,10,2))
	w._decal(w.portal,"magic_01",4.2,[Color("75ffc4"),Color("ffc878"),Color("bca8ff")][theme])
	w.aim_marker = Node3D.new()
	w.add_child(w.aim_marker)
	w._decal(w.aim_marker,"circle_02",0.22,Color.WHITE)

func _build_city(w: Node3D, root: Node3D) -> void:
	var center = ground(Vector3(0,0,104))
	w._label3d(root,center+Vector3(0,4,-10),"FLOOR %d · %s · SAFE CITY · V TO RETURN" % [floor_number,theme_name()],22)
	for side in [-1,1]:
		for z in [92,104,116]:
			var p = ground(Vector3(side*12,0,z))
			w._asset(root,"kenney/wall.glb",p,Vector3(8,6,2)).rotation.y = PI/2
			w._asset(root,"kenney/banner.glb",p+Vector3(-side*1.5,3,0),Vector3(1,3,1))
	for x in [-8,0,8]:
		w._asset(root,"nature/tent_smallOpen.glb",ground(Vector3(x,0,96)),Vector3(5,3,4))

func _build_town(w: Node3D, root: Node3D, center: Vector3, index: int) -> void:
	w._label3d(root,center+Vector3(0,5.4,0),"%s OUTPOST %d" % [theme_name(),index+1],25)
	for offset in [Vector3(-5,0,-3),Vector3(5,0,-3),Vector3(-5,0,4),Vector3(5,0,4)]:
		var p = ground(center+offset)
		w._asset(root,"nature/tent_smallOpen.glb",p,Vector3(4.5,2.8,3.5)).rotation.y = PI if offset.z < 0 else 0
	var board = ground(center+Vector3(-4,0,0))
	w._asset(root,"kenney/banner.glb",board,Vector3(1.2,3.2,1.2))
	w._label3d(root,board+Vector3(0,3.5,0),"BOUNTY BOARD · F / L",18)
	var hospital = ground(center+Vector3(0,0,0))
	w._asset(root,"kenney/potion.glb",hospital+Vector3(0,0.8,0),Vector3(0.9,1.3,0.9))
	w._label3d(root,hospital+Vector3(0,2.3,0),"HOSPITAL · 12 COINS · F / L",18)

func town_locations() -> Array:
	return TOWNS
