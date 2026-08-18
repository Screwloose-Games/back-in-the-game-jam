class_name DirectorParty
extends Node

## Where the players actually are. THE ONLY FILE IN THIS MODULE PERMITTED TO KNOW THAT.
##
## director.md's central asymmetry is that the Director "is the only system permitted to know
## the truth.
##
## THE CENTROID, NOT THE NEAREST PLAYER. director.md says the bias "drifts the alien toward
## the party". Tracking the nearest player would make ambient drift follow one person closely
## enough to read as knowledge, which is exactly the line this file exists not to cross. With
## one player the centroid is that player.

## Explicit wiring wins, the same way CreaturePerception.targets and CreatureBehavior.nests do.
@export var players: Array[Node3D] = []
## The fallback when nothing is wired. `prefab_player.tscn` already puts PlayerBody in this
## group, so a level that wires nothing at all still works.
@export var player_group: StringName = &"player"

var _members: Array[Node3D] = []
var _anchor: Vector3 = Vector3.ZERO


## Recollects the live members and recomputes the anchor. Called once per Director tick, not
## per creature: a level with three aliens must not walk the group list three times a frame.
func refresh() -> void:
	_members = _collect()
	_anchor = _centroid(_members)


## The live party. A copy, because a caller that appended to the internal array would grow the
## party from outside and nothing would say so.
func members() -> Array[Node3D]:
	return _members.duplicate()


func size() -> int:
	return _members.size()


## What "toward the party" means, or Vector3.ZERO when there is nobody to be toward.
##
## ZERO IS A REAL PLACE, and that is a trap worth naming: an empty party anchors on the world
## origin, and a nest near the origin would score a roam bonus for no reason. The Director
## therefore publishes roam_bias 0.0 whenever `size()` is zero, which makes the anchor value
## irrelevant rather than merely harmless.
func anchor() -> Vector3:
	return _anchor


## Explicit wiring, then the group, then nothing. Freed and null entries are dropped on every
## refresh rather than at some teardown that may never run.
func _collect() -> Array[Node3D]:
	var found: Array[Node3D] = []
	for node: Node3D in players:
		if is_instance_valid(node):
			found.append(node)
	if not found.is_empty() or not is_inside_tree():
		return found
	for node: Node in get_tree().get_nodes_in_group(player_group):
		var member := node as Node3D
		if member != null:
			found.append(member)
	return found


static func _centroid(of: Array[Node3D]) -> Vector3:
	if of.is_empty():
		return Vector3.ZERO
	var total := Vector3.ZERO
	for member: Node3D in of:
		total += _position_of(member)
	return total / float(of.size())


## Node3D.global_position needs the node to be in a tree, and reading it for a detached one
## logs "Condition !is_inside_tree() is true" -- which GUT counts as an unexpected error and
## FAILS THE TEST. Every fixture in this project builds detached nodes on purpose, so this is
## the same guard CreatureBehavior._body_position() and CreaturePerception._own_position()
## use, for the same reason.
static func _position_of(node: Node3D) -> Vector3:
	return node.global_position if node.is_inside_tree() else node.position
