class_name CreatureAwarenessSettings
extends PrototypeSettings

## The sliders for the creature awareness prototype.
##
## THREE MODULES' NUMBERS IN ONE PANEL. Most of these push into `NavigationConfig`,
## `PerceptionConfig` or `SuspicionConfig` rather than into this scene, because that is
## where the interesting values live. The two worth dragging first:
##
##     hearing_jitter        to 0, when you want the belief to land where you clicked
##     investigate_threshold to see how much evidence the alien needs before it commits
##
## THE NAVIGATION INVARIANTS ARE RE-RUN AGAINST THE TUNED VALUES. `invariant_failures()`
## calls through to the config's, so a slider that puts the alien into a state the module
## considers impossible warns in the panel while you are still holding it.

const SAVE_PATH := "res://prototypes/creature_awareness/creature_awareness_settings.tres"

@export_group("Bake")
@export_range(
	CreatureAwarenessKnobs.BAKE_QUERIES_MIN, CreatureAwarenessKnobs.BAKE_QUERIES_MAX, 64.0
)
var bake_queries: float = CreatureAwarenessKnobs.BAKE_QUERIES
@export_range(
	CreatureAwarenessKnobs.RECOVERY_REACH_MIN,
	CreatureAwarenessKnobs.RECOVERY_REACH_MAX,
	1.0,
	"suffix:m"
)
var recovery_reach: float = CreatureAwarenessKnobs.RECOVERY_REACH

@export_group("Stimulus")
@export_range(CreatureAwarenessKnobs.LOUDNESS_MIN, CreatureAwarenessKnobs.LOUDNESS_MAX, 0.01)
var thrust_loudness: float = CreatureAwarenessKnobs.THRUST_LOUDNESS
@export_range(
	CreatureAwarenessKnobs.INTERVAL_MIN, CreatureAwarenessKnobs.INTERVAL_MAX, 0.05, "suffix:s"
)
var thrust_interval: float = CreatureAwarenessKnobs.THRUST_INTERVAL
@export_range(CreatureAwarenessKnobs.LOUDNESS_MIN, CreatureAwarenessKnobs.LOUDNESS_MAX, 0.01)
var mining_loudness: float = CreatureAwarenessKnobs.MINING_LOUDNESS
@export_range(
	CreatureAwarenessKnobs.INTERVAL_MIN, CreatureAwarenessKnobs.INTERVAL_MAX, 0.05, "suffix:s"
)
var mining_interval: float = CreatureAwarenessKnobs.MINING_INTERVAL

@export_group("Perception")
## Section 11's spatial uncertainty. At 0 hearing reports the true origin and the alien is
## handed exact coordinates, which is the omniscience the displacement exists to prevent.
@export_range(0.0, 1.0, 0.01) var hearing_jitter: float = CreatureAwarenessKnobs.HEARING_JITTER
@export_range(
	CreatureAwarenessKnobs.HEARING_MAX_RANGE_MIN,
	CreatureAwarenessKnobs.HEARING_MAX_RANGE_MAX,
	1.0,
	"suffix:m"
)
var hearing_max_range: float = CreatureAwarenessKnobs.HEARING_MAX_RANGE
@export_range(0.1, 4.0, 0.01) var hearing_sensitivity: float = 1.0
## Section 14. Suspicion feeds alertness back as read-only context: it changes how hard the
## creature looks, never what it finds. Off also halves the credit an arrival scan earns,
## because a scan that checked one sense clears less than one that checked two.
@export var alertness_feedback: bool = true

@export_group("Suspicion")
@export_range(0.0, 2.0, 0.001, "suffix:/s") var hearing_decay_rate: float = 0.06
@export_range(0.5, 60.0, 0.5, "suffix:m") var hotspot_merge_distance: float = 6.0
## Gate merging on which chamber a point is in, using the map's own region ids. Stops a
## trail of stimuli down a tunnel from chaining two caverns into one hotspot centred in the
## rock between them.
@export var region_gated_merge: bool = true

@export_group("Behaviour")
@export_range(
	CreatureAwarenessKnobs.INVESTIGATE_THRESHOLD_MIN,
	CreatureAwarenessKnobs.INVESTIGATE_THRESHOLD_MAX,
	0.01
)
var investigate_threshold: float = CreatureAwarenessKnobs.INVESTIGATE_THRESHOLD
@export_range(1.0, 12.0, 0.5, "suffix:m")
var search_half_extent: float = CreatureAwarenessKnobs.SEARCH_HALF_EXTENT
@export_range(0.0, 1.0, 0.05)
var search_thoroughness: float = CreatureAwarenessKnobs.SEARCH_THOROUGHNESS
@export_range(0.0, 20.0, 0.5, "suffix:s") var nest_dwell: float = CreatureAwarenessKnobs.NEST_DWELL
## Off parks the alien wherever it is, so a distance test is not confused by it wandering
## off mid-measurement.
@export var wander_enabled: bool = true

@export_group("Cameras")
@export_range(
	CreatureAwarenessKnobs.ANT_FARM_SIZE_MIN, CreatureAwarenessKnobs.ANT_FARM_SIZE_MAX, 1.0
)
var ant_farm_size: float = CreatureAwarenessKnobs.ANT_FARM_SIZE

@export_group("Overlays")
@export var show_world_graph: bool = true
@export var show_locomotion: bool = true
@export var show_belief: bool = true


func settings_path() -> String:
	return SAVE_PATH


## Pushes everything that belongs to the navigation module onto a config.
##
## One place rather than scattered through the prototype, so a knob added here is applied
## by construction rather than by somebody remembering the other half.
func apply_to_navigation(config: NavigationConfig) -> void:
	config.bake_queries_per_frame = int(bake_queries)
	config.locomotion_profile.recovery_reach = recovery_reach


func apply_to_perception(config: PerceptionConfig) -> void:
	config.hearing_position_jitter = hearing_jitter
	config.hearing_max_range = hearing_max_range
	config.hearing_sensitivity = hearing_sensitivity


func apply_to_suspicion(config: SuspicionConfig) -> void:
	config.hearing_decay_rate = hearing_decay_rate
	config.hotspot_merge_distance = hotspot_merge_distance
	config.require_same_spatial_region_for_merge = region_gated_merge


## Loudness and repeat interval for a stimulus, as [loudness, interval].
func stimulus_values(mining: bool) -> Array:
	if mining:
		return [mining_loudness, mining_interval]
	return [thrust_loudness, thrust_interval]


func invariant_failures() -> PackedStringArray:
	var failures: PackedStringArray = super()
	var config := NavigationConfig.new()
	apply_to_navigation(config)
	for line: String in config.invariant_failures():
		failures.append(line)
	# Below the module's own drop threshold the alien would commit to hotspots that are
	# already being dropped from the field, and an investigation would end the moment it
	# started.
	var suspicion := SuspicionConfig.new()
	apply_to_suspicion(suspicion)
	if investigate_threshold <= suspicion.resolved_hotspot_threshold:
		var bounds: Array = [investigate_threshold, suspicion.resolved_hotspot_threshold]
		failures.append(
			"investigate_threshold %.2f is at or below resolved_hotspot_threshold %.2f" % bounds
		)
	if search_half_extent <= 0.0:
		# A degenerate scan region aborts, and an aborted scan reports a zero-strength
		# disconfirmation that resolves nothing.
		failures.append("search_half_extent must be positive, or no search ever clears anything")
	return failures
