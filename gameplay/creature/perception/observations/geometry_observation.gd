class_name GeometryObservation
extends RefCounted

## Something perception noticed about physical space (perception.md section 10).
## Flows to Spatial Memory, never to Suspicion.
##
## The representation may later become voxel- or chunk-oriented. The semantic API
## must not change: perception observed something about space, and Spatial Memory
## decides what that does to its belief. In particular, an observation carries a
## `confidence` rather than being a fact -- a cell probed at the far edge of the
## creature's sensing radius should not overwrite a memory it walked through.
##
## This name is shared with the Spatial Memory module by design; see the module
## README and the note in spatial_memory.md.

## FREE -- the creature perceived open space here.
## SOLID -- the creature perceived matter here.
## CLEARANCE -- the creature measured how wide the gap here is. `clearance` is the
## number that matters and `type` alone is not enough to act on.
enum ObservationType { FREE, SOLID, CLEARANCE }

var type: ObservationType = ObservationType.FREE
## The cell this describes. Perception reports volumes, not points, because a point
## sample of a voxel world is a claim it cannot support.
var region: AABB = AABB()
## Representative point inside `region`, normally its centre. Convenience for
## consumers that reason about points.
var position: Vector3 = Vector3.ZERO
## Measured free width in metres. Only meaningful when type == CLEARANCE.
var clearance: float = 0.0
## How much to trust this, 0..1. Falls off with sensing distance.
var confidence: float = 1.0
## Seconds on the owning CreaturePerception's clock.
var observed_at: float = 0.0


static func make(
	p_type: ObservationType,
	p_region: AABB,
	p_confidence: float,
	p_observed_at: float,
	p_clearance: float = 0.0
) -> GeometryObservation:
	var observation := GeometryObservation.new()
	observation.type = p_type
	observation.region = p_region
	observation.position = p_region.get_center()
	observation.clearance = p_clearance
	observation.confidence = p_confidence
	observation.observed_at = p_observed_at
	return observation


func type_name() -> String:
	match type:
		ObservationType.FREE:
			return "FREE"
		ObservationType.SOLID:
			return "SOLID"
		_:
			return "CLEARANCE"


func to_dictionary() -> Dictionary:
	return {
		"type": type_name(),
		"region": region,
		"position": position,
		"clearance": clearance,
		"confidence": confidence,
		"observed_at": observed_at,
	}
