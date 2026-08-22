extends SceneTree

## Builds the elevator intro clip, its RESET clip, and the library that holds
## both.
##
##     "D:/Godot_v4.7.1-stable_win64.exe" --headless --path <root> \
##       --script res://levels/asteroid_level/intro/tools/build_elevator_intro_animation.gd
##
## Safe as a bare `--script` rather than a scene: this only touches files, so the
## "nodes added during _initialize() never get _ready()" trap does not apply.
##
## RE-RUNNING THIS OVERWRITES WHATEVER THE ANIMATION DOCK SAVED. That is the trade
## for timings that live in elevator_cutscene_knobs.gd next to everything else:
## change a number, run one command, see it. Once the director starts tweaking in
## the dock, stop running this and let the .tres be the source of truth - or move
## the number that keeps changing into the knobs file so both stay true.
##
## The output is an ordinary external .anim.tres. The dock opens it, scrubs it and
## edits it like any hand-authored clip; this script generates a starting point,
## not a runtime dependency.
##
## EVERY PATH BELOW IS RELATIVE TO THE LEVEL ROOT, because that is what
## AnimationPlayer.root_node points at. A path relative to the CutscenePlayer
## resolves to nothing, silently.

const ANIM_PATH := "res://levels/asteroid_level/intro/animations/elevator_intro.anim.tres"
const RESET_PATH := "res://levels/asteroid_level/intro/animations/elevator_intro_reset.anim.tres"
const LIBRARY_PATH := "res://levels/asteroid_level/intro/animations/elevator_intro_library.tres"

const GESTURE_LIBRARY_PATH := "res://levels/asteroid_level/intro/animations/miner_gesture_library.tres"
const GESTURE_CLIP_PATH := "res://levels/asteroid_level/intro/animations/miner_helmet_gesture.anim.tres"

## The character, read at build time so the gesture starts from the pose the idle
## loop is actually in rather than from the bind rest.
const CHARACTER_SCENE := "res://assets/art/character/sk_player_character.tscn"
const SKELETON_PATH := "player_character_armature/Skeleton3D"
const HELMET_MESH := "player_character_helmet"
const BONE_UPPER := "RightUpperArm"
const BONE_LOWER := "RightLowerArm"
const BONE_TIP := "RightHand"

## THE LEFT ARM PRESSES. The mining laser is bone-attached to RightHand, and a
## 1.14 m cutter swinging through a first-person shot is the exact problem
## MinerB's left-handed grip exists to dodge. The left hand is empty.
const PRESS_UPPER := "LeftUpperArm"
const PRESS_LOWER := "LeftLowerArm"
const PRESS_TIP := "LeftHand"

const PRESS_LIBRARY_PATH := "res://levels/asteroid_level/intro/animations/player_gesture_library.tres"
const PRESS_CLIP_PATH := "res://levels/asteroid_level/intro/animations/player_door_press.anim.tres"

const ANCHOR := "Cutscenes/ElevatorIntro/CameraAnchor"
const DOOR_LEFT := "ElevatorCar/Doors/DoorLeft"
const DOOR_RIGHT := "ElevatorCar/Doors/DoorRight"

## The gesture is ONE FLOAT ON AN AnimationTree, not two bone tracks here.
##
## The miner's own AnimationTree is the only mixer that touches its skeleton -
## the idle loop runs on it all nineteen seconds. If this clip also wrote those
## bones, two mixers would be writing the same pose and which one won would
## depend on process order, which skip() does not honour: it applies its seek out
## of band, on its own frame. Keying the blend weight instead means the arm is
## driven by exactly one thing at all times, and a skip lands it at weight 0 -
## arm down, still breathing - by the same mechanism as every other track here.
##
## THE LAYER IS A HELD POSE, SO THIS WEIGHT IS THE WHOLE GESTURE. An animated
## layer would have its own clock, and an AnimationTree layer advances in real
## time rather than with the master playhead - so a director scrubbing to 9 s, or
## capture_shots seeking there and pausing, would see the arm wherever that
## second clock happened to be rather than mid-reach. One clock, one curve.
const GESTURE_BLEND := "Miners/MinerB/Rig/AnimationTree:parameters/blend/blend_amount"
const VISOR := "Miners/MinerB:visor_energy"

## The player's arm, through a proxy INSIDE the cutscene rather than a path that
## walks out to Players/Player - which is not in this scene at author time and
## would resolve to nothing, silently, at run time. See player_gesture_proxy.gd.
const PRESS_BLEND := "Cutscenes/ElevatorIntro/Gesture:press_blend"

const HUD_BOOT := "HudBoot:power_on"
const TITLE := "Hud/Title:modulate"
const STROBE := "ElevatorCar/WarningStrobe:light_energy"
const SCREEN_POWER := "ElevatorCar/QuotaScreen:power_on"
const MONITOR_SHOT := "Hud/MonitorShot:shot_alpha"

## How many keys the eased dolly is baked into.
##
## THE CAMERA TRACKS ARE LINEAR, NOT CUBIC, and this is the consequence. Cubic
## would give the push-in its ease for free, but the clip contains two hard cuts -
## and a hard cut is two keys one frame apart with completely different values.
## Cubic derives each key's tangent from its neighbours, so a one-frame segment
## either side of a three-metre jump produces an enormous tangent that bleeds
## backwards into the five seconds of *static* wide shot before it, drifting a
## locked-off camera. Linear cannot do that, and the ease is baked instead.
const DOLLY_STEPS := 10


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ANIM_PATH.get_base_dir())

	var intro := _build_intro()
	var reset := _build_reset()
	_write(intro, ANIM_PATH)
	_write(reset, RESET_PATH)

	var library := AnimationLibrary.new()
	# Loaded back off disk rather than held from above: a resource with no
	# resource_path serialises INLINE into the library, and the whole point of an
	# external .anim.tres is that the Animation Dock can open it as its own file.
	library.add_animation(&"elevator_intro", ResourceLoader.load(ANIM_PATH))
	library.add_animation(&"RESET", ResourceLoader.load(RESET_PATH))
	_write(library, LIBRARY_PATH)

	_build_gesture_library()
	_build_press_library()

	print("built elevator_intro: %.1fs, %d tracks" % [intro.length, intro.get_track_count()])
	quit()


## The arm-to-helmet clip the miners' AnimationTree blends over its idle loop.
##
## Two bone tracks, solved onto a target rather than dialled in as Euler angles.
## Safe from a bare --script: bone rests and animation keys are stored data, so
## none of this needs the scene to have run _ready().
func _build_gesture_library() -> void:
	var scene: PackedScene = ResourceLoader.load(CHARACTER_SCENE)
	var character := scene.instantiate()
	var skeleton: Skeleton3D = character.find_child("Skeleton3D", true, false)
	var player: AnimationPlayer = character.find_child("AnimationPlayer", true, false)
	if skeleton == null or player == null or not player.has_animation("idle_float"):
		printerr("  FAILED gesture: %s has no Skeleton3D + idle_float" % CHARACTER_SCENE)
		character.free()
		return
	var idle := player.get_animation("idle_float")

	var upper := skeleton.find_bone(BONE_UPPER)
	var lower := skeleton.find_bone(BONE_LOWER)
	var tip := skeleton.find_bone(BONE_TIP)
	if upper < 0 or lower < 0 or tip < 0:
		printerr("  FAILED gesture: the rig has no %s chain" % BONE_UPPER)
		character.free()
		return

	var target := _gesture_target(
		character, skeleton, idle, upper, ElevatorIntroKnobs.GESTURE_HAND_OFFSET
	)
	var raised := _solve_two_bone(
		skeleton, idle, upper, lower, tip, target, ElevatorIntroKnobs.GESTURE_ELBOW_POLE
	)
	var rest_upper := _bone_local_pose(skeleton, idle, upper, 0.0).basis.get_rotation_quaternion()
	var rest_lower := _bone_local_pose(skeleton, idle, lower, 0.0).basis.get_rotation_quaternion()

	# ONE POSE, HELD. The reach and the release are the blend weight rising and
	# falling in the master clip; this layer only has to say where the arm goes.
	# rest_upper/rest_lower are sampled from idle_float rather than from the bind
	# rest so the pose the weight blends away from is the pose the arm is in.
	var anim := Animation.new()
	anim.length = ElevatorIntroKnobs.ANIMATION_STEP
	anim.loop_mode = Animation.LOOP_NONE
	anim.step = ElevatorIntroKnobs.ANIMATION_STEP

	var pairs := [[BONE_UPPER, rest_upper, raised[0]], [BONE_LOWER, rest_lower, raised[1]]]
	for pair: Array in pairs:
		var track := _add_transform_track(
			anim, Animation.TYPE_ROTATION_3D, "%s:%s" % [SKELETON_PATH, pair[0]]
		)
		anim.rotation_track_insert_key(track, 0.0, pair[2])
		anim.rotation_track_insert_key(track, anim.length, pair[2])

	_write(anim, GESTURE_CLIP_PATH)
	var library := AnimationLibrary.new()
	library.add_animation(&"helmet_gesture", ResourceLoader.load(GESTURE_CLIP_PATH))
	_write(library, GESTURE_LIBRARY_PATH)

	var shoulder := _bone_global_pose(skeleton, idle, upper, 0.0).origin
	print(
		(
			"  gesture: hand at %v, %.3f m from a %.3f m arm"
			% [target, target.distance_to(shoulder), _arm_length(skeleton, lower, tip)]
		)
	)
	character.free()


## The player's hand on the call panel, built exactly like the miner's gesture.
##
## ONE POSE, HELD, blended in and out by PRESS_BLEND. The player's own
## AnimationTree runs their idle and their laser states all game; a clip here that
## wrote those bones would be a second mixer on the same skeleton, and which one
## won would depend on process order - which skip() does not honour.
func _build_press_library() -> void:
	var scene: PackedScene = ResourceLoader.load(CHARACTER_SCENE)
	var character := scene.instantiate()
	var skeleton: Skeleton3D = character.find_child("Skeleton3D", true, false)
	var player: AnimationPlayer = character.find_child("AnimationPlayer", true, false)
	if skeleton == null or player == null or not player.has_animation("idle_float"):
		printerr("  FAILED press: %s has no Skeleton3D + idle_float" % CHARACTER_SCENE)
		character.free()
		return
	var idle := player.get_animation("idle_float")

	var upper := skeleton.find_bone(PRESS_UPPER)
	var lower := skeleton.find_bone(PRESS_LOWER)
	var tip := skeleton.find_bone(PRESS_TIP)
	if upper < 0 or lower < 0 or tip < 0:
		printerr("  FAILED press: the rig has no %s chain" % PRESS_UPPER)
		character.free()
		return

	var target := _gesture_target(
		character, skeleton, idle, upper, ElevatorIntroKnobs.PRESS_HAND_OFFSET
	)
	var pressed := _solve_two_bone(
		skeleton, idle, upper, lower, tip, target, ElevatorIntroKnobs.PRESS_ELBOW_POLE
	)

	var anim := Animation.new()
	anim.length = ElevatorIntroKnobs.ANIMATION_STEP
	anim.loop_mode = Animation.LOOP_NONE
	anim.step = ElevatorIntroKnobs.ANIMATION_STEP
	for pair: Array in [[PRESS_UPPER, pressed[0]], [PRESS_LOWER, pressed[1]]]:
		var track := _add_transform_track(
			anim, Animation.TYPE_ROTATION_3D, "%s:%s" % [SKELETON_PATH, pair[0]]
		)
		anim.rotation_track_insert_key(track, 0.0, pair[1])
		anim.rotation_track_insert_key(track, anim.length, pair[1])

	_write(anim, PRESS_CLIP_PATH)
	var library := AnimationLibrary.new()
	library.add_animation(&"door_press", ResourceLoader.load(PRESS_CLIP_PATH))
	_write(library, PRESS_LIBRARY_PATH)

	var shoulder := _bone_global_pose(skeleton, idle, upper, 0.0).origin
	print(
		(
			"  press: hand at %v, %.3f m from a %.3f m arm"
			% [target, target.distance_to(shoulder), _arm_length(skeleton, lower, tip)]
		)
	)
	character.free()


func _arm_length(skeleton: Skeleton3D, lower: int, tip: int) -> float:
	return (
		skeleton.get_bone_rest(lower).origin.length() + skeleton.get_bone_rest(tip).origin.length()
	)


## Where the hand goes, in the character's own space.
##
## Measured off the helmet MESH rather than the Head bone, because the knob is
## written as an offset from the visor a viewer can see and the bone sits well
## below it.
func _gesture_target(
	character: Node, skeleton: Skeleton3D, idle: Animation, upper: int, offset: Vector3
) -> Vector3:
	var helmet: MeshInstance3D = character.find_child(HELMET_MESH, true, false)
	var centre := Vector3(0.0, 1.32, 0.0)
	if helmet == null:
		push_warning("no %s mesh; falling back to a hard-coded helmet centre" % HELMET_MESH)
	else:
		centre = helmet.get_aabb().get_center()
	var outward := signf(_bone_global_pose(skeleton, idle, upper, 0.0).origin.x)
	return centre + Vector3(outward * offset.x, offset.y, offset.z)


## Two-bone IK, returning the two BONE-LOCAL rotations that put the tip on target.
##
## Each joint keeps the twist it has in the idle pose and only its aim changes, so
## the solved arm still belongs to the animation the rest of the body is playing.
func _solve_two_bone(
	skeleton: Skeleton3D,
	idle: Animation,
	upper: int,
	lower: int,
	tip: int,
	target: Vector3,
	elbow_pole: Vector3
) -> Array:
	var parent := skeleton.get_bone_parent(upper)
	var parent_global := Transform3D()
	if parent >= 0:
		parent_global = _bone_global_pose(skeleton, idle, parent, 0.0)
	var lower_local := _bone_local_pose(skeleton, idle, lower, 0.0)
	var upper_global := parent_global * _bone_local_pose(skeleton, idle, upper, 0.0)
	var shoulder := upper_global.origin

	var upper_length := skeleton.get_bone_rest(lower).origin.length()
	var lower_length := skeleton.get_bone_rest(tip).origin.length()
	var to_target := target - shoulder
	var reach := clampf(
		to_target.length(),
		absf(upper_length - lower_length) + 0.001,
		upper_length + lower_length - 0.001
	)
	var aim := to_target.normalized()

	# Law of cosines: how far off the shoulder-to-hand line the elbow sits.
	var cosine := upper_length * upper_length + reach * reach - lower_length * lower_length
	cosine = clampf(cosine / (2.0 * upper_length * reach), -1.0, 1.0)
	var pole := Vector3(signf(shoulder.x) * elbow_pole.x, elbow_pole.y, elbow_pole.z)
	var side := pole - aim * pole.dot(aim)
	if side.length() < 0.0001:
		side = Vector3.UP - aim * aim.dot(Vector3.UP)
	side = side.normalized()
	var elbow_aim := (aim * cosine + side * sqrt(1.0 - cosine * cosine)).normalized()
	var elbow := shoulder + elbow_aim * upper_length

	# Rotate each bone from the aim it has now onto the aim it needs, which keeps
	# its twist. A bone's own axis is the direction of its child's rest offset.
	var upper_rotation := _aim_onto(
		upper_global.basis, skeleton.get_bone_rest(lower).origin.normalized(), elbow_aim
	)
	var lower_basis := Basis(upper_rotation) * lower_local.basis
	var lower_rotation := _aim_onto(
		lower_basis,
		skeleton.get_bone_rest(tip).origin.normalized(),
		(shoulder + aim * reach - elbow).normalized()
	)
	var parent_rotation := parent_global.basis.get_rotation_quaternion()
	return [
		parent_rotation.inverse() * upper_rotation,
		upper_rotation.inverse() * lower_rotation,
	]


func _aim_onto(basis: Basis, axis: Vector3, wanted: Vector3) -> Quaternion:
	var current := (basis * axis).normalized()
	return Quaternion(current, wanted) * basis.get_rotation_quaternion()


## A bone's own transform at a time in a clip, falling back to its rest for any
## component that clip does not animate.
func _bone_local_pose(skeleton: Skeleton3D, anim: Animation, bone: int, time: float) -> Transform3D:
	var rest := skeleton.get_bone_rest(bone)
	var path := NodePath("%s:%s" % [SKELETON_PATH, skeleton.get_bone_name(bone)])
	var origin := rest.origin
	var rotation := rest.basis.get_rotation_quaternion()
	var scale := rest.basis.get_scale()
	var position_track := anim.find_track(path, Animation.TYPE_POSITION_3D)
	if position_track >= 0:
		origin = anim.position_track_interpolate(position_track, time)
	var rotation_track := anim.find_track(path, Animation.TYPE_ROTATION_3D)
	if rotation_track >= 0:
		rotation = anim.rotation_track_interpolate(rotation_track, time)
	var scale_track := anim.find_track(path, Animation.TYPE_SCALE_3D)
	if scale_track >= 0:
		scale = anim.scale_track_interpolate(scale_track, time)
	return Transform3D(Basis(rotation).scaled(scale), origin)


func _bone_global_pose(
	skeleton: Skeleton3D, anim: Animation, bone: int, time: float
) -> Transform3D:
	var pose := _bone_local_pose(skeleton, anim, bone, time)
	var parent := skeleton.get_bone_parent(bone)
	if parent < 0:
		return pose
	return _bone_global_pose(skeleton, anim, parent, time) * pose


func _build_intro() -> Animation:
	var anim := Animation.new()
	# NOT OPTIONAL. Animation.length defaults to 1.0 and silently TRUNCATES every
	# track past it - the clip just ends one second in and the doors never open,
	# with no error anywhere. Set before anything else.
	anim.length = ElevatorIntroKnobs.CUTSCENE_LENGTH
	anim.loop_mode = Animation.LOOP_NONE
	anim.step = ElevatorIntroKnobs.ANIMATION_STEP

	_build_camera(anim)
	_build_monitor_shot(anim)
	_build_doors(anim)
	_build_gesture(anim)
	_build_press(anim)
	_build_hud(anim)
	_build_car(anim)
	return anim


## Nose-on the screen, pull back to the wide, hard cut, eased dolly, hard cut to
## the eye.
func _build_camera(anim: Animation) -> void:
	var position_track := _add_transform_track(anim, Animation.TYPE_POSITION_3D, ANCHOR)
	var rotation_track := _add_transform_track(anim, Animation.TYPE_ROTATION_3D, ANCHOR)

	var step := ElevatorIntroKnobs.ANIMATION_STEP
	var prologue := ElevatorIntroKnobs.PROLOGUE_LENGTH
	var reveal := ElevatorIntroKnobs.PROLOGUE_END
	var cut := ElevatorIntroKnobs.SHOT2_CUT_TIME
	var dolly_end := cut + ElevatorIntroKnobs.SHOT2_PUSH_IN_DURATION
	var match_cut := ElevatorIntroKnobs.MATCH_CUT_TIME

	# Shot 0: parked on the glass and held, under a full-screen 2D copy of the same
	# readout. The cut at `prologue` is the OVERLAY leaving, not the camera moving -
	# this pose is already what is behind it, which is the whole trick.
	_key_pose(
		anim,
		position_track,
		rotation_track,
		0.0,
		ElevatorIntroKnobs.CLOSEUP_POSITION,
		ElevatorIntroKnobs.CLOSEUP_TARGET
	)
	_key_pose(
		anim,
		position_track,
		rotation_track,
		prologue,
		ElevatorIntroKnobs.CLOSEUP_POSITION,
		ElevatorIntroKnobs.CLOSEUP_TARGET
	)

	# The pull-back that reveals the car, eased across the same keys as every other
	# move here and for the same reason: the tracks are linear and cannot ease
	# themselves.
	for index in DOLLY_STEPS + 1:
		var fraction := float(index) / float(DOLLY_STEPS)
		var eased := smoothstep(0.0, 1.0, fraction)
		_key_pose(
			anim,
			position_track,
			rotation_track,
			lerpf(prologue, reveal, fraction),
			ElevatorIntroKnobs.CLOSEUP_POSITION.lerp(ElevatorIntroKnobs.SHOT1_POSITION, eased),
			ElevatorIntroKnobs.CLOSEUP_TARGET.lerp(ElevatorIntroKnobs.SHOT1_TARGET, eased)
		)

	# Shot 1: locked off. Two keys with the same value is what "held" means on a
	# linear track; the rumble is added by the camera driver afterwards and is
	# deliberately not keyframed.
	_key_pose(
		anim,
		position_track,
		rotation_track,
		reveal,
		ElevatorIntroKnobs.SHOT1_POSITION,
		ElevatorIntroKnobs.SHOT1_TARGET
	)
	_key_pose(
		anim,
		position_track,
		rotation_track,
		cut - step,
		ElevatorIntroKnobs.SHOT1_POSITION,
		ElevatorIntroKnobs.SHOT1_TARGET
	)

	# The cut, and then the push-in, eased across DOLLY_STEPS keys.
	for index in DOLLY_STEPS + 1:
		var fraction := float(index) / float(DOLLY_STEPS)
		var eased := smoothstep(0.0, 1.0, fraction)
		_key_pose(
			anim,
			position_track,
			rotation_track,
			lerpf(cut, dolly_end, fraction),
			ElevatorIntroKnobs.SHOT2_START_POSITION.lerp(
				ElevatorIntroKnobs.SHOT2_END_POSITION, eased
			),
			ElevatorIntroKnobs.SHOT2_START_TARGET.lerp(ElevatorIntroKnobs.SHOT2_END_TARGET, eased)
		)

	# Hold on the close, then the match cut to the player's own eye.
	_key_pose(
		anim,
		position_track,
		rotation_track,
		match_cut - step,
		ElevatorIntroKnobs.SHOT2_END_POSITION,
		ElevatorIntroKnobs.SHOT2_END_TARGET
	)
	_key_pose(
		anim,
		position_track,
		rotation_track,
		match_cut,
		ElevatorIntroKnobs.EYE_POSITION,
		ElevatorIntroKnobs.EYE_TARGET
	)
	_build_exit(anim, position_track, rotation_track)


## Out of the car, turn, watch the doors shut, press the panel, and back around.
##
## THE ONLY THING THAT MOVES IS THE ANCHOR. The player's body rides it - see
## ElevatorIntroEffects.advance - so the drift, the turn and the pan are one track
## each rather than a second set of keys on a CharacterBody3D the solver is also
## touching. The turn and the pan hold POSITION and move only the look target,
## which is what keeps a turn from also being a shove.
func _build_exit(anim: Animation, position_track: int, rotation_track: int) -> void:
	var eye := ElevatorIntroKnobs.EYE_POSITION
	var drifted := ElevatorIntroKnobs.DRIFT_POSITION
	var exit := ElevatorIntroKnobs.EXIT_POSITION
	var out := ElevatorIntroKnobs.EXIT_TARGET
	var back := ElevatorIntroKnobs.FACE_CAR_TARGET

	# The dwell. Held on the eye, looking out at what the doors just revealed.
	_key_pose(anim, position_track, rotation_track, ElevatorIntroKnobs.EXIT_DWELL_END, eye, out)

	# The drift. Eased at both ends, because a push-off in zero-G accelerates and
	# a linear track would start at full speed.
	for index in DOLLY_STEPS + 1:
		var fraction := float(index) / float(DOLLY_STEPS)
		var eased := smoothstep(0.0, 1.0, fraction)
		_key_pose(
			anim,
			position_track,
			rotation_track,
			lerpf(ElevatorIntroKnobs.EXIT_DWELL_END, ElevatorIntroKnobs.DRIFT_END, fraction),
			eye.lerp(drifted, eased),
			out.lerp(drifted + (out - drifted).normalized() * 6.0, eased)
		)

	# The turn, which is also a short sidle across to the panel. Both at once
	# rather than one after the other: a drift that stopped, turned, then slid
	# sideways would read as three separate instructions being carried out.
	for index in DOLLY_STEPS + 1:
		var fraction := float(index) / float(DOLLY_STEPS)
		var eased := smoothstep(0.0, 1.0, fraction)
		var eye_now := drifted.lerp(exit, eased)
		_key_pose(
			anim,
			position_track,
			rotation_track,
			lerpf(ElevatorIntroKnobs.DRIFT_END, ElevatorIntroKnobs.TURN_END, fraction),
			eye_now,
			_turn_target(eye_now, out, back, eased)
		)

	# Held on the car while the doors shut.
	_key_pose(anim, position_track, rotation_track, ElevatorIntroKnobs.PRESS_START, exit, back)

	# Then down at the panel for the press, and back up once the hand is clear.
	var panel := ElevatorIntroKnobs.PRESS_AIM
	_key_ramp_pose(
		anim,
		position_track,
		rotation_track,
		ElevatorIntroKnobs.PRESS_START,
		ElevatorIntroKnobs.PRESS_CONTACT,
		exit,
		back,
		panel
	)
	_key_pose(anim, position_track, rotation_track, ElevatorIntroKnobs.PRESS_END, exit, panel)
	_key_ramp_pose(
		anim,
		position_track,
		rotation_track,
		ElevatorIntroKnobs.PRESS_END,
		ElevatorIntroKnobs.PAN_START,
		exit,
		panel,
		back
	)

	# And back around onto the mine, which is where control is handed over.
	for index in DOLLY_STEPS + 1:
		var fraction := float(index) / float(DOLLY_STEPS)
		var eased := smoothstep(0.0, 1.0, fraction)
		_key_pose(
			anim,
			position_track,
			rotation_track,
			lerpf(ElevatorIntroKnobs.PAN_START, ElevatorIntroKnobs.CUTSCENE_LENGTH, fraction),
			exit,
			_turn_target(exit, back, out, eased)
		)


## An eased swing of the look target with the eye held still.
func _key_ramp_pose(
	anim: Animation,
	position_track: int,
	rotation_track: int,
	from: float,
	to: float,
	eye: Vector3,
	start: Vector3,
	finish: Vector3
) -> void:
	for index in DOLLY_STEPS + 1:
		var fraction := float(index) / float(DOLLY_STEPS)
		_key_pose(
			anim,
			position_track,
			rotation_track,
			lerpf(from, to, fraction),
			eye,
			_turn_target(eye, start, finish, smoothstep(0.0, 1.0, fraction))
		)


## A look target swung around the eye rather than lerped through it.
##
## A STRAIGHT LERP BETWEEN TWO TARGETS PASSES THROUGH THE CAMERA. Half way between
## "nine metres that way" and "a metre this way" is a point behind the lens, and
## looking_at a point behind the lens flips the shot inside out for a frame. Both
## ends are normalised onto a fixed radius and the direction is slerped, so the
## turn is a turn.
func _turn_target(eye: Vector3, from: Vector3, to: Vector3, weight: float) -> Vector3:
	var radius := 4.0
	var start := (from - eye).normalized()
	var finish := (to - eye).normalized()
	var swung := Quaternion(start, finish)
	var turned := Quaternion.IDENTITY.slerp(swung, weight) * start
	return eye + turned * radius


## The opening 2D shot, and the hard cut off it.
##
## ONE FLOAT WITH A SETTER, exactly like SCREEN_POWER and VISOR. A `visible` track
## would be seek-safe too, and then two properties would answer "is the monitor
## covering the screen" with only one of them right after a skip.
func _build_monitor_shot(anim: Animation) -> void:
	var shot := _add_value_track(anim, MONITOR_SHOT)
	var cut := ElevatorIntroKnobs.PROLOGUE_LENGTH
	anim.track_insert_key(shot, 0.0, 1.0)
	anim.track_insert_key(shot, cut - ElevatorIntroKnobs.ANIMATION_STEP, 1.0)
	anim.track_insert_key(shot, cut, 0.0)
	anim.track_insert_key(shot, ElevatorIntroKnobs.CUTSCENE_LENGTH, 0.0)


## Open on the arrival, shut again once the player is outside.
##
## THE COLLIDERS ARE NOT HERE. doors_unlocked and doors_locked are timed effects,
## because a skip discards this clip and a level whose doors are visibly shut and
## physically open is the same bug as one whose doors are visibly open and
## physically shut. See elevator_intro_effects.gd.
func _build_doors(anim: Animation) -> void:
	var closed := ElevatorCar.DOOR_CLOSED_X
	var open := closed + ElevatorCar.DOOR_TRAVEL
	var travel := ElevatorIntroKnobs.DOOR_TRAVEL_DURATION
	var opens := ElevatorIntroKnobs.DOORS_OPEN_TIME
	var shuts := ElevatorIntroKnobs.DOORS_CLOSE_TIME

	for side: float in [-1.0, 1.0]:
		var path := DOOR_LEFT if side < 0.0 else DOOR_RIGHT
		var track := _add_transform_track(anim, Animation.TYPE_POSITION_3D, path)
		anim.position_track_insert_key(track, 0.0, Vector3(side * closed, 0.0, 0.0))
		anim.position_track_insert_key(track, opens, Vector3(side * closed, 0.0, 0.0))
		_key_leaf(anim, track, side, opens, opens + travel, closed, open)
		anim.position_track_insert_key(track, shuts, Vector3(side * open, 0.0, 0.0))
		_key_leaf(anim, track, side, shuts, shuts + travel, open, closed)
		anim.position_track_insert_key(
			track, ElevatorIntroKnobs.CUTSCENE_LENGTH, Vector3(side * closed, 0.0, 0.0)
		)


## Eased so the leaves start and stop like something heavy rather than snapping
## into motion at full speed.
func _key_leaf(
	anim: Animation, track: int, side: float, from: float, to: float, low: float, high: float
) -> void:
	for index in DOLLY_STEPS + 1:
		var fraction := float(index) / float(DOLLY_STEPS)
		var eased := smoothstep(0.0, 1.0, fraction)
		anim.position_track_insert_key(
			track, lerpf(from, to, fraction), Vector3(side * lerpf(low, high, eased), 0.0, 0.0)
		)


## The gesture layer fading in and out, and the visor coming online on the hold.
##
## blend_amount is CONTINUOUS - it is a weight and it ramps. seek_request is
## DISCRETE and armed for exactly one animation step, because an AnimationTree
## consumes a seek and resets the property to -1: a continuous track would
## re-arm it every frame and hold the layer pinned at its first frame forever.
func _build_gesture(anim: Animation) -> void:
	var blend := _add_value_track(anim, GESTURE_BLEND)
	var visor := _add_value_track(anim, VISOR)

	var start := ElevatorIntroKnobs.GESTURE_START
	var duration := ElevatorIntroKnobs.GESTURE_DURATION
	var reach := start + duration * 0.3
	var release := start + duration * 0.62

	# Eased, for the same reason the dolly is: a linear weight ramp starts and
	# stops the arm at full speed, which reads as a switch rather than a reach.
	anim.track_insert_key(blend, 0.0, 0.0)
	anim.track_insert_key(blend, start, 0.0)
	_key_ramp(anim, blend, start, reach, 0.0, 1.0)
	anim.track_insert_key(blend, release, 1.0)
	_key_ramp(anim, blend, release, start + duration, 1.0, 0.0)
	anim.track_insert_key(blend, ElevatorIntroKnobs.CUTSCENE_LENGTH, 0.0)

	var idle := MinerRig.VISOR_IDLE_ENERGY
	anim.track_insert_key(visor, 0.0, idle)
	anim.track_insert_key(visor, reach, idle)
	anim.track_insert_key(visor, reach + 0.25, MinerRig.VISOR_LIT_ENERGY)
	anim.track_insert_key(visor, ElevatorIntroKnobs.CUTSCENE_LENGTH, MinerRig.VISOR_LIT_ENERGY)


## The player's hand: up, contact, down. One weight curve, for the reason the
## miner's is one weight curve.
func _build_press(anim: Animation) -> void:
	var press := _add_value_track(anim, PRESS_BLEND)
	var start := ElevatorIntroKnobs.PRESS_START
	var contact := ElevatorIntroKnobs.PRESS_CONTACT
	var end := ElevatorIntroKnobs.PRESS_END

	anim.track_insert_key(press, 0.0, 0.0)
	anim.track_insert_key(press, start, 0.0)
	_key_ramp(anim, press, start, contact, 0.0, 1.0)
	# A beat pressed rather than a bounce off the paddle. Short, because a hand
	# resting on a button that has already said no reads as confusion.
	anim.track_insert_key(press, contact + 0.35, 1.0)
	_key_ramp(anim, press, contact + 0.35, end, 1.0, 0.0)
	anim.track_insert_key(press, ElevatorIntroKnobs.CUTSCENE_LENGTH, 0.0)


func _key_ramp(
	anim: Animation, track: int, from: float, to: float, low: float, high: float
) -> void:
	for index in DOLLY_STEPS + 1:
		var fraction := float(index) / float(DOLLY_STEPS)
		anim.track_insert_key(
			track, lerpf(from, to, fraction), lerpf(low, high, smoothstep(0.0, 1.0, fraction))
		)


## The gameplay HUD's tube striking on the match cut, and the title card.
##
## power_on, NOT modulate. The HUD arrives through the same CRT curve the quota
## terminal wears, so the helmet coming online is a raster opening from a centre
## line rather than an alpha ramp - and it is the same picture-making the film
## opened on, which is the point. One property, one track, one authority: the
## overlay derives its own `visible` from this rather than keeping a second flag.
func _build_hud(anim: Animation) -> void:
	var boot := _add_value_track(anim, HUD_BOOT)
	var title := _add_value_track(anim, TITLE)

	var cut := ElevatorIntroKnobs.MATCH_CUT_TIME
	var settled := ElevatorIntroKnobs.HUD_SETTLED_TIME
	var clear := Color(1.0, 1.0, 1.0, 0.0)
	var solid := Color(1.0, 1.0, 1.0, 1.0)

	anim.track_insert_key(boot, 0.0, 0.0)
	anim.track_insert_key(boot, cut - ElevatorIntroKnobs.ANIMATION_STEP, 0.0)
	_key_ramp(anim, boot, cut, settled, 0.0, 1.0)
	# Zero AFTER the hand-back, not before it: hud_settled reparents the HUD out
	# from behind the glass at `settled`, and a raster still open over an empty
	# SubViewport would be a full-screen smear of nothing.
	anim.track_insert_key(boot, settled + ElevatorIntroKnobs.ANIMATION_STEP, 0.0)
	anim.track_insert_key(boot, ElevatorIntroKnobs.CUTSCENE_LENGTH, 0.0)

	# The title card is a beat, not a state: it is over by the end of the clip
	# whether you watched it or skipped it. Centred on the clunk.
	var hold := ElevatorIntroKnobs.TITLE_HOLD
	var clunk := ElevatorIntroKnobs.CLUNK_TIME
	anim.track_insert_key(title, 0.0, clear)
	anim.track_insert_key(title, clunk - hold * 0.5, clear)
	anim.track_insert_key(title, clunk - hold * 0.25, solid)
	anim.track_insert_key(title, clunk + hold * 0.25, solid)
	anim.track_insert_key(title, clunk + hold * 0.5, clear)
	anim.track_insert_key(title, ElevatorIntroKnobs.CUTSCENE_LENGTH, clear)


## The clunk flash, and the DENIED flicker on the wall screen.
func _build_car(anim: Animation) -> void:
	var strobe := _add_value_track(anim, STROBE)
	var clunk := ElevatorIntroKnobs.CLUNK_TIME
	var peak := ElevatorIntroKnobs.STROBE_PEAK_ENERGY
	anim.track_insert_key(strobe, 0.0, 0.0)
	anim.track_insert_key(strobe, clunk - 0.05, 0.0)
	anim.track_insert_key(strobe, clunk, peak)
	anim.track_insert_key(strobe, clunk + 0.35, 0.0)
	anim.track_insert_key(strobe, clunk + 0.55, peak * 0.5)
	anim.track_insert_key(strobe, clunk + 0.9, 0.0)

	# And the refusal. The strobe is the only thing in the car that can answer a
	# hand on the panel from outside it, and it lands ON the contact frame rather
	# than after it - the light and the voice are the same "no".
	var denied := ElevatorIntroKnobs.PRESS_CONTACT
	anim.track_insert_key(strobe, denied - 0.05, 0.0)
	anim.track_insert_key(strobe, denied, peak)
	anim.track_insert_key(strobe, denied + 0.3, 0.0)
	anim.track_insert_key(strobe, denied + 0.5, peak * 0.6)
	anim.track_insert_key(strobe, denied + 0.8, 0.0)
	anim.track_insert_key(strobe, ElevatorIntroKnobs.CUTSCENE_LENGTH, 0.0)

	# A failing tube rather than a steady one. Three brief brownouts across the
	# descent, which is most of what makes a static screen feel live.
	#
	# THE TUBE, NOT THE WORD. This used to dim AuthValue:modulate on a Label3D. The
	# screen is now one quad whose picture is a SubViewport, so the equivalent beat
	# is the terminal browning out - and it reads better, because the whole readout
	# sags rather than one word changing colour. The gentle DENIED breath underneath
	# is the shader's own, on TIME, and survives a skip without a keyframe.
	var screen := _add_value_track(anim, SCREEN_POWER)
	var lit := 1.0
	var dim := ElevatorIntroKnobs.SCREEN_DROPOUT_LEVEL
	anim.track_insert_key(screen, 0.0, lit)
	for dropout_time: float in ElevatorIntroKnobs.SCREEN_DROPOUT_TIMES:
		anim.track_insert_key(screen, dropout_time, dim)
		anim.track_insert_key(
			screen, dropout_time + ElevatorIntroKnobs.SCREEN_DROPOUT_DURATION, lit
		)
	# One more on the refusal, longer than the rest, so the terminal visibly sags
	# under the word it is already showing.
	anim.track_insert_key(screen, denied, dim)
	anim.track_insert_key(screen, denied + 0.4, lit)
	anim.track_insert_key(screen, ElevatorIntroKnobs.CUTSCENE_LENGTH, lit)


## Every animated property at its scene rest value, in a clip 1 ms long.
##
## This is what lets the director scrub away and put the level back, and the
## Animation Dock looks for it by name. Built from the same constants as the clip
## above, so the two cannot disagree about what "rest" means.
func _build_reset() -> Animation:
	var anim := Animation.new()
	anim.length = 0.001
	anim.loop_mode = Animation.LOOP_NONE

	# SHOT1, NOT the clip's frame-0 CLOSEUP pose. RESET means "what the .tscn
	# authored", the .tscn's CameraAnchor is the wide, and the wide is the pose the
	# editor's Preview toggle is useful sitting at while you are not scrubbing.
	var anchor_position := _add_transform_track(anim, Animation.TYPE_POSITION_3D, ANCHOR)
	anim.position_track_insert_key(anchor_position, 0.0, ElevatorIntroKnobs.SHOT1_POSITION)
	var anchor_rotation := _add_transform_track(anim, Animation.TYPE_ROTATION_3D, ANCHOR)
	anim.rotation_track_insert_key(
		anchor_rotation,
		0.0,
		_look_quaternion(ElevatorIntroKnobs.SHOT1_POSITION, ElevatorIntroKnobs.SHOT1_TARGET)
	)

	var closed := ElevatorCar.DOOR_CLOSED_X
	for side: float in [-1.0, 1.0]:
		var path := DOOR_LEFT if side < 0.0 else DOOR_RIGHT
		var track := _add_transform_track(anim, Animation.TYPE_POSITION_3D, path)
		anim.position_track_insert_key(track, 0.0, Vector3(side * closed, 0.0, 0.0))

	anim.track_insert_key(_add_value_track(anim, GESTURE_BLEND), 0.0, 0.0)
	anim.track_insert_key(_add_value_track(anim, PRESS_BLEND), 0.0, 0.0)
	anim.track_insert_key(_add_value_track(anim, VISOR), 0.0, MinerRig.VISOR_IDLE_ENERGY)
	anim.track_insert_key(_add_value_track(anim, HUD_BOOT), 0.0, 0.0)
	anim.track_insert_key(_add_value_track(anim, TITLE), 0.0, Color(1.0, 1.0, 1.0, 0.0))
	anim.track_insert_key(_add_value_track(anim, STROBE), 0.0, 0.0)
	anim.track_insert_key(_add_value_track(anim, SCREEN_POWER), 0.0, 1.0)
	anim.track_insert_key(_add_value_track(anim, MONITOR_SHOT), 0.0, 0.0)
	return anim


## A 3D transform track takes a BARE node path - no ":position" suffix. Value
## tracks take the property. A transform path carrying one resolves to nothing.
func _add_transform_track(anim: Animation, type: Animation.TrackType, path: String) -> int:
	var track := anim.add_track(type)
	anim.track_set_path(track, NodePath(path))
	anim.track_set_interpolation_type(track, Animation.INTERPOLATION_LINEAR)
	return track


func _add_value_track(anim: Animation, path: String) -> int:
	var track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(track, NodePath(path))
	anim.track_set_interpolation_type(track, Animation.INTERPOLATION_LINEAR)
	anim.value_track_set_update_mode(track, Animation.UPDATE_CONTINUOUS)
	return track


func _key_pose(
	anim: Animation,
	position_track: int,
	rotation_track: int,
	time: float,
	position: Vector3,
	target: Vector3
) -> void:
	anim.position_track_insert_key(position_track, time, position)
	anim.rotation_track_insert_key(rotation_track, time, _look_quaternion(position, target))


## Camera poses are authored as position + look-at target rather than as Euler
## angles: a target is something you can reason about, an Euler triple is
## something you arrive at by trial and error and cannot review in a diff.
func _look_quaternion(from: Vector3, target: Vector3) -> Quaternion:
	return Quaternion(Basis.looking_at(target - from, Vector3.UP).orthonormalized())


func _write(resource: Resource, path: String) -> void:
	var error := ResourceSaver.save(resource, path)
	if error != OK:
		printerr("  FAILED %s: %s" % [path, error_string(error)])
		return
	print("  wrote %s" % path)
