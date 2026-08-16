class_name CreatureAwarenessKnobs
extends RefCounted

## Every default this prototype writes down, per prototypes/AGENTS.md.
##
## THE ALIEN'S OWN NUMBERS ARE NOT HERE. Crawl speed, leap bias, hearing range and hotspot
## decay live on `LocomotionProfile`, `PerceptionConfig` and `SuspicionConfig` in the three
## creature modules, because they are properties of the CREATURE rather than of this scene.
## The settings resource exposes the handful worth dragging directly. What lives here is
## what this prototype invents: the stimulus table, the investigate threshold, and the
## camera framing.

#region Bake
## Queries the bake may spend per physics frame.
##
## FAR ABOVE THE MODULE'S SHIPPED 384, and it has to be. Three 40 m caverns is roughly
## 13 000 open lattice cells against the navigation sandbox's 1 100; at the default budget
## that is about eight seconds of empty overlay, and the first thing anyone concludes is
## that the bake is broken. At 4000 it is under a second.
const BAKE_QUERIES: float = 4000.0
const BAKE_QUERIES_MIN: float = 256.0
const BAKE_QUERIES_MAX: float = 12000.0

## How far the recovery fan looks when the ordinary one has found nothing.
##
## RAISED FROM THE MODULE'S 24 M BECAUSE THE ROOMS ARE BIGGER. That default's own comment
## sizes it against "the demo cave's largest room, 19 m". The centre of a 40 m cavern is
## 20 m from any wall, so a body that slips into the middle would have no margin at all.
const RECOVERY_REACH: float = 35.0
const RECOVERY_REACH_MIN: float = 10.0
const RECOVERY_REACH_MAX: float = 60.0
#endregion

#region Stimulus
## Loudness of a single EVA thrust pulse, nominally 0..1.
##
## THE HOLD IS WHAT MAKES A STIMULUS CARRY. A single pulse only forms a hotspot inside
## about 20 m at this loudness -- below roughly 0.204 received strength, hearing emits
## evidence that is stored, decays and never crosses `resolved_hotspot_threshold`. Held,
## the pulses accumulate, which is `SuspicionConfig`'s stated intent: one is ignored, five
## in a row become a lead.
const THRUST_LOUDNESS: float = 0.85
const THRUST_INTERVAL: float = 0.3

## Mining is the loud one, and slower: a strike rather than a continuous burn.
const MINING_LOUDNESS: float = 1.0
const MINING_INTERVAL: float = 0.45

const LOUDNESS_MIN: float = 0.05
const LOUDNESS_MAX: float = 1.0
const INTERVAL_MIN: float = 0.1
const INTERVAL_MAX: float = 2.0

## Radius of the sphere the pick marches to find open air, and the step it marches in.
##
## The step has to be well under the smallest bore or the march tunnels straight through a
## passage without ever sampling inside it.
const PICK_PROBE_RADIUS: float = 0.35
const PICK_STEP: float = 0.5
const PICK_RANGE: float = 400.0

## How far the alien can hear at all, pushed onto `PerceptionConfig.hearing_max_range`.
##
## RAISED FROM THE MODULE'S 40 M BECAUSE THIS MAP IS BIGGER THAN THE SANDBOX. Adjacent
## cavern centres are 60 m apart, so at 40 m a stimulus in the next chamber is not merely
## faint -- `received_strength` returns a hard 0.0 past the range and no evidence is emitted
## at all. Every ping outside the alien's own cavern would do nothing, with nothing in the
## log, which is indistinguishable from a broken chain.
##
## 120 M, AND 90 WAS TRIED FIRST AND MEASURED WRONG. Range does not only decide what is
## audible; it decides CONFIDENCE, and confidence is what makes a record survive long enough
## to accumulate. At 90 m a stimulus 60 m away arrives at confidence 0.06, which puts each
## record's effective strength at 0.006 -- a hair over `evidence_min_retention_strength`
## (0.005), so it is pruned about three seconds later. Held for twenty seconds it still
## produced NO hotspot at all: the survivors, scattered by hearing's own position jitter,
## never clustered into anything above `resolved_hotspot_threshold`. Measured, not reasoned.
##
## At 120 m the same stimulus arrives at confidence 0.21, records persist, and the intended
## distinction survives: ONE pulse at 60 m forms a visible hotspot but stays under the
## investigate threshold, and HOLDING carries it over. That is "one is ignored, five in a
## row become a lead" at cavern range. Inside a single cavern one pulse commits the alien
## immediately, which is also right.
const HEARING_MAX_RANGE: float = 120.0
const HEARING_MAX_RANGE_MIN: float = 10.0
const HEARING_MAX_RANGE_MAX: float = 160.0

## How much of the reported position's displacement to keep, passed to
## `PerceptionConfig.hearing_position_jitter`.
##
## AT 1.0 THE HOTSPOT DOES NOT SIT ON THE STIMULUS, and that is the design working. Hearing
## displaces what it reports by up to the uncertainty radius, so a consumer that reads
## `position` and ignores `uncertainty_radius` cannot get a free omniscient alien. Drag it
## to 0 when you are debugging and want the belief to land where you clicked.
const HEARING_JITTER: float = 1.0
#endregion

#region Behaviour
## Hotspot suspicion at which the alien stops wandering and goes to look.
##
## THE MODULE PROVIDES NO SUCH NUMBER, ON PURPOSE. Suspicion describes belief and
## transitions nothing; behaviour reads it and acts on its own threshold. This is that
## threshold. Above `resolved_hotspot_threshold` (0.08) or the alien chases hotspots that
## are already on their way out.
const INVESTIGATE_THRESHOLD: float = 0.25
const INVESTIGATE_THRESHOLD_MIN: float = 0.1
const INVESTIGATE_THRESHOLD_MAX: float = 0.9

## Half-extent of the AABB handed to `request_activity_scan` on arrival.
##
## MUST PRODUCE A NON-DEGENERATE VOLUME. A zero-size region aborts the scan, and an aborted
## scan reports a zero-strength disconfirmation that clears nothing -- the alien arrives,
## searches, and the hotspot never resolves.
const SEARCH_HALF_EXTENT: float = 4.0
## Thoroughness, 0..1. Feeds both the scan duration and the disconfirmation strength.
const SEARCH_THOROUGHNESS: float = 1.0

## How close counts as arrived, when the follower has not already said so.
const ARRIVE_DISTANCE: float = 3.0
## How long the alien loiters at a nest before choosing another.
const NEST_DWELL: float = 4.0
## A nest this recently visited is not chosen again, so wandering does not ping-pong.
const NEST_RECENT_PENALTY: float = 60.0
## Give up on an investigation that has taken this long without resolving, so a hotspot the
## alien cannot physically reach does not strand it forever.
const INVESTIGATE_TIMEOUT: float = 45.0
#endregion

#region Cameras
## Far plane for every camera.
##
## The zero-g player ships with 20 m, which is atmospheric in a corridor and hides all but
## the near wall of a 40 m cavern.
const CAMERA_FAR: float = 400.0
## Orthographic width of the ant-farm view. Wide enough for all three caverns.
const ANT_FARM_SIZE: float = 150.0
const ANT_FARM_SIZE_MIN: float = 40.0
const ANT_FARM_SIZE_MAX: float = 300.0
## Where the ant-farm camera sits, relative to the middle of the map.
const ANT_FARM_OFFSET := Vector3(90.0, 70.0, 90.0)
## Chase camera stand-off from the creature.
const FOLLOW_DISTANCE: float = 14.0
const FOLLOW_HEIGHT: float = 6.0
## Fraction of the gap the chase camera closes per second, so it trails rather than snaps.
const FOLLOW_LERP: float = 4.0
#endregion
