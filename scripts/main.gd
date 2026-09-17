extends Node

const SlimeWorld = preload("res://scripts/slime_world.gd")
const PORT := 7777
const MAX_PLAYERS := 6

var world
var menu: Control
var game_hud: Control
var name_input: LineEdit
var address_input: LineEdit
var status_label: Label
var health_bar: ProgressBar
var health_label: Label
var fusion_label: Label
var objective_label: Label
var player_list: VBoxContainer
var help_label: Label
var toast_panel: PanelContainer
var toast_label: Label
var toast_tween: Tween


func _ready() -> void:
	_build_interface()
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _build_interface() -> void:
	menu = Control.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(menu)

	var background := ColorRect.new()
	background.color = Color("091018")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_child(background)

	var glow := ColorRect.new()
	glow.color = Color(0.18, 0.55, 0.34, 0.11)
	glow.position = Vector2(0, 0)
	glow.size = Vector2(480, 1000)
	background.add_child(glow)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(590, 0)
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.position = Vector2(-295, -260)
	card.add_theme_stylebox_override("panel", _panel_style(Color("111b24"), 28, Color(0.37, 0.95, 0.57, 0.25)))
	menu.add_child(card)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_top", 42)
	margin.add_theme_constant_override("margin_bottom", 42)
	card.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	var eyebrow := _label("A CO-OP DUNGEON EXPERIMENT", 13, Color("72ef9b"))
	eyebrow.add_theme_constant_override("outline_size", 2)
	column.add_child(eyebrow)

	var title := _label("SLIMEBOUND", 62, Color("effff3"))
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 4)
	column.add_child(title)

	var tagline := _label("Separate minds. One mighty blob.", 19, Color("91a29e"))
	column.add_child(tagline)
	column.add_child(_spacer(12))

	column.add_child(_label("YOUR SLIME NAME", 12, Color("d8e8df")))
	name_input = LineEdit.new()
	name_input.placeholder_text = "Gloob"
	name_input.text = "Gloob"
	name_input.max_length = 18
	name_input.custom_minimum_size.y = 48
	name_input.add_theme_font_size_override("font_size", 17)
	column.add_child(name_input)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	column.add_child(buttons)
	var host_button := _button("HOST DUNGEON", Color("72ef9b"), Color("08130d"))
	host_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_button.pressed.connect(_host_game)
	buttons.add_child(host_button)
	var join_button := _button("JOIN DUNGEON", Color("293c48"), Color("ecfff2"))
	join_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_button.pressed.connect(_join_game)
	buttons.add_child(join_button)
	var local_button := _button("LOCAL 2-PLAYER TEST", Color("6753a3"), Color("ffffff"))
	local_button.pressed.connect(_local_game)
	column.add_child(local_button)

	address_input = LineEdit.new()
	address_input.placeholder_text = "Server address"
	address_input.text = "127.0.0.1"
	address_input.custom_minimum_size.y = 42
	column.add_child(address_input)

	status_label = _label("Host a game, then share your IP address and port 7777.", 13, Color("91a29e"))
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(status_label)

	var controls := _label("WASD  move     MOUSE  aim & spit     E  fuse     Q  split", 12, Color("ffd66d"))
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(controls)

	_build_hud()


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	game_hud = Control.new()
	game_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game_hud.hide()
	layer.add_child(game_hud)

	var brand := _label("SLIMEBOUND", 24, Color("effff3"))
	brand.position = Vector2(22, 18)
	game_hud.add_child(brand)

	objective_label = _pill("CLEAR THE DUNGEON", Color("ffd66d"))
	objective_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	objective_label.position = Vector2(-110, 18)
	objective_label.size = Vector2(220, 38)
	objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_hud.add_child(objective_label)

	var roster_panel := PanelContainer.new()
	roster_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	roster_panel.position = Vector2(-218, 70)
	roster_panel.size = Vector2(196, 40)
	roster_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.05, 0.08, 0.11, 0.88), 12, Color(1, 1, 1, 0.08)))
	game_hud.add_child(roster_panel)
	var roster_margin := MarginContainer.new()
	roster_margin.add_theme_constant_override("margin_left", 12)
	roster_margin.add_theme_constant_override("margin_right", 12)
	roster_margin.add_theme_constant_override("margin_top", 10)
	roster_margin.add_theme_constant_override("margin_bottom", 10)
	roster_panel.add_child(roster_margin)
	player_list = VBoxContainer.new()
	player_list.add_theme_constant_override("separation", 5)
	roster_margin.add_child(player_list)

	var stats := VBoxContainer.new()
	stats.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	stats.position = Vector2(22, -84)
	stats.size = Vector2(350, 62)
	game_hud.add_child(stats)
	health_bar = ProgressBar.new()
	health_bar.custom_minimum_size = Vector2(350, 23)
	health_bar.show_percentage = false
	health_bar.add_theme_stylebox_override("background", _panel_style(Color("10161c"), 10, Color("26343a")))
	health_bar.add_theme_stylebox_override("fill", _panel_style(Color("54db7e"), 10, Color("8affaa")))
	stats.add_child(health_bar)
	health_label = _label("100 / 100", 11, Color("ffffff"))
	health_label.position = Vector2(0, 1)
	health_label.size = Vector2(350, 22)
	health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	health_bar.add_child(health_label)
	fusion_label = _label("SOLO SLIME", 12, Color("91a29e"))
	stats.add_child(fusion_label)

	help_label = _label("E  FUSE NEARBY     Q  SPLIT     CLICK  SPIT GEL", 11, Color("91a29e"))
	help_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	help_label.position = Vector2(-540, -44)
	help_label.size = Vector2(518, 22)
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	game_hud.add_child(help_label)

	toast_panel = PanelContainer.new()
	toast_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_panel.position = Vector2(-225, 72)
	toast_panel.size = Vector2(450, 48)
	toast_panel.modulate.a = 0.0
	toast_panel.add_theme_stylebox_override("panel", _panel_style(Color("72ef9b"), 13, Color("aaffc1")))
	game_hud.add_child(toast_panel)
	toast_label = _label("", 14, Color("0b1a10"))
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toast_panel.add_child(toast_label)


func _host_game() -> void:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(PORT, MAX_PLAYERS)
	if error != OK:
		status_label.text = "Could not host: %s" % error_string(error)
		return
	multiplayer.multiplayer_peer = peer
	_enter_game(true)


func _local_game() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_create_world()
	var player_name := name_input.text.strip_edges()
	if player_name.is_empty():
		player_name = "Gloob"
	world.setup_local_coop(player_name, "Arrow Slime")
	help_label.text = "P1: WASD · MOUSE · E/Q       P2: ARROWS · M ATTACK · N FUSE · B SPLIT"
	_show_toast("Local co-op ready: WASD versus arrow keys")


func _join_game() -> void:
	var peer := ENetMultiplayerPeer.new()
	var address := address_input.text.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"
	var error := peer.create_client(address, PORT)
	if error != OK:
		status_label.text = "Could not connect: %s" % error_string(error)
		return
	multiplayer.multiplayer_peer = peer
	status_label.text = "Connecting to %s:%d…" % [address, PORT]


func _on_connected_to_server() -> void:
	_enter_game(false)


func _enter_game(hosting: bool) -> void:
	_create_world()
	help_label.text = "E  FUSE NEARBY     Q  SPLIT     CLICK  SPIT GEL"
	var player_name := name_input.text.strip_edges()
	if player_name.is_empty():
		player_name = "Gloob"
	if hosting:
		world.setup_host(player_name)
		_show_toast("Dungeon hosted on port %d" % PORT)
	else:
		world.setup_client(player_name)
		_show_toast("You oozed into the dungeon")


func _create_world() -> void:
	menu.hide()
	game_hud.show()
	world = SlimeWorld.new()
	add_child(world)
	move_child(world, 0)
	world.toast_requested.connect(_show_toast)
	world.local_stats_changed.connect(_update_stats)
	world.roster_changed.connect(_update_roster)


func _on_connection_failed() -> void:
	status_label.text = "Connection failed. Check the address and firewall settings."
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func _on_server_disconnected() -> void:
	_show_toast("The host closed the dungeon")
	await get_tree().create_timer(1.4).timeout
	get_tree().reload_current_scene()


func _update_stats(health: float, max_health: float, member_count: int, power: float, enemies_left: int, floor_number: int, portal_open: bool) -> void:
	health_bar.max_value = max_health
	health_bar.value = health
	health_label.text = "%d / %d" % [ceil(health), ceil(max_health)]
	fusion_label.text = "SOLO SLIME · FIND AN ALLY" if member_count == 1 else "%d-PLAYER FUSION · %d POWER" % [member_count, round(power)]
	fusion_label.add_theme_color_override("font_color", Color("91a29e") if member_count == 1 else Color("72ef9b"))
	objective_label.text = "FLOOR %d · HEART GATE OPEN" % floor_number if portal_open else "FLOOR %d · %d CREATURES LEFT" % [floor_number, enemies_left]


func _update_roster(roster: Array) -> void:
	for child in player_list.get_children():
		child.queue_free()
	for entry in roster:
		var row := HBoxContainer.new()
		var dot := ColorRect.new()
		dot.color = entry.color
		dot.custom_minimum_size = Vector2(9, 9)
		row.add_child(dot)
		var player_name := _label(entry.name, 12, Color("e8f2ed"))
		player_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(player_name)
		row.add_child(_label("◆ %d" % entry.score, 12, Color("ffd66d")))
		player_list.add_child(row)


func _show_toast(message: String) -> void:
	toast_label.text = message
	if toast_tween and toast_tween.is_running():
		toast_tween.kill()
	toast_tween = create_tween()
	toast_tween.tween_property(toast_panel, "modulate:a", 1.0, 0.18)
	toast_tween.tween_interval(2.0)
	toast_tween.tween_property(toast_panel, "modulate:a", 0.0, 0.28)


func _label(text_value: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(text_value: String, background: Color, foreground: Color) -> Button:
	var result := Button.new()
	result.text = text_value
	result.custom_minimum_size.y = 50
	result.add_theme_font_size_override("font_size", 14)
	result.add_theme_color_override("font_color", foreground)
	result.add_theme_color_override("font_hover_color", foreground)
	result.add_theme_stylebox_override("normal", _panel_style(background, 12, background.lightened(0.12)))
	result.add_theme_stylebox_override("hover", _panel_style(background.lightened(0.08), 12, background.lightened(0.2)))
	result.add_theme_stylebox_override("pressed", _panel_style(background.darkened(0.08), 12, background))
	return result


func _pill(text_value: String, color: Color) -> Label:
	var result := _label(text_value, 11, color)
	result.add_theme_stylebox_override("normal", _panel_style(Color(0.04, 0.07, 0.09, 0.86), 18, Color(1, 1, 1, 0.08)))
	return result


func _panel_style(background: Color, radius: int, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func _spacer(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = height
	return spacer
