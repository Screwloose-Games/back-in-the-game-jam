class_name PlayerRigAnimation
extends Node

## Drives the rig's upper-body animation layer from the hands and the mining
## tool. The laser clips cover the Spine subtree only, so the body goes on
## floating from the base layer whatever the arms are doing.

const UPPER_PLAYBACK := "parameters/upper/playback"

## The cutscene gesture layer's clip, added to the model's own AnimationPlayer by
## method call because a library cannot be authored onto an instanced glTF in a
## .tscn and would not survive a re-import if it could.
const CUTSCENE_LIBRARY := preload(
	"res://levels/asteroid_level/intro/animations/player_gesture_library.tres"
)

var _tool_was_out := false

@onready var tree: AnimationTree = %AnimationTree
@onready var hands: PlayerHands = %Hands
@onready var mining_tool: PlayerMiningTool = %MiningTool


func _ready() -> void:
	_add_cutscene_library()
	hands.slot_changed.connect(_on_slot_changed)
	mining_tool.started_firing.connect(_on_started_firing)
	mining_tool.stopped_firing.connect(_on_stopped_firing)
	_apply_tool_visibility()


## PlayerMiningTool.tool_model is documented as "shown only while the tool is
## out", and the timing of that belongs here rather than on the slot change: the
## laser has to stay in frame for the whole put-away clip and vanish as it ends,
## not blink out of the hand the instant the hands are released.
func _process(_delta: float) -> void:
	_apply_tool_visibility()


## The tree is authored inactive so this runs before it resolves its layers; an
## AnimationNodeAnimation naming a clip that is not there yet resolves to nothing.
func _add_cutscene_library() -> void:
	var player := tree.get_node_or_null(tree.anim_player) as AnimationPlayer
	if player == null:
		push_error("PlayerRigAnimation: the AnimationTree has no anim_player.")
		return
	if not player.has_animation_library(&"cutscene"):
		player.add_animation_library(&"cutscene", CUTSCENE_LIBRARY)
	tree.active = true


## Travels the upper layer. Named states only -- the state machine owns the
## routing, so stowing mid-beam walks fire -> hold -> stow on its own.
func travel(state: StringName) -> void:
	var playback: AnimationNodeStateMachinePlayback = tree.get(UPPER_PLAYBACK)
	if playback == null:
		push_warning("No upper-body state machine on the rig's AnimationTree.")
		return
	playback.travel(state)


func _on_slot_changed(slot: PlayerHands.Slot) -> void:
	# Only the tool leaving the hands is a stow. Picking up a crate also changes
	# the slot, and playing the put-away clip for a tool that was never out reads
	# as the character miming.
	if slot == PlayerHands.Slot.TOOL:
		travel(&"laser_equip")
	elif _tool_was_out:
		travel(&"laser_stow")
	_tool_was_out = slot == PlayerHands.Slot.TOOL


func _apply_tool_visibility() -> void:
	if mining_tool.tool_model == null:
		return
	var playback: AnimationNodeStateMachinePlayback = tree.get(UPPER_PLAYBACK)
	var idle := playback == null or playback.get_current_node() == &"idle_float"
	mining_tool.tool_model.visible = _tool_was_out or not idle


func _on_started_firing() -> void:
	travel(&"laser_fire")


func _on_stopped_firing() -> void:
	travel(&"laser_hold")
