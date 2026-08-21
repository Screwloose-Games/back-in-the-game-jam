@tool
class_name MinerRig
extends Node3D

## One miner: the real character model, breathing, with a laser in one hand.
##
## Replaces the greybox box-limb miner. The root is at the feet and faces -Z like
## everything else in this project; the 180 degree yaw that the art's +Z authoring
## needs lives on the Rig node inside, exactly as prefab_player does it, so the
## three placements in the level never have to know about it.
##
## Nothing here is authored into the .tscn that could not survive a re-import of
## the glTF - see _build_visor and _bind_tool.

## Emission is AUTHORED here, not turned up. The imported helmet material has
## none at all, so a re-export of the character will not quietly take the visor
## glow with it; only the base colour comes from the model.
const VISOR_MATERIAL := preload(
	"res://prototypes/elevator_cutscene/materials/miner_visor_material.tres"
)
const GESTURE_LIBRARY := preload(
	"res://prototypes/elevator_cutscene/animations/miner_gesture_library.tres"
)
const HELMET_MESH := "player_character_helmet"
const BLEND_PARAMETER := "parameters/blend/blend_amount"
const BASE_SEEK_PARAMETER := "parameters/base_seek/seek_request"

## Where this miner starts in idle_float's 4 s loop. Three identical loops in
## lockstep read as one animation played three times.
@export var idle_phase: float = 0.0

## Which hand the laser sits in.
##
## MinerB holds theirs in the LEFT. The gesture raises the right arm to the
## helmet, and a 1.14 m cutter welded to that hand would sweep across their face
## in the medium close-up the whole cutscene is built around. Moving the camera
## instead is not available: shot 2 sits front-right precisely so the gesturing
## arm is the one nearest the lens.
@export var tool_bone: StringName = &"RightHand"

## Emission on the visor. The cutscene animates this by name on THIS node rather
## than reaching into the model, so the track survives a re-import.
@export var visor_energy: float = ElevatorCutsceneKnobs.VISOR_IDLE_ENERGY:
	set(value):
		visor_energy = value
		if _visor_material != null:
			_visor_material.emission_energy_multiplier = value

var _visor_material: StandardMaterial3D

@onready var _animation_tree: AnimationTree = $Rig/AnimationTree
@onready var _attachment: BoneAttachment3D = $Rig/ToolAttachment


func _ready() -> void:
	_build_visor()
	_bind_tool()
	_start_animation()


## Gives this miner its own visor material, with emission switched on.
##
## BY NAME AND FROM CODE. The helmet lives inside an instanced glTF scene, so a
## material assigned in this .tscn would need editable children and would not
## survive a re-import - the same rule PlayerVisibility works around by writing
## render layers at runtime. Duplicating the imported material rather than
## replacing it keeps the helmet's own texture.
##
## Per-instance uniqueness is structural here: each miner instantiates its own
## copy of the model, so a surface override on one cannot be the one another
## reads. The greybox needed an explicit duplicate() to avoid lighting all three
## visors at once; this cannot express that bug.
func _build_visor() -> void:
	var found := find_children(HELMET_MESH, "MeshInstance3D", true, false)
	if found.is_empty():
		push_error("miner rig: no %s mesh, so the visor cannot light." % HELMET_MESH)
		return
	var helmet := found[0] as MeshInstance3D
	var source := helmet.mesh.surface_get_material(0) as StandardMaterial3D
	if source == null:
		push_error("miner rig: the helmet's surface 0 is not a StandardMaterial3D.")
		return
	_visor_material = source.duplicate()
	_visor_material.emission_enabled = true
	_visor_material.emission = VISOR_MATERIAL.emission
	_visor_material.emission_energy_multiplier = visor_energy
	helmet.set_surface_override_material(0, _visor_material)


func _bind_tool() -> void:
	_attachment.bone_name = tool_bone
	if _attachment.bone_idx < 0:
		push_error("miner rig: the character has no '%s' bone." % tool_bone)


## Adds the generated gesture clip, then lets the tree run.
##
## The clip cannot be authored onto the model's own AnimationPlayer in a .tscn -
## that is an override inside an instanced glTF. Adding the library by method
## call is the sanctioned equivalent, and @tool means the editor resolves the
## layer too, so the director can still scrub the shot.
func _start_animation() -> void:
	var player := _animation_tree.get_node_or_null(_animation_tree.anim_player) as AnimationPlayer
	if player == null:
		push_error("miner rig: the AnimationTree has no anim_player.")
		return
	if not player.has_animation_library(&"cutscene"):
		player.add_animation_library(&"cutscene", GESTURE_LIBRARY)
	_animation_tree.active = true
	_animation_tree.set(BASE_SEEK_PARAMETER, idle_phase)
	reset_gesture()


## Forces the visor to its lit or unlit end state.
##
## The ramp is a keyframe; this is for CLEANUP, where the animation has stopped
## and something still has to be the authority on where it ended up.
func set_visor_lit(lit: bool) -> void:
	visor_energy = (
		ElevatorCutsceneKnobs.VISOR_LIT_ENERGY if lit else ElevatorCutsceneKnobs.VISOR_IDLE_ENERGY
	)


func get_visor_material() -> StandardMaterial3D:
	return _visor_material


func get_gesture_blend() -> float:
	return _animation_tree.get(BLEND_PARAMETER)


## Puts the arm back under the idle loop alone.
##
## A skip already lands the blend weight at zero, because it is a keyframe like
## any other. This exists so a REPLAY after a mid-gesture skip starts clean
## without depending on the clip's t=0 key having been crossed.
func reset_gesture() -> void:
	_animation_tree.set(BLEND_PARAMETER, 0.0)


func get_skeleton() -> Skeleton3D:
	return _attachment.get_node_or_null(_attachment.external_skeleton) as Skeleton3D
