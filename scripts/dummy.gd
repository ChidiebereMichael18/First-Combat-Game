extends CharacterBody3D

var health := 100.0


func _ready() -> void:
	add_to_group("enemies")


func take_damage(amount: float, _from_dir := Vector3.ZERO) -> void:
	health -= amount
	print("Dummy health: ", health)
	if health <= 0.0:
		print("Dummy destroyed! Resetting.")
		health = 100.0
