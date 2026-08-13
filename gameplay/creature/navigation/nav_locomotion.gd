class_name NavLocomotion
extends RefCounted

## The four physically distinct ways the alien moves (navigation.md section 7).
##
## A holder for one enum, because GDScript has no free-standing enums and every
## alternative is worse: duplicating the enum in each file that needs it makes two
## sources of truth, and hanging it off the facade means `route/` has to import a Node
## to name a movement mode.
##
## THESE ARE NOT INTERCHANGEABLE ANIMATIONS (section 7). Surface crawl keeps contact
## with terrain, tunnel swim is unsupported but enclosed, wiggle is a compressed body
## in a passage the normal body does not fit, and leap is an unpowered straight line
## that cannot be redirected once begun (Invariant 4). Code that treats one as another
## produces an alien that swims through solid rock or drifts across open space, which
## Invariant 3 forbids.
##
## Phases 1-2 implement none of the controllers. The enum exists now because
## `RouteFollower.can_skip_to` is defined in terms of it (section 19) and needs to
## refuse the three modes it cannot yet check, rather than silently allowing them.

enum Mode { SURFACE_CRAWL, TUNNEL_SWIM, WIGGLE, LEAP }


## Human-readable name, for debug overlays and failure messages.
static func mode_name(mode: Mode) -> String:
	match mode:
		Mode.SURFACE_CRAWL:
			return "surface_crawl"
		Mode.TUNNEL_SWIM:
			return "tunnel_swim"
		Mode.WIGGLE:
			return "wiggle"
		Mode.LEAP:
			return "leap"
	return "unknown"
