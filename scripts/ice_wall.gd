extends "res://scripts/fire_wall.gd"

@export var ice_material: ShaderMaterial
@export var count := 9
@export var width := 6.0

func _ready() -> void:
	if solid_size == Vector3.ZERO:
		solid_size = Vector3(6, 1.3, 1.0)
	super()
	
	var visual := Node3D.new()
	add_child(visual)
	
	for i in count:
		# Alternate between large main pillars and smaller jagged side shards
		var is_large := (i % 2 == 0)
		var h := randf_range(2.8, 4.0) if is_large else randf_range(1.5, 2.5)
		var radius_mult := randf_range(0.5, 0.9) if is_large else randf_range(0.2, 0.4)
		
		var m := CylinderMesh.new()
		m.top_radius = 0.0                      # Sharp pointed tip
		m.bottom_radius = radius_mult
		m.height = h
		m.radial_segments = 6                   # Clean faceted crystal look
		m.rings = 2
		
		var shard := MeshInstance3D.new()
		shard.mesh = m
		if ice_material:
			shard.material_override = ice_material
		visual.add_child(shard)

		# Position and organic rotation
		var x := lerpf(-width * 0.5, width * 0.5, float(i) / maxf(count - 1.0, 1.0))
		var x_offset = randf_range(-0.3, 0.3)
		var z_offset = randf_range(-0.3, 0.3)
		
		shard.position = Vector3(x + x_offset, 0.0, z_offset)
		# Slight random tilt so they don't look uniform
		shard.rotation = Vector3(randf_range(-0.2, 0.2), randf() * TAU, randf_range(-0.2, 0.2))
		shard.scale = Vector3(1.0, 0.01, 1.0) # Start flat underground

		# Dramatic eruption tween
		var duration = randf_range(0.25, 0.35)
		var delay = abs(x) * 0.04 # Wave effect from center outward!
		
		var t := create_tween().set_parallel(true)
		t.tween_property(shard, "scale:y", 1.0, duration).set_delay(delay) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(shard, "position:y", h * 0.5 - 0.1, duration).set_delay(delay) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
