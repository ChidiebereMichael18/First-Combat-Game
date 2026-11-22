class_name Bend
extends RefCounted

# Element numbers: 0 air, 1 water, 2 earth, 3 fire
const AIR := 0
const WATER := 1
const EARTH := 2
const FIRE := 3
const RANGE := 45.0   # every shot travels about this far, whatever the element

# Timing of your extra clips (seconds). Tune with the clip lengths printed in the Output panel.
const EARTHBLOCK := {"start": 0.0, "peak": 0.55, "end": 1.5}
# waterBend: the hand movement runs from "start" to "gather", then a punch sends the water out
const WATERBEND := {"start": 0.6, "gather": 2.4}

# LIGHT attacks (J or left click): small shots.
#  pat  = shape: single, double, fan3, fan4, ring
#  fire = how FIRE does this step differently (the kicks throw a spinning fire wheel)
const COMBO := [
	{"clip": "attack",   "start": 0.60, "end": 1.45, "releases": [1.05],       "from": "hand", "dmg": 1.0, "size": 1.0, "pat": "single"},
	{"clip": "kick",     "start": 0.40, "end": 1.25, "releases": [0.80],       "from": "foot", "dmg": 1.2, "size": 1.1, "pat": "double",
		"fire": {"kind": "spin", "pat": "single", "scale": 1.5, "speed": 22.0, "damage": 9.0, "knockback": 3.0}},
	{"clip": "uppercut", "start": 0.0,  "end": 0.5,  "releases": [0.30],       "from": "hand", "dmg": 1.1, "size": 1.0, "pat": "single"},
	{"clip": "attack",   "start": 0.60, "end": 2.25, "releases": [1.05, 1.80], "from": "hand", "dmg": 1.0, "size": 1.0, "pat": "single"},
	{"clip": "kick",     "start": 1.20, "end": 0.20, "releases": [0.80],       "from": "foot", "dmg": 1.3, "size": 1.1, "pat": "ring",
		"fire": {"kind": "spin", "pat": "single", "scale": 1.9, "speed": 20.0, "damage": 10.0, "knockback": 3.5}},
	{"clip": "uppercut", "start": 0.5,  "end": 1.0,  "releases": [0.80],       "from": "hand", "dmg": 1.2, "size": 1.1, "pat": "fan3"},
]

# HEAVY attack (H or right click): the power-punch clip, then one big shot of your element
const HEAVY := {"clip": "attack", "start": 2.50, "end": 3.00, "release": 2.75, "dmg": 1.0, "size": 1.0}
const HEAVY_STYLE := [
	{"speed": 30.0, "damage": 12.0, "knockback": 5.0, "scale": 2.2, "knockdown": true},                          # air
	{"kind": "blob", "speed": 18.0, "damage": 14.0, "knockback": 5.0, "scale": 2.2, "knockdown": true},          # water
	{"speed": 15.0, "damage": 16.0, "knockback": 5.0, "scale": 2.1, "knockdown": true},                          # earth
	{"speed": 20.0, "damage": 14.0, "knockback": 5.0, "scale": 2.3, "knockdown": true, "explode": 3.5},          # fire
]

# Base stats per element: air, water, earth, fire
const STATS := [
	{"speed": 35.0, "damage": 5.0,  "knockback": 3.5, "arc": 0.0, "homing": 0.0, "pierce": true},
	{"speed": 20.0, "damage": 6.0,  "knockback": 3.0, "arc": 0.0, "homing": 4.0, "pierce": false},
	{"speed": 20.0, "damage": 8.0,  "knockback": 2.5, "arc": 0.5, "homing": 0.0, "pierce": false},
	{"speed": 26.0, "damage": 8.0,  "knockback": 1.5, "arc": 0.0, "homing": 0.0, "pierce": false},
]

# The styles of J for each element. They cycle on every step of the combo.
const VARIANTS := [
	[{}],   # air
	[   # water: a thick ball, a long whip, an ice crystal
		{"kind": "blob", "speed": 17.0, "damage": 9.0, "knockback": 3.0, "homing": 3.0},
		{"kind": "whip", "speed": 34.0, "damage": 6.0, "knockback": 2.0, "homing": 0.0},
		{"kind": "ice",  "speed": 30.0, "damage": 8.0, "knockback": 2.0, "homing": 0.0},
	],
	[   # earth: small stones, a medium stone
		{"scale": 0.55, "speed": 26.0, "damage": 6.0, "knockback": 1.5},
		{"scale": 1.1, "speed": 20.0, "damage": 9.0, "knockback": 2.5},
	],
	[   # fire: red fire, blue fire, a round fireball
		{},
		{"kind": "blue", "speed": 34.0, "damage": 10.0, "knockback": 2.0},
		{"scale": 1.6, "speed": 22.0, "damage": 10.0, "knockback": 2.5},
	],
]


# The shape and style of a light step for this element (fire throws a spinning wheel on kicks)
static func step_style(step: Dictionary, element: int) -> Dictionary:
	var pat: String = step.get("pat", "single")
	var extra := {}
	if element == FIRE and step.has("fire"):
		extra = step["fire"].duplicate()
		pat = extra.get("pat", pat)
	return {"pat": pat, "extra": extra}


# Creates one projectile and adds it to the scene
static func spawn(shooter: Node3D, scene: PackedScene, element: int, aim: Vector3, start: Vector3, floor_y: float, on_floor: bool, dmg: float, size: float, variant: int, extra: Dictionary, target: Node3D) -> Node3D:
	if scene == null:
		return null
	var p = scene.instantiate()
	var s: Dictionary = STATS[element].duplicate()
	s.merge(VARIANTS[element][variant % VARIANTS[element].size()], true)
	s.merge(extra, true)
	var spd: float = s["speed"]
	var kind: String = s.get("kind", "")

	# Everything is set BEFORE add_child, because the projectile reads lifetime in _ready()
	p.element = element
	p.variant = 1 if (kind == "ice" or kind == "blue") else 0
	p.speed = spd
	p.damage = dmg * float(s["damage"])
	p.knockback = s["knockback"]
	p.arc = s["arc"]
	p.homing = s["homing"]
	p.pierce = s["pierce"]
	p.lifetime = float(s.get("range", RANGE)) / spd
	p.knockdown = s.get("knockdown", false)
	p.explode_radius = s.get("explode", 0.0)
	p.direction = aim
	p.shooter = shooter
	p.target = target

	match kind:
		"ice":
			Fx.to_ice(p)
		"blue":
			Fx.recolor_fire(p, Color(0.3, 0.55, 1.0), Color(0.75, 0.92, 1.0))
		"spin":
			Fx.fire_wheel(p)
		"blob":
			var main = p.get_node_or_null("StreamMain")
			var thin = p.get_node_or_null("StreamThin")
			if main != null:
				main.set("length", 1.7)
				main.set("radius", 0.6)
			if thin != null:
				thin.visible = false
		"whip":
			var main2 = p.get_node_or_null("StreamMain")
			var thin2 = p.get_node_or_null("StreamThin")
			if main2 != null:
				main2.set("length", 6.5)
				main2.set("radius", 0.13)
			if thin2 != null:
				thin2.set("length", 5.0)
				thin2.set("radius", 0.07)
	if element == AIR:
		Fx.recenter_visual(p)    # the pack's wind effect sits off to one side

	# Earth and water come up out of the ground in front of you first
	if (element == EARTH or element == WATER) and on_floor:
		var flat := Vector3(aim.x, 0.0, aim.z).normalized()
		p.rise_time = 0.22
		p.rise_height = maxf(start.y - floor_y, 0.8)
		start = Vector3(start.x, floor_y, start.z) + flat * 1.0

	shooter.get_parent().add_child(p)
	p.global_position = start
	p.look_at(p.global_position + aim, Vector3.UP)
	p.scale = Vector3.ONE * size * float(s.get("scale", 1.0))
	return p


# Fires the shape of an attack. `shoot` is a function(aim, origin, dmg, size, variant, extra).
static func pattern(pat: String, aim: Vector3, origin: Vector3, center: Vector3, dmg: float, size: float, variant: int, extra: Dictionary, shoot: Callable) -> void:
	match pat:
		"double":
			var side := aim.cross(Vector3.UP).normalized() * 0.45
			shoot.call(aim, origin + side, dmg * 0.7, size * 0.85, variant, extra)
			shoot.call(aim, origin - side, dmg * 0.7, size * 0.85, variant, extra)
		"fan3":
			for a in [-0.32, 0.0, 0.32]:
				shoot.call(aim.rotated(Vector3.UP, a), origin, dmg * 0.6, size * 0.85, variant, extra)
		"fan4":
			for a in [-0.48, -0.16, 0.16, 0.48]:
				shoot.call(aim.rotated(Vector3.UP, a), origin, dmg * 0.5, size * 0.8, variant, extra)
		"ring":
			var ex := extra.duplicate()
			ex["range"] = 13.0
			ex["speed"] = 20.0
			for i in 8:
				var a := TAU * float(i) / 8.0
				var d := Vector3(sin(a), 0.0, cos(a))
				shoot.call(d, center + d * 0.9, dmg * 0.6, size * 0.8, variant, ex)
		_:
			shoot.call(aim, origin, dmg, size, variant, extra)
