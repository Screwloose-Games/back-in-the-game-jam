extends Node3D

## Pushes the values from carry_knobs.gd onto the scene at startup, so that
## file stays the single place worth editing.

@onready var _world_environment: WorldEnvironment = $WorldEnvironment
@onready var _chamber: ChamberGenerator = $Chamber


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
	_apply_draw_distance()


# The player handles this key too, for itself. Resetting the object as well is
# what makes one press restart the experiment rather than leave the load
# wherever the last attempt abandoned it.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("reset_player"):
		_chamber.reset_carry_object()


func _apply_draw_distance() -> void:
	var scene_environment := _world_environment.environment
	scene_environment.fog_depth_begin = CarryKnobs.FOG_DEPTH_BEGIN
	scene_environment.fog_depth_end = CarryKnobs.FOG_DEPTH_END
	scene_environment.fog_density = CarryKnobs.FOG_DENSITY

	if CarryKnobs.CAMERA_FAR <= CarryKnobs.FOG_DEPTH_END:
		push_warning(
			(
				"CarryKnobs.CAMERA_FAR (%.1f) is not past FOG_DEPTH_END (%.1f): "
				+ "geometry will pop at the clip plane before fog hides it."
			)
			% [CarryKnobs.CAMERA_FAR, CarryKnobs.FOG_DEPTH_END]
		)
