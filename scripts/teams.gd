class_name Teams
extends RefCounted


static func join(node: Node, team: int) -> void:
	node.set_meta("team", team)
	node.add_to_group("fighters")
	node.add_to_group("team_" + str(team))


static func team_of(n: Node) -> int:
	if n == null or not is_instance_valid(n):
		return -1
	return int(n.get_meta("team", -1))


# true when the two are on different teams (a node with no team counts as its own side)
static func is_enemy(a: Node, b: Node) -> bool:
	if a == null or b == null:
		return true
	var ta := team_of(a)
	var tb := team_of(b)
	if ta == -1 or tb == -1:
		return a != b
	return ta != tb


static func enemies_of(node: Node) -> Array:
	var out: Array = []
	for f in node.get_tree().get_nodes_in_group("fighters"):
		if f != node and is_enemy(node, f) and not f.get("dead"):
			out.append(f)
	return out


static func nearest_enemy(node: Node3D) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for f in enemies_of(node):
		var d := node.global_position.distance_to(f.global_position)
		if d < best_d:
			best_d = d
			best = f
	return best
