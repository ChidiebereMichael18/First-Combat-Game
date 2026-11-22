extends Area3D

# These are set by whoever fires the projectile
var speed := 25.0
var damage := 8.0
var knockback := 1.0
var arc := 0.0          # above 0 makes it curve downward (earth)
var homing := 0.0       # above 0 steers toward the target (water)
var pierce := false     # true = passes through enemies (air)
var pass_walls := false # true = flies through walls and rocks
var lifetime := 3.0
var element := -1       # 0 air, 1 water, 2 earth, 3 fire
var variant := 0        # 1 = ice (water) or blue fire; decides the debris left behind
var knockdown := false  # heavy hit: knocks the target down
var explode_radius := 0.0   # above 0 = explodes on impact (rocket)
var hit_scene: PackedScene  # kept so older code still works
var hit_color := Color.WHITE
var rise_time := 0.0    # above 0 = comes up out of the ground first (earth, water)
var rise_height := 0.0  # how far it rises before flying off
var size_min := 0.55    # wider min scale range for thrown rocks (J)
var size_max := 1.9     # wider max scale range for thrown rocks (J)

var direction := Vector3.FORWARD
var shooter: Node
var target: Node3D
var fall := 0.0
var _rise_t := 0.0
var _done := false


func _ready() -> void:
	add_to_group("projectiles")
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	get_tree().create_timer(lifetime + rise_time).timeout.connect(_expire)

	# Vary the size of J rock projectiles across a wider range
	if element == 2:
		var r_scale := randf_range(size_min, size_max)
		scale = Vector3(
			r_scale * randf_range(0.85, 1.25),
			r_scale * randf_range(0.8, 1.35),
			r_scale * randf_range(0.85, 1.25)
		)


func _expire() -> void:
	if explode_radius > 0.0 and not _done:
		_detonate()
	queue_free()


func _physics_process(delta: float) -> void:
	var spin := get_node_or_null("Spin")
	if spin:
		spin.rotate_x(8.0 * delta)
		spin.rotate_z(5.0 * delta)

	if _rise_t < rise_time:
		_rise_t += delta
		global_position.y += rise_height / rise_time * delta
		return

	if homing > 0.0 and is_instance_valid(target):
		var to_target := (target.global_position + Vector3.UP - global_position).normalized()
		direction = direction.lerp(to_target, clampf(homing * delta, 0.0, 1.0)).normalized()
	fall += arc * delta
	global_position += direction * speed * delta + Vector3.DOWN * fall * delta


func _spawn_hit() -> void:
	Fx.burst(get_parent(), global_position, element, element == 2 or knockdown, variant)


func _detonate() -> void:
	_done = true
	Fx.explode(get_parent(), global_position, explode_radius, damage, element, shooter, knockdown)


func _find_damage_target(node: Node) -> Node:
	var cur: Node = node
	while cur != null:
		if cur == shooter:
			return null
		if cur.has_method("take_damage"):
			return cur
		cur = cur.get_parent()
	return null


func _apply_hit_to(hit_node: Node) -> bool:
	if _done or hit_node == null or hit_node == shooter:
		return false
	if "owner_node" in hit_node and hit_node.owner_node == shooter:
		return false

	if explode_radius > 0.0:
		_detonate()
		queue_free()
		return true

	hit_node.set_meta("hit_element", element)
	hit_node.take_damage(damage, direction * knockback)
	if knockdown and hit_node.has_method("knock_down"):
		hit_node.knock_down(direction)
	_spawn_hit()
	if is_instance_valid(shooter) and shooter.has_method("on_hit_landed"):
		shooter.on_hit_landed(damage)
	if not pierce:
		queue_free()
	return true


func _on_body_entered(body: Node) -> void:
	if _done or body == shooter or _rise_t < rise_time:
		return

	var dmg_target := _find_damage_target(body)
	if dmg_target != null:
		_apply_hit_to(dmg_target)
		return

	if body.is_in_group("solid_shield") or body.is_in_group("shields") or body.is_in_group("walls"):
		if explode_radius > 0.0:
			_detonate()
		else:
			_spawn_hit()
		queue_free()
		return

	if pass_walls:
		return
	if explode_radius > 0.0:
		_detonate()
	else:
		_spawn_hit()
	queue_free()


func _on_area_entered(other: Area3D) -> void:
	if _done or _rise_t < rise_time:
		return

	var dmg_target := _find_damage_target(other)
	if dmg_target != null and (dmg_target.is_in_group("shields") or dmg_target.is_in_group("walls") or other.is_in_group("shields") or other.is_in_group("walls")):
		_apply_hit_to(dmg_target)
		return

	if not other.is_in_group("projectiles"):
		return
	if other.shooter == shooter:
		return
	var other_el: int = other.element
	if element < 0 or other_el < 0:
		return
	var i_lose := Clash.beats(other_el, element) or other_el == element
	var i_win := Clash.beats(element, other_el)
	if i_lose and not (pierce and i_win):
		_spawn_hit()
		queue_free()
