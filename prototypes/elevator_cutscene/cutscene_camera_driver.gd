class_name CutsceneCameraDriver
extends Camera3D

## The camera control seam from the cutscene spec, section 7: a direct driver,
## no addon.
##
##     request_control(anchor, authority, blend_time)
##     release_control(blend_time)
##
## A DEDICATED CAMERA, NOT THE PLAYER'S HEAD CAMERA. The head camera is a child
## of the CharacterBody3D, so writing its global_transform each frame is a fight
## with the rig: Godot back-solves a local transform against a parent that
## move_and_slide is moving on the physics clock, and the result beats against
## the render frame. A sibling camera that takes `current` and hands it back has
## no such coupling, and the head camera is never disturbed at all - which is why
## the exit is a pure hand-back with nothing to restore.
##
## It is also the only arrangement in which the exit blend has a target. The spec
## says to reverse "against wherever the gameplay camera is now" rather than
## against a stored transform; if the driver WERE the gameplay camera, there
## would be no "now" to blend toward.
##
## `current` IS ALWAYS SET EXPLICITLY, NEVER LEFT TO TREE ORDER. Godot gives it
## to whichever camera readies last, which is a fact about node order rather than
## about anything anyone chose. Three cameras exist in this scene. See
## tentacle_crawler_chaser_prototype.gd, which hit this and fixed it the same way.
##
## process_priority is set in the .tscn so this runs AFTER the AnimationPlayer
## that writes the anchor. Tree order happens to give the right answer today;
## nothing states that it must, and the failure is one frame of camera lag per
## cut - invisible at 60 fps and obvious at 20.

## Emitted once the exit blend has finished and the gameplay camera is current
## again. Not when release_control is called, which is a whole blend earlier.
signal control_released

## How the camera takes its pose from the anchor.
enum Authority {
	## Position and rotation both come from the anchor. Full takeover.
	FULL,
	## Position from the anchor, rotation from the player's own look input. Not
	## exercised by this prototype - the branch exists so that turning it on is a
	## flag change rather than a re-authoring pass, which is the whole point of
	## driving an anchor instead of the camera.
	ANCHORED,
}

enum Phase { IDLE, BLEND_IN, HOLD, BLEND_OUT }

## Live-tunable, pushed from ElevatorCutsceneSettings by the prototype root.
## Defaulted from the knobs so the driver works standing alone.
var rumble_amplitude := ElevatorCutsceneKnobs.RUMBLE_AMPLITUDE
var rumble_frequency := ElevatorCutsceneKnobs.RUMBLE_FREQUENCY
var cutscene_fov := ElevatorCutsceneKnobs.CUTSCENE_FOV

var _gameplay_camera: Camera3D
var _anchor: Node3D
var _authority := Authority.FULL
var _phase := Phase.IDLE
var _blend_time := 0.0
var _blend_elapsed := 0.0
var _blend_from := Transform3D.IDENTITY
var _rumble_gain := 0.0
var _rumble_clock := 0.0


func _ready() -> void:
	# Never on by default. The gameplay camera owns the viewport until something
	# asks for it, and a driver that claimed `current` in _ready would win or lose
	# that race depending on where it sits in the scene dock.
	current = false


## Points the driver at the camera it borrows from and returns to.
func bind(gameplay_camera: Camera3D) -> void:
	_gameplay_camera = gameplay_camera


## The ownership flag. True from request_control until the exit blend has
## finished and `current` is back on the gameplay camera.
func has_control() -> bool:
	return _phase != Phase.IDLE


func request_control(anchor: Node3D, authority: Authority, blend_time: float) -> void:
	if _gameplay_camera == null:
		push_error("CutsceneCameraDriver.request_control before bind(); no camera to blend from.")
		return
	_anchor = anchor
	_authority = authority
	_blend_from = _gameplay_camera.global_transform
	_blend_time = maxf(blend_time, 0.0)
	_blend_elapsed = 0.0
	_rumble_clock = 0.0

	fov = cutscene_fov
	# Inherited rather than chosen: the fog in this scene is tuned against the
	# gameplay clip plane, and a cutscene camera that sees further would show the
	# fog's far edge as a visible wall of nothing.
	near = _gameplay_camera.near
	far = _gameplay_camera.far

	global_transform = _blend_from
	current = true
	if _blend_time > 0.0:
		_phase = Phase.BLEND_IN
		return
	# Zero blend is a cut, and a cut has to land THIS frame. Falling through to
	# _process would leave one frame sitting at the gameplay pose - a single-frame
	# flash of the wrong shot, which is exactly the artefact a cut is meant not to
	# have.
	_phase = Phase.HOLD
	global_transform = _anchor_pose()


func release_control(blend_time: float) -> void:
	if _phase == Phase.IDLE:
		return
	_blend_from = global_transform
	_blend_time = maxf(blend_time, 0.0)
	_blend_elapsed = 0.0
	# Blend time is 0 on the skip path (spec section 7), and 0 means hand back now
	# rather than divide by zero one line further down.
	if is_zero_approx(_blend_time):
		_hand_back()
		return
	_phase = Phase.BLEND_OUT


## The descending car's shake, from 0 (still) to 1 (full amplitude).
##
## Deliberately not a keyframe. Rumble is a state - the car is descending or it
## is not - and it has to still be true after a skip cuts to the last frame,
## where a keyframed shake would be whatever the final key happened to say. The
## effects list owns it; see elevator_effects.gd.
func set_rumble_gain(gain: float) -> void:
	_rumble_gain = clampf(gain, 0.0, 1.0)


func get_rumble_gain() -> float:
	return _rumble_gain


func _process(delta: float) -> void:
	advance(delta)


## One tick of the blend. Public so a test can settle it in a single call rather
## than waiting out a real blend in wall-clock time.
func advance(delta: float) -> void:
	if _phase == Phase.IDLE:
		return
	_rumble_clock += delta
	match _phase:
		Phase.BLEND_IN:
			var entering := _advance(delta)
			global_transform = _mix(_blend_from, _anchor_pose(), entering)
			if entering >= 1.0:
				_phase = Phase.HOLD
		Phase.HOLD:
			global_transform = _anchor_pose()
		Phase.BLEND_OUT:
			# Against where the gameplay camera IS this frame, not a transform
			# stored on entry: CLEANUP has just teleported the rig to its exit
			# pose, so the target has moved since anything could have been
			# captured.
			var leaving := _advance(delta)
			global_transform = _mix(_blend_from, _gameplay_camera.global_transform, leaving)
			if leaving >= 1.0:
				_hand_back()


func _advance(delta: float) -> float:
	_blend_elapsed += delta
	# Eased, not linear. A linear boundary blend starts and stops with a visible
	# step in velocity, which reads as the camera being snatched rather than
	# handed over.
	return smoothstep(0.0, 1.0, clampf(_blend_elapsed / _blend_time, 0.0, 1.0))


## Position lerps; rotation slerps through a quaternion.
##
## Basis.lerp is the obvious thing and it is wrong: interpolating nine components
## independently shears through the midpoint and arrives non-orthonormal, so a
## half-turn blend passes through a squashed frustum on the way. Both ends are
## orthonormalized first because a Basis carrying any scale at all makes
## Quaternion() throw.
func _mix(from: Transform3D, to: Transform3D, weight: float) -> Transform3D:
	var turn := Quaternion(from.basis.orthonormalized()).slerp(
		Quaternion(to.basis.orthonormalized()), weight
	)
	return Transform3D(Basis(turn), from.origin.lerp(to.origin, weight))


## The anchor's pose, plus the rumble.
##
## FULL takes both position and rotation from the anchor; ANCHORED keeps the
## player's own look direction. One mechanism, one authored track, two
## behaviours - which is why the animation drives an anchor and never the camera.
func _anchor_pose() -> Transform3D:
	var pose := _anchor.global_transform
	if _authority == Authority.ANCHORED:
		pose.basis = _gameplay_camera.global_basis

	var amplitude := rumble_amplitude * _rumble_gain
	if amplitude > 0.0:
		# Applied AFTER the anchor is read, so it never fights the keyframes, and
		# in camera space, so the shake is always across frame rather than along
		# whatever axis the shot happens to face.
		#
		# The axis ratio is deliberately not a round number: at 1.0 or 2.0 the two
		# sines phase-lock and the shake collapses into a diagonal line.
		var rate := rumble_frequency
		var shake := Vector3(
			sin(_rumble_clock * rate),
			sin(_rumble_clock * rate * ElevatorCutsceneKnobs.RUMBLE_AXIS_RATIO + 1.7),
			0.0
		)
		pose.origin += pose.basis * shake * amplitude
	return pose


func _hand_back() -> void:
	_phase = Phase.IDLE
	_anchor = null
	# Order matters. Handing `current` to the gameplay camera first means the
	# viewport is never, even for an instant, without one - clearing ours first
	# would leave Godot to pick a replacement on its own.
	_gameplay_camera.current = true
	current = false
	control_released.emit()
