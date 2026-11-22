extends Control

const ELEMENTS := [
	{"name": "AIR", "desc": "Fast and slippery", "color": Color(0.45, 0.62, 0.82)},
	{"name": "WATER", "desc": "Control and ice", "color": Color(0.2, 0.45, 0.85)},
	{"name": "EARTH", "desc": "Heavy and tough", "color": Color(0.55, 0.42, 0.25)},
	{"name": "FIRE", "desc": "Burst damage", "color": Color(0.85, 0.35, 0.12)},
]
const DIFFICULTIES := ["Easy", "Normal", "Hard"]

var screens := {}
var el_buttons: Array = []
var diff_buttons: Array = []
var quality_buttons: Array = []
var arena_box: VBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var glow := ColorRect.new()
	glow.color = Color(0.85, 0.35, 0.12, 0.10)
	glow.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	glow.offset_top = -260
	add_child(glow)

	_build_title()
	_build_mode()
	_build_arena()
	_build_character()
	_build_settings()
	_show(GameState.menu_start)
	GameState.menu_start = "title"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _screen(name: String, title: String) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	box.add_child(UiKit.label(title, 52 if name == "title" else 40, Color(1.0, 0.8, 0.3)))
	screens[name] = center
	return box


func _show(name: String) -> void:
	for k in screens.keys():
		screens[k].visible = (k == name)
	if name == "arena":
		_refresh_arenas()
	if name == "character":
		_refresh_selection()


# ---------- Title ----------
func _build_title() -> void:
	var box := _screen("title", "ELEMENTAL SHOWDOWN")
	box.add_child(UiKit.label("Air  -  Water  -  Earth  -  Fire", 22, Color(0.8, 0.85, 1.0)))
	box.add_child(Control.new())
	box.add_child(UiKit.button("PLAY", func(): _show("mode"), Color(0.8, 0.3, 0.1), Vector2(340, 74), 32))
	box.add_child(UiKit.button("Settings", func(): _show("settings")))
	if not OS.has_feature("web"):
		box.add_child(UiKit.button("Quit", func(): get_tree().quit(), Color(0.3, 0.12, 0.14)))


# ---------- Mode ----------
func _build_mode() -> void:
	var box := _screen("mode", "CHOOSE A MODE")
	for n in [1, 2, 3, 4]:
		box.add_child(UiKit.button("%d  vs  %d" % [n, n], _pick_mode.bind(n), Color(0.17, 0.21, 0.31), Vector2(340, 66), 28))
	box.add_child(UiKit.label("3v3 and 4v4 can run slowly on phones", 18, Color(0.7, 0.7, 0.75)))
	box.add_child(UiKit.button("Back", func(): _show("title"), Color(0.25, 0.25, 0.3), Vector2(340, 56), 22))


func _pick_mode(n: int) -> void:
	GameState.team_size = n
	_show("arena")


# ---------- Arena ----------
func _build_arena() -> void:
	arena_box = _screen("arena", "CHOOSE AN ARENA")


func _refresh_arenas() -> void:
	# keep the title, rebuild the rest
	while arena_box.get_child_count() > 1:
		var c := arena_box.get_child(1)
		arena_box.remove_child(c)
		c.queue_free()
	var avail := GameState.available_arenas()
	if avail.is_empty():
		arena_box.add_child(UiKit.label("No arena files found. Edit ARENAS in game_state.gd", 20, Color(1, 0.5, 0.5)))
	for i in avail:
		arena_box.add_child(UiKit.button(GameState.ARENAS[i]["name"], _pick_arena.bind(i), Color(0.17, 0.21, 0.31), Vector2(340, 70), 28))
	arena_box.add_child(UiKit.button("Back", func(): _show("mode"), Color(0.25, 0.25, 0.3), Vector2(340, 56), 22))


func _pick_arena(i: int) -> void:
	GameState.arena_index = i
	_show("character")


# ---------- Character ----------
func _build_character() -> void:
	var box := _screen("character", "CHOOSE YOUR ELEMENT")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	for i in ELEMENTS.size():
		var e: Dictionary = ELEMENTS[i]
		var b := UiKit.button("%s\n%s" % [e["name"], e["desc"]], _pick_element.bind(i), e["color"], Vector2(200, 150), 22)
		row.add_child(b)
		el_buttons.append(b)
	box.add_child(UiKit.label("Difficulty", 24))
	var drow := HBoxContainer.new()
	drow.add_theme_constant_override("separation", 12)
	drow.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(drow)
	for i in DIFFICULTIES.size():
		var b := UiKit.button(DIFFICULTIES[i], _pick_difficulty.bind(i), Color(0.17, 0.21, 0.31), Vector2(150, 54), 22)
		drow.add_child(b)
		diff_buttons.append(b)
	box.add_child(UiKit.button("START MATCH", _start, Color(0.8, 0.3, 0.1), Vector2(340, 74), 30))
	box.add_child(UiKit.button("Back", func(): _show("arena"), Color(0.25, 0.25, 0.3), Vector2(340, 52), 22))


func _pick_element(i: int) -> void:
	GameState.player_element = i
	_refresh_selection()


func _pick_difficulty(i: int) -> void:
	GameState.difficulty = i
	_refresh_selection()


func _refresh_selection() -> void:
	for i in el_buttons.size():
		el_buttons[i].modulate = Color(1, 1, 1) if i == GameState.player_element else Color(0.55, 0.55, 0.6)
	for i in diff_buttons.size():
		diff_buttons[i].modulate = Color(1, 1, 1) if i == GameState.difficulty else Color(0.55, 0.55, 0.6)


func _start() -> void:
	GameState.save_settings()
	MatchManager.start_match()


# ---------- Settings ----------
func _build_settings() -> void:
	var box := _screen("settings", "SETTINGS")
	box.add_child(UiKit.label("Volume", 24))
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = GameState.master_volume
	s.custom_minimum_size = Vector2(340, 30)
	s.value_changed.connect(func(v: float):
		GameState.master_volume = v
		GameState.apply_settings())
	box.add_child(s)
	box.add_child(UiKit.label("Graphics quality (Low for phones)", 24))
	var qrow := HBoxContainer.new()
	qrow.add_theme_constant_override("separation", 12)
	qrow.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(qrow)
	for i in 3:
		var b := UiKit.button(["Low", "Medium", "High"][i], _pick_quality.bind(i), Color(0.17, 0.21, 0.31), Vector2(110, 52), 22)
		qrow.add_child(b)
		quality_buttons.append(b)
	_refresh_quality()
	box.add_child(UiKit.button("Back", _settings_back, Color(0.25, 0.25, 0.3), Vector2(340, 56), 22))


func _pick_quality(i: int) -> void:
	GameState.quality = i
	GameState.apply_settings()
	_refresh_quality()


func _refresh_quality() -> void:
	for i in quality_buttons.size():
		quality_buttons[i].modulate = Color(1, 1, 1) if i == GameState.quality else Color(0.55, 0.55, 0.6)


func _settings_back() -> void:
	GameState.save_settings()
	_show("title")
