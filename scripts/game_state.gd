extends Node

const MENU_PATH := "res://scenes/main_menu.tscn"
const FIGHTER_PATH := "res://scenes/fighter.tscn"
const ROUNDS_TO_WIN := 2

# Edit these to your real arena files. Arenas whose file doesn't exist are hidden from the menu.
const ARENAS := [
	{"name": "Arena 1", "path": "res://scenes/arena.tscn"},
	{"name": "Arena 2", "path": "res://scenes/arena2.tscn"},
	{"name": "Arena 3", "path": "res://scenes/arena3.tscn"},
]

var arena_index := 0
var team_size := 1          # fighters per side, 1 to 4
var player_element := 3     # 0 air, 1 water, 2 earth, 3 fire
var difficulty := 1         # 0 easy, 1 normal, 2 hard
var master_volume := 0.8
var quality := 2            # 0 low (phones), 1 medium, 2 high
var menu_start := "title"
var wins := [0, 0]
var round_number := 1


func _ready() -> void:
	load_settings()
	apply_settings()


func available_arenas() -> Array:
	var out: Array = []
	for i in ARENAS.size():
		if ResourceLoader.exists(ARENAS[i]["path"]):
			out.append(i)
	return out


func arena_paths() -> Array:
	var out: Array = []
	for a in ARENAS:
		out.append(a["path"])
	return out


func current_arena_path() -> String:
	return ARENAS[arena_index]["path"]


func reset_match() -> void:
	wins = [0, 0]
	round_number = 1


func apply_settings() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))
	var vp := get_viewport()
	match quality:
		0:
			vp.scaling_3d_scale = 0.67
			vp.msaa_3d = Viewport.MSAA_DISABLED
		1:
			vp.scaling_3d_scale = 0.85
			vp.msaa_3d = Viewport.MSAA_2X
		_:
			vp.scaling_3d_scale = 1.0
			vp.msaa_3d = Viewport.MSAA_2X


func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("settings", "master_volume", master_volume)
	cf.set_value("settings", "quality", quality)
	cf.set_value("choices", "player_element", player_element)
	cf.set_value("choices", "difficulty", difficulty)
	cf.save("user://settings.cfg")


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://settings.cfg") != OK:
		return
	master_volume = cf.get_value("settings", "master_volume", master_volume)
	quality = cf.get_value("settings", "quality", quality)
	player_element = cf.get_value("choices", "player_element", player_element)
	difficulty = cf.get_value("choices", "difficulty", difficulty)
