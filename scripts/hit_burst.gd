extends GPUParticles3D

var color := Color.WHITE


func _ready() -> void:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	material_override = m
	emitting = true
	get_tree().create_timer(lifetime + 0.3).timeout.connect(queue_free)
