class_name NavPatchResult
extends RefCounted

## What one completed local patch changed (navigation.md sections 24.2, 39).
##
## RETURNED RATHER THAN SIGNALLED FROM INSIDE THE PATCHER, the same way
## `SuspicionHotspotField.rebuild` returns its changes: emitting from within the patch
## would let a listener re-enter the graph part-way through an edit, and the graph is the
## one structure in this module with no defence against that.
##
## Section 39 asks the overlay to draw "dirty chunks, new candidates, accepted nodes, new
## edges", so all four are here as data rather than as a count in a log line.

var region: AABB = AABB()
var chunk: Vector3i = Vector3i.ZERO
var nodes_added: PackedInt32Array = PackedInt32Array()
var edges_added: int = 0
## WIGGLE edges the normal body now fits. This is what turns Scenario F from "the graph
## gained some nodes" into "the route got better".
var edges_upgraded: int = 0
var nodes_refreshed: int = 0
var terrain_revision: int = 0


static func make(p_region: AABB, p_chunk: Vector3i, p_revision: int) -> NavPatchResult:
	var result := NavPatchResult.new()
	result.region = p_region
	result.chunk = p_chunk
	result.terrain_revision = p_revision
	return result


func is_empty() -> bool:
	return nodes_added.is_empty() and edges_added == 0 and edges_upgraded == 0


func to_dictionary() -> Dictionary:
	return {
		"region": region,
		"chunk": chunk,
		"nodes_added": nodes_added.size(),
		"edges_added": edges_added,
		"edges_upgraded": edges_upgraded,
		"nodes_refreshed": nodes_refreshed,
		"terrain_revision": terrain_revision,
	}
