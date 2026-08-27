class_name BehaviorConfig
extends Resource

## Every tunable in the behavior module, in one Resource (fsm.md, "Configuration").
##
## THIS IS THE WHOLE TEMPERAMENT DIAL, the way PerceptionConfig is the whole difficulty dial
## and SuspicionConfig the whole memory dial. How readily the alien leaves a nest, how long
## it commits to a hunt, how far it walks before an encounter is over -- all of it is here
## and none of it is anywhere else. That property is what keeps the HFSM readable, and it
## only survives if no state, tree or action hardcodes a number.
##
## THE ALIEN'S OWN NUMBERS ARE NOT HERE. Hearing range, hotspot decay and crawl speed live
## on PerceptionConfig, SuspicionConfig and LocomotionProfile, because they are properties
## of the CREATURE rather than of its decision-making.
##
## A bare `BehaviorConfig.new()` is fully usable. Five defaults below are measured values
## carried across from prototypes/creature_awareness rather than re-guessed.

## Metres the investigate goal must move before Behavior re-issues it, and the floor is not
## a matter of taste.
##
## `CreatureNavigation.set_goal` nulls the route AND calls `progress.reset()`, and `progress`
## is the section-40 stuck watchdog whose window is `NavigationConfig.progress_window`
## (2.0 s). An action re-issuing more often than that permanently disables the only backstop
## against a wedged alien -- which presents as a creature that stands still forever, with a
## trip count of zero and nothing in the log. Navigation already replans on drift at
## `target_move_threshold` (2.0 m) WITHOUT nulling the route, so anything below 2.0 here is
## strictly more destructive than doing nothing at all.
const MINIMUM_GOAL_REFRESH_M: float = 2.0

@export_group("Thresholds")
## Strongest-hotspot suspicion at which the alien stops wandering and goes to look.
##
## Measured in the prototype. Keep it above SuspicionConfig.resolved_hotspot_threshold
## (0.08) or the alien chases hotspots that are already on their way out.
@export_range(0.0, 1.0, 0.01) var investigate_threshold: float = 0.25
## Player-candidate suspicion that turns an investigation into a hunt.
@export_range(0.0, 1.0, 0.01) var hunt_threshold: float = 0.55
## Player-candidate suspicion that starts a hunt straight out of UNALERTED, skipping
## investigation entirely. Deliberately high: this is behavior.md's "extremely strong direct
## evidence", not a shortcut. Note it is NOT shifted by escalation_bias -- fsm.md's table
## biases the other two rows and not this one.
@export_range(0.0, 1.0, 0.01) var direct_hunt_threshold: float = 0.85
## How sure the creature must be about WHO before it hunts anybody.
##
## Only vision and touch set source_confidence; hearing deliberately never does. So this is
## also the rule that you cannot be hunted by name for a noise -- a hotspot gets
## investigated, a person gets hunted.
@export_range(0.0, 1.0, 0.01) var hunt_confidence: float = 0.6
## Below this, a hotspot is not worth staying in INVESTIGATING for. Matched to
## SuspicionConfig.resolved_hotspot_threshold, so Behavior gives up at the same point
## Suspicion calls a hotspot resolved.
@export_range(0.0, 1.0, 0.01) var attention_floor: float = 0.08
## How far a full +/-1 escalation_bias moves the investigate and hunt thresholds.
##
## At 0.15 a bored Director can pull the investigate threshold from 0.25 to 0.10 -- enough
## that a faint noise becomes a lead. Set it near investigate_threshold and a positive bias
## makes the alien investigate literally everything, which reads as a broken sense of
## hearing rather than as pacing.
@export_range(0.0, 0.5, 0.01) var bias_span: float = 0.15

@export_group("Commitment")
## No transition out of any state is evaluated before this much time in it.
##
## NOT A ROW IN THE TRANSITION TABLE -- a global pre-guard on all of them. It is the whole
## of what stops an alien sitting on a threshold boundary flickering between modes, which
## looks like a seizure and makes every debug trace unreadable.
@export_range(0.0, 10.0, 0.1, "suffix:s") var min_dwell_s: float = 1.0
## Give up on an investigation that has taken this long, so a hotspot the alien cannot
## physically reach does not strand it forever.
@export_range(1.0, 300.0, 0.5, "suffix:s") var investigate_timeout_s: float = 45.0
## How long an approach must be getting nowhere before the creature gives up on it.
##
## THE GAP fsm.md LEFT, and `retreat_max_s` above is the same gap answered for RETREATING.
## `investigate_location` fails only on UNREACHABLE, but against a baked graph a target the
## creature cannot fit to comes back PARTIAL -- deliberately not a failure -- so the alien
## walks at rock, arrives at the far end of what it could reach, searches the wrong place, and
## re-commands the goal several times a second for as long as the lead stays warm.
## `investigate_timeout_s` does eventually fire, and drops to UNALERTED, which re-enters on the
## same lead the next tick because lead selection has no memory of having failed.
##
## Five seconds is long enough to outlast a legitimate detour -- a route round a chamber can
## briefly stop closing -- and short enough that the creature does not spend a whole
## `investigate_timeout_s` grinding.
@export_range(0.5, 60.0, 0.1, "suffix:s") var give_up_s: float = 5.0
## How long the creature holds still in RECONSIDERING before going back to wandering.
##
## Matched to `nest_dwell_s`. It must exceed `min_dwell_s`, which is a global pre-guard on
## every transition: a dwell shorter than the floor can never be reached, so the state would
## be entered and never left.
@export_range(0.0, 60.0, 0.1, "suffix:s") var reconsider_dwell_s: float = 4.0
## Candidate suspicion below which a hunt is no longer being fed.
@export_range(0.0, 1.0, 0.01) var hunt_sustain_threshold: float = 0.35
## How long that must hold continuously before the hunt is at risk. This is what makes
## hunting a commitment: losing sight of the player does not end a hunt.
@export_range(0.0, 60.0, 0.1, "suffix:s") var hunt_sustain_grace_s: float = 8.0
## Unresolved suspicion within this radius of the last credible target position sustains a
## hunt on its own, even with no candidate at all. The alien searches rather than gives up.
@export_range(0.0, 60.0, 0.5, "suffix:m") var hunt_sustain_radius: float = 12.0
## A retreat lasts at least this long, however quickly separation is achieved.
@export_range(0.0, 60.0, 0.1, "suffix:s") var retreat_min_s: float = 6.0
## EUCLIDEAN distance from where the alien gave up, not route distance.
##
## The opposite of the Director's menace term, which is emphatically route distance. There
## is no route to the point separation is measured from -- navigation's route goes to a nest
## -- so it could not be a path length even if that were wanted.
@export_range(1.0, 200.0, 0.5, "suffix:m") var retreat_separation_m: float = 25.0
## Hard cap on a retreat. NOT IN fsm.md, and it is the backstop rather than a workaround.
##
## RETREATING reuses `travel_to_nest` outright, so the asymmetry fsm.md left -- one node with
## an UNREACHABLE failure clause and one without -- is gone. What remains is the case no
## per-nest failure can express. Against a baked graph a target outside it comes back PARTIAL
## rather than UNREACHABLE, because a partial route is deliberately not a failure, so an alien
## sent to a nest it can only half reach walks at rock without ever failing; and an alien whose
## every known nest sits inside `retreat_separation_m` of where it gave up has nowhere to walk
## that would end the encounter at all. This is what guarantees it comes back.
@export_range(1.0, 300.0, 0.5, "suffix:s") var retreat_max_s: float = 45.0

@export_group("Actions")
## How long the alien loiters at a nest before choosing another. Measured in the prototype.
@export_range(0.0, 60.0, 0.1, "suffix:s") var nest_dwell_s: float = 4.0
## A nest visited this recently scores no recency credit at all, so wandering does not
## ping-pong between the two nearest nests.
@export_range(0.0, 600.0, 1.0, "suffix:s") var nest_recent_penalty_s: float = 60.0
## How close counts as arrived when the route follower has not already said so. Measured in
## the prototype. The fallback exists because a route that never attached leaves the
## follower with nothing to be finished with.
@export_range(0.1, 20.0, 0.1, "suffix:m") var arrive_distance: float = 3.0
## Half-extent of the AABB handed to request_activity_scan on arrival. Measured in the
## prototype.
##
## MUST PRODUCE A NON-DEGENERATE VOLUME. A zero-size region aborts the scan, and an aborted
## scan reports a zero-strength disconfirmation that clears nothing -- so the alien arrives,
## searches, and the hotspot never resolves. It looks like disconfirmation is broken when it
## is the region that is.
@export_range(0.5, 40.0, 0.1, "suffix:m") var search_half_extent: float = 4.0
## Thoroughness, 0..1. Feeds both the scan duration and the disconfirmation strength.
@export_range(0.0, 1.0, 0.01) var search_thoroughness: float = 1.0
## Minimum gap between two searches, and it is load-bearing rather than polite.
##
## `request_activity_scan` completes SYNCHRONOUSLY when perception has no config, an unbound
## probe, or a zero-volume region -- so a stateless search action would re-request at the
## frame rate, and each request writes a zero-strength disconfirmation into a ring capped at
## SuspicionConfig.max_disconfirmation_count (48). The storm does not merely waste work: it
## evicts real search records with junk. Keep it above SuspicionConfig.hotspot_update_interval
## (0.2 s) too, or the alien re-aims on pre-search belief.
@export_range(0.0, 30.0, 0.1, "suffix:s") var search_cooldown_s: float = 1.0
## See MINIMUM_GOAL_REFRESH_M. Asserted in invariant_failures().
@export_range(0.0, 20.0, 0.1, "suffix:m") var goal_refresh_m: float = 3.0
## Shortest a lurk outside an impassable tunnel lasts.
##
## The RANGE is the mechanic. A fixed timer is something the player counts, and a tunnel
## with a known safe interval stops being a gamble.
@export_range(0.0, 120.0, 0.1, "suffix:s") var lurk_min_s: float = 6.0
@export_range(0.0, 120.0, 0.1, "suffix:s") var lurk_max_s: float = 14.0
## How close the alien has to be to strike, MEASURED TO THE TARGET ESTIMATE.
##
## Not to a player transform, and that is the whole reason this number is here rather than on
## a collision shape. Behavior decides from belief; an attack keyed off where the player
## actually is would be the alien reaching around its own senses, and
## `test_behavior_invariants.gd` asserts it never reads a target's position. The consequence
## is legible in play: an alien with a stale estimate swipes at where it thinks you are.
@export_range(0.1, 20.0, 0.1, "suffix:m") var attack_range_m: float = 2.5
## Shortest gap between two attacks.
##
## Load-bearing rather than polite. `attack` returns SUCCESS either way, so with no cooldown
## the bite branch wins every tick for as long as the estimate stays close -- the alien
## machine-guns, the Director's `attack_window_open` never falls, and nothing errors.
@export_range(0.05, 30.0, 0.05, "suffix:s") var attack_cooldown_s: float = 2.0
## How long after the last evidence NAMING the target a strike at its estimated position is
## still honest (behavior.md section 27, "less trustworthy as evidence ages").
##
## It gates the bite, not the chase. An alien that has lost you still walks to where it last
## believed you were and sweeps it -- section 28 -- because standing still and scanning a
## region twenty metres away is not searching. Swinging at a position nobody has confirmed in
## four seconds, on the other hand, is the alien getting a free hit off its own memory.
##
## AGED ON SUSPICION'S CLOCK, not Behavior's. `PlayerSuspicionCandidate.last_evidence_at` is
## stamped by CreatureSuspicion, whose clock starts when that node is constructed; the two
## agree only if the nodes were built on the same frame. Subtracting Behavior's clock from it
## compiles, runs, and produces garbage.
@export_range(0.1, 60.0, 0.1, "suffix:s") var target_estimate_max_age_s: float = 4.0

@export_subgroup("Nest choice")
## How much a nest being close counts. Negated for retreat, which wants a far one.
@export_range(0.0, 4.0, 0.05) var nest_distance_weight: float = 1.0
## Distance at which the distance term is fully spent. Roughly the size of a level.
@export_range(1.0, 500.0, 1.0, "suffix:m") var nest_distance_span: float = 60.0
## How much not having been there lately counts.
@export_range(0.0, 4.0, 0.05) var nest_recency_weight: float = 1.0
## Distance at which the Director's roam term is fully spent.
@export_range(1.0, 500.0, 1.0, "suffix:m") var nest_roam_span: float = 40.0

@export_group("Perception")
## Alertness published to Perception while UNALERTED (fsm.md's tick contract, step 6).
##
## ZERO IS BELOW PerceptionConfig.vision_activation_suspicion (0.25), SO VISION IS OFF, which
## is behavior.md section 6's "unavailable or weak while calm" and is deliberate. It has a
## consequence worth knowing: only vision and touch set source_confidence, so with vision
## gated the UNALERTED -> HUNTING row can fire on TOUCH ALONE. A calm alien cannot be
## surprised into hunting you by seeing you; it has to walk into you.
@export_range(0.0, 1.0, 0.01) var alertness_unalerted: float = 0.0
## Must clear PerceptionConfig.vision_activation_suspicion, or a searching alien is blind and
## every search clears half as much (the VISION bit drops out of the disconfirmation mask).
@export_range(0.0, 1.0, 0.01) var alertness_investigating: float = 0.5
@export_range(0.0, 1.0, 0.01) var alertness_hunting: float = 1.0
## Below the vision gate on purpose: an alien walking away genuinely stops looking for you,
## which is behavior.md section 30's visible consequence rather than an oversight.
@export_range(0.0, 1.0, 0.01) var alertness_retreating: float = 0.2
## Standing still and thinking, not switched off. Above the vision gate on purpose: the
## creature has stopped WALKING at a lead it cannot reach, and a player who wanders into view
## while it stands there is exactly the thing it should still notice.
@export_range(0.0, 1.0, 0.01) var alertness_reconsidering: float = 0.5
## How long after a sighting the encounter report still claims visual contact.
##
## Must outlast PerceptionConfig.vision_scan_interval_calm (0.6 s) or contact flickers off
## between vision ticks and the Director's sight term stutters on a creature staring
## straight at you.
@export_range(0.0, 10.0, 0.05, "suffix:s") var visual_contact_grace_s: float = 1.5


## The alertness this state publishes to Perception.
func alertness_for(state: CreatureState.State) -> float:
	match state:
		CreatureState.State.UNALERTED:
			return alertness_unalerted
		CreatureState.State.INVESTIGATING:
			return alertness_investigating
		CreatureState.State.HUNTING:
			return alertness_hunting
		CreatureState.State.RETREATING:
			return alertness_retreating
		CreatureState.State.RECONSIDERING:
			return alertness_reconsidering
	return 0.0


## How far escalation_bias moves a threshold. Applies to the investigate row and the
## INVESTIGATING -> HUNTING row, and deliberately not to direct_hunt_threshold.
func threshold_shift(escalation_bias: float) -> float:
	return clampf(escalation_bias, -1.0, 1.0) * bias_span


## A lurk duration inside the configured range, drawn from the supplied generator so the
## caller owns the seed and a test can pin it.
func lurk_duration(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(minf(lurk_min_s, lurk_max_s), maxf(lurk_min_s, lurk_max_s))


## Cross-field rules no single @export_range can express, mirroring
## PerceptionConfig.invariant_failures() and SuspicionConfig.invariant_failures().
##
## `perception` is optional because three of these rules are about how this config sits
## against THAT one, and a BehaviorConfig on its own genuinely cannot know. Pass the
## creature's PerceptionConfig and the alertness table is checked against the vision gate.
func invariant_failures(perception: PerceptionConfig = null) -> PackedStringArray:
	var failures := PackedStringArray()
	if goal_refresh_m < MINIMUM_GOAL_REFRESH_M:
		(
			failures
			. append(
				(
					"goal_refresh_m %.2f is below %.2f: re-issuing a goal resets navigation's stuck watchdog, so the alien can wedge silently"
					% [goal_refresh_m, MINIMUM_GOAL_REFRESH_M]
				)
			)
		)
	if investigate_threshold <= attention_floor:
		(
			failures
			. append(
				(
					"investigate_threshold %.2f is at or below attention_floor %.2f: the alien would investigate hotspots it immediately gives up on"
					% [investigate_threshold, attention_floor]
				)
			)
		)
	if direct_hunt_threshold < hunt_threshold:
		(
			failures
			. append(
				(
					"direct_hunt_threshold %.2f is below hunt_threshold %.2f: hunting straight from calm would be EASIER than hunting mid-investigation"
					% [direct_hunt_threshold, hunt_threshold]
				)
			)
		)
	if lurk_min_s > lurk_max_s:
		failures.append("lurk_min_s %.2f exceeds lurk_max_s %.2f" % [lurk_min_s, lurk_max_s])
	if lurk_min_s == lurk_max_s and lurk_max_s > 0.0:
		(
			failures
			. append(
				(
					"lurk_min_s and lurk_max_s are both %.2f: a fixed lurk is something the player counts, and a tunnel with a known safe interval is not a gamble"
					% lurk_max_s
				)
			)
		)
	if give_up_s <= 0.0:
		failures.append("give_up_s must be positive; a zero window gives up on the first tick")
	if reconsider_dwell_s <= min_dwell_s:
		# min_dwell_s pre-guards every row out of every state, so a shorter dwell than the floor
		# is a state the creature enters and never leaves.
		var dwell: Array = [reconsider_dwell_s, min_dwell_s]
		failures.append("reconsider_dwell_s %.2f does not outlast min_dwell_s %.2f" % dwell)
	if investigate_timeout_s <= give_up_s:
		# The give-up row sits above the timeout row, so a timeout that fires first makes the
		# whole of RECONSIDERING unreachable while looking perfectly configured.
		var caps: Array = [investigate_timeout_s, give_up_s]
		failures.append("investigate_timeout_s %.2f does not exceed give_up_s %.2f" % caps)
	if retreat_max_s <= retreat_min_s:
		(
			failures
			. append(
				(
					"retreat_max_s %.2f is at or below retreat_min_s %.2f: the backstop would fire before the retreat was allowed to end normally"
					% [retreat_max_s, retreat_min_s]
				)
			)
		)
	if search_half_extent <= 0.0:
		failures.append(
			(
				"search_half_extent %.2f encloses no volume: every scan aborts and clears nothing"
				% search_half_extent
			)
		)
	if attack_cooldown_s <= 0.0:
		(
			failures
			. append(
				(
					"attack_cooldown_s %.2f leaves no gap between attacks: the bite branch wins every tick and the alien machine-guns"
					% attack_cooldown_s
				)
			)
		)
	if target_estimate_max_age_s <= 0.0:
		(
			failures
			. append(
				(
					"target_estimate_max_age_s %.2f makes every estimate stale on arrival: the alien could never chase, only lurk and search"
					% target_estimate_max_age_s
				)
			)
		)
	elif target_estimate_max_age_s <= visual_contact_grace_s:
		(
			failures
			. append(
				(
					"target_estimate_max_age_s %.2f is at or below visual_contact_grace_s %.2f: the alien would stop chasing something the encounter report still says it can see"
					% [target_estimate_max_age_s, visual_contact_grace_s]
				)
			)
		)
	failures.append_array(_perception_failures(perception))
	return failures


## The three rules that are about this config's fit with PerceptionConfig. Silent every one
## of them: the creature runs, and is quietly worse at something nobody is measuring.
func _perception_failures(perception: PerceptionConfig) -> PackedStringArray:
	var failures := PackedStringArray()
	if perception == null:
		return failures
	var gate: float = perception.vision_activation_suspicion
	if alertness_investigating < gate:
		(
			failures
			. append(
				(
					"alertness_investigating %.2f is below the vision gate %.2f: a searching alien would be blind, and each search would clear half as much"
					% [alertness_investigating, gate]
				)
			)
		)
	if alertness_hunting < gate:
		(
			failures
			. append(
				(
					"alertness_hunting %.2f is below the vision gate %.2f: a hunting alien could not see its target"
					% [alertness_hunting, gate]
				)
			)
		)
	if visual_contact_grace_s <= perception.vision_scan_interval_calm:
		(
			failures
			. append(
				(
					"visual_contact_grace_s %.2f does not outlast a %.2fs vision interval: contact would flicker off between ticks"
					% [visual_contact_grace_s, perception.vision_scan_interval_calm]
				)
			)
		)
	return failures
