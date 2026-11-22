class_name Clash
extends RefCounted

# Element numbers: 0 air, 1 water, 2 earth, 3 fire
const BEATS := {
	0: [3, 1, 2],   # air blows away fire, water and earth
	3: [1, 2, 0],   # fire quenches water, burns earth, blows away air
	2: [1, 3],      # earth breaks ice and puts out fire
	1: [3, 0, 2],   # water puts out fire, flushes away air and earth
}


static func beats(attacker: int, defender: int) -> bool:
	if not BEATS.has(attacker):
		return false
	return defender in BEATS[attacker]
