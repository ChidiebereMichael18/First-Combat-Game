extends CharacterBody3D

signal died

enum Difficulty { EASY, NORMAL, HARD }
enum Mode { CHASE, SPRINT, RETREAT, STRAFE }

const AIR := 0
const WATER := 1
const EARTH := 2
const FIRE := 3

@export var team := 1                            # 0 = the player's side, 1 = the other side
@export var difficulty: Difficulty = Difficulty.NORMAL
@export_enum("Air", "Water", "Earth", "Fire") var element: int = 3
@export var element_scenes: Array[PackedScene]   # order: air, water, earth, fire
@export var defense_scenes: Array[PackedScene]   # order: air shield, ice wall, earth wall, fire wall
@export var hit_scene: PackedScene               # not used any more, kept so the Inspector keeps working
@export var max_health := 150.0
@export var respawn_after := 4.0                 # seconds after dying; 0 = stay dead
@export var fall_depth := 14.0                   # falling this far below where he spawned = dead
@export var land_ledge_drop := 1.5

const HEAVY_HIT := 18.0   # a single hit this strong knocks him down

# He fights from a distance: closer than NEAR he backs off, farther than FAR he moves in
const NEAR := 11.0
const FAR := 22.0
const SPRINT_DIST := 32.0

# Difficulty settings: Easy, Normal, Hard
#  light_gap = seconds between the steps of a light combo, heavy_gap = seconds between heavy attacks
const DIFF := [
	{"move_speed": 5.0, "react": 0.15, "attack_gap": 3.2, "light_gap": 1.2, "combo_len": 2, "dmg": 0.6, "aim_error": 0.25, "lead": 0.0, "special_gap": 12.0, "heavy_gap": 14.0},
	{"move_speed": 6.5, "react": 0.45, "attack_gap": 2.4, "light_gap": 1.0, "combo_len": 3, "dmg": 1.0, "aim_error": 0.10, "lead": 0.5, "special_gap": 8.0,  "heavy_gap": 9.0},
	{"move_speed": 8.0, "react": 0.80, "attack_gap": 1.5, "light_gap": 0.7, "combo_len": 4, "dmg": 1.3, "aim_error": 0.03, "lead": 0.9, "special_gap": 5.0,  "heavy_gap": 6.0},
]

# Cast clip (special)
const CAST_START := 0.1
const STREAM_START := 0.85
const STREAM_END := 1.6
const VOLLEY_TIME := 1.2
const CAST_END := 2.1

@onready var model: Node3D = $Model
@onready var anim: AnimationPlayer = $Anim
@onready var hand: Node3D = get_node_or_null("%HandMarker")
@onready var foot: Node3D = get_node_or_null("%FootMarker")

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var player: Node3D= null          # his current target: the nearest living fighter on the other team
var health := 100.0
var dead := false
var down := false          # knocked down
var down_immune := 0.0
var frozen := 0.0          # seconds left frozen in ice
var busy := false          # playing a move, dodging, blocking or staggering
var attacking := false     # in the middle of a combo
var guarding := false
var armor := false         # super armor while casting the special
var flipping := false      # the dodge somersault is playing
var move_id := 0           # changes whenever a new move starts (cancels the old one)
var current_anim := ""
var mode := Mode.STRAFE
var attack_cd := 1.5
var special_cd := 3.0
var heavy_cd := 5.0
var guard_cd := 0.0
var dodge_cd := 0.0
var jump_cd := 0.0
var hit_cd := 0.0
var inv := 0.0
var stun := 0.0
var flinch := 0.0
var think_t := 0.0
var retarget_t := 0.0
var strafe_dir := 1.0
var strafe_t := 2.0
var dash_t := 0.0
var dash_vec := Vector3.ZERO
var knock := Vector3.ZERO  # push from hits, fades out by itself
var fire_toggle := false
var spawn_pos := Vector3.ZERO
var kill_y := -1000.0      # below this height he is dead
var hand_fx: Array = []
var ground_y := 0.0        # height of the ground he last stood on
var was_floor := true


func _ready() -> void:
	collision_layer = 1
	collision_mask = 1 | 2
	add_to_group("fighters")
	add_to_group("enemies")
	add_to_group("team_" + str(team))
	set_meta("team", team)
	_check_assets()
	Fx.setup(element_scenes, defense_scenes)
	health = max_health
	spawn_pos = global_position
	ground_y = global_position.y
	kill_y = global_position.y - fall_depth
	for c in ["block", "idle", "run", "walk", "fall"]:
		if anim.has_animation(c):
			anim.get_animation(c).loop_mode = Animation.LOOP_LINEAR
	print("FIGHTER ready | team=", team, " element=", element, " scenes=", element_scenes.size(), " hit clip=", _clip(["hit", "hit_reaction"]), " death clip=", _clip(["death", "die"]))


# Fills any empty slot in the scene lists from your scene files
func _fill(arr: Array[PackedScene], paths: Array, label: String) -> Array[PackedScene]:
	var out: Array[PackedScene] = []
	for i in paths.size():
		var s: PackedScene = null
		if i < arr.size():
			s = arr[i]
		if s == null:
			for p in paths[i]:
				if ResourceLoader.exists(p):
					s = load(p)
					break
		if s == null:
			print("FIGHTER ", label, " slot ", i, " is MISSING")
		out.append(s)
	return out


func _check_assets() -> void:
	element_scenes = _fill(element_scenes, [
		["res://scenes/air_blast.tscn"],
		["res://scenes/water_orb.tscn", "res://scenes/water_orb1.tscn"],
		["res://scenes/rock.tscn"],
		["res://scenes/fireball.tscn"],
	], "ELEMENT")
	defense_scenes = _fill(defense_scenes, [
		["res://scenes/air_shield.tscn"],
		["res://scenes/ice_wall.tscn"],
		["res://scenes/earth_wall.tscn"],
		["res://scenes/firewall.tscn", "res://scenes/fire_wall.tscn"],
	], "DEFENSE")


# The first clip name that exists in his library ("" if none)
func _clip(names: Array) -> String:
	for n in names:
		if anim.has_animation(n):
			return n
	return ""


# ---------- Targets ----------
func _target_ok() -> bool:
	return player != null and is_instance_valid(player) and not player.get("dead")


# The nearest living fighter on the other team
func _pick_target():
	var best = null
	var best_d := INF
	var seen := {}
	for g in ["fighters", "enemies", "player"]:
		for f in get_tree().get_nodes_in_group(g):
			if f == self or seen.has(f) or f.get("dead"):
				continue
			seen[f] = true
			if int(f.get_meta("team", 0)) == team:
				continue
			var d := global_position.distance_to(f.global_position)
			if d < best_d:
				best_d = d
				best = f
	return best


# ---------- Main loop ----------
func _physics_process(delta: float) -> void:
	attack_cd = maxf(0.0, attack_cd - delta)
	special_cd = maxf(0.0, special_cd - delta)
	heavy_cd = maxf(0.0, heavy_cd - delta)
	guard_cd = maxf(0.0, guard_cd - delta)
	dodge_cd = maxf(0.0, dodge_cd - delta)
	jump_cd = maxf(0.0, jump_cd - delta)
	hit_cd = maxf(0.0, hit_cd - delta)
	down_immune = maxf(0.0, down_immune - delta)
	inv = maxf(0.0, inv - delta)
	stun = maxf(0.0, stun - delta)
	flinch = move_toward(flinch, 0.0, delta * 2.5)

	if not is_on_floor():
		velocity.y -= gravity * 1.6 * delta
	else:
		ground_y = global_position.y

	# Fell out of the arena
	if not dead and global_position.y < kill_y:
		print("FIGHTER fell out of the arena")
		health = 0.0
		_die()
		return

	retarget_t -= delta
	if retarget_t <= 0.0 or not _target_ok():
		retarget_t = 0.5
		player = _pick_target()

	# Frozen in ice: can't do anything until it shatters
	if frozen > 0.0 and not dead:
		frozen -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		_slide_with_knock(delta)
		if frozen <= 0.0:
			frozen = 0.0
			anim.speed_scale = 1.0
			busy = false
			current_anim = ""
		return

	if dead or down or not _target_ok():
		velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
		_slide_with_knock(delta)
		_check_landing()
		_update_animation()
		return

	var d: Dictionary = DIFF[difficulty]
	var to := player.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	var dir := to / dist if dist > 0.01 else Vector3.FORWARD
	if dist > 0.1:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(dir.x, dir.z), 10.0 * delta)
	if not flipping:
		model.rotation.x = lerpf(model.rotation.x, -flinch, 14.0 * delta)

	strafe_t -= delta
	if strafe_t <= 0.0:
		strafe_t = randf_range(1.2, 2.8)
		strafe_dir = 1.0 if randf() < 0.5 else -1.0

	# Think a few times a second, only when free to act
	if not busy and not attacking and stun <= 0.0 and dash_t <= 0.0:
		think_t -= delta
		if think_t <= 0.0:
			think_t = 0.12
			_think(dist, d)

	_locomote(delta, dist, dir, d)
	_slide_with_knock(delta)
	_check_landing()
	_update_animation()


# Moves the body, adding the push from hits on top without disturbing normal movement
func _slide_with_knock(delta: float) -> void:
	var saved := velocity
	velocity.x += knock.x
	velocity.z += knock.z
	move_and_slide()
	velocity = Vector3(saved.x, velocity.y, saved.z)
	knock *= exp(-6.0 * delta)


# ---------- Deciding what to do ----------
func _think(dist: float, d: Dictionary) -> void:
	# 1. react to incoming shots: block or dodge
	var threat = _find_threat()
	if threat != null and randf() < float(d["react"]):
		if guard_cd <= 0.0 and randf() < 0.35:
			_guard()
		elif dodge_cd <= 0.0:
			_dodge(threat)
		return
	# 2. special move from a distance
	if special_cd <= 0.0 and dist > 6.0 and dist < 36.0:
		_special()
		return
	# 3. heavy attack
	if heavy_cd <= 0.0 and dist > 8.0 and dist < 32.0:
		_heavy()
		return
	# 4. light combo (his hits are shots, so he attacks from far away)
	if attack_cd <= 0.0 and dist < 34.0:
		_attack()
		return
	# 5. otherwise keep a fighting distance
	if dist > SPRINT_DIST:
		mode = Mode.SPRINT
	elif dist > FAR:
		mode = Mode.CHASE
	elif dist < NEAR:
		mode = Mode.RETREAT
	else:
		mode = Mode.STRAFE


func _locomote(delta: float, dist: float, dir: Vector3, d: Dictionary) -> void:
	if dash_t > 0.0:
		dash_t -= delta
		velocity.x = dash_vec.x
		velocity.z = dash_vec.z
		return

	var side := dir.cross(Vector3.UP) * strafe_dir
	var spd: float = d["move_speed"]
	var accel := spd * 8.0 if is_on_floor() else 22.0
	var wish := Vector3.ZERO
	if guarding or stun > 0.0:
		wish = Vector3.ZERO
	elif attacking:
		wish = side * 0.4          # drift sideways while shooting
		spd = 3.0
		if dist < NEAR - 2.0:
			wish = -dir * 0.7      # back away if you rush him
	elif busy:
		wish = Vector3.ZERO
	else:
		match mode:
			Mode.CHASE:
				wish = dir
			Mode.SPRINT:
				wish = dir
				spd *= 1.6
			Mode.RETREAT:
				wish = -dir
				if is_on_wall():
					wish = side   # cornered: slip sideways
			Mode.STRAFE:
				wish = side
	velocity.x = move_toward(velocity.x, wish.x * spd, accel * delta)
	velocity.z = move_toward(velocity.z, wish.z * spd, accel * delta)

	# Stuck behind something: jump over it and switch sides
	if wish.length() > 0.1 and is_on_wall() and is_on_floor() and jump_cd <= 0.0:
		velocity.y = 8.0
		jump_cd = 0.9
		strafe_dir = -strafe_dir


# ---------- Helpers ----------
func _flat_dist() -> float:
	var to := player.global_position - global_position
	to.y = 0.0
	return to.length()


func _flat_dir_to_player() -> Vector3:
	var to := player.global_position - global_position
	to.y = 0.0
	return to.normalized() if to.length() > 0.01 else Vector3.FORWARD


func _chest_pos(side := 0.0) -> Vector3:
	var aim := _flat_dir_to_player()
	return global_position + Vector3(0, 1.5, 0) + aim * 0.9 + aim.cross(Vector3.UP) * 0.35 * side


func _hand_pos() -> Vector3:
	return hand.global_position if hand != null else _chest_pos()


func _foot_pos() -> Vector3:
	return foot.global_position if foot != null else _chest_pos()


func _aim_at_player(from: Vector3, spd: float) -> Vector3:
	var d: Dictionary = DIFF[difficulty]
	var target_pos: Vector3 = player.global_position + Vector3(0, 1.0, 0)
	var lead := float(d["lead"])
	if lead > 0.0:
		var t := from.distance_to(target_pos) / maxf(spd, 1.0)
		target_pos += player.velocity * t * lead
	var aim := (target_pos - from).normalized()
	var err := float(d["aim_error"])
	return aim.rotated(Vector3.UP, randf_range(-err, err))


# The nearest enemy shot that is flying at us
func _find_threat():
	var best = null
	var best_d := 999.0
	var me := global_position + Vector3(0, 1.0, 0)
	for p in get_tree().get_nodes_in_group("projectiles"):
		if not is_instance_valid(p):
			continue
		var sh = p.shooter
		if sh == self:
			continue
		if is_instance_valid(sh) and int(sh.get_meta("team", -1)) == team:
			continue
		var to_me: Vector3 = me - p.global_position
		var dist := to_me.length()
		if dist > 14.0 or dist < 1.5:
			continue
		if p.direction.dot(to_me.normalized()) < 0.8:
			continue
		if dist < best_d:
			best_d = dist
			best = p
	return best


# One projectile (used by every attack shape)
func _shoot(aim: Vector3, origin: Vector3, dmg: float, size: float, variant := 0, extra := {}) -> void:
	if not _target_ok() or element >= element_scenes.size() or element_scenes[element] == null:
		return
	var d: Dictionary = DIFF[difficulty]
	Bend.spawn(self, element_scenes[element], element, aim, origin, global_position.y, is_on_floor(),
		dmg * float(d["dmg"]), size, variant, extra, player)


# Aimed at the target, with the difficulty's accuracy and prediction
func _aimed(from: Vector3) -> Vector3:
	return _aim_at_player(from, float(Bend.STATS[element]["speed"]))


# ---------- Move runner ----------
func _run_move(clip: String, start: float, end: float, events: Array) -> bool:
	if not anim.has_animation(clip):
		push_warning("Animation not found: " + clip)
		return false
	move_id += 1
	var my := move_id
	var reverse := start > end
	busy = true
	current_anim = clip
	anim.play(clip, 0.08, -1.0 if reverse else 1.0, reverse)
	anim.seek(start, true)

	for e in events:
		await _wait_until(clip, e[0], my, reverse)
		if move_id != my or dead or anim.current_animation != clip:
			return false
		e[1].call()

	await _wait_until(clip, end, my, reverse)
	if move_id != my or dead:
		return false
	busy = false
	current_anim = ""
	return true


func _wait_until(clip: String, t: float, id: int, reverse := false) -> void:
	while id == move_id and not dead and anim.current_animation == clip:
		var p := anim.current_animation_position
		if (reverse and p <= t) or (not reverse and p >= t):
			return
		await get_tree().process_frame


func _busy_for(t: float) -> void:
	move_id += 1
	var my := move_id
	busy = true
	await get_tree().create_timer(t).timeout
	if move_id == my and not dead:
		busy = false
		current_anim = ""


# ---------- Light combo ----------
func _attack() -> void:
	var d: Dictionary = DIFF[difficulty]
	attacking = true
	attack_cd = 99.0
	var steps: int = d["combo_len"]
	for i in steps:
		if dead or down or frozen > 0.0 or not _target_ok():
			break
		var step: Dictionary = Bend.COMBO[i % Bend.COMBO.size()]
		var variant: int = i % Bend.VARIANTS[element].size()
		var events := []
		for r in step["releases"]:
			events.append([r, _step_hit.bind(step, variant)])
		var ok: bool = await _run_move(step["clip"], step["start"], step["end"], events)
		if not ok or not _target_ok() or _flat_dist() > 45.0:
			break
		await get_tree().create_timer(float(d["light_gap"])).timeout     # a pause between steps: no spamming
	attacking = false
	attack_cd = float(d["attack_gap"]) * randf_range(0.8, 1.25)


func _step_hit(step: Dictionary, variant: int) -> void:
	if not _target_ok() or dead:
		return
	var origin := _hand_pos() if step["from"] == "hand" else _foot_pos()
	var st := Bend.step_style(step, element)
	var pat: String = st["pat"]
	# the round burst only reaches close targets; from far away he fans his shots instead
	if pat == "ring" and _flat_dist() > 12.0:
		pat = "fan4"
	Bend.pattern(pat, _aimed(origin), origin, global_position + Vector3(0, 1.2, 0),
		float(step["dmg"]), float(step["size"]), variant, st["extra"], _shoot)


# ---------- Heavy attack ----------
func _heavy() -> void:
	var d: Dictionary = DIFF[difficulty]
	heavy_cd = float(d["heavy_gap"]) * randf_range(0.9, 1.2)
	attack_cd = maxf(attack_cd, 1.5)
	attacking = true
	var h: Dictionary = Bend.HEAVY
	await _run_move(h["clip"], h["start"], h["end"], [[h["release"], _heavy_shot]])
	attacking = false


func _heavy_shot() -> void:
	if not _target_ok() or dead:
		return
	var origin := _hand_pos()
	_shoot(_aimed(origin), origin, float(Bend.HEAVY["dmg"]), float(Bend.HEAVY["size"]), 0, Bend.HEAVY_STYLE[element])


# ---------- Water cast: gather the water (waterBend), then a punch sends it out ----------
func _water_cast(action: Callable) -> void:
	if not anim.has_animation("waterBend"):
		await _run_move("cast2", CAST_START, CAST_END, [[VOLLEY_TIME, action]])
		return
	_water_hands(true)
	var ok: bool = await _run_move("waterBend", Bend.WATERBEND["start"], Bend.WATERBEND["gather"], [])
	if ok and not dead and not down and frozen <= 0.0:
		if anim.has_animation("attack"):
			await _run_move("attack", 0.6, 1.45, [[1.05, action]])
		else:
			action.call()
	_water_hands(false)


func _water_hands(on: bool) -> void:
	for n in hand_fx:
		if is_instance_valid(n):
			n.queue_free()
	hand_fx.clear()
	if not on:
		return
	for h in [hand, get_node_or_null("%HandMarkerL")]:
		if h != null:
			hand_fx.append(Fx.hand_water(h))
	hand_fx.append(Fx.water_float(model))


# ---------- Special ----------
func _special() -> void:
	var d: Dictionary = DIFF[difficulty]
	special_cd = float(d["special_gap"]) * randf_range(0.9, 1.2)
	attack_cd = maxf(attack_cd, 1.0)
	armor = true
	match element:
		AIR:
			await _run_move("cast2", CAST_START, CAST_END, [[VOLLEY_TIME, _air_tornado]])
		WATER:
			await _water_cast(_water_freeze)
		EARTH:
			await _earth_combo()
		FIRE:
			fire_toggle = not fire_toggle
			if fire_toggle:
				var events := []
				var n := 8
				for i in n:
					var t := STREAM_START + i * (STREAM_END - STREAM_START) / float(n - 1)
					var side := 1.0 if i % 2 == 0 else -1.0
					events.append([t, func(): _fire_stream_shot(side)])
				await _run_move("cast2", CAST_START, CAST_END, events)
			else:
				await _run_move("cast2", CAST_START, CAST_END, [[VOLLEY_TIME, _fire_rocket]])
	armor = false


func _fire_stream_shot(side: float) -> void:
	if not _target_ok() or dead:
		return
	var origin := _chest_pos(side)
	_shoot(_aimed(origin), origin, 0.8, 1.0)


func _fire_rocket() -> void:
	if not _target_ok() or dead:
		return
	var origin := _hand_pos()
	_shoot(_aimed(origin), origin, 1.0, 2.4, 0,
		{"speed": 40.0, "damage": 26.0, "knockback": 4.5, "explode": 5.0, "knockdown": true})


func _air_tornado() -> void:
	if not _target_ok() or dead:
		return
	var scene = load("res://scenes/air_tornado_vfx.tscn")
	var vis: Node3D = null
	if scene != null:
		vis = scene.instantiate()
		vis.position = Vector3.ZERO
		Fx.recenter_visual(vis)
		vis.scale = Vector3.ONE * 1.4
	var aim := _flat_dir_to_player()
	var pos := global_position + aim * 5.0
	Zone.create(get_parent(), pos, self, AIR, {
		"duration": 4.0, "radius": 3.0, "height": 6.0, "tick_damage": 9.0 * float(DIFF[difficulty]["dmg"]),
		"pull": 5.0, "lift": 4.5, "move_dir": aim, "move_speed": 5.0, "knockdown_end": true}, vis)


# Water special: ice spikes rise under the target (with a warning, so he can run out) and freeze him
func _water_freeze() -> void:
	if not _target_ok() or dead:
		return
	var pos: Vector3 = player.global_position
	Fx.ring(get_parent(), pos + Vector3(0, 0.08, 0), Color(Fx.COLORS[WATER], 0.7), 2.8, 0.8)
	Zone.create(get_parent(), pos, self, WATER, {
		"delay": 0.8, "duration": 1.0, "radius": 2.6, "height": 5.0,
		"start_damage": 8.0 * float(DIFF[difficulty]["dmg"]), "freeze_time": 2.0, "rise_visual": true}, Fx.ice_spikes())


# Earth: earthBlock or uppercut (random), rocks throw the target up, then a flying kick
func _earth_combo() -> void:
	if not _target_ok():
		return
	var target_pos: Vector3 = player.global_position
	var clip := "uppercut"
	var c_start := 0.0
	var c_peak := 0.30
	var c_end := 0.7
	if anim.has_animation("earthBlock") and (not anim.has_animation("uppercut") or randf() < 0.5):
		clip = "earthBlock"
		c_start = Bend.EARTHBLOCK["start"]
		c_peak = Bend.EARTHBLOCK["peak"]
		c_end = Bend.EARTHBLOCK["end"]
	if not anim.has_animation(clip):
		_earth_lift(target_pos)
		await get_tree().create_timer(0.5).timeout
	else:
		var ok: bool = await _run_move(clip, c_start, c_end, [[c_peak, _earth_lift.bind(target_pos)]])
		if not ok or dead:
			return
	await _flying_kick(target_pos)


func _earth_rock_scene() -> PackedScene:
	if Fx.rock_scenes.size() > 0:
		return Fx.rock_scenes[randi() % Fx.rock_scenes.size()]
	return null


func _earth_lift(pos: Vector3) -> void:
	var vis := Node3D.new()
	var scene := _earth_rock_scene()
	if scene != null:
		for i in 5:
			var rock := Fx.make_rock(scene, randf_range(1.0, 1.8), 1.6)
			var a := TAU * float(i) / 5.0
			rock.position = Vector3(cos(a), 0.0, sin(a)) * 1.3
			rock.rotation.y = randf() * TAU
			vis.add_child(rock)
		var mid := Fx.make_rock(scene, 2.2, 1.8)
		vis.add_child(mid)
	pos.y = global_position.y
	Fx.ring(get_parent(), pos + Vector3(0, 0.08, 0), Color(Fx.COLORS[EARTH], 0.7), 2.6, 0.4)
	Zone.create(get_parent(), pos, self, EARTH, {
		"delay": 0.35, "duration": 1.2, "radius": 2.4, "height": 4.0,
		"launch": 10.0, "knockdown_start": true, "rise_visual": true}, vis)


func _flying_kick(target_pos: Vector3) -> void:
	var to := target_pos - global_position
	to.y = 0.0
	var dist := clampf(to.length(), 4.0, 16.0)
	var dir := to.normalized() if to.length() > 0.1 else Vector3(sin(model.rotation.y), 0.0, cos(model.rotation.y))
	model.rotation.y = atan2(dir.x, dir.z)
	dash_vec = dir * (dist / 0.6)
	dash_t = 0.6
	inv = 0.5
	velocity.y = 5.5
	_run_move("kick", 0.4, 1.25, [])
	await get_tree().create_timer(0.62).timeout
	if dead:
		return
	Fx.explode(get_parent(), global_position, 5.0, 20.0 * float(DIFF[difficulty]["dmg"]), EARTH, self, true)


# ---------- Defense ----------
func _guard() -> void:
	if not _target_ok():
		return
	guard_cd = 4.0
	guarding = true
	move_id += 1
	var my := move_id
	busy = true
	current_anim = "block"
	if anim.has_animation("block"):
		anim.play("block", 0.1)
	if element < defense_scenes.size() and defense_scenes[element] != null:
		_spawn_defense()
	await get_tree().create_timer(randf_range(1.0, 1.8)).timeout
	if move_id == my and not dead:
		guarding = false
		busy = false
		current_anim = ""


func _spawn_defense() -> void:
	if not _target_ok():
		return
	var w = defense_scenes[element].instantiate()
	var aim := _flat_dir_to_player()
	if "owner_node" in w:
		w.owner_node = self
	if "element" in w:
		w.element = element
	get_parent().add_child(w)
	var dist: float = w.get("spawn_distance") if "spawn_distance" in w else 2.5
	w.global_position = global_position + aim * dist
	w.look_at(w.global_position + aim, Vector3.UP)


func _dodge(threat) -> void:
	dodge_cd = 1.2
	var side: Vector3 = threat.direction.cross(Vector3.UP).normalized()
	if randf() < 0.5:
		side = -side
	dash_vec = side * 12.0
	dash_t = 0.3
	inv = 0.4
	velocity.y = 4.0
	model.rotation.y = atan2(side.x, side.z)
	if anim.has_animation("dodge"):
		current_anim = "dodge"
		anim.play("dodge", 0.05)
	else:
		flipping = true
		Fx.flip_body(model, 1.0, get_tree(), 0.42)
		get_tree().create_timer(0.46).timeout.connect(func(): flipping = false)
	_busy_for(0.46)


# ---------- Freeze ----------
func freeze(t: float) -> void:
	if dead or inv > 0.0 or frozen > 0.0:
		return
	frozen = t
	guarding = false
	attacking = false
	armor = false
	flipping = false
	busy = true
	move_id += 1
	_water_hands(false)
	anim.speed_scale = 0.0
	Fx.ice_block(self, t)


# ---------- Health and hit reactions ----------
# A number that floats up from a fighter when he is hit
func _popup(amount: float, he: int) -> void:
	var p := get_parent()
	if p == null:
		return
	var l := Label3D.new()
	l.text = str(int(round(amount)))
	l.font_size = 64
	l.outline_size = 14
	l.pixel_size = 0.01
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.shaded = false
	var c: Color = Fx.COLORS[he] if he >= 0 and he < 4 else Color(1, 1, 1)
	l.modulate = c.lightened(0.3)
	l.outline_modulate = Color(0, 0, 0, 0.9)
	p.add_child(l)
	l.global_position = global_position + Vector3(randf_range(-0.4, 0.4), 2.7, randf_range(-0.2, 0.2))
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "global_position:y", l.global_position.y + 1.5, 0.8)
	tw.tween_property(l, "modulate:a", 0.0, 0.5).set_delay(0.3)
	tw.chain().tween_callback(l.queue_free)


func take_damage(amount: float, from_dir := Vector3.ZERO) -> void:
	if dead or inv > 0.0:
		return
	var he: int = get_meta("hit_element", -1)
	var light: bool = get_meta("hit_light", false)
	set_meta("hit_light", false)
	if guarding:
		amount *= 0.2
		from_dir *= 0.3
	health = maxf(0.0, health - amount)
	print("FIGHTER hit ", snappedf(amount, 0.1), " | hp ", snappedf(health, 0.1), " / ", max_health)
	_popup(amount, he)
	var flat := Vector3(from_dir.x, 0.0, from_dir.z)
	knock += flat * (1.5 if light else 4.5)                # the push
	Fx.flash(model, he, get_tree())
	flinch = 0.25 if light else 0.9                         # leans back (big, because the camera is far)
	if health <= 0.0:
		_die()
	elif frozen > 0.0:
		pass
	elif amount >= HEAVY_HIT and not guarding and not armor and not light:
		knock_down(from_dir)                                # a heavy blast puts him on the ground
	elif not guarding and not armor and not light and not down and hit_cd <= 0.0 and amount >= 4.0:
		# stagger, then a short window where he can't be staggered again
		hit_cd = 1.6
		stun = 0.4
		attacking = false
		if is_on_floor():
			velocity.y = maxf(velocity.y, 3.0)               # a little hop back
		var c := _clip(["hit", "hit_reaction"])
		if c != "":
			current_anim = c
			anim.play(c, 0.05, 1.6)
		_busy_for(0.45)


# Heavy hits: launched backward, land flat, lie there a moment, get back up. Can't happen again for 4 seconds.
func knock_down(dir := Vector3.ZERO) -> void:
	if dead or down or down_immune > 0.0 or inv > 0.0 or frozen > 0.0:
		return
	print("FIGHTER KNOCKED DOWN")
	down = true
	guarding = false
	attacking = false
	armor = false
	busy = true
	move_id += 1
	_water_hands(false)
	var d := Vector3(dir.x, 0.0, dir.z)
	d = d.normalized() if d.length() > 0.01 else -Vector3(sin(model.rotation.y), 0.0, cos(model.rotation.y))
	knock += d * 14.0
	velocity.y = 8.0
	var hc := _clip(["hit", "hit_reaction"])
	if hc != "":
		anim.play(hc, 0.05, 0.7)
	var tw := create_tween()
	tw.tween_property(model, "rotation:x", -1.45, 0.3)       # falls onto his back
	tw.tween_callback(_land_thud)
	tw.tween_interval(1.0)
	tw.tween_property(model, "rotation:x", 0.0, 0.4)         # gets up
	await tw.finished
	down = false
	down_immune = 4.0
	if not dead:
		busy = false
		current_anim = ""


func _land_thud() -> void:
	Fx.ring(get_parent(), global_position + Vector3(0, 0.1, 0), Color(1, 1, 1, 0.6), 2.2, 0.35)


func _die() -> void:
	if dead:
		return
	print("FIGHTER DIED")
	dead = true
	guarding = false
	attacking = false
	armor = false
	flipping = false
	frozen = 0.0
	anim.speed_scale = 1.0
	busy = true
	move_id += 1
	_water_hands(false)
	var c := _clip(["death", "die"])
	if c != "":
		current_anim = c
		anim.play(c, 0.1)
	else:
		create_tween().tween_property(model, "rotation:x", -1.5, 0.4)   # no clip: fall backward
	died.emit()
	if respawn_after > 0.0:
		await get_tree().create_timer(respawn_after).timeout
		_respawn()


func _respawn() -> void:
	health = max_health
	dead = false
	down = false
	busy = false
	attacking = false
	guarding = false
	frozen = 0.0
	inv = 0.0
	current_anim = ""
	velocity = Vector3.ZERO
	knock = Vector3.ZERO
	model.rotation.x = 0.0
	model.position = Vector3.ZERO
	anim.speed_scale = 1.0
	global_position = spawn_pos
	ground_y = spawn_pos.y
	attack_cd = 2.0
	special_cd = 3.0
	heavy_cd = 5.0


# ---------- Animation ----------
func _play(anim_name: String, blend := 0.15, start := 0.0, speed_scale := 1.0) -> void:
	if anim_name == "" or anim_name == current_anim or not anim.has_animation(anim_name):
		return
	current_anim = anim_name
	anim.play(anim_name, blend, speed_scale)
	if start > 0.0:
		anim.seek(start, true)


# Landing: the "landing" clip plays ONLY after dropping onto lower ground than where he took off
func _check_landing() -> void:
	var on := is_on_floor()
	if on and not was_floor:
		var drop := ground_y - global_position.y
		var c := _clip(["landing", "land"])
		if drop >= land_ledge_drop and c != "" and not dead and not down and not attacking and not guarding:
			current_anim = c
			anim.play(c, 0.05)
			velocity.x *= 0.3
			velocity.z *= 0.3
			_busy_for(minf(anim.get_animation(c).length, 0.8))
	was_floor = on


func _update_animation() -> void:
	if dead or down or busy or attacking or stun > 0.0 or frozen > 0.0:
		return
	var horizontal := Vector2(velocity.x, velocity.z).length()
	if not is_on_floor():
		if velocity.y > 0.5:
			_play("jump", 0.08, 0.3, 1.4)
		else:
			_play(_clip(["fall", "idle"]), 0.15)
	elif horizontal > 0.5:
		_play(_clip(["run", "walk"]))
	else:
		_play("idle")
