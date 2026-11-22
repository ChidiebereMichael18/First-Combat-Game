extends "res://scripts/fire_wall.gd"

@export var rocks: Array[PackedScene]   # drag your rock models here
@export var count := 6
@export var width := 6.0
@export var min_height_scale := 2.2     # How tall the rocks stretch
@export var max_height_scale := 3.5     # Max height multiplier
@export var burst_depth := 5.0          # How deep underground they start
@export var wall_hp := 40.0             # damage before the shield breaks

var hp := 40.0
var _broken := false


func _ready() -> void:
	hp = wall_hp
	add_to_group("shields")
	add_to_group("walls")

	if solid_size == Vector3.ZERO:
		solid_size = Vector3(5, 2.0, 0.9)
	super()

	for c in find_children("*", "CollisionObject3D", true, false):
		var co := c as CollisionObject3D
		co.collision_layer = co.collision_layer | 2
		co.collision_mask = co.collision_mask | 1 | 2 | 4

	if rocks.is_empty():
		return

	var visual := Node3D.new()
	add_child(visual)

	for i in count:
		var r: Node3D = rocks[randi() % rocks.size()].instantiate()
		visual.add_child(r)

		var x := lerpf(-width * 0.5, width * 0.5, float(i) / maxf(count - 1.0, 1.0))

		var random_height = randf_range(min_height_scale, max_height_scale)
		var random_width = randf_range(1.0, 1.4)
		r.scale = Vector3(random_width, random_height, random_width)

		r.rotation = Vector3(randf_range(-0.2, 0.2), randf() * TAU, randf_range(-0.2, 0.2))

		var end := Vector3(x + randf_range(-0.2, 0.2), 0.0, randf_range(-0.2, 0.2))
		r.position = end + Vector3(0, -burst_depth, 0)

		create_tween().tween_property(r, "position", end, 0.35) \
			.set_delay(randf() * 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func take_damage(amount: float, _from_dir := Vector3.ZERO) -> void:
	if _broken:
		return
	var hit_elem: int = int(get_meta("hit_element", -1))
	set_meta("hit_element", -1)

	hp -= maxf(amount, 1.0)
	if is_inside_tree() and get_parent() != null:
		Fx.burst(get_parent(), global_position + Vector3(0, 0.9, 0), hit_elem if hit_elem >= 0 else 2, false, 0, false)

	if hp <= 0.0:
		_broken = true
		if is_inside_tree() and get_parent() != null:
			Fx.ring(get_parent(), global_position + Vector3(0, 0.1, 0), Color(0.55, 0.42, 0.25, 0.65), 2.2, 0.28)
			Fx.rock_chunks(get_parent(), global_position + Vector3(0, 0.85, 0), 3)
		queue_free()
