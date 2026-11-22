extends MeshInstance3D
# A long, flowing tube of water. The head is at the origin, the body trails behind
# along +Z, and the shader makes it snake from side to side.

@export var length := 4.5      # how long the stream is
@export var radius := 0.3      # how thick it is
@export var rings := 64        # smoothness along the length
@export var sides := 14        # smoothness around
@export var lump := 0.18       # how uneven the thickness is


func _ready() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in rings:
		var u0 := float(i) / float(rings)
		var u1 := float(i + 1) / float(rings)
		for j in sides:
			var v0 := float(j) / float(sides)
			var v1 := float(j + 1) / float(sides)
			var a := _vert(u0, v0)
			var b := _vert(u0, v1)
			var c := _vert(u1, v0)
			var d := _vert(u1, v1)
			_tri(st, a, c, b)
			_tri(st, b, c, d)
	mesh = st.commit()


func _vert(u: float, v: float) -> Array:
	var ang := v * TAU
	var head := clampf(u / 0.08, 0.0, 1.0)
	var cap := sqrt(1.0 - pow(1.0 - head, 2.0))            # rounded head
	var taper := 1.0 - 0.9 * smoothstep(0.3, 1.0, u)       # thins toward the tail
	var bump := 1.0 + lump * sin(u * 20.0)                 # uneven thickness
	var r := radius * cap * taper * bump
	var pos := Vector3(cos(ang) * r, sin(ang) * r, length * u)
	var nrm := Vector3(cos(ang), sin(ang), 0.0)
	return [pos, Vector2(u, v), nrm]


func _tri(st: SurfaceTool, a: Array, b: Array, c: Array) -> void:
	for p in [a, b, c]:
		st.set_normal(p[2])
		st.set_uv(p[1])
		st.add_vertex(p[0])
