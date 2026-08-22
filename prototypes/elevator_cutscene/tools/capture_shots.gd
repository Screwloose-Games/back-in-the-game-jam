extends Node

## Renders the cutscene at chosen times so the shots can be LOOKED AT rather than
## asserted.
##
## Worth its keep, and not a nice-to-have. Every geometry assertion in
## verify_elevator_cutscene.gd passed against a first draft in which the wide shot
## was a miner's head filling the frame, the player's eye was inside a helmet, the
## shot 2 camera was pointed at the back of the subject's head, and a third miner
## stood between the lens and the arm the shot exists to show. None of that is
## reachable by a check; all of it is obvious in a PNG.
##
##     "D:/Godot_v4.7.1-stable_win64.exe" --path <root> --resolution 1280x720 \
##       res://prototypes/elevator_cutscene/tools/capture_shots.tscn
##
## Seeks the clip rather than playing it in real time, so a frame is captured at
## exactly the authored time and the run takes a second instead of nineteen. The
## camera is driven the same way the cutscene drives it - request_control on the
## anchor - so what is captured is what the seam produces, not a hand-placed
## camera that happens to agree with it.

const PROTOTYPE_SCENE := "res://prototypes/elevator_cutscene/elevator_cutscene_prototype.tscn"
const OUT_DIR := "user://shots"

## Warm-up frames. CSGCombiner3D raises its geometry in its own _ready and the
## shaft column is built in one too, so a capture on frame one photographs an
## empty room.
const WARMUP_FRAMES := 12

## What each sample is meant to show, so a bad frame names its own beat.
##
## THE PAIR EITHER SIDE OF 3.0 IS THE POINT OF THIS FILE NOW. The prologue cuts
## from a full-screen 2D copy of the readout to the 3D plate at a matched frame,
## and nothing except diffing those two PNGs can say whether it matches - the
## tonemap and the glow apply to one side and not the other, which is a difference
## no assertion in verify_elevator_cutscene.gd can see.
const SAMPLES := [
	[1.5, "t01.5_prologue_monitor"],
	[2.9, "t02.9_prologue_last"],
	[3.0, "t03.0_closeup_after_cut"],
	[4.5, "t04.5_pullback"],
	[7.0, "t07.0_shot1_wide"],
	[11.0, "t11.0_shot1_late"],
	[12.0, "t12.0_shot2_cut"],
	[12.5, "t12.5_before_gesture"],
	[14.5, "t14.5_gesture_reach"],
	[15.5, "t15.5_visor_lit"],
	[17.0, "t17.0_shot2_close"],
	[18.1, "t18.1_match_cut_hud"],
	[20.5, "t20.5_clunk_title"],
	[22.5, "t22.5_doors_opening"],
	[24.4, "t24.4_doors_open"],
	[25.0, "t25.0_dwell_on_the_mine"],
	[27.5, "t27.5_drifting_out"],
	[30.0, "t30.0_outside_before_turn"],
	[31.0, "t31.0_mid_turn"],
	[32.0, "t32.0_facing_the_car"],
	[33.5, "t33.5_doors_closing"],
	[34.9, "t34.9_doors_shut"],
	[35.6, "t35.6_hand_rising"],
	[36.0, "t36.0_contact_denied"],
	[37.0, "t37.0_hand_down"],
	[41.0, "t41.0_panning_back"],
	[41.9, "t41.9_control"],
]


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var prototype: Node3D = load(PROTOTYPE_SCENE).instantiate()
	var settings: ElevatorCutsceneSettings = prototype.settings.duplicate()
	settings.autoplay_on_start = false
	prototype.settings = settings
	add_child(prototype)

	var intro: ElevatorIntro = prototype.get_node("Intro")
	var animation_player: AnimationPlayer = intro.get_node(
		"Cutscenes/ElevatorIntro/AnimationPlayer"
	)
	var anchor: Node3D = intro.get_node("Cutscenes/ElevatorIntro/CameraAnchor")
	var driver: CutsceneCameraDriver = intro.get_node("CutsceneCamera")
	var car: ElevatorCar = intro.get_node("ElevatorCar")

	car.set_shaft_running(true)
	# The overlay is a third of the frame and none of it is the shot. Reviewing
	# composition through the tuning panel is how you talk yourself into a framing
	# that is actually blocked. The HUD stays - it IS part of shot 3 onward.
	prototype.get_node("Tuning").visible = false
	intro.get_node("Hud/Readout").visible = false
	intro.get_node("Hud/SkipPrompt").visible = false
	# MonitorShot and HudBoot are deliberately NOT in that list. They are the
	# opening shot and the HUD striking, not overlay, and hiding either would
	# capture the thing it is covering.

	for _index in WARMUP_FRAMES:
		await get_tree().process_frame

	# The exit sequence renders from the PLAYER'S OWN RIG, not from the camera:
	# the suit has to be drawn and standing where the anchor is, or every frame
	# after the match cut is a shot of an empty tunnel. This is what
	# ElevatorIntroEffects does at hud_online; the capture is not running the
	# effects list, so it does it here.
	var rig: CutscenePlayerRig = prototype.get_node("CutsceneRig")
	rig.set_avatar_hidden(false)
	rig.set_tool_visible(false)
	# And hud_settled, which hands the HUD back out from behind the boot glass.
	# Without it every frame past HUD_SETTLED_TIME has no HUD at all: power_on is
	# keyed to zero there, and the HUD is still inside the SubViewport.
	intro.get_effects().apply(&"hud_settled", 0.0)

	driver.request_control(anchor, CutsceneCameraDriver.Authority.FULL, 0.0)
	# Zero, so a still frame is not blurred by a shake that only reads in motion.
	driver.set_rumble_gain(0.0)

	for sample: Array in SAMPLES:
		animation_player.play(&"elevator_intro")
		animation_player.seek(sample[0], true, true)
		animation_player.pause()
		await get_tree().process_frame
		# The driver reads the anchor in its own tick, which the seek has just
		# moved. One call rather than waiting for the engine to schedule it.
		driver.advance(0.0)
		# And the body follows the anchor from the match cut on, the same way the
		# effects list carries it at run time.
		if sample[0] >= ElevatorIntroKnobs.MATCH_CUT_TIME:
			rig.global_transform = anchor.global_transform
		await _capture(sample[1])

	# Where the limbs actually end up at the gesture peak.
	#
	# Kept because it is what settled the gesture. Reasoning about Euler order and
	# rotation sign from a close-up screenshot is guesswork - the arm looked flung
	# out sideways when in fact the hand was already inside the helmet's radius and
	# it was the foreshortening reading badly. Four printed positions answered in
	# one run what three re-renders had not.
	animation_player.play(&"elevator_intro")
	animation_player.seek(ElevatorIntroKnobs.GESTURE_START + 1.0, true, true)
	animation_player.pause()
	await get_tree().process_frame
	await get_tree().process_frame
	var miner: MinerRig = intro.get_node("Miners/MinerB")
	var skeleton := miner.get_skeleton()
	print("gesture pose, local to MinerB (blend %.2f):" % miner.get_gesture_blend())
	var helmet_y := 0.0
	for bone_name: String in ["Head", "RightUpperArm", "RightLowerArm", "RightHand"]:
		var bone := skeleton.find_bone(bone_name)
		var pose := skeleton.global_transform * skeleton.get_bone_global_pose(bone)
		var local: Vector3 = miner.global_transform.affine_inverse() * pose.origin
		print("  %-16s %v" % [bone_name, local])
		if bone_name == "Head":
			helmet_y = local.y
	var wrist := (
		skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("RightHand"))
	)
	var head := (
		skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("Head"))
	)
	# The number the target is tuned against: a hand that stops short of the
	# helmet reads as reaching for it, not as pressing something on it.
	print("  wrist to head    %.3f m" % wrist.origin.distance_to(head.origin))

	print("wrote shots to %s" % ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit()


func _capture(shot_name: String) -> void:
	# Two frames then frame_post_draw: the transform lands in one, is drawn in the
	# next, and the texture is only readable once the draw has finished.
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("%s/%s.png" % [OUT_DIR, shot_name])
	print("  captured %s" % shot_name)
