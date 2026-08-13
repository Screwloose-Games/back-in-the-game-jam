class_name CreatureNavDemoSettings
extends PrototypeSettings

## The sliders for the creature navigation demo.
##
## MOST OF THESE PUSH INTO `NavigationConfig` AND `LocomotionProfile` rather than into
## this scene, because that is where the interesting numbers live. `leap_bias` is the one
## worth dragging first: section 11.4 asks that a leap become attractive at roughly 10 m
## of crawling saved, and the flip point between the Gallery's leap and its crawl is the
## most legible thing in the prototype.
##
## THE SCENARIO INVARIANTS ARE RE-RUN AGAINST THE TUNED VALUES. `invariant_failures()`
## calls through to the config's, so dragging `leap_bias` past the point where section
## 43's Scenario D or E flips warns with the scenario named, in the panel, while you are
## still holding the slider.

const SAVE_PATH := "res://prototypes/creature_navigation/creature_nav_demo_settings.tres"

@export_group("Leap")
@export_range(0.0, 4.0, 0.05, "suffix:s") var leap_bias: float = 0.9
@export_range(1.0, 20.0, 0.5, "suffix:m/s") var leap_speed: float = 9.0

@export_group("Crawl")
@export_range(0.5, 12.0, 0.1, "suffix:m/s") var crawl_max_speed: float = 5.0
@export_range(0.2, 8.0, 0.1, "suffix:m") var crawl_turn_radius: float = 2.5
@export_range(1.0, 8.0, 0.1, "suffix:m") var crawl_surface_reach: float = 3.5

@export_group("Tunnel and squeeze")
@export_range(0.1, 1.0, 0.01) var tunnel_enter_enclosure: float = 0.6
@export_range(0.05, 6.0, 0.05, "suffix:m/s") var wiggle_speed: float = 1.2

@export_group("Demo")
@export_range(CreatureNavDemoKnobs.BAKE_QUERIES_MIN, CreatureNavDemoKnobs.BAKE_QUERIES_MAX, 64.0)
var bake_queries: float = CreatureNavDemoKnobs.BAKE_QUERIES
@export_range(
	CreatureNavDemoKnobs.GOAL_STANDOFF_SCALE_MIN, CreatureNavDemoKnobs.GOAL_STANDOFF_SCALE_MAX, 0.05
)
var goal_standoff_scale: float = CreatureNavDemoKnobs.GOAL_STANDOFF_SCALE
## Section 27. Off means the alien plans against the world and is omniscient about
## geometry; on means it plans against what it believes, and mining is something it has to
## find out about.
@export var use_knowledge: bool = false
@export var show_world_graph: bool = true
@export var show_locomotion: bool = true


func settings_path() -> String:
	return SAVE_PATH


## Pushes everything that belongs to the navigation module onto a config.
##
## One place rather than scattered through the prototype, so a knob added here is applied
## by construction rather than by somebody remembering the other half.
func apply_to(config: NavigationConfig) -> void:
	config.bake_queries_per_frame = int(bake_queries)
	config.wiggle_speed = wiggle_speed
	var profile: LocomotionProfile = config.locomotion_profile
	profile.leap_bias = leap_bias
	profile.leap_speed = leap_speed
	profile.crawl_max_speed = crawl_max_speed
	profile.crawl_turn_radius = crawl_turn_radius
	profile.crawl_surface_reach = crawl_surface_reach
	profile.tunnel_enter_enclosure = tunnel_enter_enclosure
	# The exit threshold has to stay below the enter threshold or the mode flickers, and a
	# single slider cannot express that. Kept at two thirds of enter, which preserves the
	# shipped 0.6 / 0.4 relationship at any setting.
	profile.tunnel_exit_enclosure = tunnel_enter_enclosure * (2.0 / 3.0)


func invariant_failures() -> PackedStringArray:
	var failures: PackedStringArray = super()
	var config := NavigationConfig.new()
	apply_to(config)
	for line: String in config.invariant_failures():
		failures.append(line)
	return failures
