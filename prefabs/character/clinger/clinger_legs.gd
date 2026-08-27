class_name ClingerLegs
extends Node

## Poses the eight legs. Each is its own root node in the glTF carrying nothing but the
## translation out to its own shoulder, so A LEG'S OUTWARD DIRECTION IS ITS POSITION and
## nothing here has to know which leg is which -- add a ninth and it works.

## Curled back over the shell, dead-spider. What a dormant one reads as at four metres.
const CURLED_DEGREES := 55.0

## Flat on the rock, gripping.
const PLANTED_DEGREES := -6.0

## Thrown forward around a visor. Negative is toward the player, so a fresh grip is the
## most view it will ever take; every press after that opens the fan back up.
const GRIP_DEGREES := -18.0
const PEELED_DEGREES := 42.0

## How fast a leg reaches its pose.
const POSE_RATE := 9.0

var _legs: Array[Node3D] = []
var _axes: Array[Vector3] = []
var _shown := CURLED_DEGREES


## Collects every leg under an imported model and works out the axis each swings about.
func bind(model: Node3D) -> void:
	_legs.clear()
	_axes.clear()
	if model == null:
		return
	for child: Node in model.get_children():
		var leg := child as Node3D
		if leg == null or not leg.name.begins_with("leg_"):
			continue
		# Rotating about outward x up raises the tip away from the surface. A leg whose
		# shoulder sits on the shell's own axis has no outward direction to recover, and
		# an axis of zero would spin it; skip it rather than pose it wrong.
		var axis := leg.position.cross(Vector3.UP)
		if axis.is_zero_approx():
			continue
		_legs.append(leg)
		_axes.append(axis.normalized())


func advance(delta: float, wanted_degrees: float) -> void:
	_shown = lerpf(_shown, wanted_degrees, ClingerSurface.smoothing(POSE_RATE, delta))
	var angle := deg_to_rad(_shown)
	for index: int in _legs.size():
		_legs[index].basis = Basis(_axes[index], angle)


## The pose a phase wants, with `peel` walking the attached one open.
static func pose_for(phase: ClingerState.Phase, peel: float) -> float:
	match phase:
		ClingerState.Phase.DORMANT:
			return CURLED_DEGREES
		ClingerState.Phase.ATTACHED:
			return lerpf(GRIP_DEGREES, PEELED_DEGREES, clampf(peel, 0.0, 1.0))
		ClingerState.Phase.LEAPING:
			return GRIP_DEGREES
		ClingerState.Phase.DEAD:
			return CURLED_DEGREES
		_:
			return PLANTED_DEGREES


func debug_state() -> Dictionary:
	return {"legs": _legs.size(), "shown": _shown}
