class_name CreatureNavDemoKnobs
extends RefCounted

## Every default this prototype writes down, per prototypes/AGENTS.md.
##
## MOST OF THE INTERESTING NUMBERS ARE NOT HERE, and that is deliberate. Crawl speed, turn
## radius, leap bias and the squeeze timings live on `LocomotionProfile` in the navigation
## module, because they are properties of the ALIEN rather than of this scene -- a
## prototype that redeclared them would be tuning a creature nobody ships. The settings
## resource exposes the module's numbers directly so a playtester can still drag them.

#region Bake
## Queries the bake may spend per physics frame.
##
## Far above the module's shipped 384. This cave is roughly 64 x 42 x 56 m, which is about
## 15 000 lattice points; at the default budget that is a visible second and a half of
## empty overlay before anything appears, and the first thing a playtester concludes is
## that the bake is broken.
const BAKE_QUERIES: float = 4000.0
const BAKE_QUERIES_MIN: float = 256.0
const BAKE_QUERIES_MAX: float = 12000.0
#endregion

#region Mining
## Edge length of the alien-sized brush. Wider than the normal body's 2.5 m, so what it
## carves is a passage the alien can use once it knows about it (Scenario F).
const DIG_WIDE: float = 4.0
## Edge length of the player-only brush. Narrower than the squeezed body's 1.5 m, so the
## world graph gains open space and the alien still cannot follow (Scenario G).
const DIG_NARROW: float = 1.0
const DIG_RANGE: float = 40.0
#endregion

#region Commanding
## How far off a clicked surface the goal is placed.
##
## THE MOST LIKELY BUG IN THE WHOLE PROTOTYPE if it is zero. A raycast hit is ON the wall,
## so the goal sits inside it, `RoutePlanner.attach` fails at the destination end, and
## every single click returns a PARTIAL route -- which looks exactly like broken
## pathfinding and is nothing of the sort. Scaled from the body's own clearance at use.
const GOAL_STANDOFF_SCALE: float = 1.2
const GOAL_STANDOFF_SCALE_MIN: float = 1.0
const GOAL_STANDOFF_SCALE_MAX: float = 3.0
const PICK_RANGE: float = 200.0
#endregion

#region Camera
## The neighbouring prototype's player ships with a 20 m far plane, which is atmospheric
## in a corridor and hides two thirds of this cave.
const CAMERA_FAR: float = 300.0
#endregion
