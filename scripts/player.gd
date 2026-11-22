extends CharacterBody3D

signal health_changed(value: float)

# ---------- Settings (editable in the Inspector) ----------
@export var speed := 7.0
@export var slide_speed := 13.0          # speed while sliding (hold Shift while moving)
@export var jump_velocity := 6.5
@export var gravity_mult := 1.6
@export var jump_skip := 0.3             # seconds of the jump clip to skip
@export var jump_speed_mult := 1.0       # playback speed of the jump clip
@export var flip_speed_mult := 1.10
@export var air_shot_delay := 0.25       # seconds between shots while flipping
@export var max_health := 300.0
@export var element_scenes: Array[PackedScene]   # order: air, water, earth, fire
@export var defense_scenes: Array[PackedScene]   # order: air shield, ice wall, earth wall, fire wall
@export var combo_reset := 2.2                   # seconds of pause before the light chain restarts
@export var light_cooldown := 0.2              # left click / J: seconds after the shot leaves before the next attack
@export var heavy_cooldown := 2.0                # right click / H
@export var uppercut_start := 0.0
@export var uppercut_peak := 0.35   # when the fist is highest: the rocks appear here
@export var uppercut_end := 0.9
@export var face_mouse_always := false           # true = body always faces aim direction, even while running

# Element lift (third Space press; Earth cannot lift)
@export var lift_height := 5.0
@export var lift_hover_time := 4.0
@export var lift_speed := 8.0
@export var descend_speed := 6.0
@export var land_ledge_drop := 1.5       # kept for inspector compatibility

# Camera: mouse controls yaw/pitch so you always see clearly
@export var cam_yaw_deg := 0.0
@export var cam_pitch_deg := -22.0
@export var cam_min_dist := 3.0
@export var cam_max_dist := 6.0

# Dodge (move + Mouse Thumb1 or Q): quick dash without leaving your mouse hand
@export var dodge_speed := 10.5
@export var dodge_duration := 0.30
@export var dodge_cooldown := 0.9

# Cast clip (special)
@export var cast_start := 0.1
@export var stream_start := 0.85
@export var stream_end := 1.6
@export var volley_time := 1.2
@export var cast_end := 2.1
@export var special_cooldown := 5.0
@export var wall_cooldown := 2.0

# Kept for inspector compatibility
@export var hit_scene: PackedScene
@export var fixed_camera := false
@export var mouse_sens := 0.003
@export var cam_turn_speed := 2.0
@export var aim_assist_deg := 0.0
@export var land_min_drop := 1.0

# Element numbers used everywhere in this script
const AIR := 0
const WATER := 1
const EARTH := 2
const FIRE := 3

const HEAVY_HIT := 18.0   # a single hit this strong (after blocking) knocks you down

var shake := 0.0
@onready var cam: Camera3D = $CameraPivot/SpringArm3D/Camera3D

# ---------- Node references ----------
@onready var pivot: Node3D = $CameraPivot
@onready var spring: SpringArm3D = $CameraPivot/SpringArm3D
@onready var model: Node3D = $Model
@onready var anim: AnimationPlayer = $Anim
@onready var hand: Node3D = %HandMarker
@onready var foot: Node3D = get_node_or_null("%FootMarker")
@onready var health_bar: ProgressBar = $HUD/HealthBar

# ---------- State ----------
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var jumps := 0                   # 0 = on the ground, 1 = jumped, 2 = double-jumped
var jumping := false             # true while mid-jump in the air
var busy := false
var flipping := false            # the double-jump flip is playing
var flip_busy := false           # fallback flip is playing
var current_anim := ""
var floor_y := 0.0               # height of the ground you last stood on
var health := 100.0
var dead := false
var down := false                # knocked down (falling -> lying -> rising)
var down_immune := 0.0           # can't be knocked down again for a few seconds
var frozen := 0.0                # seconds left frozen in ice
var hit_cd := 0.0
var flinch := 0.0                # leans the body back when hit
var element := 0
var element_names := ["Air", "Water", "Earth", "Fire"]
var element_label := Label.new()
var move_id := 0                 # increases every time a new move starts (cancels the old one)
var guarding := false
var special_cd := 0.0
var wall_cd := 0.0
var light_cd := 0.0
var heavy_cd := 0.0
var air_shot_cd := 0.0
var fire_toggle := false         # fire special alternates between stream and rocket
var knock := Vector3.ZERO        # push from hits, fades out by itself
var inv := 0.0                   # invulnerable time left (dodge)
var dodge_cd := 0.0
var dodge_t := 0.0
var dodge_vec := Vector3.ZERO
var hand_fx: Array = []          # water in the hands and floating in front during water moves

var cam_yaw := 0.0
var cam_pitch := -22.0

# Sliding (hold Shift while moving)
var gliding := false
var slide_fx = null
var ride_lift := 0.0             # how high the character is raised while riding

# Element lift
var lift_on := false             # rising or hovering
var lift_down := false           # being lowered
var lift_used := false
var lift_t := 0.0
var lift_base := 0.0
var lift_fx: Node3D = null
var landed_from_lift := false

# Landing
var was_floor := true
var landing_busy := false

# Light combo state
var combo_index := 0
var step_variant := 0
var in_combo := false
var last_step_end_ms := 0


func _ready() -> void:
	collision_layer = 1
	collision_mask = 1 | 2           # the floor and the shield walls
	add_to_group("player")
	_check_assets()
	Fx.setup(element_scenes, defense_scenes)
	anim.animation_finished.connect(_on_anim_finished)
	health = max_health
	health_bar.max_value = max_health
	health_bar.value = health
	health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Looping clips
	for c in ["block", "idle", "run", "walk"]:
		if anim.has_animation(c):
			anim.get_animation(c).loop_mode = Animation.LOOP_LINEAR

	# One-shot clips
	for c in ["jump", "Jump", "fall", "Fall", "rise", "Rise", "death", "Death", "die", "dodge", "Roll", "roll", "flip"]:
		if anim.has_animation(c):
			anim.get_animation(c).loop_mode = Animation.LOOP_NONE

	element_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	element_label.position = Vector2(20, 52)
	element_label.add_theme_font_size_override("font_size", 20)
	$HUD.add_child(element_label)
	_update_element_label()

	# Mouse controls camera look smoothly; press Esc or Tab to toggle cursor
	cam_yaw = deg_to_rad(cam_yaw_deg)
	cam_pitch = cam_pitch_deg
	pivot.top_level = true
	pivot.global_position = global_position + Vector3(0, 1, 0)
	pivot.rotation = Vector3(0.0, cam_yaw, 0.0)
	spring.rotation = Vector3(deg_to_rad(cam_pitch), 0.0, 0.0)
	spring.collision_mask = 0
	spring.spring_length = cam_min_dist
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# Fills any empty slot in the scene lists from your scene files, and prints what it found
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
			print(label, " slot ", i, " is MISSING - tell me the real file name for it")
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


func _clip(names: Array) -> String:
	for n in names:
		if anim.has_animation(n):
			return n
	return ""


# ---------- Aim & Camera Direction ----------
func _facing() -> Vector3:
	return Vector3(sin(model.rotation.y), 0.0, cos(model.rotation.y))


func _aim_direction() -> Vector3:
	var e := _nearest_enemy()
	if e != null:
		var to_e := e.global_position - global_position
		to_e.y = 0.0
		var cam_fwd := -cam.global_transform.basis.z
		cam_fwd.y = 0.0
		if to_e.length() > 0.2 and cam_fwd.length() > 0.01:
			# Gently snap toward nearby enemy in front of camera if aimed close
			if to_e.normalized().dot(cam_fwd.normalized()) > 0.65:
				return to_e.normalized()
	var fwd := -pivot.global_basis.z
	fwd.y = 0.0
	return fwd.normalized() if fwd.length() > 0.01 else _facing()


func _target_point(maxd := 25.0) -> Vector3:
	var e := _nearest_enemy()
	if e != null and global_position.distance_to(e.global_position) <= maxd:
		return e.global_position
	var fwd := -pivot.global_basis.z
	fwd.y = 0.0
	if fwd.length() < 0.01:
		fwd = _facing()
	return global_position + fwd.normalized() * minf(10.0, maxd)


func _smart_aim(from_pos: Vector3) -> Vector3:
	var base := _aim_direction()
	var e := _nearest_enemy()
	if e != null:
		var aim_pt := e.global_position + Vector3(0, 1.0, 0)
		var d := aim_pt - from_pos
		if d.length() > 0.1:
			return d.normalized()
	if is_on_floor() and not _lifted():
		return base
	return Vector3(base.x, -0.2, base.z).normalized()


func _face(d: Vector3, rate: float, delta: float) -> void:
	if d.length() < 0.01:
		return
	model.rotation.y = lerp_angle(model.rotation.y, atan2(d.x, d.z), rate * delta)


# ---------- Input (Mouse Look + Left/Right Click + Dodge + Abilities) ----------
# ---------- Input (Mouse Look + Left/Right Click + Dodge + Abilities) ----------
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		cam_yaw -= event.relative.x * mouse_sens
		cam_pitch = clampf(cam_pitch - event.relative.y * mouse_sens * 55.0, -65.0, 12.0)
		pivot.rotation = Vector3(0.0, cam_yaw, 0.0)
		spring.rotation = Vector3(deg_to_rad(cam_pitch), 0.0, 0.0)

	if event is InputEventKey and not event.echo:
		if event.pressed:
			match event.physical_keycode:
				KEY_1: _set_element(AIR)
				KEY_2: _set_element(WATER)
				KEY_3: _set_element(EARTH)
				KEY_4: _set_element(FIRE)
				KEY_H: _heavy()
				KEY_K: _special()
				KEY_F: _guard_start()
				KEY_Q: _dodge()
				KEY_ESCAPE, KEY_TAB:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
				KEY_R:
					if dead:
						get_tree().reload_current_scene()
		elif event.physical_keycode == KEY_F:
			_guard_end()

	if event is InputEventMouseButton:
		if event.pressed:
			if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			match event.button_index:
				MOUSE_BUTTON_LEFT:
					_attack()
				MOUSE_BUTTON_RIGHT:
					_heavy()
				MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2:
					_dodge()

func _aim_world_point(max_dist := 35.0) -> Vector3:
	if cam == null:
		return _target_point(max_dist)
	var from := cam.global_position
	var dir := -cam.global_transform.basis.z.normalized()
	var to := from + dir * max_dist
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1 | 2
	var exclude: Array[RID] = [get_rid()]
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is CollisionObject3D:
			exclude.append(e.get_rid())
	query.exclude = exclude
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		return hit["position"]
	return to

func add_shake(amount: float) -> void:
	shake = maxf(shake, amount)


func on_hit_landed(dmg: float) -> void:
	add_shake(clampf(dmg * 0.01, 0.03, 0.18))


func _physics_process(delta: float) -> void:
	shake = move_toward(shake, 0.0, delta * 1.2)
	cam.h_offset = randf_range(-1.0, 1.0) * shake
	cam.v_offset = randf_range(-1.0, 1.0) * shake
	_update_camera_follow(delta)
	special_cd = maxf(0.0, special_cd - delta)
	wall_cd = maxf(0.0, wall_cd - delta)
	light_cd = maxf(0.0, light_cd - delta)
	heavy_cd = maxf(0.0, heavy_cd - delta)
	air_shot_cd = maxf(0.0, air_shot_cd - delta)
	dodge_cd = maxf(0.0, dodge_cd - delta)
	hit_cd = maxf(0.0, hit_cd - delta)
	down_immune = maxf(0.0, down_immune - delta)
	inv = maxf(0.0, inv - delta)
	flinch = move_toward(flinch, 0.0, delta * 2.5)

	if dead:
		_apply_gravity(delta)
		velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
		_slide_with_knock(delta)
		return

	if frozen > 0.0:
		frozen -= delta
		_apply_gravity(delta)
		velocity.x = 0.0
		velocity.z = 0.0
		_slide_with_knock(delta)
		if frozen <= 0.0:
			frozen = 0.0
			anim.speed_scale = 1.0
			busy = false
			jumping = false
			current_anim = ""
		return

	_apply_gravity(delta)
	_handle_jump()
	_handle_lift(delta)
	_handle_slide()
	if Input.is_action_just_pressed("attack"):
		_attack()
	_move(delta)
	_slide_with_knock(delta)
	_check_landing()
	_update_animation()


func _slide_with_knock(delta: float) -> void:
	var saved := velocity
	velocity.x += knock.x
	velocity.z += knock.z
	move_and_slide()
	velocity = Vector3(saved.x, velocity.y, saved.z)
	knock *= exp(-6.0 * delta)


func _update_camera_follow(delta: float) -> void:
	var focus := global_position + Vector3(0.0, 1.35, 0.0)
	pivot.global_position = pivot.global_position.lerp(focus, 1.0 - exp(-12.0 * delta))
	var e := _nearest_enemy()
	var dist := cam_min_dist
	if e != null:
		var sep := global_position.distance_to(e.global_position)
		dist = clampf(cam_min_dist + sep * 0.25, cam_min_dist, cam_max_dist)
	spring.spring_length = lerpf(spring.spring_length, dist, 1.0 - exp(-5.0 * delta))


# ---------- Physics ----------
func _lifted() -> bool:
	return lift_on or lift_down


func _apply_gravity(delta: float) -> void:
	if _lifted():
		return
	if is_on_floor() and velocity.y <= 0.0:
		jumps = 0
		jumping = false
		lift_used = false
		floor_y = global_position.y
	else:
		velocity.y -= gravity * gravity_mult * delta


func _handle_jump() -> void:
	if guarding or down or flip_busy or landing_busy:
		return
	if not Input.is_action_just_pressed("jump"):
		return
	if _lifted():
		lift_on = false
		lift_down = true
		return
	if is_on_floor() and not jumping:
		_stop_glide()
		_cancel_combo()
		velocity.y = jump_velocity
		jumps = 1
		jumping = true
		flipping = false
		busy = false
		var j_clip := _clip(["jump", "Jump"])
		if j_clip != "":
			var a := anim.get_animation(j_clip)
			a.loop_mode = Animation.LOOP_NONE
			current_anim = j_clip
			anim.play(j_clip, 0.0, jump_speed_mult)
			if jump_skip > 0.0:
				anim.seek(jump_skip, true)
	elif jumps == 1:
		_cancel_combo()
		jumping = false
		velocity.y = jump_velocity * 0.95
		jumps = 2
		_start_flip()
	elif jumps >= 2 and not lift_used and element != EARTH:
		jumping = false
		_start_lift()


func _move(delta: float) -> void:
	if down:
		velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)
		return

	if dodge_t > 0.0:
		dodge_t -= delta
		velocity.x = dodge_vec.x
		velocity.z = dodge_vec.z
		if dodge_t <= 0.0 and busy and current_anim in ["dodge", "Roll", "roll"]:
			busy = false
			current_anim = ""
		return

	var input := Input.get_vector("left", "right", "forward", "back")
	var cam_basis := Basis(Vector3.UP, cam_yaw)
	var dir := cam_basis * Vector3(input.x, 0.0, input.y)
	dir.y = 0.0
	dir = dir.normalized()
	var moving := dir.length() > 0.1
	var spd := 0.0 if guarding else speed
	var accel := speed * 8.0 if is_on_floor() else 22.0
	if gliding:
		spd = slide_speed
		accel = 14.0
	elif _lifted():
		spd = speed * 0.8
	velocity.x = move_toward(velocity.x, dir.x * spd, accel * delta)
	velocity.z = move_toward(velocity.z, dir.z * spd, accel * delta)

	if not flip_busy:
		if guarding:
			_face(_aim_direction(), 14.0, delta)
		elif not busy:
			if gliding or (moving and not face_mouse_always):
				_face(dir, 7.0 if gliding else 16.0, delta)
			else:
				_face(_aim_direction(), 14.0, delta)
		var lean := (0.3 if gliding else 0.0) - flinch
		model.rotation.x = lerpf(model.rotation.x, lean, 14.0 * delta)
		model.position.y = lerpf(model.position.y, ride_lift if gliding else 0.0, 10.0 * delta)


# ---------- Element lift ----------
func _handle_lift(delta: float) -> void:
	if not _lifted():
		return
	if down or dead or flip_busy:
		_end_lift()
		return
	lift_t += delta
	if lift_on:
		if global_position.y < lift_base + lift_height - 0.05:
			velocity.y = lift_speed
		else:
			velocity.y = 0.0
		if lift_t >= lift_hover_time:
			lift_on = false
			lift_down = true
			_dissolve_lift_fx()
	if lift_down:
		velocity.y = -descend_speed
		if is_on_floor():
			_end_lift()
			return
	_update_lift_fx()


func _start_lift() -> void:
	if element >= element_scenes.size() or element_scenes[element] == null:
		return
	flipping = false
	jumping = false
	busy = false
	current_anim = ""
	lift_on = true
	lift_down = false
	lift_used = true
	landed_from_lift = true
	lift_t = 0.0
	lift_base = floor_y
	_stop_glide()
	_cancel_combo()
	_build_lift_fx()
	Fx.ring(get_parent(), Vector3(global_position.x, lift_base + 0.08, global_position.z), Color(Fx.COLORS[element], 0.55), 2.2, 0.35)
	add_shake(0.1)


func _build_lift_fx() -> void:
	_free_lift_fx()
	var parent := get_parent()
	match element:
		AIR:
			var t := Fx.tornado_under()
			if t != null:
				lift_fx = t
				parent.add_child(t)
		WATER:
			lift_fx = Fx.water_column()
			parent.add_child(lift_fx)
		FIRE:
			lift_fx = Fx.fire_jets()
			model.add_child(lift_fx)
			lift_fx.position = Vector3(0, 0.05, 0)
	_update_lift_fx()


func _update_lift_fx() -> void:
	if not is_instance_valid(lift_fx):
		return
	var base := Vector3(global_position.x, lift_base, global_position.z)
	var height := maxf(global_position.y - lift_base, 0.1)
	match element:
		AIR:
			lift_fx.global_position = base
			lift_fx.scale = Vector3.ONE * clampf(height - 0.1, 0.8, 8.0)
		WATER:
			lift_fx.global_position = base
			Fx.set_water_column_height(lift_fx, height + 0.35)


func _dissolve_lift_fx() -> void:
	if not is_instance_valid(lift_fx):
		return
	var n := lift_fx
	if n.get_parent() == model:
		return
	var tw := n.create_tween()
	tw.tween_property(n, "scale", Vector3.ZERO, 0.35)
	tw.tween_callback(func():
		if is_instance_valid(n) and n != lift_fx:
			n.queue_free()
	)


func _end_lift() -> void:
	lift_on = false
	lift_down = false
	_free_lift_fx()


func _free_lift_fx() -> void:
	var n := lift_fx
	lift_fx = null
	if not is_instance_valid(n):
		return
	if n.get_parent() == model:
		n.queue_free()
		return
	var tw := n.create_tween()
	tw.tween_property(n, "scale", n.scale * 0.01, 0.25)
	tw.tween_callback(n.queue_free)


# ---------- Slide on your element (hold Shift while moving) ----------
func _handle_slide() -> void:
	var moving := Input.get_vector("left", "right", "forward", "back").length() > 0.1
	var shift := Input.is_physical_key_pressed(KEY_SHIFT)
	if shift and moving and is_on_floor() and not busy and not guarding and not down and not _lifted() and not gliding:
		_start_glide()
	if gliding and (not shift or not moving or not is_on_floor() or down):
		_stop_glide()


func _start_glide() -> void:
	if gliding or down or element >= element_scenes.size() or element_scenes[element] == null:
		return
	gliding = true
	_cancel_combo()
	ride_lift = 0.0
	match element:
		AIR:
			var t := Fx.tornado_under()
			if t != null:
				t.scale = Vector3.ONE * 1.5
				model.add_child(t)
				slide_fx = t
		WATER:
			var fx = element_scenes[WATER].instantiate()
			fx.lifetime = 999.0
			model.add_child(fx)
			fx.remove_from_group("projectiles")
			fx.set_physics_process(false)
			if fx is Area3D:
				fx.monitoring = false
				fx.monitorable = false
			fx.rotation.y = PI
			fx.position = Vector3(0, 0.15, 0)
			slide_fx = fx
		EARTH:
			var scene := _earth_rock_scene()
			if scene != null:
				var slab := Fx.make_slab(scene, 1.5, 0.25)
				slab.rotation.y = randf() * TAU
				model.add_child(slab)
				ride_lift = 0.25
				slide_fx = slab
		FIRE:
			var jets := Fx.fire_jets()
			jets.position = Vector3(0, 0.05, 0)
			model.add_child(jets)
			slide_fx = jets


func _stop_glide() -> void:
	gliding = false
	ride_lift = 0.0
	if is_instance_valid(slide_fx):
		slide_fx.queue_free()
	slide_fx = null


func _earth_rock_scene() -> PackedScene:
	if Fx.rock_scenes.size() > 0:
		return Fx.rock_scenes[randi() % Fx.rock_scenes.size()]
	if element_scenes.size() > EARTH:
		return element_scenes[EARTH]
	return null


# ---------- Dodge (Move + Mouse Thumb1 or Q): without leaving your mouse ----------
func _dodge() -> void:
	if dead or down or guarding or _lifted() or not is_on_floor() or dodge_cd > 0.0 or flip_busy or frozen > 0.0:
		return
	var input := Input.get_vector("left", "right", "forward", "back")
	var cam_basis := Basis(Vector3.UP, cam_yaw)
	var dir := cam_basis * Vector3(input.x, 0.0, input.y) if input.length() > 0.1 else _facing()
	dir.y = 0.0
	if dir.length() < 0.05:
		dir = _facing()
	dir = dir.normalized()

	_stop_glide()
	_cancel_combo()
	move_id += 1
	dodge_vec = dir * dodge_speed
	dodge_t = dodge_duration
	inv = dodge_duration + 0.12
	dodge_cd = dodge_cooldown
	flipping = false
	jumping = false
	busy = true
	model.rotation.y = atan2(dir.x, dir.z)

	var roll_clip := _clip(["dodge", "Roll", "roll"])
	if roll_clip != "":
		anim.get_animation(roll_clip).loop_mode = Animation.LOOP_NONE
		current_anim = roll_clip
		anim.play(roll_clip, 0.0, 1.5)
	else:
		current_anim = ""
		busy = false


func _busy_for(t: float) -> void:
	move_id += 1
	var my := move_id
	busy = true
	await get_tree().create_timer(t).timeout
	if move_id == my and not dead:
		busy = false
		current_anim = ""


# ---------- Helpers ----------
func _set_element(i: int) -> void:
	if i < element_scenes.size():
		if gliding:
			_stop_glide()
		if _lifted() and i == EARTH:
			_end_lift()
		element = i
		if _lifted():
			_build_lift_fx()
		_update_element_label()


func _update_element_label() -> void:
	element_label.text = "Element: " + element_names[element] + "   (1 Air, 2 Water, 3 Earth, 4 Fire)\nLMB/J Light   RMB/H Heavy   K Special   F Shield   MouseSide/Q Dodge   Shift Slide"


func _chest_pos(side := 0.0) -> Vector3:
	var aim := _aim_direction()
	return global_position + Vector3(0, 1.5, 0) + aim * 0.9 + aim.cross(Vector3.UP) * 0.35 * side


func _foot_pos() -> Vector3:
	return foot.global_position if foot != null else _chest_pos()


func _nearest_enemy() -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Node3D and not e.get("dead"):
			var d := global_position.distance_to(e.global_position)
			if d < best_d:
				best_d = d
				best = e
	return best


func _shoot(aim: Vector3, origin: Vector3, dmg: float, size: float, variant := 0, extra := {}) -> void:
	if element >= element_scenes.size() or element_scenes[element] == null:
		return
	Bend.spawn(self, element_scenes[element], element, aim, origin, floor_y, is_on_floor() and not _lifted(), dmg, size, variant, extra, _nearest_enemy())


# ---------- Move runner ----------
func _run_move(clip: String, start: float, end: float, events: Array) -> bool:
	if not anim.has_animation(clip):
		push_warning("Animation not found: " + clip)
		return false
	move_id += 1
	var my := move_id
	var reverse := start > end
	busy = true
	flipping = false
	jumping = false
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
	while id == move_id and not dead and is_inside_tree() and anim.current_animation == clip:
		var p := anim.current_animation_position
		if (reverse and p <= t) or (not reverse and p >= t):
			return
		var tree := get_tree()
		if tree == null:
			return
		await tree.process_frame

# ---------- Light attack (Left Click / J) ----------
func _light_steps() -> Array:
	if not _lifted():
		return Bend.COMBO
	var out := []
	for s in Bend.COMBO:
		if s["from"] == "hand":
			out.append(s)
	return out


func _attack() -> void:
	if dead or down or guarding or gliding or flip_busy or landing_busy or frozen > 0.0 or element_scenes.is_empty():
		return
	if flipping:
		_air_shot()
		return
	if busy or light_cd > 0.0:
		return
	if Time.get_ticks_msec() - last_step_end_ms > combo_reset * 1000.0:
		combo_index = 0
	_combo_step()


func _air_shot() -> void:
	if air_shot_cd > 0.0:
		return
	air_shot_cd = air_shot_delay
	var origin := hand.global_position
	_shoot(_smart_aim(origin), origin, 0.8, 1.0)


func _combo_step() -> void:
	var list := _light_steps()
	var step: Dictionary = list[combo_index % list.size()]
	step_variant = combo_index % Bend.VARIANTS[element].size()
	combo_index += 1
	in_combo = true

	var aim := _aim_direction()
	model.rotation.y = atan2(aim.x, aim.z)

	var events := []
	var rel: Array = step["releases"]
	for i in rel.size():
		events.append([rel[i], _step_hit.bind(step, i == rel.size() - 1)])

	var finished: bool = await _run_move(step["clip"], step["start"], step["end"], events)
	if not finished:
		return
	in_combo = false
	last_step_end_ms = Time.get_ticks_msec()


func _step_hit(step: Dictionary, is_last: bool) -> void:
	var origin := hand.global_position if step["from"] == "hand" else _foot_pos()
	var st := Bend.step_style(step, element)
	Bend.pattern(st["pat"], _smart_aim(origin), origin, global_position + Vector3(0, 1.2, 0),
		float(step["dmg"]), float(step["size"]), step_variant, st["extra"], _shoot)
	if is_last:
		light_cd = light_cooldown


func _cancel_combo() -> void:
	in_combo = false
	combo_index = 0
	move_id += 1


# ---------- Heavy attack (Right Click / H) ----------
func _heavy() -> void:
	if dead or down or guarding or gliding or flip_busy or flipping or busy or landing_busy or frozen > 0.0 or heavy_cd > 0.0 or element_scenes.is_empty():
		return
	heavy_cd = heavy_cooldown
	light_cd = maxf(light_cd, 0.8)
	var aim := _aim_direction()
	model.rotation.y = atan2(aim.x, aim.z)
	var h: Dictionary = Bend.HEAVY
	_run_move(h["clip"], h["start"], h["end"], [[h["release"], _heavy_hit]])


func _heavy_hit() -> void:
	var origin := hand.global_position
	_shoot(_smart_aim(origin), origin, float(Bend.HEAVY["dmg"]), float(Bend.HEAVY["size"]), 0, Bend.HEAVY_STYLE[element])
	add_shake(0.18)


# ---------- Earth clips ----------
func _earth_cast_clip() -> Array:
	var has_eb := anim.has_animation("earthBlock")
	var has_up := anim.has_animation("uppercut")
	if has_eb and (not has_up or randf() < 0.5):
		return ["earthBlock", Bend.EARTHBLOCK["start"], Bend.EARTHBLOCK["peak"], Bend.EARTHBLOCK["end"]]
	if has_up:
		return ["uppercut", uppercut_start, uppercut_peak, uppercut_end]
	return ["", 0.0, 0.0, 0.0]


# ---------- Water move ----------
func _water_move(action: Callable) -> void:
	if not anim.has_animation("waterBend"):
		action.call()
		return
	_water_hands(true)
	var ok: bool = await _run_move("waterBend", Bend.WATERBEND["start"], Bend.WATERBEND["gather"], [])
	if not ok or dead or down or frozen > 0.0:
		_water_hands(false)
		return
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


# ---------- Defense (F) ----------
func _guard_start() -> void:
	if dead or down or _lifted() or flipping or frozen > 0.0:
		return
	_stop_glide()
	if element == EARTH:
		if wall_cd > 0.0 or defense_scenes.size() <= EARTH or defense_scenes[EARTH] == null:
			return
		wall_cd = wall_cooldown
		_cancel_combo()
		var c := _earth_cast_clip()
		if c[0] == "":
			_spawn_defense()
		else:
			_run_move(c[0], c[1], c[3], [[c[2], _spawn_defense]])
		return
	if element == WATER and anim.has_animation("waterBend"):
		if wall_cd > 0.0 or busy or defense_scenes.size() <= WATER or defense_scenes[WATER] == null:
			return
		wall_cd = wall_cooldown
		_cancel_combo()
		_water_move(_spawn_defense)
		return
	if guarding or busy or not is_on_floor():
		return
	guarding = true
	busy = true
	_cancel_combo()
	current_anim = "block"
	if anim.has_animation("block"):
		anim.play("block", 0.1)
	if wall_cd <= 0.0 and element < defense_scenes.size() and defense_scenes[element] != null:
		wall_cd = wall_cooldown
		_spawn_defense()


func _guard_end() -> void:
	if not guarding:
		return
	guarding = false
	busy = false
	current_anim = ""


func _spawn_defense() -> void:
	var w = defense_scenes[element].instantiate()
	var aim := _aim_direction()
	if "owner_node" in w:
		w.owner_node = self
	if "element" in w:
		w.element = element
	if w.has_method("set_lifetime"):
		w.set_lifetime(10.0)
	get_parent().add_child(w)
	var dist: float = w.get("spawn_distance") if "spawn_distance" in w else 2.5
	w.global_position = global_position + aim * dist
	w.look_at(w.global_position + aim, Vector3.UP)


# ---------- Special (K) ----------
func _special() -> void:
	if busy or dead or down or guarding or flipping or frozen > 0.0 or _lifted() or special_cd > 0.0 or element_scenes.is_empty():
		return
	_stop_glide()
	var aim := _aim_direction()
	model.rotation.y = atan2(aim.x, aim.z)

	match element:
		AIR:
			special_cd = 7.0
			_run_move("cast2", cast_start, cast_end, [[volley_time, _air_tornado]])
		WATER:
			special_cd = 8.0
			_water_move(_water_freeze)
		EARTH:
			special_cd = 8.0
			_earth_stone_crush()
		FIRE:
			special_cd = 6.0
			fire_toggle = not fire_toggle
			if fire_toggle:
				var events := []
				var n := 6
				for i in n:
					var t := stream_start + i * (stream_end - stream_start) / float(n - 1)
					var side := 1.0 if i % 2 == 0 else -1.0
					events.append([t, func(): _shoot(_aim_direction(), _chest_pos(side), 0.8, 1.0)])
				_run_move("cast2", cast_start, cast_end, events)
			else:
				_run_move("cast2", cast_start, cast_end, [[volley_time, _fire_rocket]])


func _air_tornado() -> void:
	var scene = load("res://scenes/air_tornado_vfx.tscn")
	var vis: Node3D = null
	if scene != null:
		vis = scene.instantiate()
		vis.position = Vector3.ZERO
		Fx.recenter_visual(vis)
		vis.scale = Vector3.ONE * 1.25
	var aim := _aim_direction()
	var pos := global_position + aim * 5.0
	pos.y = floor_y
	Zone.create(get_parent(), pos, self, AIR, {
		"duration": 3.5, "radius": 2.8, "height": 5.5, "tick_damage": 8.0,
		"pull": 4.5, "lift": 4.0, "move_dir": aim, "move_speed": 5.0, "knockdown_end": true}, vis)
	add_shake(0.12)


func _water_freeze() -> void:
	var pos := _target_point(25.0)
	var e := _nearest_enemy()
	pos.y = e.global_position.y if e != null else floor_y
	Fx.ring(get_parent(), pos + Vector3(0, 0.08, 0), Color(Fx.COLORS[WATER], 0.55), 2.4, 0.35)
	Zone.create(get_parent(), pos, self, WATER, {
		"delay": 0.4, "duration": 1.0, "radius": 2.4, "height": 4.5,
		"start_damage": 10.0, "freeze_time": 3.0, "rise_visual": true}, Fx.ice_spikes())
	add_shake(0.12)


func _fire_rocket() -> void:
	var origin := hand.global_position
	_shoot(_smart_aim(origin), origin, 1.0, 2.0, 0,
		{"speed": 40.0, "damage": 24.0, "knockback": 4.0, "explode": 4.2, "knockdown": true})
	add_shake(0.18)


# Earth Special: covers the target in stone slabs, then drops a big rock that shatters and knocks them down
func _earth_stone_crush() -> void:
	var target_pos := _target_point(25.0)
	var e := _nearest_enemy()
	if e != null and global_position.distance_to(e.global_position) <= 25.0:
		target_pos = e.global_position

	var c := _earth_cast_clip()
	if c[0] != "":
		var ok: bool = await _run_move(c[0], c[1], c[3], [[c[2], _cover_in_stone.bind(target_pos)]])
		if not ok or dead:
			return
	else:
		_cover_in_stone(target_pos)
		await get_tree().create_timer(0.45).timeout
		if dead:
			return

	await get_tree().create_timer(0.22).timeout
	if not dead:
		await _drop_crushing_boulder(target_pos)


func _cover_in_stone(center: Vector3) -> void:
	var scene := _earth_rock_scene()
	if scene == null or get_parent() == null:
		return
	var shell := Node3D.new()
	get_parent().add_child(shell)
	shell.global_position = Vector3(center.x, floor_y, center.z)

	var count := 4
	for i in count:
		var angle := TAU * float(i) / float(count)
		var slab := Fx.make_slab(scene, 1.4, 0.35)
		shell.add_child(slab)
		slab.position = Vector3(cos(angle) * 1.15, 0.0, sin(angle) * 1.15)
		slab.rotation.y = -angle + PI * 0.5
		slab.scale = Vector3(1.0, 0.1, 1.0)
		var tw := slab.create_tween()
		tw.tween_property(slab, "scale", Vector3(1.0, 4.5, 1.0), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	Fx.ring(get_parent(), Vector3(center.x, floor_y + 0.06, center.z), Color(Fx.COLORS[EARTH], 0.6), 2.4, 0.35)
	add_shake(0.14)
	get_tree().create_timer(1.3).timeout.connect(func():
		if is_instance_valid(shell):
			shell.queue_free()
	)


func _drop_crushing_boulder(center: Vector3) -> void:
	var scene := _earth_rock_scene()
	if scene == null or get_parent() == null:
		return

	var boulder := Fx.make_rock(scene, 2.4, 1.4)
	get_parent().add_child(boulder)
	var drop_start := Vector3(center.x, floor_y + 8.5, center.z)
	var drop_end := Vector3(center.x, floor_y + 0.4, center.z)
	boulder.global_position = drop_start

	var tw := boulder.create_tween()
	tw.tween_property(boulder, "global_position", drop_end, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished
	if dead:
		if is_instance_valid(boulder):
			boulder.queue_free()
		return

	# Shatter the big rock and knock nearby targets down
	Fx.rock_chunks(get_parent(), drop_end, 3)
	Fx.explode(get_parent(), drop_end, 3.6, 26.0, EARTH, self, true)
	add_shake(0.25)
	if is_instance_valid(boulder):
		boulder.queue_free()


# ---------- Freeze ----------
func freeze(t: float) -> void:
	if dead or inv > 0.0 or frozen > 0.0:
		return
	frozen = t
	guarding = false
	flipping = false
	jumping = false
	_stop_glide()
	_end_lift()
	_cancel_combo()
	_water_hands(false)
	busy = true
	anim.speed_scale = 0.0
	Fx.ice_block(self, t)


# ---------- Health and hit reactions ----------
func take_damage(amount: float, from_dir := Vector3.ZERO) -> void:
	if dead or inv > 0.0:
		return
	var he: int = get_meta("hit_element", -1)
	var light: bool = get_meta("hit_light", false)
	set_meta("hit_light", false)
	if guarding:
		amount *= 0.2
		from_dir *= 0.3
	else:
		_stop_glide()
	health = maxf(0.0, health - amount)
	add_shake(0.08 if guarding else 0.2)
	health_bar.value = health
	health_changed.emit(health)
	var flat := Vector3(from_dir.x, 0.0, from_dir.z)
	knock += flat * (1.5 if light else 4.5)
	Fx.flash(model, he, get_tree())
	flinch = 0.25 if light else 0.9
	if health <= 0.0:
		_die()
	elif frozen > 0.0:
		pass
	elif amount >= HEAVY_HIT and not guarding and not light:
		knock_down(from_dir)
	elif not guarding and not light and not down:
		busy = false
		hit_cd = 0.4
		_cancel_combo()
		flipping = false
		if is_on_floor() and not _lifted():
			velocity.y = maxf(velocity.y, 2.5)
		var c := _clip(["hit", "hit_reaction"])
		if c != "":
			current_anim = c
			anim.play(c, 0.04, 1.5)
		_busy_for(0.35)


func knock_down(dir := Vector3.ZERO) -> void:
	if dead or down or down_immune > 0.0 or inv > 0.0 or frozen > 0.0:
		return
	down = true
	guarding = false
	flipping = false
	jumping = false
	_stop_glide()
	_end_lift()
	_cancel_combo()
	_water_hands(false)
	busy = true
	move_id += 1
	var my := move_id

	var d := Vector3(dir.x, 0.0, dir.z)
	d = d.normalized() if d.length() > 0.01 else -_facing()
	knock += d * 14.0
	velocity.y = 8.0

	var fall_clip := _clip(["fall", "Fall"])
	if fall_clip != "":
		anim.get_animation(fall_clip).loop_mode = Animation.LOOP_NONE
		current_anim = fall_clip
		anim.stop()
		anim.play(fall_clip, 0.0, 1.0)
		await anim.animation_finished
		if move_id != my or dead:
			return

	_land_thud()
	await get_tree().create_timer(0.8).timeout
	if move_id != my or dead:
		return

	var rise_clip := _clip(["rise", "Rise"])
	if rise_clip != "":
		anim.get_animation(rise_clip).loop_mode = Animation.LOOP_NONE
		current_anim = rise_clip
		anim.stop()
		anim.play(rise_clip, 0.0, 1.0)
		await anim.animation_finished
		if move_id != my or dead:
			return

	anim.stop()
	down = false
	down_immune = 4.0
	busy = false
	current_anim = ""


func _land_thud() -> void:
	Fx.ring(get_parent(), global_position + Vector3(0, 0.1, 0), Color(1, 1, 1, 0.45), 1.8, 0.25)
	add_shake(0.18)


func _die() -> void:
	if dead:
		return
	dead = true
	down = false
	guarding = false
	flipping = false
	jumping = false
	landing_busy = false
	frozen = 0.0
	anim.speed_scale = 1.0
	busy = true
	move_id += 1
	_stop_glide()
	_end_lift()
	_water_hands(false)
	_cancel_combo()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	element_label.text = "You were defeated - press R to restart"
	var d_clip := _clip(["death", "Death", "die", "Die"])
	if d_clip != "":
		anim.get_animation(d_clip).loop_mode = Animation.LOOP_NONE
		current_anim = d_clip
		anim.stop()
		anim.play(d_clip, 0.0, 1.0)


# ---------- Animation ----------
func _air_time() -> float:
	var g := gravity * gravity_mult
	var h := maxf(0.0, global_position.y - floor_y)
	return (velocity.y + sqrt(velocity.y * velocity.y + 2.0 * g * h)) / g


func _clip_speed(anim_name: String, skip: float) -> float:
	if not anim.has_animation(anim_name):
		return 1.0
	var length := anim.get_animation(anim_name).length - skip
	return clampf(length / maxf(_air_time(), 0.1), 0.7, 2.5)


func _play(anim_name: String, blend := 0.12, start := 0.0, speed_scale := 1.0) -> void:
	if anim_name == "" or not anim.has_animation(anim_name):
		return
	if anim_name == current_anim and anim.is_playing():
		return
	current_anim = anim_name
	anim.play(anim_name, blend, speed_scale)
	if start > 0.0:
		anim.seek(start, true)


func _update_animation() -> void:
	if dead or down or busy or landing_busy or flip_busy or frozen > 0.0:
		return
	if gliding or _lifted():
		_play("idle", 0.12)
		return

	if not is_on_floor():
		return

	jumping = false
	var horizontal := Vector2(velocity.x, velocity.z).length()
	if horizontal > 0.5:
		var run_clip := _clip(["run", "walk"])
		var run_spd := clampf(horizontal / maxf(speed, 0.1), 0.85, 1.45)
		if run_clip != "" and (run_clip != current_anim or not anim.is_playing()):
			current_anim = run_clip
			anim.play(run_clip, 0.1, run_spd)
		elif run_clip == current_anim:
			anim.speed_scale = run_spd
	else:
		_play("idle", 0.12, 0.0, 1.0)


func _start_flip() -> void:
	if not anim.has_animation("flip"):
		return
	move_id += 1
	flipping = true
	jumping = false
	busy = true
	current_anim = "flip"
	anim.stop()
	anim.play("flip", 0.0, _clip_speed("flip", 0.0) * flip_speed_mult)


func _check_landing() -> void:
	var on := is_on_floor() and velocity.y <= 0.0
	if on and not was_floor:
		if flipping:
			flipping = false
			busy = false
		jumping = false
		if current_anim in ["jump", "Jump"]:
			current_anim = ""
		landed_from_lift = false
	was_floor = on

func _setup_camera_rig() -> void:
	cam_yaw = deg_to_rad(cam_yaw_deg)
	cam_pitch = cam_pitch_deg
	pivot.top_level = true
	pivot.global_position = global_position + Vector3(0.0, 1.4, 0.0)
	pivot.rotation = Vector3(0.0, cam_yaw, 0.0)
	spring.rotation = Vector3(deg_to_rad(cam_pitch), 0.0, 0.0)
	spring.collision_mask = 1
	spring.add_excluded_object(get_rid())
	spring.spring_length = maxf(cam_min_dist, 6.5)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_anim_finished(anim_name: StringName) -> void:
	if dead:
		return
	if guarding or down or frozen > 0.0:
		return
	var n := String(anim_name)
	if n == "flip":
		flipping = false
		jumping = false
		busy = false
		current_anim = ""
	elif n in ["dodge", "Roll", "roll"]:
		dodge_t = 0.0
		busy = false
		current_anim = ""
	elif n in ["jump", "Jump"]:
		if is_on_floor():
			jumping = false
			current_anim = ""
	elif busy and not in_combo:
		busy = false
		current_anim = ""
