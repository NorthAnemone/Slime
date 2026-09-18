extends Node
## Local co-op: two third-person views while separate; one while fused.
var world: Node3D
var cameras: Array[Camera3D] = []
var panes: Array[SubViewportContainer] = []
var yaw = [0.0, 0.0]
var pitch = [-0.42, -0.42]
var distance = [7.0, 7.0]
var orbit_yaw = [0.0, 0.0]
var orbit_pitch = [-0.42, -0.42]
var eye_height = [1.0, 1.0]
var boom = [7.0, 7.0]
var zoom = [0.0, 0.0]
var split = false
var layer: CanvasLayer
var divider: ColorRect
var view_labels: Array[Label] = []

func setup(owner_world: Node3D) -> void:
	world = owner_world
	layer = CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	for i in 2:
		var pane = SubViewportContainer.new()
		pane.stretch = true
		pane.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(pane)
		var view = SubViewport.new()
		view.world_3d = world.get_world_3d()
		view.handle_input_locally = false
		pane.add_child(view)
		var cam = Camera3D.new()
		cam.fov = 72
		cam.near = 0.15
		cam.far = 400
		cam.position = Vector3(0, 4, 60)
		view.add_child(cam)
		cam.current = true
		cameras.append(cam)
		panes.append(pane)
		var label = Label.new()
		label.text = "PLAYER %d" % (i + 1)
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_shadow_color", Color.BLACK)
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
		layer.add_child(label)
		view_labels.append(label)
	divider = ColorRect.new()
	divider.color = Color(0.05, 0.09, 0.08, 0.8)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(divider)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or (event.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0):
		yaw[0] -= event.relative.x * 0.003
		pitch[0] = clampf(pitch[0] - event.relative.y * 0.003, -1.25, 0.3)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: zoom[0] = clampf(zoom[0] - 1, -2, 8)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: zoom[0] = clampf(zoom[0] + 1, -2, 8)
		if event.button_index == MOUSE_BUTTON_RIGHT: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_HOME:
		pitch = [-0.42, -0.42]
		yaw = [0.0, 0.0]
		zoom = [0.0, 0.0]
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_TAB:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED

func movement(raw: Vector2, index: int) -> Vector2:
	return raw.rotated(-orbit_yaw[index if split else 0])

func aim(index: int) -> Vector2:
	var angle = orbit_yaw[index if split else 0]
	return Vector2(-sin(angle), -cos(angle))

func update(delta: float) -> void:
	var first = world._local_body()
	if first.is_empty(): return
	var second = {}
	if world.local_coop:
		for b in world.state.bodies:
			if 2 in b.members: second = b
	var was_split = split
	split = not second.is_empty() and first.id != second.id
	if split and not was_split:
		yaw[1] = yaw[0]
		orbit_yaw[1] = orbit_yaw[0]
		pitch[1] = pitch[0]
		orbit_pitch[1] = orbit_pitch[0]
	if world.local_coop:
		var index = 1 if split else 0
		yaw[index] += (float(Input.is_physical_key_pressed(KEY_U)) - float(Input.is_physical_key_pressed(KEY_O))) * delta * 1.8
		pitch[index] = clampf(pitch[index] + (float(Input.is_physical_key_pressed(KEY_I)) - float(Input.is_physical_key_pressed(KEY_K))) * delta * 1.3, -1.25, 0.3)
		zoom[index] = clampf(zoom[index] + (float(Input.is_physical_key_pressed(KEY_BRACKETRIGHT)) - float(Input.is_physical_key_pressed(KEY_BRACKETLEFT))) * delta * 5, -2, 8)
	# Keyboard fallback also works if an embedded window does not capture the mouse.
	pitch[0] = clampf(pitch[0] + (float(Input.is_physical_key_pressed(KEY_T)) - float(Input.is_physical_key_pressed(KEY_G))) * delta * 1.3, -1.25, 0.3)
	var size = get_viewport().get_visible_rect().size
	panes[0].size = Vector2(size.x * (0.5 if split else 1.0), size.y)
	panes[1].size = Vector2(size.x * 0.5, size.y)
	panes[1].position = Vector2(size.x * 0.5, 0)
	panes[1].visible = split
	divider.visible = split
	divider.position = Vector2(size.x / 2 - 1, 0)
	divider.size = Vector2(2, size.y)
	for i in 2:
		view_labels[i].visible = split
		view_labels[i].position = Vector2(18 + size.x * 0.5 * i, size.y - 164)
	panes[1].get_child(0).render_target_update_mode = SubViewport.UPDATE_ALWAYS if split else SubViewport.UPDATE_DISABLED
	for i in (2 if split else 1):
		var body = first if i == 0 else second
		var fused = body.members.size() > 1
		# Position and look target use the same rendered anchor. Never chase a raw
		# network position with one half of the camera transform.
		eye_height[i] = lerpf(eye_height[i], 1.8 if fused else 1.0, 1.0 - exp(-delta * 8))
		var target = world.camera_anchor(body) + Vector3(0, eye_height[i], 0)
		orbit_yaw[i] = lerp_angle(orbit_yaw[i], yaw[i], 1.0 - exp(-delta * 22))
		orbit_pitch[i] = lerpf(orbit_pitch[i], pitch[i], 1.0 - exp(-delta * 22))
		distance[i] = lerpf(distance[i], (9.0 + body.members.size() * 0.15 if fused else 7.0) + zoom[i], 1.0 - exp(-delta * 4))
		var offset = Vector3(0, 0, distance[i]).rotated(Vector3.RIGHT, orbit_pitch[i]).rotated(Vector3.UP, orbit_yaw[i])
		var desired = target + offset
		desired.y = maxf(desired.y, world.terrain.elevation(desired) + 0.7)
		var direction = (desired - target).normalized()
		var allowed = target.distance_to(desired)
		var right = Vector3.RIGHT.rotated(Vector3.UP, orbit_yaw[i]) * 0.22
		# Probe the near-plane edges as well as the center to avoid wall clipping.
		for probe in [Vector3.ZERO, right, -right, Vector3.UP * 0.22, Vector3.DOWN * 0.22]:
			var hit = world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(target + probe, desired + probe))
			if not hit.is_empty(): allowed = minf(allowed, maxf(0.2, (hit.position - target - probe).length() - 0.35))
		# Retract immediately for safety, release smoothly instead of snapping out.
		boom[i] = allowed if allowed < boom[i] else lerpf(boom[i], allowed, 1.0 - exp(-delta * 5))
		cameras[i].position = target + direction * boom[i]
		cameras[i].look_at(target)
