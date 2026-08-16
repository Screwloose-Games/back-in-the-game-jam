class_name EncounterReport
extends RefCounted

## What Behavior tells the Director, once per tick (director.md, "The single output").
##
## Everything here is something only Behavior knows. The two navigation metrics are the
## reason this type exists at all: `RouteFollower.distance_remaining()` and
## `NavRoute.status` are what the Director's proximity and stall terms need, and a
## level-scoped Director reaching into one creature's route follower to get them would be
## a dependency the design does not allow. Behavior already holds the route, so both ride
## up here instead.
##
## One struct up, one struct down, once per tick. The whole coupling is a pure function of
## two structs, so it tests without a scene, a body, or a baked graph.

## No route means NO PRESSURE, and that has to be spelled or the Director reads it
## backwards. `RouteFollower.distance_remaining` returns 0.0 when there is no route, and
## the menace term is `w_proximity * (1 - clamp(route_distance / menace_range))` -- so a
## zero would report an alien breathing down your neck while it idles at a nest, forever.
const NO_ROUTE_DISTANCE: float = INF

var state: CreatureState.State = CreatureState.State.UNALERTED
var time_in_state: float = 0.0
var position: Vector3 = Vector3.ZERO

## Path length remaining, in metres, or NO_ROUTE_DISTANCE. Never Euclidean: an alien twelve
## metres away through forty metres of tunnel is not delivering twelve metres of dread.
var route_distance: float = NO_ROUTE_DISTANCE
## True when there is no route at all, so the Director's stall term does not fire on
## "the creature has not been given anywhere to go".
var target_reachable: bool = true

var has_visual_contact: bool = false
## Owed to the HUNTING tree. Ships false, which zeroes the Director's w_attack term.
var attack_window_open: bool = false
## Owed to the HUNTING tree. Ships false, which zeroes the Director's w_lurk term.
var lurking_at_crevice: bool = false


func to_dictionary() -> Dictionary:
	return {
		"state": CreatureState.state_name(state),
		"time_in_state": time_in_state,
		"position": position,
		"route_distance": route_distance,
		"target_reachable": target_reachable,
		"has_visual_contact": has_visual_contact,
		"attack_window_open": attack_window_open,
		"lurking_at_crevice": lurking_at_crevice,
	}
