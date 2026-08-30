class_name CutscenePlayer
extends Node3D

## One cutscene, living in the level next to the actors it controls.
##
## Not a separate scene, deliberately. Its entire job is to intercept live
## gameplay - take the camera off the player, pose actors already standing in the
## room, suppress input. AnimationPlayer resolves track paths against its own
## root_node, so animating a live actor from an instanced cutscene scene would
## mean paths that walk out into the level, against nodes that are not there while
## you are authoring. You would be typing paths blind.
##
## THE CLOCK IS AUTHORITATIVE AND THE ANIMATION IS NOT. Presentation is
## discardable, seekable and client-local; effects are ordered, replayable and
## must survive a skip. Keeping them apart is the one architectural claim this
## design rests on, and it earns its keep three times over - on skip, on scrub,
## and (later) on the network.
##
## GENERIC ON PURPOSE. It talks to a CutsceneHud and a CutsceneEffects and knows
## nothing about elevators; the two numbers it used to read off a knobs file are
## public vars the owner pushes.

signal started
signal finished

enum Phase { IDLE, PLAYING }

## The effects list and the playback flags. Assigned in the .tscn.
@export var data: CutsceneData

## How long the camera takes to hand back at a normal end. Zero on the skip
## path, always - a skip that eased would take longer than the thing it skipped.
var exit_blend_time := 0.35

## Radius of the sphere the exit-marker check casts. The player's hull.
var rig_hull_radius := 0.4

var _phase := Phase.IDLE
var _clock := 0.0
var _length := 0.0
var _speed_scale := 1.0
var _next_effect := 0
var _effects: Array[CutsceneTimedEffect] = []

var _level_root: Node3D
var _rig: CutscenePlayerRig
var _rig_shape: CollisionShape3D
var _exit_marker: Node3D
var _camera_driver: CutsceneCameraDriver
var _hud: CutsceneHud
var _effects_target: CutsceneEffects

@onready var _animation_player: AnimationPlayer = $AnimationPlayer
@onready var _camera_anchor: Node3D = $CameraAnchor
@onready var _preview_camera: Camera3D = get_node_or_null("CameraAnchor/PreviewCamera")


func bind(
	level_root: Node3D,
	rig: CutscenePlayerRig,
	rig_shape: CollisionShape3D,
	exit_marker: Node3D,
	camera_driver: CutsceneCameraDriver,
	hud: CutsceneHud,
	effects_target: CutsceneEffects
) -> void:
	_level_root = level_root
	_rig = rig
	_rig_shape = rig_shape
	_exit_marker = exit_marker
	_camera_driver = camera_driver
	_hud = hud
	_effects_target = effects_target

	_assert_animation_root()
	_load_data()
	# The collider does not exist yet: CSGCombiner3D raises its geometry in its
	# own _ready, so a shape query this frame hits nothing and reports the exit
	# marker clear no matter where it is.
	await get_tree().process_frame
	await get_tree().process_frame
	_warn_if_exit_is_inside_geometry()


## The node the animation poses and the camera follows. Public because an
## effects subclass may want to carry the player's own body along with it.
func get_camera_anchor() -> Node3D:
	return _camera_anchor


func is_playing() -> bool:
	return _phase == Phase.PLAYING


func get_clock() -> float:
	return _clock


func get_length() -> float:
	return _length


func get_fired_count() -> int:
	return _next_effect


func set_speed_scale(speed_scale: float) -> void:
	_speed_scale = maxf(speed_scale, 0.01)
	_animation_player.speed_scale = _speed_scale


## Starts the cutscene: input off, camera taken, clip playing, clock running.
func enter(blend_time: float) -> void:
	if _phase != Phase.IDLE:
		# DROP, DO NOT QUEUE. A beat that fires thirty seconds late, in a room
		# the player has already left, reads as a bug; a beat that never played
		# is at least legible.
		push_warning("%s requested while already playing; dropped." % name)
		return
	if data == null:
		push_error("CutscenePlayer has no CutsceneData; nothing to play.")
		return

	_phase = Phase.PLAYING
	_clock = 0.0
	_next_effect = 0
	_effects_target.reset()

	# --- input lock -------------------------------------------------------
	# set_input_enabled(false) already zeroes both, but the rig's angular
	# velocity is the script's own member rather than a body property, and
	# leaving that to one call in another file is how a tumbling cutscene
	# happens. Cheap to be explicit.
	_rig.set_input_enabled(false)
	_rig.velocity = Vector3.ZERO
	_rig.angular_velocity = Vector3.ZERO
	# Four bodies in a car composed for three, and shot 3 sits inside the
	# player's own head. Put back in _cleanup, or the player stays invisible.
	_rig.set_avatar_hidden(true)

	# --- physics handoff --------------------------------------------------
	# A body driven along keyframes with collision live fights the solver and
	# either jitters or ejects. Nothing keyframes this rig while the avatar is
	# hidden, but the shape comes off anyway so that posing it later cannot
	# quietly break.
	_rig_shape.disabled = true

	# --- avatar handling: hide -------------------------------------------
	# Free, because the rig carries no mesh. The lamp is the only part of the
	# player that would otherwise be in frame - as a moving pool of light with
	# no source, which is worse than a body.
	_rig.set_lamp_enabled(false)

	# --- HUD and pointer --------------------------------------------------
	# VISIBLE, not CAPTURED. There is nothing to aim, and a captured pointer
	# parked at screen centre is what makes the tuning panel unclickable - the
	# one surface a director needs while the thing they are tuning is playing.
	_rig.set_pointer_visible(true)
	_hud.set_gameplay_visible(false)
	_hud.set_skip_prompt_visible(data.skippable)

	# --- camera -----------------------------------------------------------
	_camera_driver.request_control(_camera_anchor, CutsceneCameraDriver.Authority.FULL, blend_time)

	# --- presentation -----------------------------------------------------
	_animation_player.speed_scale = _speed_scale
	_animation_player.play(data.animation_name)

	# The window is half-open at the low end (see _dispatch_window), so an effect
	# at exactly t=0 could never be inside it once the clock has started at 0.
	# Opening the window below zero once, here, is what lets an author put an
	# effect on the first frame - which car_descending genuinely wants to be.
	_dispatch_window(-1.0, 0.0)
	started.emit()


## Discards the presentation, replays every un-fired effect, cuts to the end.
##
## THE SEEK IS WHAT MAKES "the same end state" TRUE RATHER THAN HOPED FOR. Every
## visible thing in this cutscene is a keyframe, so seeking to the last frame with
## update = true puts the doors, the HUD alpha, the visor and the miner's arm
## exactly where playing through would have left them - in one call, with no
## per-property teardown list to keep in sync with the animation as it grows.
func skip() -> void:
	if _phase != Phase.PLAYING or not data.skippable:
		return
	_animation_player.seek(_length, true, true)
	_animation_player.stop()
	_dispatch_window(_clock, _length)
	_clock = _length
	# Blend time is zero on the skip path. A skip that eased would take longer
	# than the thing it skipped.
	_cleanup(0.0)


func _process(delta: float) -> void:
	advance(delta)


## One tick of the authoritative clock.
##
## Public so the frame-hitch case can be driven directly: one call with a
## twenty-second delta is exactly the hitch that puts several effects inside a
## single dispatch window, and it is the case the naive equality check drops.
## Testing it through the real code path beats reaching into a private method.
func advance(delta: float) -> void:
	if _phase != Phase.PLAYING:
		return
	var previous := _clock
	# Advanced by delta here, NOT read off AnimationPlayer.current_position. The
	# clock is authoritative and the animation is presentation; the moment they
	# are the same number, skipping - which stops the animation - has no clock
	# left to dispatch against.
	_clock = minf(_clock + delta * _speed_scale, _length)
	_dispatch_window(previous, _clock)
	# After the window, so a beat that starts carrying the rig this tick carries
	# it on the same frame it fires rather than one frame later.
	_effects_target.advance(delta)
	if _clock >= _length:
		_cleanup(_exit_blend_time())


## Fires every effect where previous < t <= current, in timestamp order.
##
## A WINDOW, NOT AN EQUALITY. A frame hitch can put three effects inside one tick,
## and the naive is_equal_approx(t, _clock) check drops all three - silently, and
## only under load, which means only on the playtester's machine and never on
## yours.
##
## Half-open at the low end so an effect landing exactly on a tick boundary fires
## once rather than twice. _next_effect is the fired-index: skip resumes from it
## and so can never re-run what already ran.
func _dispatch_window(previous: float, current: float) -> void:
	while _next_effect < _effects.size():
		var timed: CutsceneTimedEffect = _effects[_next_effect]
		if timed.time <= previous or timed.time > current:
			return
		_effects_target.apply(timed.effect_name, timed.detail)
		_next_effect += 1


## THE ONE TEARDOWN PATH. Reached from a normal end and from a skip, and nothing
## else does any of this. If a third terminal state ever appears - an abort, a
## disconnect - it comes through here or it is a bug.
func _cleanup(blend_time: float) -> void:
	_phase = Phase.IDLE
	_animation_player.stop()

	# --- where the player ends up ----------------------------------------
	# The exit marker, NOT wherever the animation left the rig. With the avatar
	# hidden the rig is never keyframed at all, so "its position on the last
	# frame" is just where it was standing when the cutscene started - inside the
	# car, in a spot the shot was composed around. Using the same marker on both
	# terminal paths is what stops skipping and watching ending somewhere
	# different, which would be two endings with only one of them tested.
	_rig.global_transform = _exit_marker.global_transform
	# Ordered: the transform is written while the shape is still disabled, so the
	# solver never sees the rig at the old pose with collision live and shove it
	# out of the wall it was standing in.
	_rig_shape.disabled = false
	# Velocity stays at zero rather than being restored. Resuming a drift begun a
	# minute of screen time ago is surprising, and in zero-G it is unrecoverable.
	_rig.velocity = Vector3.ZERO
	_rig.angular_velocity = Vector3.ZERO
	_rig.set_spawn_transform(_exit_marker.global_transform)
	_rig.set_lamp_enabled(true)
	_rig.set_avatar_hidden(false)

	# --- the end state the effects own -----------------------------------
	# Delegated, because which flags a cutscene keeps is its own business. The
	# monitor-shot line stays here: a stuck full-screen opaque overlay is the
	# worst failure any cutscene has, and it is not up to a subclass to remember.
	_effects_target.settle_terminal_state()
	_hud.set_monitor_shot_visible(false)
	_hud.set_skip_prompt_visible(false)

	# --- camera back ------------------------------------------------------
	_camera_driver.release_control(blend_time)

	# --- HUD, pointer, input, in that order -------------------------------
	_hud.set_gameplay_visible(true)
	_rig.set_pointer_visible(false)
	# LAST. set_input_enabled(true) clears the mouse motion that banked up while
	# the pointer was free, so it has to run after the mode change rather than
	# before it - otherwise the motion generated between the two is spent as a
	# whip-pan on the first frame of restored control.
	_rig.set_input_enabled(true)

	finished.emit()


func _exit_blend_time() -> float:
	return exit_blend_time


## The silent failure the spec singles out, turned into a named error.
##
## AnimationPlayer.root_node left at its default resolves to this node rather than
## to the level, so every track path - all of which are written relative to the
## level root - resolves to nothing. Nothing errors. Nothing warns. The cutscene
## plays as a still frame and you are left guessing which of eleven tracks broke.
func _assert_animation_root() -> void:
	var resolved := _animation_player.get_node_or_null(_animation_player.root_node)
	if resolved == _level_root:
		return
	push_error(
		(
			"AnimationPlayer.root_node resolves to %s, not the level root %s. Every track path is dead and nothing else will tell you."
			% [resolved, _level_root]
		)
	)


## The backstop for the one authoring rule this design has: do not park the exit
## marker inside geometry.
##
## Ten lines, and it turns "the player sometimes ends up stuck in a wall" into a
## named warning at startup. Cheap because there is exactly one exit pose; a real
## implementation with per-slot exit transforms would check each of them.
func _warn_if_exit_is_inside_geometry() -> void:
	var shape := SphereShape3D.new()
	shape.radius = rig_hull_radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, _exit_marker.global_position)
	# Layer 1 is `hull` in project.godot's [layer_names]: the car shell, the door
	# leaves and the tunnel rock.
	query.collision_mask = 1
	var hits := get_world_3d().direct_space_state.intersect_shape(query, 1)
	if hits.is_empty():
		return
	push_warning(
		(
			"PlayerExit at %s is inside %s; control returns with the rig stuck in geometry."
			% [_exit_marker.global_position, hits[0]["collider"]]
		)
	)


func _load_data() -> void:
	if data == null:
		return
	_effects = data.sorted_effects()
	var animation := _animation_player.get_animation(data.animation_name)
	if animation == null:
		push_error(
			(
				"AnimationPlayer has no animation '%s'; check the library on the node."
				% data.animation_name
			)
		)
		return
	_length = animation.length
	for failure: String in data.validate(_length):
		push_warning("%s.cutscene.tres: %s" % [data.animation_name, failure])

	# The editor's Preview toggle writes current = true back into the .tscn, and
	# using it is exactly the workflow this node exists for - so the saved scene
	# will have it set sooner or later. Freeing the node is one fewer camera that
	# can win the `current` race at runtime.
	if _preview_camera != null:
		_preview_camera.queue_free()
