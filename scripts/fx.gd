class_name Fx
extends RefCounted

# Element numbers: 0 air, 1 water, 2 earth, 3 fire
const COLORS := [Color(0.92, 0.97, 1.0), Color(0.55, 0.82, 1.0), Color(0.55, 0.42, 0.25), Color(1.0, 0.55, 0.1)]
const MAX_DEBRIS := 20

static var fire_scene: PackedScene      # your fireball scene: its real flames are reused
static var water_mat: Material          # the water stream material
static var rock_scenes: Array = []      # your rock models (from the earth wall)


static func setup(elements: Array, defenses: Array) -> void:
	if elements.size() > 3 and elements[3] != null:
		fire_scene = elements[3]
	if elements.size() > 1 and elements[1] != null:
		var w = elements[1].instantiate()
		var sm = w.get_node_or_null("StreamMain")
		if sm != null:
			water_mat = sm.material_override
		w.free()
	if defenses.size() > 2 and defenses[2] != null:
		var e = defenses[2].instantiate()
		var rocks = e.get("rocks")
		if rocks is Array:
			rock_scenes = rocks.duplicate()
		e.free()


# ---------- Impact: soft, short feedback ----------
static func burst(parent: Node, pos: Vector3, element: int, strong := false, variant := 0, leave_debris := true) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	match element:
		0:
			_wind(parent, pos, strong)
		1:
			_splash(parent, pos, strong, variant == 1)
		2:
			var s := SphereMesh.new()
			s.radius = 0.06
			s.height = 0.12
			s.material = _unshaded()
			_cpu(parent, pos, s, 8 if strong else 4, 0.25, 1.4, 2.8, Vector3(0, -11.0, 0), Color(0.45, 0.35, 0.22, 0.75))
		3:
			# Short, compact flame puff (no long trail)
			_flames(parent, pos, 0.42 if strong else 0.28, variant == 1, 0.24 if strong else 0.16, false)
	if leave_debris and element != 0:
		_later(parent, pos, element, variant, strong)


static func _later(parent: Node, pos: Vector3, element: int, variant: int, strong: bool) -> void:
	var tree := parent.get_tree()
	await tree.physics_frame
	if not is_instance_valid(parent) or not parent.is_inside_tree():
		return
	match element:
		1:
			if variant == 1:
				_shards(parent, pos, 4 if strong else 2)
			else:
				_puddle(parent, pos)
		2:
			rock_chunks(parent, pos, 3 if strong else 2)
		3:
			if strong:
				_ground_fire(parent, pos, variant == 1)


static func _trim(tree: SceneTree, add: int) -> void:
	var old := tree.get_nodes_in_group("debris")
	var over := old.size() + add - MAX_DEBRIS
	for i in range(maxi(over, 0)):
		if i < old.size() and is_instance_valid(old[i]):
			old[i].queue_free()


# ---------- Air ----------
static func _wind(parent: Node, pos: Vector3, strong: bool) -> void:
	ring(parent, pos, Color(0.95, 0.98, 1.0, 0.55), 2.4 if strong else 1.7, 0.3, 0.0)
	var s := SphereMesh.new()
	s.radius = 0.14
	s.height = 0.28
	s.material = _unshaded()
	_cpu(parent, pos, s, 12 if strong else 8, 0.35, 3.0, 6.0, Vector3.ZERO, Color(1, 1, 1, 0.55))


# ---------- Water ----------
static func _splash(parent: Node, pos: Vector3, strong: bool, ice: bool) -> void:
	var col := Color(0.85, 0.96, 1.0, 0.6) if ice else Color(0.55, 0.82, 1.0, 0.55)
	ring(parent, pos, col, 2.2 if strong else 1.6, 0.3, 0.0)
	var s := SphereMesh.new()
	s.radius = 0.09
	s.height = 0.18
	s.material = _unshaded()
	_cpu(parent, pos, s, 24 if strong else 14, 0.45, 2.5, 6.0, Vector3(0, -12, 0), col)


static func _puddle(parent: Node, pos: Vector3) -> void:
	_trim(parent.get_tree(), 1)
	var fp := _floor_point(parent, pos)
	if fp == Vector3.INF:
		return
	var puddle := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	var r := randf_range(0.5, 1.0)
	cyl.top_radius = r
	cyl.bottom_radius = r
	cyl.height = 0.025
	puddle.mesh = cyl
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.6, 0.85, 1.0, 0.42)
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.roughness = 0.1
	puddle.material_override = pm
	puddle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	puddle.add_to_group("debris")
	parent.add_child(puddle)
	puddle.global_position = fp + Vector3(0, 0.02, 0)
	parent.get_tree().create_timer(randf_range(2.0, 3.2)).timeout.connect(_fade.bind(puddle, puddle))


static func _shards(parent: Node, pos: Vector3, count: int) -> void:
	var tree := parent.get_tree()
	_trim(tree, count)
	for i in count:
		var body := RigidBody3D.new()
		body.collision_layer = 8
		body.collision_mask = 1
		body.add_to_group("debris")
		var s := randf_range(0.08, 0.15)
		var pr := PrismMesh.new()
		pr.size = Vector3(s, s * 1.3, s)
		var mesh := MeshInstance3D.new()
		mesh.mesh = pr
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.75, 0.92, 1.0, 0.6)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.roughness = 0.1
		mesh.material_override = mat
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = pr.size * 0.8
		cs.shape = bs
		body.add_child(cs)
		body.add_child(mesh)
		parent.add_child(body)
		body.global_position = pos + Vector3(randf_range(-0.25, 0.25), 0.15, randf_range(-0.25, 0.25))
		body.linear_velocity = Vector3(randf_range(-1.6, 1.6), randf_range(1.5, 3.0), randf_range(-1.6, 1.6))
		body.angular_velocity = Vector3(randf_range(-3.0, 3.0), randf_range(-3.0, 3.0), randf_range(-3.0, 3.0))
		tree.create_timer(randf_range(1.8, 3.0)).timeout.connect(_fade.bind(body, mesh))


# ---------- Earth: flat slab/plank debris that settles cleanly on the floor ----------
static func rock_chunks(parent: Node, pos: Vector3, count: int) -> void:
	var tree := parent.get_tree()
	_trim(tree, count)
	var safe_count := mini(count, 3)

	for i in safe_count:
		var body := RigidBody3D.new()
		body.collision_layer = 8
		body.collision_mask = 1
		body.mass = 0.9
		var pm := PhysicsMaterial.new()
		pm.friction = 0.9
		pm.bounce = 0.02
		body.physics_material_override = pm
		body.add_to_group("debris")

		var w := randf_range(0.22, 0.42)
		var h := randf_range(0.04, 0.08)
		var visual: Node3D

		if rock_scenes.size() > 0:
			visual = make_slab(rock_scenes[randi() % rock_scenes.size()], w, h)
		else:
			var mi := MeshInstance3D.new()
			var b := BoxMesh.new()
			b.size = Vector3(w, h, w * randf_range(0.5, 0.9))
			mi.mesh = b
			var mat := StandardMaterial3D.new()
			var g := randf_range(0.38, 0.56)
			mat.albedo_color = Color(g * 1.06, g * 0.92, g * 0.76)
			mat.roughness = 0.92
			mi.material_override = mat
			mi.position.y = h * 0.5
			visual = Node3D.new()
			visual.add_child(mi)

		visual.rotation.y = randf() * TAU

		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(w * 0.9, maxf(h, 0.05), w * 0.75)
		cs.shape = bs
		body.add_child(cs)
		body.add_child(visual)
		parent.add_child(body)

		body.global_position = pos + Vector3(randf_range(-0.25, 0.25), 0.1, randf_range(-0.25, 0.25))
		body.linear_velocity = Vector3(randf_range(-1.2, 1.2), randf_range(0.8, 1.8), randf_range(-1.2, 1.2))
		body.angular_velocity = Vector3(randf_range(-2.0, 2.0), randf_range(-3.0, 3.0), randf_range(-2.0, 2.0))

		tree.create_timer(randf_range(1.6, 2.5)).timeout.connect(_fade.bind(body, visual))


# ---------- Fire: short flame puffs that clear quickly ----------
static func _ground_fire(parent: Node, pos: Vector3, blue: bool) -> void:
	_trim(parent.get_tree(), 1)
	var fp := _floor_point(parent, pos)
	if fp == Vector3.INF:
		return
	var h := _flames(parent, fp + Vector3(0, 0.04, 0), 0.45, blue, 0.45, false)
	h.add_to_group("debris")


static func hand_water(hand_node: Node3D) -> Node3D:
	var holder := Node3D.new()
	hand_node.add_child(holder)
	holder.position = Vector3.ZERO
	var gs := hand_node.global_transform.basis.get_scale()
	if gs.x > 0.0001 and gs.y > 0.0001 and gs.z > 0.0001:
		holder.scale = Vector3(1.0 / gs.x, 1.0 / gs.y, 1.0 / gs.z)
	var ball := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.14
	sph.height = 0.28
	ball.mesh = sph
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.85, 1.0, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.1
	ball.material_override = mat
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(ball)
	return holder


static func _flames(parent: Node, pos: Vector3, scl: float, blue: bool, life: float, light: bool) -> Node3D:
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.global_position = pos
	holder.scale = Vector3.ONE * scl
	if fire_scene != null:
		var src: Node = fire_scene.instantiate()
		for n in src.find_children("*", "GPUParticles3D", true, false):
			var d := n.duplicate() as GPUParticles3D
			d.lifetime = minf(d.lifetime, maxf(life, 0.12))
			holder.add_child(d)
			d.position = Vector3.ZERO
			d.emitting = true
		if light:
			for l in src.find_children("*", "OmniLight3D", true, false):
				var dl := l.duplicate() as OmniLight3D
				holder.add_child(dl)
				dl.position = Vector3(0, 0.5, 0)
				dl.light_energy = 0.45
		src.free()
	else:
		var s := SphereMesh.new()
		s.radius = 0.08
		s.height = 0.16
		s.material = _unshaded()
		_cpu(holder, pos, s, 12, life, 0.8, 2.0, Vector3(0, 1.5, 0), Color(1.0, 0.5, 0.1, 0.7))
	if blue:
		recolor_fire(holder, Color(0.3, 0.55, 1.0), Color(0.75, 0.92, 1.0))
	parent.get_tree().create_timer(life).timeout.connect(_stop_flames.bind(holder))
	return holder


static func _stop_flames(holder: Node3D) -> void:
	if not is_instance_valid(holder):
		return
	for p in holder.find_children("*", "GPUParticles3D", true, false):
		p.emitting = false
	for p in holder.find_children("*", "CPUParticles3D", true, false):
		p.emitting = false
	for l in holder.find_children("*", "OmniLight3D", true, false):
		holder.create_tween().tween_property(l, "light_energy", 0.0, 0.25)
	holder.get_tree().create_timer(0.25).timeout.connect(holder.queue_free)


# ---------- Shared helpers ----------
static func ring(parent: Node, pos: Vector3, col: Color, to_scale: float, t: float, tilt_deg := 0.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var m := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.44
	tor.outer_radius = 0.5
	m.mesh = tor
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = col
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	m.global_position = pos
	m.rotation_degrees = Vector3(tilt_deg, randf() * 360.0, 0.0)
	m.scale = Vector3.ONE * 0.35
	var tw := m.create_tween()
	tw.set_parallel(true)
	tw.tween_property(m, "scale", Vector3.ONE * to_scale, t).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, t)
	tw.chain().tween_callback(m.queue_free)


static func _unshaded() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat


static func _cpu(parent: Node, pos: Vector3, mesh: Mesh, amount: int, life: float, vmin: float, vmax: float, grav: Vector3, col: Color) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 180.0
	p.amount = amount
	p.lifetime = life
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.gravity = grav
	p.color = col
	p.mesh = mesh
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = g
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	parent.get_tree().create_timer(life + 0.4).timeout.connect(p.queue_free)


static func _fade(body: Node, mesh: Node3D) -> void:
	if not is_instance_valid(body) or not is_instance_valid(mesh) or not mesh.is_inside_tree():
		return
	var tw := mesh.create_tween()
	tw.tween_property(mesh, "scale", Vector3.ZERO, 0.3)
	tw.tween_callback(body.queue_free)


static func _floor_point(parent: Node, pos: Vector3) -> Vector3:
	var n3 := parent as Node3D
	if n3 == null:
		return Vector3.INF
	var space := n3.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 1.0, 0), pos + Vector3(0, -40.0, 0), 1)
	var ex: Array[RID] = []
	for g in ["player", "enemies"]:
		for n in parent.get_tree().get_nodes_in_group(g):
			if n is CollisionObject3D:
				ex.append(n.get_rid())
	q.exclude = ex
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return Vector3.INF
	return hit["position"]


static func explode(parent: Node, pos: Vector3, radius: float, damage: float, element: int, shooter: Node, knockdown := false) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	burst(parent, pos, element, true)
	var tree := parent.get_tree()
	var hit_any := false
	for group in ["player", "enemies"]:
		for t in tree.get_nodes_in_group(group):
			if t == shooter or not t.has_method("take_damage") or t.get("dead"):
				continue
			var off: Vector3 = t.global_position + Vector3(0, 1.0, 0) - pos
			var d := off.length()
			if d > radius:
				continue
			var dir := Vector3(off.x, 0.0, off.z)
			dir = dir.normalized() if dir.length() > 0.01 else Vector3.UP
			t.set_meta("hit_element", element)
			t.take_damage(damage * (1.0 - 0.5 * d / radius), dir * 3.0)
			burst(parent, t.global_position + Vector3(0, 1.0, 0), element, false)
			if knockdown and t.has_method("knock_down"):
				t.knock_down(dir)
			hit_any = true
	if hit_any and is_instance_valid(shooter) and shooter.has_method("on_hit_landed"):
		shooter.on_hit_landed(damage)


static func to_ice(root: Node3D) -> void:
	for n in root.get_children():
		if n is CollisionShape3D:
			continue
		if n is Node3D:
			n.visible = false
	var m := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = 0.2
	c.height = 1.3
	c.radial_segments = 5
	c.rings = 1
	m.mesh = c
	m.rotation_degrees = Vector3(-90, 0, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.9, 1.0, 0.65)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.1
	m.material_override = mat
	root.add_child(m)


static func recolor_fire(root: Node, a: Color, b: Color) -> void:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([a, b, Color(b.r, b.g, b.b, 0.0)])
	var tex := GradientTexture1D.new()
	tex.gradient = g
	for n in root.find_children("*", "GPUParticles3D", true, false):
		var pm = n.process_material
		if pm is ParticleProcessMaterial:
			var c: ParticleProcessMaterial = pm.duplicate()
			c.color_ramp = tex
			n.process_material = c
	for l in root.find_children("*", "OmniLight3D", true, false):
		l.light_color = a


static func make_rock(scene: PackedScene, width: float, height_mult := 1.0) -> Node3D:
	var holder := Node3D.new()
	var rock: Node3D = scene.instantiate()
	holder.add_child(rock)
	var box := _local_aabb(rock)
	var h := 1.0
	if box.size.x > 0.001:
		var s := width / maxf(box.size.x, box.size.z)
		rock.scale = Vector3(s, s * height_mult, s)
		rock.position = Vector3(
			-(box.position.x + box.size.x * 0.5) * s,
			-box.position.y * s * height_mult,
			-(box.position.z + box.size.z * 0.5) * s)
		h = box.size.y * s * height_mult
	holder.set_meta("h", h)
	return holder


static func _local_aabb(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for m in root.find_children("*", "MeshInstance3D", true, false):
		var t := Transform3D.IDENTITY
		var n: Node = m
		while n != null and n != root:
			if n is Node3D:
				t = (n as Node3D).transform * t
			n = n.get_parent()
		var b: AABB = t * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


static func recenter_visual(root: Node3D) -> void:
	var box := _local_aabb(root)
	if box.size == Vector3.ZERO:
		return
	var c := box.position + box.size * 0.5
	for n in root.get_children():
		if n is Node3D and not (n is CollisionShape3D):
			(n as Node3D).position -= Vector3(c.x, 0.0, c.z)


static func water_spout() -> Node3D:
	var vis := Node3D.new()
	var script = load("res://scripts/water_stream.gd")
	if script == null or water_mat == null:
		return vis
	for i in 2:
		var a := TAU * float(i) / 2.0
		var m := MeshInstance3D.new()
		m.set_script(script)
		m.set("length", randf_range(2.8, 3.6))
		m.set("radius", 0.42)
		m.material_override = water_mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.extra_cull_margin = 3.0
		m.rotation_degrees = Vector3(-90, 0, 0)
		m.position = Vector3(cos(a), 0.0, sin(a)) * 0.75
		vis.add_child(m)
	return vis


static func flip_body(model: Node3D, sgn: float, tree: SceneTree, t := 0.42) -> void:
	var tw := tree.create_tween()
	tw.tween_method(_flip_step.bind(model, sgn), 0.0, TAU, t)
	tw.tween_callback(_flip_end.bind(model))


static func _flip_step(a: float, model: Node3D, sgn: float) -> void:
	if not is_instance_valid(model):
		return
	var th := a * sgn
	model.rotation.x = th
	model.position = Basis(Vector3.UP, model.rotation.y) * Vector3(0.0, 1.0 - cos(th), -sin(th))


static func _flip_end(model: Node3D) -> void:
	if is_instance_valid(model):
		model.rotation.x = 0.0
		model.position = Vector3.ZERO


static func flash(model: Node, element: int, tree: SceneTree) -> void:
	if model == null or tree == null:
		return
	var col: Color = COLORS[element] if element >= 0 and element < COLORS.size() else Color.WHITE
	col.a = 0.45
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = col
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	for m in meshes:
		m.material_overlay = mat
	await tree.create_timer(0.12).timeout
	for m in meshes:
		if is_instance_valid(m):
			m.material_overlay = null


# ---------- Rides and lifts ----------

static func make_slab(scene: PackedScene, width: float, thickness: float) -> Node3D:
	var holder := Node3D.new()
	var rock: Node3D = scene.instantiate()
	holder.add_child(rock)

	var box := _local_aabb(rock)
	if box.size.x > 0.001 and box.size.y > 0.001:
		var sxz := width / maxf(box.size.x, box.size.z)
		var sy := thickness / box.size.y
		rock.scale = Vector3(sxz, sy, sxz)
		rock.position = Vector3(
			-(box.position.x + box.size.x * 0.5) * sxz,
			-(box.position.y + box.size.y) * sy,
			-(box.position.z + box.size.z * 0.5) * sxz
		)

	holder.set_meta("h", thickness)
	return holder


static func tornado_under() -> Node3D:
	var scene = load("res://scenes/air_tornado_vfx.tscn")
	if scene == null:
		return null
	var vis: Node3D = scene.instantiate()
	var box := _local_aabb(vis)
	if box.size.y > 0.001:
		var c := box.position + box.size * 0.5
		for n in vis.get_children():
			if n is Node3D and not (n is CollisionShape3D):
				(n as Node3D).position -= Vector3(c.x, box.position.y, c.z)
		vis.scale = Vector3.ONE / box.size.y
	var holder := Node3D.new()
	holder.add_child(vis)
	return holder


static func fire_jets() -> Node3D:
	var holder := Node3D.new()
	for side in [-0.18, 0.18]:
		var jet := Node3D.new()
		jet.position = Vector3(side, 0.05, 0.0)
		holder.add_child(jet)
		if fire_scene != null:
			var src: Node = fire_scene.instantiate()
			for n in src.find_children("*", "GPUParticles3D", true, false):
				var d := n.duplicate() as GPUParticles3D
				d.lifetime = minf(d.lifetime, 0.22)
				var pm = d.process_material
				if pm is ParticleProcessMaterial:
					var c := pm.duplicate() as ParticleProcessMaterial
					c.direction = Vector3(0, -1, 0)
					c.spread = 12.0
					c.initial_velocity_min = 2.0
					c.initial_velocity_max = 3.4
					c.gravity = Vector3(0, -5, 0)
					c.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
					c.emission_sphere_radius = 0.07
					d.process_material = c
				d.local_coords = false
				d.emitting = true
				d.position = Vector3.ZERO
				jet.add_child(d)
			src.free()
		else:
			var s := SphereMesh.new()
			s.radius = 0.07
			s.height = 0.14
			s.material = _unshaded()
			var p := CPUParticles3D.new()
			p.amount = 14
			p.lifetime = 0.22
			p.local_coords = false
			p.direction = Vector3(0, -1, 0)
			p.spread = 12.0
			p.initial_velocity_min = 2.0
			p.initial_velocity_max = 3.4
			p.gravity = Vector3(0, -5, 0)
			p.color = Color(1.0, 0.55, 0.1, 0.75)
			p.mesh = s
			jet.add_child(p)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.15)
	light.light_energy = 0.65
	light.omni_range = 3.5
	light.position = Vector3(0, -0.2, 0)
	holder.add_child(light)
	return holder


static func water_column() -> Node3D:
	var holder := Node3D.new()
	var core := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.45
	cyl.bottom_radius = 0.55
	cyl.height = 1.0
	cyl.radial_segments = 18
	core.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.9, 1.0, 0.42)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.1
	core.material_override = mat
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(core)
	holder.set_meta("core", core)
	return holder


static func set_water_column_height(holder: Node3D, h: float) -> void:
	var core = holder.get_meta("core", null)
	if core != null and is_instance_valid(core):
		core.scale.y = h
		core.position.y = h * 0.5


# ---------- Freeze ----------

static func _ice_mat() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.9, 1.0, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.1
	return mat


static func ice_block(target: Node3D, duration: float) -> void:
	if target == null or not target.is_inside_tree():
		return
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.6, 2.4, 1.6)
	m.mesh = box
	m.material_override = _ice_mat()
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.position = Vector3(0, 1.2, 0)
	m.scale = Vector3.ONE * 0.25
	target.add_child(m)
	var tw := m.create_tween()
	tw.tween_property(m, "scale", Vector3.ONE, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_interval(maxf(duration - 0.15, 0.1))
	tw.tween_callback(_shatter_ice.bind(m))


static func _shatter_ice(m: Node3D) -> void:
	if not is_instance_valid(m) or not m.is_inside_tree():
		return
	var pos := m.global_position
	var parent: Node = m.get_tree().current_scene
	m.queue_free()
	if parent != null:
		burst(parent, pos, 1, true, 1)


static func ice_spikes() -> Node3D:
	var vis := Node3D.new()
	var mat := _ice_mat()
	for i in 5:
		var a := TAU * float(i) / 5.0 + randf_range(-0.2, 0.2)
		var r := 0.0 if i == 0 else randf_range(0.8, 1.3)
		var h := 2.6 if i == 0 else randf_range(1.3, 2.2)
		var c := CylinderMesh.new()
		c.top_radius = 0.0
		c.bottom_radius = randf_range(0.22, 0.35)
		c.height = h
		c.radial_segments = 5
		c.rings = 1
		var m := MeshInstance3D.new()
		m.mesh = c
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.position = Vector3(cos(a) * r, h * 0.5, sin(a) * r)
		m.rotation = Vector3(randf_range(-0.15, 0.15), randf() * TAU, randf_range(-0.15, 0.15))
		vis.add_child(m)
	return vis


# Clean, subtle flame aura instead of a busy spinning wheel
static func fire_wheel(root: Node3D) -> void:
	var src: Array = root.find_children("*", "GPUParticles3D", true, false)
	for n in src:
		var p := n as GPUParticles3D
		p.lifetime = minf(p.lifetime, 0.22)
		p.emitting = true


static func water_float(model: Node3D, grow_time := 1.2) -> Node3D:
	var holder := Node3D.new()
	model.add_child(holder)
	holder.position = Vector3(0, 1.5, 0.9)
	var ball := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.32
	sph.height = 0.64
	ball.mesh = sph
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.85, 1.0, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.1
	ball.material_override = mat
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(ball)
	holder.scale = Vector3.ONE * 0.25
	holder.create_tween().tween_property(holder, "scale", Vector3.ONE, grow_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return holder
