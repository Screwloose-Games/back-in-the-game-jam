class_name ElevatorOutroKnobs
extends RefCounted

## Every tunable value for the asteroid level's elevator outro, in one place --
## the departure's counterpart to ElevatorIntroKnobs, and much shorter, because
## the outro's shot timing is already baked into animations/elevator_outro.anim.tres
## and its geometry is authored in the .tscn. What is left is what is read at the
## point of use: camera runtime numbers and copy.

#region Camera runtime
# Read at the point of use. Editing these takes effect on the next run.

## Seconds to blend the live gameplay camera onto the anchor when the outro
## starts. Unlike the intro, which opens on a cut before the player has seen
## anything, this takes over mid-play -- so it settles rather than snaps.
const ENTER_BLEND_TIME := 0.35

## Seconds to blend back at CLEANUP. The run ends here, so this is a formality,
## but a zero would snap the frame on the one shot meant to read as a close.
const EXIT_BLEND_TIME := 0.35

## Field of view of the outro camera. Kept near the gameplay camera's 67 for the
## same reason as the intro: the blend interpolates position and rotation but NOT
## fov, so a distant value snaps on the handover.
const CUTSCENE_FOV := 62.0

## Radius of the player rig's hull, from prefab_player.tscn. Cross-checked
## against the shape itself at runtime rather than trusted.
const RIG_HULL_RADIUS := 0.4
#endregion

#region Text
# All copy in one place, like the intro's, because copy is the thing most likely
# to change.

const HUD_TITLE := "EXTRACTION COMPLETE"
#endregion
