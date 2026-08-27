@tool
class_name ElevatorCar
extends Node3D

## The elevator car: text, lights, doors, and which of the model's meshes show.
##
## THE GEOMETRY IS NOT HERE. Sizes and positions are authored in the .tscn, not
## pushed from the knobs file at _ready. That is the opposite of what the other
## prototypes do, and it is deliberate: the payoff of this whole exercise is the
## director opening the level, hitting Preview on the camera under the anchor and
## scrubbing. If a script resized the car at runtime, the editor viewport would
## show one car and the game would show another, and the shot the director
## composed would not be the shot that ships.
##
## What this script owns is everything that is a state rather than a shape: the
## text on the screen, how bright the lights are, whether the car is running, and
## whether the doors are solid. Which meshes are drawn is the one exception, and
## _hide_parts says why it has to be.
##
## THE DOOR NUMBERS LIVE HERE, NOT IN A CUTSCENE'S KNOBS FILE. They are facts
## about the art, and the animation builder reads them off this class. A knobs
## file that owned them would be a second copy of a measurement the glTF already
## decides.

## The three meshes in sm_elevator_car.gltf. The shell and the two leaves move
## independently, so the container scene is instanced three times and each copy
## shows exactly one of them.
const SHELL_MESH := "car_shell"
const DOOR_LEFT_MESH := "door_left"
const DOOR_RIGHT_MESH := "door_right"

## Where the leaf pivots sit with the doors shut. Both leaves are modelled in
## place, so this is zero and the animation moves them apart from it.
const DOOR_CLOSED_X := 0.0

## How far each leaf travels to clear the doorway: exactly one leaf width.
## _assert_door_invariant checks it against the imported mesh.
const DOOR_TRAVEL := 1.08

const CEILING_LIGHT_ENERGY := 1.6
const CEILING_FLICKER_DEPTH := 0.12
const CEILING_FLICKER_FREQUENCY := 11.0

## Copy on the car. Exported so a second car in a second level can say something
## else, defaulted so no level has to say anything at all.
@export var crew_id: String = "EXTRACTION CREW 067"
@export var quota_caption: String = "OUTSTANDING BALANCE:"
@export var auth_caption: String = "DEPARTURE AUTHORIZATION:"
@export var auth_denied_text: String = "DENIED"
@export var quota_target: int = 47560
@export_multiline var placard_text: String = "PROPERTY OF"

var _base_light_energy := CEILING_LIGHT_ENERGY
var _flicker_phase := 0.0
var _shaft_running := false

@onready var _door_left: Node3D = $Doors/DoorLeft
@onready var _door_right: Node3D = $Doors/DoorRight
@onready var _door_left_shape: CollisionShape3D = $Doors/DoorLeft/LeafBody/LeafShape
@onready var _door_right_shape: CollisionShape3D = $Doors/DoorRight/LeafBody/LeafShape
@onready var _quota_screen: ElevatorScreen = $QuotaScreen
@onready var _placard_text: Label3D = $Placard/PlacardText
@onready var _ceiling_light: OmniLight3D = $CeilingLight
# Typed as Node, not as ShaftLights: the bar column lives in the prototype that
# still wants it, and a shipped prefab does not reference a prototype's class.
@onready var _shaft_lights: Node = get_node_or_null("ShaftLights")


func _ready() -> void:
	_hide_parts()
	if Engine.is_editor_hint():
		return
	_apply_text()
	_assert_door_invariant()


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not _shaft_running:
		return
	_flicker_phase += delta * CEILING_FLICKER_FREQUENCY
	var wobble := sin(_flicker_phase) * sin(_flicker_phase * 0.37)
	var depth := CEILING_FLICKER_DEPTH
	_ceiling_light.light_energy = _base_light_energy * (1.0 + wobble * depth)


## Shows one mesh per glTF instance and hides the rest.
##
## BY NAME, FROM CODE, AND @tool - none of those three is a preference. The
## meshes live inside an instanced glTF scene, so a visible = false authored in
## this .tscn would need editable children and would not survive a re-import.
## That is the same rule PlayerVisibility works around by writing render layers
## at runtime. Name lookup does survive a re-import. @tool is what stops the
## editor viewport showing three overlapping cars, which the director's
## scrub-and-preview workflow depends on.
func _hide_parts() -> void:
	_show_only($Shell/sm_elevator_car, SHELL_MESH)
	_show_only($Doors/DoorLeft/sm_elevator_car, DOOR_LEFT_MESH)
	_show_only($Doors/DoorRight/sm_elevator_car, DOOR_RIGHT_MESH)


func _show_only(instance: Node3D, kept: String) -> void:
	var found := false
	for mesh: MeshInstance3D in instance.find_children("*", "MeshInstance3D", true, false):
		mesh.visible = mesh.name == kept
		found = found or mesh.visible
	if not found:
		push_error(
			(
				"elevator car: sm_elevator_car has no mesh named '%s'; the model was re-exported with different node names."
				% kept
			)
		)


## Copy lives in the knobs file and is pushed here, which is the one case where
## pushing beats authoring in the scene: copy is the thing most likely to change,
## and it should change in one place rather than in six Label3D inspectors.
func _apply_text() -> void:
	_quota_screen.crew_id = crew_id
	_quota_screen.quota_caption = quota_caption
	_quota_screen.auth_caption = auth_caption
	_quota_screen.denied_text = auth_denied_text
	_quota_screen.quota_target = quota_target
	# Nothing has been mined yet during the intro, so the whole quota is
	# outstanding. PlayerHudBinding._bind_quota_screens takes it over from here
	# the moment a player with a HUD exists.
	_placard_text.text = placard_text


## The door numbers, checked against the ART rather than a second copy of a knob.
##
## The old version compared the authored pivot x against DOOR_CLOSED_X. Both are
## zero now, so that comparison reads 0 == -0 and passes forever. The number that
## is genuinely duplicated is DOOR_TRAVEL: the animation opens each leaf by it,
## and the leaf's own width decides whether that clears the opening. Reading the
## width off the imported mesh means a re-export that resized a leaf fails here,
## by name, instead of leaving a visible gap in the shot.
func _assert_door_invariant() -> void:
	var problems := PackedStringArray()
	var closed := DOOR_CLOSED_X
	var travel := DOOR_TRAVEL
	if not is_equal_approx(_door_left.position.x, -closed):
		# Built into a local first: passing the formatted string straight to the
		# call makes gdformat wrap it into a parenthesised chain nobody can read.
		var misplaced := (
			"DoorLeft is authored at x=%.3f but DOOR_CLOSED_X says %.3f"
			% [_door_left.position.x, -closed]
		)
		problems.append(misplaced)
	var leaf := _door_left_aabb()
	if leaf.size.is_zero_approx():
		problems.append("the left leaf mesh is missing, so its width cannot be checked")
	else:
		if not is_equal_approx(travel, leaf.size.x):
			var mismatched := (
				"DOOR_TRAVEL is %.3f but the leaf is %.3f wide, so the doors will not clear"
				% [travel, leaf.size.x]
			)
			problems.append(mismatched)
		if not is_equal_approx(leaf.end.x, -closed):
			var gapped := "the leaves do not meet when closed: inner edge at x=%.3f" % leaf.end.x
			problems.append(gapped)
	for problem: String in problems:
		push_error("elevator doors: %s" % problem)


func _door_left_aabb() -> AABB:
	var found := _door_left.find_children(DOOR_LEFT_MESH, "MeshInstance3D", true, false)
	if found.is_empty():
		return AABB()
	return (found[0] as MeshInstance3D).get_aabb()


## Whether the car is running. The ceiling lamp wavers while it is.
##
## THIS USED TO BE THE SHAFT-LIGHT COLUMN, and the signature is unchanged so that
## ElevatorIntroEffects never learned the difference. The real shell has no wall slot,
## so bars streaming past outside it cannot be seen from in here; the lamp
## reacting to the machinery is what is left to say the car is moving. ShaftLights
## survives for the day a slot is authored into the art, and drives again the
## moment the node is put back in the scene.
func set_shaft_running(running: bool) -> void:
	_shaft_running = running
	if _shaft_lights != null and _shaft_lights.has_method("set_running"):
		_shaft_lights.set_running(running)
	if not running:
		_ceiling_light.light_energy = _base_light_energy


## Whether the door leaves still block the doorway.
##
## SEPARATE BODIES FROM THE SHELL. The leaves stop blocking the doorway at 15.6 s
## while the shell goes on being solid, so each carries its own StaticBody3D.
## That was true when the shell was a CSGCombiner3D whose collision could not be
## partly disabled, and it stays true now the shell's collision is eight boxes.
func set_doors_solid(solid: bool) -> void:
	_door_left_shape.disabled = not solid
	_door_right_shape.disabled = not solid


func are_doors_solid() -> bool:
	return not _door_left_shape.disabled


## Plain floats rather than a settings resource, so a shipped prefab does not know
## what a prototype tuning panel is.
func apply_settings(ceiling_energy: float, shaft_speed: float, shaft_spacing: float) -> void:
	_base_light_energy = ceiling_energy
	_ceiling_light.light_energy = _base_light_energy
	if _shaft_lights != null and _shaft_lights.has_method("set_stream"):
		_shaft_lights.set_stream(shaft_speed, shaft_spacing)


## Read by the verifier: doors visually shut while their colliders are off is the
## exact inverse of the bug doors_unlocked exists to prevent.
func are_doors_shut() -> bool:
	return (
		is_equal_approx(_door_left.position.x, DOOR_CLOSED_X)
		and is_equal_approx(_door_right.position.x, DOOR_CLOSED_X)
	)


func get_warning_strobe() -> OmniLight3D:
	return $WarningStrobe


func get_quota_screen() -> ElevatorScreen:
	return _quota_screen
