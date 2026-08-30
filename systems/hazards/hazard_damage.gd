class_name HazardDamage
extends RefCounted

## How a world object bills a player. The player prefab's node names live here and
## nowhere else, so a hazard never has to know how a suit is built -- the same
## group-then-named-child lookup LifeSupportCube.tethered_players() already uses.

## The group every player body joins.
const PLAYER_GROUP := &"player"

## The group a hazard joins so the level can wire its noise into the creature's
## perception. See AsteroidLevel._wire_hazard_noise.
const NOISE_GROUP := &"world_noise_emitter"


## Share of a radial effect at `distance`, falling linearly to nothing at `radius`.
static func falloff(distance: float, radius: float) -> float:
	if radius <= 0.0:
		return 0.0
	return clampf(1.0 - distance / radius, 0.0, 1.0)


static func players(tree: SceneTree) -> Array[Node3D]:
	var found: Array[Node3D] = []
	if tree == null:
		return found
	for node: Node in tree.get_nodes_in_group(PLAYER_GROUP):
		var body := node as Node3D
		if body != null:
			found.append(body)
	return found


static func health_of(body: Node) -> PlayerHealth:
	return body.get_node_or_null("Health") as PlayerHealth


static func power_of(body: Node) -> PlayerPowerClient:
	return body.get_node_or_null("PowerClient") as PlayerPowerClient


static func oxygen_of(body: Node) -> PlayerOxygen:
	return body.get_node_or_null("Oxygen") as PlayerOxygen


static func input_of(body: Node) -> PlayerInput:
	return body.get_node_or_null("Input") as PlayerInput


static func head_of(body: Node) -> Node3D:
	return body.get_node_or_null("Head") as Node3D


## Pushes a suit away from `from`, applied AT `from` so the off-centre lever tumbles it
## away from whatever hit it rather than spinning it about nothing.
static func shove(body: Node3D, from: Vector3, impulse: float) -> void:
	var locomotion := body.get_node_or_null("Locomotion") as PlayerLocomotion
	if locomotion == null or impulse <= 0.0:
		return
	var direction := body.global_position - from
	if direction.length_squared() <= 0.0:
		direction = Vector3.UP
	locomotion.apply_external_impulse(direction.normalized() * impulse, from)
