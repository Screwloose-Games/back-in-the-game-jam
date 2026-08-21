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

@export var body: CharacterBody3D
@export var hull_shape: CollisionShape3D
@export var head_camera: Camera3D
@export var input: Node
@export var locomotion: Node
@export var lamp: Node
@export var respawn: Node
@export var visibility: Node

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
	input.enabled = enabled
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
