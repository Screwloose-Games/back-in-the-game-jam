class_name NavMotionCommand
extends RefCounted

## What the local planner decided the body should do this tick
## (navigation.md section 20's `AlienMotionCommand`).
##
## THE WHOLE INTERFACE BETWEEN NAVIGATION AND A BODY. Section 20 lists seven things the
## planner determines -- current mode, next desired position, preferred forward, preferred
## orientation, preferred surface normal, whether to prepare a leap, whether to squeeze --
## and every one of them is a field below. Nothing else crosses the boundary, which is why
## the body can be a CharacterBody3D, a kinematic node or a Vector3 in a test.
##
## A DIRECTION AND A SPEED, NOT A RESOLVED POSITION. `desired_position` is where the body
## would arrive if nothing were in the way, and it is advisory; contact resolution belongs
## to whatever is moving the body. A planner that returned only a position would have to
## own collision response, and would then be resolving the same contact the physics server
## is about to resolve differently.
##
## `abort` IS NOT AN ERROR CODE. Section 40 lists failures the alien should visibly react
## to rather than push through -- a crevice it cannot enter, a surface that is not there,
## a leap invalidated on the launch tick. A command carrying one is a well-formed
## instruction to stop and let the behaviour layer decide, not a bug.

## Section 40's recoverable local failures. NONE is by far the common case.
enum Abort {
	NONE,
	## Section 8.2: nothing within tentacle reach, so crawling cannot continue here.
	NO_SURFACE,
	## There is a surface, and every direction off it is blocked. Section 40 has no name for
	## this and it needs one: it was reported as NO_SURFACE, which sent the facade off to
	## raise a GEOMETRY_MISMATCH about a wall the alien could see perfectly well and was
	## simply wedged against. A stall whose stated reason is wrong costs an afternoon.
	BLOCKED,
	## Section 40.2: repeated attempts, no progress. Stop rather than grind.
	CREVICE_GRIND,
	## Section 10.3: neither body fits. There is no route here at any speed.
	NO_FIT,
	## Section 40.5: the flight stopped being clear while the alien was winding up.
	LEAP_INVALIDATED,
}

var mode: NavLocomotion.Mode = NavLocomotion.Mode.SURFACE_CRAWL
## Unit heading. Zero when the command is a stall.
var desired_direction: Vector3 = Vector3.ZERO
## Advisory target for this tick. See the class note: contact resolution is not ours.
var desired_position: Vector3 = Vector3.ZERO
var desired_speed: float = 0.0
var preferred_forward: Vector3 = Vector3.FORWARD
var preferred_up: Vector3 = Vector3.UP
var preferred_surface_normal: Vector3 = Vector3.UP
var squeeze: bool = false
var preparing_leap: bool = false
## Section 11.1. Set only on the tick a leap launches, and constant for the whole flight
## thereafter -- Invariant 4 forbids redirection, so nothing may recompute it mid-air.
var leap_velocity: Vector3 = Vector3.ZERO
var clearance: float = 0.0
## This tick is escaping a pose the body should not be in, not executing the route.
##
## SET RATHER THAN INFERRED, because the two recoveries look like ordinary motion from
## outside and are the two states worth seeing on screen. A body too close to terrain to
## cast from, and a body that has slipped off its surface entirely, both produce a perfectly
## normal-looking command in a perfectly normal-looking mode -- and an alien visibly
## nudging itself off a wall reads as a bug unless something says what it is doing.
var recovering: bool = false
var abort: Abort = Abort.NONE


## The ordinary case. Everything else is a field the caller sets afterwards, because a
## `make` taking all thirteen would break gdlint's argument cap and be unreadable anyway.
static func make(
	p_mode: NavLocomotion.Mode, p_direction: Vector3, p_speed: float, p_from: Vector3
) -> NavMotionCommand:
	var command := NavMotionCommand.new()
	command.mode = p_mode
	command.desired_direction = p_direction.normalized()
	command.desired_speed = p_speed
	command.desired_position = p_from + command.desired_direction * p_speed
	command.preferred_forward = command.desired_direction
	return command


## A command that says "do not move, and here is why". Section 40's stop-rather-than-push
## answer, and the thing the facade turns into an inspection request.
static func stalled(p_mode: NavLocomotion.Mode, p_why: Abort) -> NavMotionCommand:
	var command := NavMotionCommand.new()
	command.mode = p_mode
	command.abort = p_why
	return command


func is_stalled() -> bool:
	return abort != Abort.NONE


static func abort_name(p_abort: Abort) -> String:
	match p_abort:
		Abort.NONE:
			return "none"
		Abort.NO_SURFACE:
			return "no_surface"
		Abort.BLOCKED:
			return "blocked"
		Abort.CREVICE_GRIND:
			return "crevice_grind"
		Abort.NO_FIT:
			return "no_fit"
		Abort.LEAP_INVALIDATED:
			return "leap_invalidated"
	return "unknown"


func to_dictionary() -> Dictionary:
	return {
		"mode": NavLocomotion.mode_name(mode),
		"desired_direction": desired_direction,
		"desired_position": desired_position,
		"desired_speed": desired_speed,
		"preferred_forward": preferred_forward,
		"preferred_up": preferred_up,
		"preferred_surface_normal": preferred_surface_normal,
		"squeeze": squeeze,
		"preparing_leap": preparing_leap,
		"leap_velocity": leap_velocity,
		"clearance": clearance,
		"recovering": recovering,
		"abort": abort_name(abort),
	}
