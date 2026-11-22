extends Area3D

@export var lifetime := 6.0
@export var rise := false          # true = grows up from the floor
@export var follow_owner := false  # true = stays on the player (air shield only)
@export var spawn_distance := 3.0  # meters in front of the player (0 = on the player)
@export var solid_size := Vector3.ZERO   # above 0 = adds a solid body you can stand on
var owner_node: Node
var element := -1                  # set by whoever creates it (0 air, 1 water, 2 earth, 3 fire)
var broken := false
var variant := 0

func _ready() -> void:
	area_entered.connect(_on_area_entered)
	get_tree().create_timer(lifetime).timeout.connect(queue_free)
	var v := get_node_or_null("Visual")
	if rise and v:
		v.scale.y = 0.05
		create_tween().tween_property(v, "scale:y", 1.0, 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_make_solid()


func _make_solid() -> void:
	if solid_size == Vector3.ZERO:
		return
	var body := StaticBody3D.new()
	body.name = "Solid"
	body.collision_layer = 2    # layer 2 = shield walls; the camera arm ignores it
	body.collision_mask = 0
	body.add_to_group("solid_shield")
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = solid_size
	cs.shape = box
	cs.position = Vector3(0, solid_size.y * 0.5, 0)
	body.add_child(cs)
	add_child(body)


func _physics_process(_delta: float) -> void:
	if follow_owner and is_instance_valid(owner_node):
		global_position = owner_node.global_position


func _on_area_entered(area: Area3D) -> void:
	if broken or not area.is_in_group("projectiles") or area.shooter == owner_node:
		return
	var attacker: int = area.element
	if attacker >= 0 and element >= 0 and Clash.beats(attacker, element):
		_shatter()                      # the attacking element breaks this defense
		if not area.pierce:
			area.queue_free()
	else:
		if attacker >= 0:
			Fx.burst(get_parent(), area.global_position, attacker)
		area.queue_free()               # blocked


func _shatter() -> void:
	broken = true
	var side := global_basis.x * 1.6
	var up := Vector3(0, 1.0, 0)
	var v := 1 if element == 1 else 0       # the ice wall leaves ice shards
	Fx.burst(get_parent(), global_position + up, maxi(element, 0), true, v)
	Fx.burst(get_parent(), global_position + up + side, maxi(element, 0), true, v)
	Fx.burst(get_parent(), global_position + up - side, maxi(element, 0), true, v)
	queue_free()
