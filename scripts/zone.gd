class_name Zone
extends Area3D

var shooter: Node
var element := 0
var duration := 3.0
var radius := 2.5
var height := 4.0
var tick_damage := 0.0       # damage per second to everything inside
var pull := 0.0              # pulls targets toward the center
var lift := 0.0              # holds targets up in the air at this speed
var move_dir := Vector3.ZERO
var move_speed := 0.0
var delay := 0.0             # warning time before it does anything
var launch := 0.0            # one-time throw upward when it starts
var knockdown_start := false
var knockdown_end := false
var rise_visual := false     # the visual rises out of the ground
var start_damage := 0.0      # one-time damage when it starts
var freeze_time := 0.0       # freezes everything inside for this many seconds when it starts
var visual: Node3D

var _t := 0.0
var _tick := 0.0
var _started := false
var _ending := false


static func create(parent: Node, pos: Vector3, shooter_node: Node, element_id: int, opts: Dictionary, vis: Node3D = null) -> Zone:
	var z := Zone.new()
	z.shooter = shooter_node
	z.element = element_id
	for k in opts:
		z.set(k, opts[k])
	z.collision_layer = 0
	z.collision_mask = 1
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = z.radius
	cyl.height = z.height
	cs.shape = cyl
	cs.position = Vector3(0, z.height * 0.5, 0)
	z.add_child(cs)
	if vis != null:
		z.visual = vis
		z.add_child(vis)
		if z.rise_visual:
			vis.position.y = -3.0
	parent.add_child(z)
	z.global_position = pos
	return z


func _physics_process(delta: float) -> void:
	_t += delta
	if _t < delay:
		return
	if not _started:
		_started = true
		if rise_visual and visual != null:
			create_tween().tween_property(visual, "position:y", 0.0, 0.3) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		for b in get_overlapping_bodies():
			if _valid(b):
				if start_damage > 0.0:
					b.set_meta("hit_element", element)
					b.set_meta("hit_light", true)
					b.take_damage(start_damage, Vector3.ZERO)
				if freeze_time > 0.0 and b.has_method("freeze"):
					b.freeze(freeze_time)
				if launch > 0.0:
					b.velocity.y = launch
				if knockdown_start:
					b.knock_down(_away(b))
				Fx.burst(get_parent(), b.global_position + Vector3(0, 1.0, 0), element, true)

	if move_speed > 0.0:
		global_position += move_dir * move_speed * delta

	_tick -= delta
	var do_tick := _tick <= 0.0
	if do_tick:
		_tick = 0.4
	for b in get_overlapping_bodies():
		if not _valid(b):
			continue
		if pull > 0.0:
			var to_c := global_position - b.global_position
			to_c.y = 0.0
			b.knock += to_c.normalized() * pull * delta * 8.0
		if lift > 0.0:
			b.velocity.y = lift
		if do_tick and tick_damage > 0.0:
			b.set_meta("hit_element", element)
			b.set_meta("hit_light", true)
			b.take_damage(tick_damage * 0.4, Vector3.ZERO)

	if _t >= delay + duration and not _ending:
		_ending = true
		if knockdown_end:
			for b in get_overlapping_bodies():
				if _valid(b):
					b.knock_down(_away(b))
					Fx.burst(get_parent(), b.global_position + Vector3(0, 1.0, 0), element, true)
		if visual != null:
			create_tween().tween_property(visual, "scale", Vector3.ZERO, 0.4)
		get_tree().create_timer(0.4).timeout.connect(queue_free)
		set_physics_process(false)


func _valid(b: Node) -> bool:
	return b != shooter and b.has_method("take_damage") and b.has_method("knock_down") and not b.get("dead")


func _away(b: Node3D) -> Vector3:
	var d := b.global_position - global_position
	d.y = 0.0
	return d.normalized() if d.length() > 0.01 else Vector3.FORWARD
