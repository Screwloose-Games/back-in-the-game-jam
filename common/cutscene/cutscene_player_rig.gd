class_name CutscenePlayerRig
extends Node

## The cutscene's whole view of the player, in one file.
##
## THIS IS THE FIREWALL. prefab_player is twenty-seven components, ten autoloads
## and three shared systems, none of which belong to this prototype; the cutscene
## needs about six things from it. Everything the cutscene says to the player
## comes through here, so a change on the other side of this seam breaks one
## small file with a name that says what it is, rather than breaking a
## nineteen-second cinematic in a way whose failure message talks about cameras.
##
## The vocabulary is deliberately the one the forked rig in imported/ used to
## offer before it was deleted, so cutscene_player.gd changed only the TYPE of its
## rig and not one call.

## Where the cutscene gesture layer's weight lives on the player's blend tree.
## Named here rather than at the call site so a rename in prefab_player.tscn
## breaks one line instead of every cutscene that raises an arm.
const GESTURE_BLEND_PARAMETER := "parameters/gesture/blend_amount"

@export var body: CharacterBody3D
@export var hull_shape: CollisionShape3D
@export var head_camera: Camera3D
@export var input: Node
@export var locomotion: Node
@export var lamp: Node
@export var respawn: Node
@export var visibility: Node
@export var animation_tree: AnimationTree
@export var tool_model: Node3D

var velocity: Vector3:
	get:
		return body.velocity
	set(value):
		body.velocity = value

var angular_velocity: Vector3:
	get:
		return locomotion.angular_velocity
	set(value):
		locomotion.angular_velocity = value

var global_transform: Transform3D:
	get:
		return body.global_transform
	set(value):
		body.global_transform = value


## Builds a rig over a prefab_player instance, by path.
##
## THE ALTERNATIVE IS TEN node_paths IN EVERY SCENE THAT WANTS ONE, and a level
## that spawns its player at runtime cannot author them at all. Paths rather than
## %unique names because those only resolve from inside the player's own scene.
static func for_player(player: Node) -> CutscenePlayerRig:
	var body := player.get_node_or_null("PlayerBody") as CharacterBody3D
	if body == null:
		push_error("CutscenePlayerRig.for_player: %s has no PlayerBody." % player)
		return null
	var rig := CutscenePlayerRig.new()
	rig.name = "CutsceneRig"
	rig.body = body
	rig.hull_shape = body.get_node_or_null("HullShape")
	rig.head_camera = body.get_node_or_null("Head/HeadCamera")
	rig.input = body.get_node_or_null("Input")
	rig.locomotion = body.get_node_or_null("Locomotion")
	rig.lamp = body.get_node_or_null("Lamp")
	rig.respawn = body.get_node_or_null("Respawn")
	rig.visibility = body.get_node_or_null("Visibility")
	rig.animation_tree = body.get_node_or_null("Rig/AnimationTree")
	rig.tool_model = body.get_node_or_null("Rig/LaserAttachment/prefab_mining_laser")
	for named: String in [
		"hull_shape", "head_camera", "input", "locomotion", "lamp", "respawn", "visibility"
	]:
		if rig.get(named) == null:
			push_error("CutscenePlayerRig.for_player: %s has no %s." % [player, named])
	return rig


## Parks or releases the player.
##
## FOUR THINGS, NOT ONE. Disabling input stops the polling and clears the banked
## mouse motion, which is what keeps a whole cutscene's worth of stirred-up mouse
## from being spent as a whip-pan on the first frame of restored control.
## Locomotion.halt() zeroes the body's velocity AND the angular velocity it owns
## itself - zeroing only the former leaves the rig spinning on the spot. The two
## externally_driven flags stop move_and_slide running at all: with input off it
## is already a no-op, but "a no-op because the numbers happen to be zero" is not
## the same guarantee as "it does not run".
func set_input_enabled(enabled: bool) -> void:
	# Cleared first, or the assignment below is refused by its own guard.
	input.locked = false
	input.enabled = enabled
	input.locked = not enabled
	locomotion.externally_driven = not enabled
	get_collision_response().externally_driven = not enabled
	if not enabled:
		locomotion.halt()


func set_spawn_transform(pose: Transform3D) -> void:
	respawn.set_spawn_transform(pose)


func set_lamp_enabled(enabled: bool) -> void:
	lamp.set_lit(enabled)


## Whether the player's own suit is drawn.
##
## The cutscene camera is not the player's camera, so PlayerVisibility's normal
## first-person culling does not apply to it: during shots 1 and 2 the player
## would stand in frame as a fourth body in a car composed for three, and shot 3
## sits inside their own head. HIDE_WHOLE_MODEL for the duration is the answer,
## and it has to be put back or the terminal state is an invisible player.
func set_avatar_hidden(hidden: bool) -> void:
	visibility.self_view = (
		PlayerVisibility.SelfView.HIDE_WHOLE_MODEL
		if hidden
		else PlayerVisibility.SelfView.HIDE_LISTED_PARTS
	)


## Draws the whole suit, as a remote player sees it.
##
## The opposite of set_avatar_hidden, and it exists for the opposite kind of shot. An
## intro composed AROUND the crew has to get the player out of frame; an outro whose
## subject IS the crew has to put them in it. SHOW_EVERYTHING puts their meshes on the
## world layer, so a cutscene camera on the ordinary cull mask draws them.
func set_avatar_fully_visible() -> void:
	visibility.self_view = PlayerVisibility.SelfView.SHOW_EVERYTHING


## THE WEIGHT, NEVER THE LAYER: an AnimationTree layer runs on its own real-time
## clock and does not scrub, so the layer holds one solved pose and this is the
## whole gesture.
func set_gesture_blend(weight: float) -> void:
	if animation_tree == null:
		return
	animation_tree.set(GESTURE_BLEND_PARAMETER, clampf(weight, 0.0, 1.0))


func get_gesture_blend() -> float:
	if animation_tree == null:
		return 0.0
	return animation_tree.get(GESTURE_BLEND_PARAMETER)


## Whether the held tool is drawn; a 1.14 m cutter sweeps across frame in any shot
## composed around the arm holding it.
func set_tool_visible(is_visible: bool) -> void:
	if tool_model != null:
		tool_model.visible = is_visible


func set_pointer_visible(visible_pointer: bool) -> void:
	if visible_pointer:
		input.release_mouse()
	else:
		input.capture_mouse()


func get_head_camera() -> Camera3D:
	return head_camera


func get_body() -> CharacterBody3D:
	return body


func get_hull_shape() -> CollisionShape3D:
	return hull_shape


func get_collision_response() -> Node:
	return body.get_node("%CollisionResponse")


func get_drift_speed() -> float:
	return body.velocity.length()


func is_input_enabled() -> bool:
	return input.enabled


func is_mouse_captured() -> bool:
	return input.is_mouse_captured()


func is_lamp_lit() -> bool:
	return lamp.requested_lit()


func is_avatar_hidden() -> bool:
	return visibility.self_view == PlayerVisibility.SelfView.HIDE_WHOLE_MODEL


func get_angular_velocity() -> Vector3:
	return locomotion.angular_velocity


func is_tool_visible() -> bool:
	return tool_model != null and tool_model.visible
