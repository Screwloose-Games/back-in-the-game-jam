class_name NavBodyState
extends RefCounted

## Where the body is, how it is moving, and what it is currently doing
## (navigation.md section 20's `AlienBodyState`).
##
## THE INPUT HALF OF THE LOCOMOTION CONTRACT; NavMotionCommand is the output half.
## Navigation does not own the body and never reads a transform off one -- section 20
## hands the planner a state, which is what lets the entire locomotion path be driven from
## a GUT test with no node, no physics server and no scene.
##
## `mode` AND `squeezed` DESCRIBE WHAT THE BODY IS DOING, NOT WHAT IT WAS ASKED TO DO, and
## the distinction is load-bearing. Section 9.3's hysteresis and section 10's squeeze
## timing are both defined against the mode already held; a state that echoed the last
## command back would make every transition instantaneous, and the hysteresis that exists
## to stop mode flicker would quietly stop doing anything.

var position: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
var forward: Vector3 = Vector3.FORWARD
var up: Vector3 = Vector3.UP
## Normal of the surface the body is holding. Left as UP when unattached rather than
## zeroed, so a caller building a basis from it gets a usable one.
var surface_normal: Vector3 = Vector3.UP
var mode: NavLocomotion.Mode = NavLocomotion.Mode.SURFACE_CRAWL
## Whether terrain is within tentacle reach. Invariant 3's entire subject: a body that is
## not attached and not leaping is somewhere the alien has no way to be.
var attached: bool = false
var squeezed: bool = false
## Local clearance in metres. Zero means "not measured", not "inside rock".
var clearance: float = 0.0


static func make(p_position: Vector3, p_forward: Vector3, p_up: Vector3) -> NavBodyState:
	var state := NavBodyState.new()
	state.position = p_position
	state.forward = p_forward.normalized()
	state.up = p_up.normalized()
	return state


func speed() -> float:
	return velocity.length()


func to_dictionary() -> Dictionary:
	return {
		"position": position,
		"velocity": velocity,
		"forward": forward,
		"up": up,
		"surface_normal": surface_normal,
		"mode": NavLocomotion.mode_name(mode),
		"attached": attached,
		"squeezed": squeezed,
		"clearance": clearance,
	}
