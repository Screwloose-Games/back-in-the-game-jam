extends Node3D

## Pushes the values from prototype_knobs.gd onto the scene at startup, so that
## file stays the single place worth editing.
##
## The handful of values with sliders come from navigation_settings.tres instead,
## which starts life holding exactly those consts. See PrototypeSettings.

## Flight feel and murk you can move from the tuning panel, and what SAVE writes
## back to. Assigned in the .tscn; see _ready for what happens when it is missing.
@export var settings: NavigationSettings

@onready var _world_environment: WorldEnvironment = $WorldEnvironment
@onready var _player: ZeroGPlayer = $ZeroGPlayer
@onready var _tuning: PrototypeTuningPanel = $HUD/Tuning


func _ready() -> void:
	# A fresh clone has no navigation_settings.tres yet, and anyone may delete it.
	# A bare instance holds exactly the knobs consts, so the fallback is the old
	# behaviour rather than a crash.
	if settings == null:
		settings = NavigationSettings.new()
		push_warning("No navigation_settings.tres wired; running on prototype_knobs.gd defaults.")
	settings.changed.connect(_apply_settings)

	# The player owns the movement values and watches the resource itself, because
	# it reads most of them per frame rather than having them pushed at it.
	_player.bind_settings(settings)
	_tuning.bind(settings)
	_apply_settings()


## Runs once at startup and again on every change from the tuning panel, so
## "it took effect while flying" and "it took effect on the next run" are the
## same code path rather than two that can drift apart.
func _apply_settings() -> void:
	var scene_environment := _world_environment.environment
	scene_environment.fog_depth_begin = PrototypeKnobs.FOG_DEPTH_BEGIN
	scene_environment.fog_depth_end = settings.fog_depth_end
	scene_environment.fog_density = PrototypeKnobs.FOG_DENSITY

	# The clip-plane-inside-the-fog warning that used to live here is now
	# NavigationSettings.invariant_failures(), so it is checked against the SAVED
	# numbers and by verify_prototype_settings.tscn rather than only at startup.
	for failure: String in settings.invariant_failures():
		push_warning("navigation_settings: %s" % failure)
