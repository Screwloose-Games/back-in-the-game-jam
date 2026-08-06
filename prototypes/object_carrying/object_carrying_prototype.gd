extends Node3D

## Pushes the values from carry_knobs.gd onto the scene at startup, so that
## file stays the single place worth editing.
##
## The handful of values with sliders come from carry_settings.tres instead,
## which starts life holding exactly those consts. See PrototypeSettings.

## Grip, tether and murk you can move from the tuning panel, and what SAVE writes
## back to. Assigned in the .tscn; see _ready for what happens when it is missing.
@export var settings: CarrySettings

@onready var _world_environment: WorldEnvironment = $WorldEnvironment
@onready var _chamber: ChamberGenerator = $Chamber
@onready var _player: CarrierPlayer = $CarrierPlayer
@onready var _tuning: PrototypeTuningPanel = $HUD/Tuning


# The player has to be moved to its spawn before it enters the tree, which is
# why this runs here and not in _ready. Once a body is in the physics world,
# repositioning it is a kinematic move rather than a teleport: anything sitting
# inside it at the old pose gets carried to the new one and released at the
# speed of the move. The old pose is the scene origin, which is where the carry
# object spawns, so the load would be flung across the chamber on the first
# frame - or not, depending on which face of it the contact resolved against.
func _enter_tree() -> void:
	var player: Node3D = $CarrierPlayer
	player.position = CarryKnobs.PLAYER_SPAWN


func _ready() -> void:
	# A fresh clone has no carry_settings.tres yet, and anyone may delete it. A
	# bare instance holds exactly the knobs consts, so the fallback is the old
	# behaviour rather than a crash.
	if settings == null:
		settings = CarrySettings.new()
		push_warning("No carry_settings.tres wired; running on carry_knobs.gd defaults.")
	settings.changed.connect(_apply_settings)

	# The player owns the grip and tether values and watches the resource itself,
	# because it reads most of them per frame rather than having them pushed at it.
	_player.bind_settings(settings)
	_tuning.bind(settings)
	_apply_settings()


# The player handles this key too, for itself. Resetting the object as well is
# what makes one press restart the experiment rather than leave the load
# wherever the last attempt abandoned it.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("reset_player"):
		_chamber.reset_carry_object()


## Runs once at startup and again on every change from the tuning panel, so
## "it took effect while flying" and "it took effect on the next run" are the
## same code path rather than two that can drift apart.
func _apply_settings() -> void:
	var scene_environment := _world_environment.environment
	scene_environment.fog_depth_begin = CarryKnobs.FOG_DEPTH_BEGIN
	scene_environment.fog_depth_end = settings.fog_depth_end
	scene_environment.fog_density = CarryKnobs.FOG_DENSITY

	# The clip-plane-inside-the-fog warning that used to live here is now
	# CarrySettings.invariant_failures(), so it is checked against the SAVED
	# numbers and by verify_prototype_settings.tscn rather than only at startup.
	for failure: String in settings.invariant_failures():
		push_warning("carry_settings: %s" % failure)
