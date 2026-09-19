extends Control
## Network-safe minimap and teammate compass. It only renders replicated positions.

var world: Node3D
var expanded := false
var tracking := false
var tracked_id := 0

func setup(owner_world: Node3D) -> void:
	world = owner_world
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)

func toggle_map() -> void:
	expanded = not expanded
	queue_redraw()

func toggle_tracking() -> void:
	tracking = not tracking
	queue_redraw()

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if world == null or world.state.is_empty(): return
	var map_size = Vector2(520,620) if expanded else Vector2(210,210)
	size = map_size
	position = Vector2(22,115) if expanded else Vector2(22,105)
	draw_style_box(_box(Color(0.025,0.045,0.055,0.92)),Rect2(Vector2.ZERO,map_size))
	var bounds: Rect2 = world.map_bounds()
	var margin = 16.0
	var scale = minf((map_size.x-margin*2)/bounds.size.x,(map_size.y-margin*2)/bounds.size.y)
	var origin = (map_size-bounds.size*scale)*0.5
	var city = world.terrain.ground(world.terrain.LANDMARKS[0])
	draw_circle(_point(city,bounds,origin,scale),6 if expanded else 4,Color("7bffc1"))
	draw_string(ThemeDB.fallback_font,_point(city,bounds,origin,scale)+Vector2(8,4),"CITY",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("d8fff0"))
	draw_circle(_point(world.PORTAL,bounds,origin,scale),6 if expanded else 4,Color("ffd66d"))
	for town in world._town_locations():
		draw_circle(_point(town,bounds,origin,scale),4,Color("72bfff"))
	for entry in world.state.get("bodies",[]):
		var radius = 7 if world.local_peer_id in entry.members else 5
		draw_circle(_point(entry.position,bounds,origin,scale),radius,entry.color)
		if expanded:
			draw_string(ThemeDB.fallback_font,_point(entry.position,bounds,origin,scale)+Vector2(8,4),_names(entry.members),HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color.WHITE)
	if tracking:
		_draw_tracker(map_size)
	draw_string(ThemeDB.fallback_font,Vector2(12,map_size.y-9),"M: close" if expanded else "M: map  ·  P: teammate",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("d8e8df"))

func _draw_tracker(map_size: Vector2) -> void:
	var local = world._local_body()
	if local.is_empty(): return
	var target := {}
	for body in world.state.get("bodies",[]):
		if body.id != local.id:
			target = body
			break
	if target.is_empty():
		draw_string(ThemeDB.fallback_font,Vector2(map_size.x/2-55,26),"ALLY IS WITH YOU",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("7bffc1"))
		return
	var delta = Vector2(target.position.x-local.position.x,target.position.z-local.position.z)
	if delta.length_squared() < 0.01: return
	var center = Vector2(map_size.x/2,34)
	var direction = delta.normalized()
	var angle = direction.angle()+PI/2
	var points = PackedVector2Array([Vector2(0,-16),Vector2(-9,9),Vector2(0,5),Vector2(9,9)])
	for i in points.size(): points[i] = center+points[i].rotated(angle)
	draw_colored_polygon(points,Color("ffdf63"))
	draw_string(ThemeDB.fallback_font,center+Vector2(16,4),"ALLY %dm" % int(delta.length()),HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("ffdf63"))

func _names(member_ids: Array) -> String:
	var result: Array[String] = []
	for id in member_ids:
		for player in world.state.get("players",[]):
			if player.id == id: result.append(player.name)
	return "+".join(result)

func _point(pos: Vector3, bounds: Rect2, origin: Vector2, scale: float) -> Vector2:
	return origin+Vector2(pos.x-bounds.position.x,pos.z-bounds.position.y)*scale

func _box(color: Color) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(0.45,0.95,0.65,0.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	return style
