class_name ElevatorCutsceneKnobs
extends RefCounted

## Every tunable value for the elevator cutscene prototype, in one place.
##
## Change a number here and re-run the scene. These values are read directly by
## the prototype's scripts and pushed onto the scene at startup, so they win over
## whatever is saved in the .tscn files.
##
## TWO KINDS OF NUMBER LIVE HERE AND THEY BEHAVE DIFFERENTLY.
##
## Behaviour (blends, speeds, energies, text) is read at the point of use, so
## editing it and re-running is the whole loop. Shot timing and camera poses are
## consumed by tools/build_elevator_intro_animation.gd and BAKED into
## animations/elevator_intro.anim.tres - editing one of those does nothing until
## the build script is re-run. Each region says which it is.
##
## GEOMETRY IS NOT HERE. Sizes and positions are authored in the .tscn so the
## editor viewport shows the same car the game does, which is the entire point of
## the director's scrub-and-preview workflow. The two numbers that have to exist
## in both places - DOOR_CLOSED_X and DOOR_TRAVEL - are guarded by a push_error in
## elevator_car.gd rather than trusted.

#region Shot timing
# BAKED INTO THE ANIMATION. Re-run tools/build_elevator_intro_animation.gd after
# changing anything in this region, or nothing happens.
#
# Seconds from the start of the cutscene. The three shots are the three panels of
# the pitch: a wide on the descending car, a push-in on one miner activating their
# helmet, and a match cut to the player's own eye.

## The opening: a full-screen shot of the quota monitor, held, then a match-framed
## hard cut to the same screen in 3D and a dolly back that reveals the car.
##
## THE READOUT IS THE PITCH, so it is what the film opens on. Everything below this
## used to start at zero and now starts at PROLOGUE_END - the three shots are
## unchanged, they just begin later.
const PROLOGUE_LENGTH := 3.0
const PULLBACK_DURATION := 2.5

## Derived, so the three cannot disagree about when the room is revealed.
const PROLOGUE_END := PROLOGUE_LENGTH + PULLBACK_DURATION

## Shot 1 runs from PROLOGUE_END to here: a static wide on the car, held dead still
## except for the rumble. Long enough to read the quota screen and register that
## this is routine.
const SHOT2_CUT_TIME := 11.5

## Shot 2 is a hard cut, then a dolly. The cut is what the storyboard's second
## panel is; the dolly is "move closer to one miner". A single eased move from the
## wide would have to swing through 140 degrees of yaw, which reads as a whip-pan
## rather than as a new shot.
const SHOT2_PUSH_IN_DURATION := 5.0

## When the miner's hand starts up toward the helmet, and how long the whole
## gesture takes. Sits inside the push-in so the camera is still closing when it
## happens.
const GESTURE_START := 13.7
const GESTURE_DURATION := 2.4

## The gesture itself, as a place to put the hand.
##
## A TARGET, NOT TWO EULER TRIPLES. The greybox version hand-picked angles for a
## shoulder and an elbow pivot, and its own comment records that the first guess
## was wrong in BOTH joints - at a shoulder roll of 132 degrees the upper arm went
## out rather than up. That is the argument this file already makes for camera
## poses: a target is something you can reason about and review in a diff, an
## Euler triple is something you arrive at by trial and error. The real rig is
## skinned, so the build script can do what the greybox could not and solve two
## bones onto the target by IK - the same way the shipped laser clips are solved
## onto the tool's rear_grip_point.
##
## Offsets from the HELMET CENTRE, in the character's own space, as
## (outward, up, forward). Outward is applied on whichever side the gesturing arm
## is, so this never has to know which way the art faces.
##
## BOUNDED BY THE ARM, NOT BY TASTE. Shoulder to wrist is 0.42 m and the shoulder
## sits 0.48 m below the helmet centre, so a target level with the visor is
## already out of reach and the solver would clamp to it - giving a straight arm
## reaching at the helmet rather than a bent one arriving at it. Hence the
## negative rise: the hand comes up to the jaw, not to the brow.
const GESTURE_HAND_OFFSET := Vector3(0.24, -0.12, 0.13)

## Which way the elbow breaks, in the same space. Only the component across the
## shoulder-to-hand line matters; it is what stops a two-bone solve choosing an
## equally valid pose with the elbow folded through the miner's own chest.
const GESTURE_ELBOW_POLE := Vector3(1.0, -0.6, -0.2)

## The match cut to first person. A hard cut: two keys one animation step apart.
const MATCH_CUT_TIME := 17.5

## How long the helmet HUD takes to fade up after the cut.
const HUD_FADE_IN := 0.9

## BEGIN WORKDAY fades in, holds, and fades out over this many seconds, centred
## on the clunk.
const TITLE_HOLD := 3.2

## The car reaching the bottom. The strobe flashes and the rumble stops.
const CLUNK_TIME := 20.5

## When the doors start moving, and how long they take to clear the opening.
const DOORS_OPEN_TIME := 21.1
const DOOR_TRAVEL_DURATION := 2.6

## Three brief tube brownouts across the descent, which is most of what makes a
## static screen feel live. Times, not offsets: the beat is "this screen has been
## on too long", not "this many seconds after a cut".
const SCREEN_DROPOUT_TIMES := [7.9, 13.4, 18.7]
const SCREEN_DROPOUT_DURATION := 0.15
const SCREEN_DROPOUT_LEVEL := 0.45

## Total length of the clip.
##
## NOT OPTIONAL AND NOT INFERRED. Animation.length defaults to 1.0 and silently
## truncates every track past it - the clip simply ends one second in and the
## doors never open, with no error anywhere.
const CUTSCENE_LENGTH := 24.5

## Keyframe quantisation. Also the width of a hard cut: two keys one step apart.
const ANIMATION_STEP := 1.0 / 30.0
#endregion

#region Camera poses
# BAKED INTO THE ANIMATION. Same warning as above.
#
# Stored as position + look-at target rather than position + Euler angles. A
# target is something you can reason about ("frame the miner's helmet"); an Euler
# triple is something you arrive at by trial and error and cannot review. The
# build script turns each pair into a rotation key with Transform3D.looking_at.
#
# World space, because CameraAnchor's parent chain is identity all the way to the
# level root. See the scene tree note in elevator_cutscene_prototype.tscn.

## Shot 0: parked nose-on the quota screen's glass, close enough that the glass
## covers the frame exactly at CUTSCENE_FOV and 16:9. The full-screen 2D monitor
## sits over the top of this pose, so the cut at PROLOGUE_LENGTH has nothing in it.
##
## COMPUTED, NOT COMPOSED, AND CHECKED RATHER THAN TRUSTED. The glass is
## 0.7298 x 0.4581 m in world space - a 1.6 x 1.09551 quad at 0.593 scale, times
## screen_rect's 0.769129 x 0.705202 - and its centre sits 2.5 mm left and 4.4 mm
## above the quad's. The trap is the height: QuotaScreen reads y = 2.4 in the .tscn,
## but it is a child of ElevatorCar and the car carries -1.42, so the world figure
## is 0.9844. Poses in this file are WORLD space. verify_elevator_cutscene.gd's
## [framing] check recomputes all of it off the live scene and prints the numbers
## when they drift.
const CLOSEUP_DISTANCE := 0.3416
const CLOSEUP_POSITION := Vector3(-0.0025, 0.9844, -1.3284)
const CLOSEUP_TARGET := Vector3(-0.0025, 0.9844, -1.6700)

## How far cutscene_fov may drift before the close-up stops being a match frame.
## TIGHT, BECAUSE THE FIT IS EXACT: any wider and the plate's bezel comes into
## shot, any narrower and the crop starts eating EXTRACTION CREW 067.
const CLOSEUP_FOV_TOLERANCE := 3.0

## Shot 1: high at the back wall, looking past the crew at the quota screen over
## the doorway. Slightly off-centre so the composition is not symmetrical.
##
## THREE METRES BACK FROM THE SUBJECT IS WHY THE CAR IS 3.4 m DEEP. The first
## version of this was a 2.4 m car, and at that depth the widest shot available
## from inside it was a miner's head filling the frame. The set is sized by the
## shot, not the other way round.
const SHOT1_POSITION := Vector3(0.30, 0.42, 1.58)
const SHOT1_TARGET := Vector3(0.00, -0.05, -1.78)

## Shot 2 opens on a medium of MinerB from their front-right, so the arm that
## performs the gesture is the one nearest camera.
##
## IN FRONT OF THE MINER, not beside them. The first pass put the camera level
## with the subject and it photographed the back of a helmet with the visor
## edge-on - the gesture would have happened entirely out of sight. MinerB stands
## further back than the other two precisely to leave this camera somewhere to be.
##
## FURTHER BACK THAN THE GREYBOX NEEDED. The real character is shorter than the
## blocky stand-in but its HELMET is far bigger - 0.48 m deep against a 0.32 m
## sphere - so the distance that framed a greybox medium put a voxel helmet across
## the middle third of frame, which is the exact failure this prototype's README
## warns about. These are set so the helmet is about a quarter of frame height.
const SHOT2_START_POSITION := Vector3(1.45, 0.20, -1.50)
const SHOT2_START_TARGET := Vector3(0.05, 0.02, -0.30)

## ...and closes on their helmet as it comes online.
##
## Not as close as it could be. At 0.84 m the raised forearm is nearer the lens
## than the head is and takes the left half of the frame; a metre back holds the
## hand and the visor in the same shot, which is the point of the beat.
const SHOT2_END_POSITION := Vector3(1.15, 0.14, -1.35)
const SHOT2_END_TARGET := Vector3(0.05, 0.02, -0.30)

## Shot 3: the player's own eye, facing the doors. This is where the match cut
## lands and where the camera sits until CLEANUP hands control back.
##
## Must agree with the PlayerStart marker in the .tscn - it is the same eye. The
## sightline is threaded down the lane between MinerB and MinerC so the crew
## frames the doorway instead of blocking it.
##
## THE OTHER LANE IS FULL. The greybox threaded between MinerA and MinerB, and
## that gap is now where MinerB's cutter hangs: they hold it left-handed so the
## gesture can have their right arm, which puts a 1.14 m tool exactly across the
## old sightline. This lane is clear because MinerC holds theirs right-handed,
## out towards the wall.
const EYE_POSITION := Vector3(0.55, 0.02, 1.20)
const EYE_TARGET := Vector3(0.50, -0.45, -3.50)
#endregion

#region Camera runtime
# Read at the point of use. Editing these takes effect on the next run.

## Seconds to blend the live gameplay camera onto the anchor when the cutscene
## starts. Zero, deliberately: the cutscene opens on a cut, and the player has not
## seen anything yet for a blend to be continuous with.
const ENTER_BLEND_TIME := 0.0

## Seconds to blend back to the gameplay camera at CLEANUP. Short enough to read
## as a settle rather than a move.
##
## ALWAYS ZERO ON THE SKIP PATH, whatever this says - a skip that eased would be
## slower than the thing it skipped.
const EXIT_BLEND_TIME := 0.35
const EXIT_BLEND_TIME_MIN := 0.0
const EXIT_BLEND_TIME_MAX := 2.0

## Field of view of the cutscene camera.
##
## Kept near GAMEPLAY_FOV on purpose. The exit blend interpolates position and
## rotation but NOT fov, so a cutscene fov far from the gameplay camera's snaps on
## the handover - a zoom the blend was meant to hide. The settings resource has an
## invariant that fails loudly when the slider drifts too far.
const CUTSCENE_FOV := 62.0
const CUTSCENE_FOV_MIN := 40.0
const CUTSCENE_FOV_MAX := 100.0

## The gameplay camera's fov, from prefabs/character/player/player_settings.tres.
## Here only so the invariant above has something to compare against.
const GAMEPLAY_FOV := 67.0

## Metres of camera shake while the car is descending. Felt, not seen - past about
## 0.03 it stops reading as machinery and starts reading as nausea.
const RUMBLE_AMPLITUDE := 0.012
const RUMBLE_AMPLITUDE_MIN := 0.0
const RUMBLE_AMPLITUDE_MAX := 0.06

## Shake rate in radians per second. Low reads as swaying, high as machinery.
const RUMBLE_FREQUENCY := 17.0
const RUMBLE_FREQUENCY_MIN := 2.0
const RUMBLE_FREQUENCY_MAX := 40.0

## Ratio between the two shake axes. Deliberately not a round number: at 1.0 or
## 2.0 the axes phase-lock and the shake collapses into a diagonal line.
const RUMBLE_AXIS_RATIO := 1.37
#endregion

#region Car and shaft
# Read at the point of use, except the two door numbers, which are also authored
# in the .tscn and guarded by elevator_car.gd.

## Local x of each closed door pivot. ZERO, because the art authors both leaves
## closed and in place: their origins sit on the doorway centre-line and the
## leaves meet at x = 0. Nothing to mirror.
const DOOR_CLOSED_X := 0.0

## How far each leaf slides. Equal to the leaf's own width, so the opening ends
## fully clear and each leaf finishes inside its pocket. Checked against the
## imported mesh's AABB in elevator_car.gd rather than trusted.
const DOOR_TRAVEL := 1.08

## Emissive bars streaming upward past the wall slot.
##
## NO LONGER WIRED INTO THE SCENE. The real sm_elevator_car shell has no wall
## slot, so a column outside it is invisible from inside a closed car. The node
## is gone; shaft_lights.gd, this region and the invariant that reads
## SHAFT_SLOT_HEIGHT are kept for the day a slot is authored into the art.
## ElevatorCar.set_shaft_running() now flickers the ceiling lamp instead.
##
## Speed and spacing trade off against each other and have to be felt as a pair,
## so both keep their sliders.
const SHAFT_LIGHT_SPEED := 9.0
const SHAFT_LIGHT_SPEED_MIN := 0.0
const SHAFT_LIGHT_SPEED_MAX := 30.0

const SHAFT_LIGHT_SPACING := 3.5
const SHAFT_LIGHT_SPACING_MIN := 1.0
const SHAFT_LIGHT_SPACING_MAX := 12.0

## How many bars exist. Not a slider: changing it rebuilds the column.
const SHAFT_LIGHT_COUNT := 12

## Size of each bar. Where the column sits is authored on the ShaftLights node in
## the .tscn, like the rest of the geometry - it has to be lined up with the wall
## slot by eye, and a number in this file could not be checked against one.
const SHAFT_LIGHT_SIZE := Vector3(0.16, 0.10, 0.62)

## Height of the wall slot the bars are seen through. Used by the invariant that
## checks the column is long enough not to visibly run out.
const SHAFT_SLOT_HEIGHT := 1.90

## Ceiling light strength. How dark the car is decides whether the quota screen
## reads at all, which is why it is worth a slider.
const CEILING_LIGHT_ENERGY := 1.6
const CEILING_LIGHT_ENERGY_MIN := 0.0
const CEILING_LIGHT_ENERGY_MAX := 6.0

## How far the ceiling lamp wavers while the car descends, as a fraction of its
## tuned energy, and how fast.
##
## THIS IS WHAT REPLACES THE SHAFT-LIGHT COLUMN. The real car has no window, so
## the only thing that can still say "moving" from inside it is its own lighting
## reacting to the machinery. Past about 0.2 it reads as a fault, not a descent.
const CEILING_FLICKER_DEPTH := 0.12
const CEILING_FLICKER_FREQUENCY := 11.0

## Peak energy of the red strobe on the clunk. Keyframed from 0 up and back down.
##
## 4.0 washed the whole car - including the HUD text, which is white and stopped
## reading. A flash should punctuate the shot, not repaint it.
const STROBE_PEAK_ENERGY := 2.2

## Radius of the player rig's hull, from prefab_player.tscn. Cross-checked against
## the shape itself at runtime rather than trusted, and used to check the exit
## marker is not parked inside geometry.
const RIG_HULL_RADIUS := 0.4

## Where each miner starts in idle_float's 4.0 s loop.
##
## THIS IS WHAT REPLACES THE SWAY TRACK. The greybox needed a keyframed torso
## rotation to look like a body compensating for motion; the real rig already
## breathes. What it cannot do on its own is breathe out of step, and three
## identical loops in lockstep read as one animation played three times.
const MINER_IDLE_PHASES := [0.0, 1.3, 2.7]
#endregion

#region Cutscene runtime

## AnimationPlayer.speed_scale. The ONLY live timing control there is - every
## other timing number in this file is baked into the .anim.tres.
const PLAYBACK_SPEED := 1.0
const PLAYBACK_SPEED_MIN := 0.1
const PLAYBACK_SPEED_MAX := 2.0

## Whether the skip key does anything. Worth a switch because toggling it live is
## exactly what testing skip looks like.
const SKIPPABLE := true

## Whether the cutscene plays on load. Off means you boot into the car with
## control and press the replay key when you want it.
const AUTOPLAY_ON_START := true

## Emission on a miner's helmet before and after it comes online.
##
## THESE ARE AN ORDER OF MAGNITUDE BELOW THE GREYBOX'S. There, the emissive node
## was a 0.185 x 0.075 m visor box and 4.0 made it punch. The real character has
## ONE material for the whole helmet - dome, visor and all - so the same number
## turns the head into a white blob that blows out the shot it is the climax of.
## Lighting the whole helmet is the right read for "the suit comes online"; it
## just has to be lit, not detonated.
##
## Idle is zero because a helmet that has not been switched on should be dark.
## Nothing needs it to match materials/miner_visor_material.tres any more - only
## the emission COLOUR is taken from there now, and the energy is owned here.
const VISOR_IDLE_ENERGY := 0.0
const VISOR_LIT_ENERGY := 0.7
#endregion

#region Text
# All copy in one place, pushed onto the screen and the Labels at startup. Copy is
# the thing most likely to change, and it should change in one file.

const SCREEN_CREW := "EXTRACTION CREW 067"
const SCREEN_QUOTA_LABEL := "OUTSTANDING QUOTA:"

## Credits owed, as a number rather than as the string "-47560 CR". The quota
## terminal derives its own readout from this and whatever has been collected, so
## the value and the DENIED/APPROVED line cannot drift apart the way two hand-typed
## strings could.
const SCREEN_QUOTA_TARGET := 47560

const SCREEN_AUTH_LABEL := "DEPARTURE AUTHORIZATION:"
const SCREEN_AUTH_VALUE := "DENIED"

## Plain hyphens and no em dashes, so nothing depends on the .tscn's encoding
## surviving a round trip through a tool that does not care.
const PLACARD_TEXT := "PROPERTY OF\nASTERIX EXTRACTIONS\n- - -\nUNAUTHORIZED DESCENT\nPROHIBITED"

const HUD_DEBT := "EXTRACTION DEBT: -41,365 CREDITS"
const HUD_QUOTA := "TODAY'S QUOTA: 2,000 CREDITS"
const HUD_TITLE := "BEGIN WORKDAY"
const HUD_SKIP_PROMPT := "[ENTER] SKIP    [P] REPLAY"
#endregion
