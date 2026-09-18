extends RefCounted
static func build(w: Node3D) -> void:
	var root=w.get_node("GeneratedGeometry")
	# Existing cliff models form real solid steps, not just decorative scenery.
	for i in 3:
		var p=w.terrain.ground(Vector3(-30+i*4,0,36))
		var height=1.0+i*0.9
		w._asset(root,"nature/cliff_block_rock.glb",p,Vector3(4, height, 5))
		w.platforms.append({"rect":Rect2(p.x-2,p.z-2.5,4,5),"bottom":p.y,"top":p.y+height})
		preload("res://scripts/outdoor_level.gd")._camera_blocker(root,p+Vector3(0,height/2,0),Vector3(4,height,5))
	w._label3d(root,w.terrain.ground(Vector3(-30,0,40))+Vector3(0,2,0),"JUMP THE STONE STEPS",24)
	if w.map_index != 1:return
	for side in [-1,1]:
		var p=w.terrain.ground(Vector3(side*24,0,-8))
		# Three walls and a low roof: enter from the south as a small slime.
		for offset in [Vector3(-4,0,0),Vector3(4,0,0),Vector3(0,0,-4)]:
			var size=Vector3(1,3,9) if offset.x != 0 else Vector3(9,3,1)
			w._asset(root,"nature/cliff_block_rock.glb",p+offset,size)
			w.walls.append(Rect2(p.x+offset.x-size.x/2,p.z+offset.z-size.z/2,size.x,size.z))
		var roof=p+Vector3(0,1.55,0)
		w._asset(root,"nature/cliff_block_rock.glb",roof,Vector3(7,0.55,8))
		w.platforms.append({"rect":Rect2(p.x-3.5,p.z-4,7,8),"bottom":roof.y,"top":roof.y+0.55})
		preload("res://scripts/outdoor_level.gd")._camera_blocker(root,roof+Vector3(0,0.275,0),Vector3(7,0.55,8))
		w.plates.append(p)
		var holder=Node3D.new()
		root.add_child(holder)
		holder.position=p+Vector3(0,0.04,0)
		w.plate_visuals.append(w._decal(holder,"magic_01",1.4,Color("ffd66d")))
		w._label3d(root,p+Vector3(0,3.4,3),"SOLO PASSAGE · HOLD BOTH SEALS",23)
	w.puzzle_gate=w._asset(root,"kenney/wall-opening.glb",w.terrain.ground(Vector3(w.terrain.trail_x(-20),0,-20)),Vector3(9,6,2))
	w._label3d(w.puzzle_gate,Vector3(0,6.8,0),"TWIN SEALS · SPLIT TO OPEN",24)
