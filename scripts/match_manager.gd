extends Node

const ELEMENT_NAMES := ["Air", "Water", "Earth", "Fire"]

var match_active := false
var in_arena := false
var arena_ready := false
var round_over := false
var match_over := false
var _scene_id := 0
var _check_t := 0.0
var _round_time := 0.0

var layer: CanvasLayer
var hud: Control
var top_label: Label
var banner: Label
var pause_panel: Control
var result_panel: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = CanvasLayer.new()
	layer.layer = 50
	add_child(layer)

	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.visible = false
	layer.add_child(hud)

	top_label = UiKit.label("", 24)
	top_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top_label.offset_top = 8
	top_label.offset_bottom = 46
	top_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(top_label)

	banner = UiKit.label("", 76)
	banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.offset_bottom = -140
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.modulate.a = 0.0
	hud.add_child(banner)

	pause_panel = _overlay("PAUSED", "", [
		["Resume", _toggle_pause],
		["Restart round", _restart_round],
		["Change arena", go_menu.bind("arena")],
		["Main menu", go_menu.bind("title")],
	])
	pause_panel.visible = false
	layer.add_child(pause_panel)


# ---------- Starting and leaving matches ----------
func start_match() -> void:
	match_active = true
	match_over = false
	round_over = false
	GameState.reset_match()
	get_tree().paused = false
	get_tree().change_scene_to_file(GameState.current_arena_path())


func go_menu(start := "title") -> void:
	match_active = false
	in_arena = false
	arena_ready = false
	get_tree().paused = false
	pause_panel.visible = false
	_clear_result()
	hud.visible = false
	GameState.menu_start = start
	get_tree().change_scene_to_file(GameState.MENU_PATH)


func _restart_round() -> void:
	get_tree().paused = false
	pause_panel.visible = false
	round_over = false
	get_tree().change_scene_to_file(GameState.current_arena_path())


func _rematch() -> void:
	_clear_result()
	match_over = false
	round_over = false
	GameState.reset_match()
	get_tree().change_scene_to_file(GameState.current_arena_path())


func _toggle_pause() -> void:
	if not in_arena or match_over:
		return
	get_tree().paused = not get_tree().paused
	pause_panel.visible = get_tree().paused


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and in_arena:
		_toggle_pause()


# ---------- Watching for the arena to load ----------
func _process(delta: float) -> void:
	var sc := get_tree().current_scene
	if sc != null and sc.get_instance_id() != _scene_id:
		_scene_id = sc.get_instance_id()
		_on_scene_changed(sc)
	if match_active and in_arena and arena_ready and not round_over:
		_round_time += delta
		_check_t += delta
		if _check_t >= 0.25:
			_check_t = 0.0
			_check_round()


func _on_scene_changed(sc: Node) -> void:
	in_arena = match_active and sc.scene_file_path in GameState.arena_paths()
	hud.visible = in_arena
	arena_ready = false
	round_over = false
	_round_time = 0.0
	if not in_arena:
		return
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(sc) or get_tree().current_scene != sc:
		return
	_setup_teams(sc)
	arena_ready = true
	_banner("ROUND %d" % GameState.round_number, Color(1, 1, 1), 1.0)
	await get_tree().create_timer(1.0).timeout
	if in_arena:
		_banner("FIGHT!", Color(1.0, 0.7, 0.2), 0.9)


# ---------- Building the teams ----------
func _setup_teams(scene: Node) -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		print("MATCH: no player found in the arena")
		return
	var size := GameState.team_size

	# your element
	player._set_element(GameState.player_element)
	player.set_meta("team", 0)
	_mark(player, true)

	# the fighters already in the arena
	var existing: Array = []
	for f in get_tree().get_nodes_in_group("fighters"):
		if f != player and not existing.has(f):
			existing.append(f)
	var template_path := GameState.FIGHTER_PATH
	if existing.size() > 0 and existing[0].scene_file_path != "":
		template_path = existing[0].scene_file_path
	var base0: Vector3 = player.global_position
	var base1: Vector3 = existing[0].global_position if existing.size() > 0 else base0 + Vector3(0, 0, -18)
	var line := base1 - base0
	line.y = 0.0
	var side := line.cross(Vector3.UP)
	side = side.normalized() if side.length() > 0.01 else Vector3.RIGHT

	var exclude: Array = [player]
	exclude.append_array(existing)

	# enemies: keep the first `size` existing fighters, remove extras, add what is missing
	var enemy_elements := _pick_elements(size, -1)
	var enemies: Array = []
	for i in existing.size():
		if i < size:
			enemies.append(existing[i])
		else:
			existing[i].queue_free()
	while enemies.size() < size:
		var k := enemies.size()
		var pos := _spot(base1, side, _offset(k), exclude)
		var nf = _spawn(template_path, scene, 1, pos, base0)
		if nf == null:
			break
		enemies.append(nf)
		exclude.append(nf)
	for i in enemies.size():
		_configure(enemies[i], 1, enemy_elements[i % enemy_elements.size()])
		_mark(enemies[i], false)

	# allies
	var ally_elements := _pick_elements(maxi(size - 1, 0), GameState.player_element)
	for i in size - 1:
		var pos := _spot(base0, side, _offset(i + 1), exclude)
		var af = _spawn(template_path, scene, 0, pos, base1)
		if af == null:
			break
		exclude.append(af)
		_configure(af, 0, ally_elements[i % ally_elements.size()])
		_mark(af, true)

	print("MATCH: ", size, " v ", size, " | arena=", scene.scene_file_path, " | you are ", ELEMENT_NAMES[GameState.player_element])


# 0, +3, -3, +6 ... lateral offsets for the k-th fighter of a team
func _offset(k: int) -> float:
	if k == 0:
		return 0.0
	var step := float((k + 1) / 2) * 3.0
	return step if k % 2 == 1 else -step


# n different elements, starting with the ones other than `avoid`
func _pick_elements(n: int, avoid: int) -> Array:
	var pool: Array = [0, 1, 2, 3]
	pool.shuffle()
	if avoid >= 0:
		pool.erase(avoid)
		pool.append(avoid)
	var out: Array = []
	for i in n:
		out.append(pool[i % pool.size()])
	if out.is_empty():
		out.append(3)
	return out


func _configure(f: Node, team: int, element: int) -> void:
	f.set("element", element)
	f.set("difficulty", GameState.difficulty)
	f.set("respawn_after", 0.0)
	f.set("team", team)
	f.set_meta("team", team)
	for g in ["team_0", "team_1"]:
		if f.is_in_group(g):
			f.remove_from_group(g)
	f.add_to_group("team_" + str(team))


func _spawn(path: String, scene: Node, team: int, pos: Vector3, look_at_pos: Vector3) -> Node:
	if not ResourceLoader.exists(path):
		print("MATCH: fighter scene missing: ", path)
		return null
	var ps: PackedScene = load(path)
	var f = ps.instantiate()
	f.set("team", team)
	f.set("respawn_after", 0.0)
	var local_pos := pos
	if scene is Node3D:
		local_pos = (scene as Node3D).to_local(pos)
	f.position = local_pos
	scene.add_child(f)
	var d := look_at_pos - pos
	d.y = 0.0
	var m = f.get_node_or_null("Model")
	if m != null and d.length() > 0.01:
		m.rotation.y = atan2(d.x, d.z)
	return f


# The floor under a wanted spot (falls back toward the base if there is no floor there)
func _spot(base: Vector3, side: Vector3, offset: float, exclude: Array) -> Vector3:
	for o in [offset, offset * 0.5, 0.0]:
		var p := _ground(base + side * o, exclude)
		if p != Vector3.INF:
			return p
	return base


func _ground(p: Vector3, exclude: Array) -> Vector3:
	var space := get_viewport().world_3d.direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 4, 0), p + Vector3(0, -8, 0), 1)
	var ex: Array[RID] = []
	for n in exclude:
		if is_instance_valid(n) and n is CollisionObject3D:
			ex.append(n.get_rid())
	q.exclude = ex
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return Vector3.INF
	return hit["position"] + Vector3(0, 0.15, 0)


# A colored ring under a fighter: green = your team, red = the other team
func _mark(f: Node3D, ally: bool) -> void:
	var old := f.get_node_or_null("TeamRing")
	if old != null:
		old.queue_free()
	var m := MeshInstance3D.new()
	m.name = "TeamRing"
	var c := CylinderMesh.new()
	c.top_radius = 0.95
	c.bottom_radius = 0.95
	c.height = 0.03
	m.mesh = c
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.3, 0.9, 0.45, 0.5) if ally else Color(1.0, 0.25, 0.25, 0.5)
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.position = Vector3(0, 0.05, 0)
	f.add_child(m)


# ---------- Rounds ----------
func _check_round() -> void:
	var alive := [0, 0]
	for f in get_tree().get_nodes_in_group("fighters"):
		if not is_instance_valid(f) or f.get("dead"):
			continue
		var t := int(f.get_meta("team", 1))
		if t == 0 or t == 1:
			alive[t] += 1
	top_label.text = "YOUR TEAM  %d     Round %d  (%d - %d)     ENEMIES  %d" % [alive[0], GameState.round_number, GameState.wins[0], GameState.wins[1], alive[1]]
	if _round_time < 3.0:
		return
	if alive[0] == 0 or alive[1] == 0:
		_end_round(alive)


func _end_round(alive: Array) -> void:
	round_over = true
	var winner := -1
	if alive[1] == 0 and alive[0] > 0:
		winner = 0
	elif alive[0] == 0 and alive[1] > 0:
		winner = 1
	if winner >= 0:
		GameState.wins[winner] += 1
	var txt := "ROUND WON" if winner == 0 else ("ROUND LOST" if winner == 1 else "DRAW")
	var col := Color(0.4, 1.0, 0.5) if winner == 0 else (Color(1.0, 0.35, 0.35) if winner == 1 else Color(1, 1, 1))
	_banner(txt, col, 2.4)
	await get_tree().create_timer(2.6).timeout
	if not match_active or not in_arena:
		return
	if GameState.wins[0] >= GameState.ROUNDS_TO_WIN or GameState.wins[1] >= GameState.ROUNDS_TO_WIN:
		_show_result(GameState.wins[0] > GameState.wins[1])
	else:
		GameState.round_number += 1
		round_over = false
		get_tree().change_scene_to_file(GameState.current_arena_path())


func _show_result(win: bool) -> void:
	match_over = true
	_clear_result()
	var sub := "Final score  %d - %d" % [GameState.wins[0], GameState.wins[1]]
	result_panel = _overlay("VICTORY!" if win else "DEFEAT", sub, [
		["Rematch", _rematch],
		["Change arena", go_menu.bind("arena")],
		["Main menu", go_menu.bind("title")],
	])
	layer.add_child(result_panel)


func _clear_result() -> void:
	if result_panel != null and is_instance_valid(result_panel):
		result_panel.queue_free()
	result_panel = null


# ---------- UI helpers ----------
func _banner(text: String, color: Color, time: float) -> void:
	banner.text = text
	banner.add_theme_color_override("font_color", color)
	banner.modulate.a = 1.0
	banner.scale = Vector2.ONE
	banner.pivot_offset = banner.size * 0.5
	var tw := create_tween()
	tw.tween_interval(maxf(time - 0.5, 0.1))
	tw.tween_property(banner, "modulate:a", 0.0, 0.5)


func _overlay(title: String, subtitle: String, buttons: Array) -> Control:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	box.add_child(UiKit.label(title, 64, Color(1.0, 0.8, 0.3)))
	if subtitle != "":
		box.add_child(UiKit.label(subtitle, 28))
	for b in buttons:
		box.add_child(UiKit.button(b[0], b[1]))
	return dim
