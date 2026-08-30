extends Node

## Headless checks for the elevator cutscene prototype. Run it as:
##
##     godot --headless --path <root> \
##       res://levels/asteroid_level/intro/verify_elevator_intro.tscn
##
## As a SCENE named on the command line, not as `--script` and not bare. Nodes
## added during SceneTree._initialize() never receive _ready(), and this
## instantiates the whole prototype, so a bare script harness would print nothing
## and exit 0 - which is indistinguishable from a pass. run/main_scene is the main
## menu, so naming the scene is not optional either.
##
## [camera] is the check this file was started for. Godot gives `current` to
## whichever Camera3D readies last, and this scene has three of them. The failure
## is not a crash: it is the wrong shot, or no shot, decided by scene dock order.

const PROTOTYPE_SCENE := "res://prototypes/elevator_cutscene/elevator_cutscene_prototype.tscn"
const LEVEL_SCENE := "res://levels/asteroid_level/asteroid_level.tscn"
const INTRO_SCENE := "res://levels/asteroid_level/intro/elevator_intro.tscn"

## Every node the animation names, and the type it has to be.
##
## THIS IS THE CHECK THAT CATCHES A RENAME. An AnimationPlayer track whose path no
## longer resolves does not error and does not warn - the property simply never
## moves, and you are left looking at a still frame wondering which of eleven
## tracks is dead. Asserting the paths from outside the animation is how that
## becomes a named failure instead.
const ANIMATED_NODES := {
	"Cutscenes/ElevatorIntro/CameraAnchor": "Node3D",
	"ElevatorCar/Doors/DoorLeft": "Node3D",
	"ElevatorCar/Doors/DoorRight": "Node3D",
	"ElevatorCar/Doors/DoorLeft/LeafBody/LeafShape": "CollisionShape3D",
	"ElevatorCar/Doors/DoorRight/LeafBody/LeafShape": "CollisionShape3D",
	"ElevatorCar/QuotaScreen": "ElevatorScreen",
	"ElevatorCar/WarningStrobe": "OmniLight3D",
	"Miners/MinerB": "Node3D",
	"Miners/MinerB/Rig/AnimationTree": "AnimationTree",
	"Cutscenes/ElevatorIntro/Gesture": "PlayerGestureProxy",
	"HudBoot": "HudBootCrt",
	"Hud/Title": "Label",
	"Hud/MonitorShot": "ElevatorMonitorShot",
}

## The window the close-up was framed against, from project.godot. Not read off the
## live viewport: a headless run reports whatever the dummy driver felt like, and
## the pose was baked for this shape.
const DESIGN_VIEWPORT := Vector2(1280.0, 720.0)

var _missing_transforms := PackedStringArray()
var _failures := 0
var _checks := 0


func _ready() -> void:
	_verify_level_placement()
	await _verify_scene_paths()
	await _verify_camera_seam()
	await _verify_animation()
	await _verify_window_dispatch()
	await _verify_skip_equivalence()
	_report()


## Instantiates the prototype with autoplay forced off.
##
## The settings resource is an ExtResource shared with the committed .tres, so it
## is duplicated rather than written to - a verifier that leaves autoplay disabled
## in the repo is worse than no verifier. Overriding before add_child() is what
## makes it stick: @export values are applied at instantiate(), and _ready (which
## reads autoplay_on_start) does not run until the node enters the tree.
func _spawn() -> Node3D:
	var prototype: Node3D = load(PROTOTYPE_SCENE).instantiate()
	var settings: ElevatorCutsceneSettings = prototype.settings.duplicate()
	settings.autoplay_on_start = false
	prototype.settings = settings
	add_child(prototype)
	# Two frames: CSGCombiner3D raises its geometry in its own _ready, and the
	# cutscene player's deferred exit-marker check runs a frame after that.
	await get_tree().process_frame
	await get_tree().process_frame
	return prototype


## The intro's exit pose lands on the level's own spawn marker.
##
## THE ONE NUMBER TWO FILES HAVE TO AGREE ABOUT. asteroid_level.tscn positions the
## whole intro so that PlayerExit coincides with %PlayerSpawn, which is what makes
## CLEANUP's teleport invisible and lets respawn go on using the marker it always
## used. Nothing enforces it: get the placement wrong and the cutscene still plays
## perfectly, then drops the player somewhere else in the chamber.
##
## READ OFF THE SCENE STATE, NOT AN INSTANCE. Instantiating asteroid_level runs a
## navigation bake and spawns a creature, which is a lot of machinery to ask a
## geometry assertion to survive.
func _verify_level_placement() -> void:
	_missing_transforms = PackedStringArray()
	var placement := _packed_transform(LEVEL_SCENE, "ElevatorIntro")
	var spawn := _packed_transform(LEVEL_SCENE, "PlayerSpawn")
	var exit := _packed_transform(INTRO_SCENE, "PlayerExit")
	if not _missing_transforms.is_empty():
		_check(
			"[spawn] the placement is readable",
			false,
			"no authored transform on %s" % ", ".join(_missing_transforms)
		)
		return

	var landed := (placement * exit).origin
	var marker := spawn.origin
	_check(
		"[spawn] the intro hands control back on the level's spawn marker",
		landed.distance_to(marker) < 0.01,
		(
			"PlayerExit lands at %v, %.3f m from the marker at %v - check the placement basis, whose serialised triples are ROWS"
			% [landed, landed.distance_to(marker), marker]
		)
	)

	# And facing the same way, or a death mid-level turns the player round.
	var landed_forward := (placement.basis * exit.basis) * Vector3.FORWARD
	var marker_forward := spawn.basis * Vector3.FORWARD
	_check(
		"[spawn] and facing the same way",
		landed_forward.dot(marker_forward) > 0.999,
		(
			"the intro leaves the player facing %v; the marker faces %v"
			% [landed_forward, marker_forward]
		)
	)


## A node's authored transform, straight out of a .tscn's scene state.
##
## Misses are recorded rather than returned, so callers stay typed: a Variant
## return would infer Variant at every call site and fail the strict parser.
func _packed_transform(scene_path: String, node_name: String) -> Transform3D:
	var state := (ResourceLoader.load(scene_path) as PackedScene).get_state()
	for index in state.get_node_count():
		if state.get_node_name(index) != node_name:
			continue
		for property in state.get_node_property_count(index):
			if state.get_node_property_name(index, property) != &"transform":
				continue
			var value: Variant = state.get_node_property_value(index, property)
			if value is Transform3D:
				return value
	_missing_transforms.append("%s in %s" % [node_name, scene_path.get_file()])
	return Transform3D.IDENTITY


## The nodes the animation will name all exist, and are the type it expects.
func _verify_scene_paths() -> void:
	var prototype: Node3D = await _spawn()

	var intro: ElevatorIntro = prototype.get_node("Intro")
	var missing := PackedStringArray()
	for path: String in ANIMATED_NODES:
		var node := intro.get_node_or_null(NodePath(path))
		if node == null:
			missing.append("%s (absent)" % path)
			continue
		var expected: String = ANIMATED_NODES[path]
		if not _is_a(node, expected):
			missing.append("%s is %s, expected %s" % [path, _class_of(node), expected])
	_check("[paths] animated nodes", missing.is_empty(), "; ".join(missing))

	# A PLAIN Node ANYWHERE IN THE CHAIN DETACHES THE 3D HIERARCHY. Everything
	# below it becomes its own transform root, so its global transform equals its
	# local one and the whole cutscene plays at the world origin however the level
	# placed this scene. Nothing errors, nothing warns, and it is invisible in any
	# harness that happens to sit at the origin - which this one does.
	var detached := PackedStringArray()
	for path: String in ANIMATED_NODES:
		var node := intro.get_node_or_null(NodePath(path))
		if not (node is Node3D):
			continue
		var walk := node.get_parent()
		while walk != null and walk != intro:
			if not (walk is Node3D):
				detached.append("%s (under %s, a %s)" % [path, walk.name, walk.get_class()])
				break
			walk = walk.get_parent()
	_check(
		"[hierarchy] every animated node inherits the placement",
		detached.is_empty(),
		"a plain Node breaks the transform chain for: %s" % "; ".join(detached)
	)

	# The visor has to be per-miner, or the track that names one lights all three.
	#
	# BEHAVIOURAL, NOT BY IDENTITY. Each miner now instantiates its own copy of the
	# model, so comparing three material objects would pass however the emission is
	# wired - including if it were never wired at all. Light one and look at the
	# other two instead.
	var miner_a: MinerRig = prototype.get_node("Intro/Miners/MinerA")
	var miner_b: MinerRig = prototype.get_node("Intro/Miners/MinerB")
	var miner_c: MinerRig = prototype.get_node("Intro/Miners/MinerC")
	miner_b.set_visor_lit(true)
	var visor_material := miner_b.get_visor_material()
	_check(
		"[materials] the visor is per-miner",
		(
			visor_material != null
			and visor_material.emission_enabled
			and is_equal_approx(miner_a.visor_energy, MinerRig.VISOR_IDLE_ENERGY)
			and is_equal_approx(miner_c.visor_energy, MinerRig.VISOR_IDLE_ENERGY)
		),
		"lighting MinerB moved another miner's visor, or emission was never enabled"
	)
	miner_b.set_visor_lit(false)

	# The laser cannot ride the arm that performs the gesture.
	_check(
		"[gesture] the hero miner's tool is off the gesturing arm",
		miner_b.tool_bone != &"RightHand",
		"MinerB holds the cutter in the hand the gesture raises to their own face"
	)

	# The door numbers, checked against the model rather than a second knob.
	var door_left: Node3D = prototype.get_node("Intro/ElevatorCar/Doors/DoorLeft")
	var leaf: MeshInstance3D = (
		door_left.find_children("door_left", "MeshInstance3D", true, false)[0]
	)
	_check(
		"[doors] the leaf width matches DOOR_TRAVEL",
		(
			is_equal_approx(door_left.position.x, -ElevatorCar.DOOR_CLOSED_X)
			and is_equal_approx(leaf.get_aabb().size.x, ElevatorCar.DOOR_TRAVEL)
			and is_equal_approx(leaf.get_aabb().end.x, -ElevatorCar.DOOR_CLOSED_X)
		),
		(
			"leaf is %.3f wide with its inner edge at x=%.3f; DOOR_TRAVEL says %.3f and DOOR_CLOSED_X %.3f"
			% [
				leaf.get_aabb().size.x,
				leaf.get_aabb().end.x,
				ElevatorCar.DOOR_TRAVEL,
				ElevatorCar.DOOR_CLOSED_X
			]
		)
	)

	_verify_framing(prototype)
	_verify_voice_over(prototype)
	_verify_exit_pose(prototype)

	# prefab_player brings twenty-seven live components into a shot that was
	# composed without them. These three are the ones that fail SILENTLY.

	# PlayerView writes the SHARED WorldEnvironment in its _ready. Left on, it
	# replaces the shaft's 3..18 m fog with its own 0..30 and drops the ambient,
	# repainting every composed shot - and it does that without an error anywhere.
	# Only a rendered frame would ever show it, which is why it is asserted here.
	var view: Node = prototype.get_node("Player/PlayerBody/View")
	var environment: Environment = (
		(prototype.get_node("WorldEnvironment") as WorldEnvironment).environment
	)
	_check(
		"[environment] the player did not repaint the shot",
		not view.applies_fog and is_equal_approx(environment.fog_depth_end, 18.0),
		(
			"applies_fog=%s and the fog ends at %.1f m; the prototype authored 18.0"
			% [view.applies_fog, environment.fog_depth_end]
		)
	)

	# THE GAMEPLAY HUD IS THE ONE THAT BOOTS. It is adopted into HudBootCrt's
	# SubViewport at bind, so anything still parented to the binding at this point
	# is a second HUD the CRT will never show.
	var hud_binding: Node = prototype.get_node("Player/PlayerBody/UI/HudBinding")
	var boot: HudBootCrt = prototype.get_node("Intro/HudBoot")
	var adopted := boot.get_node("Content").get_child_count() > 0
	_check(
		"[hud] the gameplay HUD is behind the glass",
		hud_binding.hud() != null and adopted,
		"the HUD was not adopted into the boot viewport; the tube will strike over nothing"
	)

	# The pause menu is one of three paths that can hand input back mid-shot, and
	# a shipped level cannot delete it the way the old prototype did. The lock is
	# the fix; this proves the lock, not the deletion.
	var input: Node = prototype.get_node("Player/PlayerBody/Input")
	var rig: CutscenePlayerRig = prototype.get_node("CutsceneRig")
	rig.set_input_enabled(false)
	# Exactly what PlayerUi._on_game_unpaused and PlayerLife._revive do.
	input.enabled = true
	_check(
		"[input_lock] no unpause or revive can un-park the rig",
		not input.enabled,
		"input.enabled was set true behind the cutscene's back; PlayerInput.locked did not hold"
	)
	rig.set_input_enabled(true)

	prototype.queue_free()
	await get_tree().process_frame


## The refusal is imported, routed, and finishes before control comes back.
##
## The last of those is the one worth having: a line that runs past the end of the
## clip is cut off mid-word on every playthrough, and nothing else would say so.
func _verify_voice_over(prototype: Node3D) -> void:
	var vo: AudioStreamPlayer = prototype.get_node_or_null("Intro/Vo")
	if vo == null or vo.stream == null:
		_check("[vo] the line is wired", false, "Intro/Vo has no stream; was the .wav imported?")
		return
	_check("[vo] on the Dialogue bus", vo.bus == &"Dialogue", "routed to %s" % vo.bus)
	var ends := ElevatorIntroKnobs.VO_TIME + vo.stream.get_length()
	_check(
		"[vo] the line finishes before control does",
		ends <= ElevatorIntroKnobs.CUTSCENE_LENGTH,
		(
			"a %.2fs line at %.2fs ends at %.2fs, past the %.2fs clip"
			% [
				vo.stream.get_length(),
				ElevatorIntroKnobs.VO_TIME,
				ends,
				ElevatorIntroKnobs.CUTSCENE_LENGTH
			]
		)
	)


## The pose the intro hands control back at is reachable and not inside rock.
##
## PlayerExit is also where CLEANUP teleports the rig on every terminal path, so a
## marker parked in geometry is a player stuck in a wall after every skip.
func _verify_exit_pose(prototype: Node3D) -> void:
	var exit: Node3D = prototype.get_node("Intro/PlayerExit")
	var panel: Node3D = prototype.get_node_or_null("Intro/ElevatorCar/CallPanel/PressTarget")
	if panel == null:
		_check("[press] the call panel exists", false, "no CallPanel/PressTarget on the car")
		return
	# The press is solved by two-bone IK against a 0.42 m arm, which reaches about
	# 0.44 m from the eye. A little further is fine - the hand sits between the lens
	# and the panel and occludes it, so a small gap along the view ray cannot be
	# seen. A lot further is a hand grasping at air, on screen, in the shot the
	# whole ending is built around, and no assertion but this one sees it.
	var reach := exit.global_position.distance_to(panel.global_position)
	_check(
		"[press] the panel is within arm's reach",
		reach <= 0.65,
		"PressTarget is %.3f m from PlayerExit; the arm reaches about 0.44 m" % reach
	)


## The opening close-up really does frame the glass, recomputed off the live scene.
##
## THE USABLE WINDOW IS ABOUT 2.4% WIDE, which is why this is a check rather than a
## comment. Below 1.00x the plate bezel comes into shot and the full-screen 2D copy,
## which has no bezel, stops matching it; above about 1.024x the crop starts eating
## the top of EXTRACTION CREW 067. The pose is also the one place in the knobs where
## the .tscn lies: QuotaScreen reads y = 2.4 there and is at world 0.9844, because
## ElevatorCar carries -1.42.
func _verify_framing(prototype: Node3D) -> void:
	var screen: ElevatorScreen = prototype.get_node("Intro/ElevatorCar/QuotaScreen")
	var quad := screen.plate.mesh as QuadMesh
	var material := screen.plate.material_override as ShaderMaterial
	if quad == null or material == null:
		_check("[framing] the plate is a shaded quad", false, "no QuadMesh or no ShaderMaterial")
		return

	var rect: Vector4 = material.get_shader_parameter("screen_rect")
	var world := screen.plate.global_transform
	var scale := world.basis.get_scale()
	var glass := Vector2(quad.size.x * rect.z * scale.x, quad.size.y * rect.w * scale.y)
	var centre := (
		world
		* Vector3(
			(rect.x + rect.z * 0.5 - 0.5) * quad.size.x,
			(0.5 - (rect.y + rect.w * 0.5)) * quad.size.y,
			0.0
		)
	)

	var position := ElevatorIntroKnobs.CLOSEUP_POSITION
	var target := ElevatorIntroKnobs.CLOSEUP_TARGET
	var distance := position.z - centre.z
	_check(
		"[framing] the close-up is nose-on the glass",
		(
			target.distance_to(centre) < 0.001
			and absf(position.x - centre.x) < 0.001
			and absf(position.y - centre.y) < 0.001
			and _near(distance, ElevatorIntroKnobs.CLOSEUP_DISTANCE)
		),
		(
			"glass centre %v, cover distance %.4f; knobs say %v looking at %v from %.4f"
			% [
				centre,
				_cover_distance(glass),
				position,
				target,
				ElevatorIntroKnobs.CLOSEUP_DISTANCE
			]
		)
	)

	# Covers: at this distance and fov the glass has to overflow BOTH axes, or the
	# bezel the 2D copy does not have appears around it.
	var half_height := distance * tan(deg_to_rad(ElevatorIntroKnobs.CUTSCENE_FOV) * 0.5)
	var half_width := half_height * DESIGN_VIEWPORT.x / DESIGN_VIEWPORT.y
	_check(
		"[framing] the glass covers the frame",
		half_width <= glass.x * 0.5 + 0.0001 and half_height <= glass.y * 0.5 + 0.0001,
		(
			"the frame is %.4f x %.4f m at %.4f m; the glass is only %.4f x %.4f"
			% [half_width * 2.0, half_height * 2.0, distance, glass.x, glass.y]
		)
	)

	# ...and does not crop the copy. The frame is shorter than the glass, so the
	# readout loses a band top and bottom; CONTENT_BOUNDS is what may not be in it.
	var seen := (half_height * 2.0) / glass.y
	var inset := ElevatorScreenReadout.DESIGN.y * (1.0 - seen) * 0.5
	var bounds := ElevatorScreenReadout.CONTENT_BOUNDS
	_check(
		"[framing] the crop does not eat the copy",
		inset <= bounds.position.y and inset <= ElevatorScreenReadout.DESIGN.y - bounds.end.y,
		(
			"the crop takes %.1f design px off each edge; the copy starts at %.1f and ends %.1f from the bottom"
			% [inset, bounds.position.y, ElevatorScreenReadout.DESIGN.y - bounds.end.y]
		)
	)


## The distance at which the glass would exactly cover the frame, so a drifted pose
## reports the number to paste rather than only that it is wrong.
func _cover_distance(glass: Vector2) -> float:
	var half := tan(deg_to_rad(ElevatorIntroKnobs.CUTSCENE_FOV * 0.5))
	var by_height := glass.y * 0.5 / half
	var by_width := glass.x * 0.5 / (half * DESIGN_VIEWPORT.x / DESIGN_VIEWPORT.y)
	return minf(by_height, by_width)


func _near(left: float, right: float) -> bool:
	return absf(left - right) < 0.001


## The four phases of the seam, checked for exactly one current camera at each.
func _verify_camera_seam() -> void:
	var prototype: Node3D = await _spawn()

	var rig: CutscenePlayerRig = prototype.get_node("CutsceneRig")
	var head_camera: Camera3D = rig.get_head_camera()
	var driver: CutsceneCameraDriver = prototype.get_node("Intro/CutsceneCamera")
	var anchor: Node3D = prototype.get_node("Intro/Cutscenes/ElevatorIntro/CameraAnchor")
	# The seam is what is under test, not the shake. Left at the descent's gain
	# the pose check fails by about a centimetre, which is the rumble doing
	# exactly what it should.
	driver.set_rumble_gain(0.0)

	_check_current("idle", prototype, head_camera)
	_check("[control] idle", not driver.has_control(), "driver claims control before any request")

	# Zero blend is the enter path this cutscene actually uses, and it has to land
	# on the anchor the same frame - a frame spent at the gameplay pose is a
	# single-frame flash of the wrong shot.
	driver.request_control(anchor, CutsceneCameraDriver.Authority.FULL, 0.0)
	_check_current("takeover", prototype, driver)
	_check(
		"[pose] cut lands same frame",
		driver.global_position.distance_to(anchor.global_position) < 0.001,
		"camera is %s, anchor is %s" % [driver.global_position, anchor.global_position]
	)

	# A blend that is genuinely mid-flight: still ours, not yet at the target.
	driver.release_control(1.0)
	_check(
		"[control] blending out",
		driver.has_control(),
		"released control the instant release_control was called, a whole blend early"
	)
	_check_current("blend out", prototype, driver)

	await get_tree().process_frame
	await get_tree().process_frame
	_check_current("mid blend", prototype, driver)

	# ...and the skip path, which hands back the same frame.
	driver.release_control(0.0)
	_check_current("handed back", prototype, head_camera)
	_check(
		"[control] released", not driver.has_control(), "still claims control after a zero blend"
	)

	prototype.queue_free()
	await get_tree().process_frame


## The clip is the length it claims, and every track path resolves.
##
## [length] catches the Animation.length default. It is 1.0, and it silently
## TRUNCATES every track past it - the clip just ends one second in and the doors
## never open, with nothing anywhere saying so.
##
## [tracks] catches the other silent one. An AnimationPlayer track whose path no
## longer resolves does not error and does not warn; the property simply never
## moves.
func _verify_animation() -> void:
	var prototype: Node3D = await _spawn()
	var animation_player: AnimationPlayer = prototype.get_node(
		"Intro/Cutscenes/ElevatorIntro/AnimationPlayer"
	)

	# The load-bearing NodePath in the whole scene. Wrong, every track below is
	# dead and every check on them still passes, because they resolve against
	# whatever root_node points at.
	_check(
		"[root_node] resolves to the intro root",
		(
			animation_player.get_node_or_null(animation_player.root_node)
			== prototype.get_node("Intro")
		),
		(
			"root_node is %s, which resolves to %s"
			% [
				animation_player.root_node,
				animation_player.get_node_or_null(animation_player.root_node)
			]
		)
	)

	var animation := animation_player.get_animation(&"elevator_intro")
	_check("[animation] clip exists", animation != null, "no elevator_intro in the library")
	if animation == null:
		prototype.queue_free()
		return

	_check(
		"[length] not the default 1.0",
		is_equal_approx(animation.length, ElevatorIntroKnobs.CUTSCENE_LENGTH),
		"clip is %.2fs, knobs say %.2fs" % [animation.length, ElevatorIntroKnobs.CUTSCENE_LENGTH]
	)

	var dead := PackedStringArray()
	for track in animation.get_track_count():
		var path := animation.track_get_path(track)
		# Value tracks carry the property as subnames; transform tracks are a bare
		# node path. Either way only the node half is resolvable.
		var node_path := NodePath(path.get_concatenated_names())
		if prototype.get_node("Intro").get_node_or_null(node_path) == null:
			dead.append(String(path))
	_check("[tracks] every path resolves", dead.is_empty(), "dead: %s" % ", ".join(dead))

	# The overlay track, asserted on the CLIP. _cleanup() also forces the monitor
	# off, so the runtime [no-orphan] check would pass with this keyframe deleted -
	# and the prologue would then simply never appear.
	var shot_track := animation.find_track(
		NodePath("Hud/MonitorShot:shot_alpha"), Animation.TYPE_VALUE
	)
	_check(
		"[prologue] the monitor shot opens, cuts, and stays gone",
		(
			shot_track >= 0
			and _near(animation.value_track_interpolate(shot_track, 0.0), 1.0)
			and _near(
				animation.value_track_interpolate(shot_track, ElevatorIntroKnobs.PROLOGUE_LENGTH),
				0.0
			)
			and _near(
				animation.value_track_interpolate(shot_track, ElevatorIntroKnobs.CUTSCENE_LENGTH),
				0.0
			)
		),
		"no shot_alpha track, or it does not open at 1 and cut to 0 at PROLOGUE_LENGTH"
	)

	# The camera is already on the glass under that overlay, or the cut at
	# PROLOGUE_LENGTH is a cut to somewhere the audience has not been.
	var anchor_track := animation.find_track(
		NodePath("Cutscenes/ElevatorIntro/CameraAnchor"), Animation.TYPE_POSITION_3D
	)
	var opens_on := Vector3.ZERO
	var reveals_at := Vector3.ZERO
	if anchor_track >= 0:
		opens_on = animation.position_track_interpolate(anchor_track, 0.0)
		reveals_at = animation.position_track_interpolate(
			anchor_track, ElevatorIntroKnobs.PROLOGUE_END
		)
	_check(
		"[prologue] the camera opens on the close-up and reveals by PROLOGUE_END",
		(
			anchor_track >= 0
			and opens_on.distance_to(ElevatorIntroKnobs.CLOSEUP_POSITION) < 0.001
			and reveals_at.distance_to(ElevatorIntroKnobs.SHOT1_POSITION) < 0.001
		),
		"the anchor opens at %v and is at %v by PROLOGUE_END" % [opens_on, reveals_at]
	)

	# The RESET clip is what lets a director scrub away and put the level back,
	# and the dock looks for it by name.
	_check(
		"[reset] clip exists",
		animation_player.get_animation(&"RESET") != null,
		"no RESET in the library; scrubbing leaves the level wherever it stopped"
	)

	prototype.queue_free()
	await get_tree().process_frame


## Every effect fires, in order, from a SINGLE oversized tick.
##
## THIS IS THE FRAME-HITCH CASE, TESTED DIRECTLY RATHER THAN HOPED FOR. One
## _process with a twenty-second delta puts all five effects inside one dispatch
## window. The naive is_equal_approx(t, clock) check drops all five - silently,
## and only under load, which means only on the playtester's machine.
##
## It also covers the t = 0.0 edge: the window is half-open at the low end, so
## car_descending could never be inside it unless enter() opens the window below
## zero once.
func _verify_window_dispatch() -> void:
	var prototype: Node3D = await _spawn()
	var cutscene: CutscenePlayer = prototype.get_node("Intro/Cutscenes/ElevatorIntro")
	var effects: ElevatorIntroEffects = prototype.get_node("Intro/Cutscenes/ElevatorIntro/Effects")

	cutscene.enter(0.0)
	_check(
		"[t-zero] car_descending fired on the first frame",
		cutscene.get_fired_count() >= 1,
		"nothing fired at t=0; the dispatch window was never opened below zero"
	)

	var expected := cutscene.data.effects.size()
	cutscene.advance(ElevatorIntroKnobs.CUTSCENE_LENGTH + 1.0)
	_check(
		"[window] every effect fired in one tick",
		cutscene.get_fired_count() == expected,
		(
			"%d of %d effects fired from a single oversized delta"
			% [cutscene.get_fired_count(), expected]
		)
	)
	_check(
		"[window] end state reached",
		(
			effects.workday_begun
			and effects.doors_unlocked
			and effects.doors_locked
			and effects.hud_online
			and effects.hud_settled
			and effects.access_denied
		),
		(
			"flags after a full run: workday=%s open=%s shut=%s hud=%s settled=%s denied=%s"
			% [
				effects.workday_begun,
				effects.doors_unlocked,
				effects.doors_locked,
				effects.hud_online,
				effects.hud_settled,
				effects.access_denied
			]
		)
	)

	prototype.queue_free()
	await get_tree().process_frame


## THE CHECK THIS PROTOTYPE EXISTS FOR.
##
## Skipping at any point must land on exactly the same world state as watching
## the whole thing. If it does not, the cutscene has two endings and only one of
## them is ever tested.
func _verify_skip_equivalence() -> void:
	var watched := await _run_to_end()
	# 1.5 is mid-2D-shot and 4.0 is mid-pull-back: the two moments the prologue can
	# leave something covering the screen. 18.0 is mid-tube-strike, which is the
	# other way to leave a full-screen overlay behind. The last four are one inside
	# each beat of the exit sequence - drift, doors shutting, press, and pan.
	for skip_at: float in [0.0, 1.5, 4.0, 13.5, 18.0, 23.5, 27.0, 33.0, 36.0, 41.0]:
		var skipped := await _run_and_skip_at(skip_at)
		var differences := PackedStringArray()
		for key: String in watched:
			if not _same(watched[key], skipped[key]):
				differences.append("%s: watched %s, skipped %s" % [key, watched[key], skipped[key]])
		_check(
			"[equivalence] skip at %.0fs" % skip_at, differences.is_empty(), "; ".join(differences)
		)


func _run_to_end() -> Dictionary:
	var prototype: Node3D = await _spawn()
	var cutscene: CutscenePlayer = prototype.get_node("Intro/Cutscenes/ElevatorIntro")
	cutscene.enter(0.0)
	cutscene.advance(ElevatorIntroKnobs.CUTSCENE_LENGTH + 1.0)
	var body: Node = prototype.get_node("Player/PlayerBody")
	# Nothing here fires today only because player_settings.tres tunes the drain
	# rates down to 0.1/s; the class defaults are 3.0 and 1.0. A balance pass on a
	# shared resource could put a death inside a cutscene, and this is the cheapest
	# way for that to name itself rather than show up as a mystery.
	_check(
		"[budget] the suit survives the cutscene",
		(
			body.get_node("PowerClient").has_power()
			and body.get_node("Life").is_alive()
			and not body.get_node("Oxygen").is_empty()
		),
		(
			"a %.1f s cutscene emptied the suit; check the drain rates in player_settings.tres"
			% ElevatorIntroKnobs.CUTSCENE_LENGTH
		)
	)

	var state := _snapshot(prototype, "watched")
	prototype.queue_free()
	await get_tree().process_frame
	return state


func _run_and_skip_at(skip_at: float) -> Dictionary:
	var prototype: Node3D = await _spawn()
	var cutscene: CutscenePlayer = prototype.get_node("Intro/Cutscenes/ElevatorIntro")
	cutscene.enter(0.0)
	if skip_at > 0.0:
		cutscene.advance(skip_at)
	cutscene.skip()
	var state := _snapshot(prototype, "skip@%.0f" % skip_at)
	prototype.queue_free()
	await get_tree().process_frame
	return state


## Everything a player could notice, after the camera has settled.
func _snapshot(prototype: Node3D, label: String) -> Dictionary:
	var rig: CutscenePlayerRig = prototype.get_node("CutsceneRig")
	var driver: CutsceneCameraDriver = prototype.get_node("Intro/CutsceneCamera")
	var effects: ElevatorIntroEffects = prototype.get_node("Intro/Cutscenes/ElevatorIntro/Effects")
	var car: ElevatorCar = prototype.get_node("Intro/ElevatorCar")

	# Force the exit blend to completion. A normal finish eases over
	# EXIT_BLEND_TIME and a skip hands back instantly, so without this the two
	# paths differ on which camera is current for a third of a second - a real
	# difference, but a transient one, and not the end state under test.
	if driver.has_control():
		driver.advance(10.0)

	# [no-orphan]: the spec's "the one that matters most" - no terminal state may
	# leave the player without input, without collision, or without a camera.
	_check("[no-orphan] %s: input restored" % label, rig.is_input_enabled(), "input still disabled")
	_check(
		"[no-orphan] %s: collision restored" % label,
		not rig.get_hull_shape().disabled,
		"the rig's collision shape is still off"
	)
	_check(
		"[no-orphan] %s: a camera is current" % label,
		rig.get_head_camera().current,
		"the gameplay camera was never handed back"
	)
	_check(
		"[no-orphan] %s: the pointer is captured" % label,
		rig.is_mouse_captured(),
		"the cutscene freed the mouse and never took it back"
	)
	_check(
		"[no-orphan] %s: the lamp is back on" % label,
		rig.is_lamp_lit(),
		"the helmet lamp was switched off for the shot and left off"
	)
	_check(
		"[no-orphan] %s: the suit is drawn again" % label,
		not rig.is_avatar_hidden(),
		"the player's own model is still hidden"
	)

	var monitor: ElevatorMonitorShot = prototype.get_node("Intro/Hud/MonitorShot")
	_check(
		"[no-orphan] %s: the monitor shot is gone" % label,
		monitor.shot_alpha <= 0.001 and not monitor.visible,
		"the full-screen quota monitor still covers the game at alpha %.3f" % monitor.shot_alpha
	)

	# The inverse of doors_unlocked, and just as silent: leaves the shot visibly
	# shut in the player's face while the collider they name is still off.
	_check(
		"[doors_closed] %s: the car is shut, in both halves" % label,
		car.are_doors_shut() and car.are_doors_solid(),
		(
			"doors shut=%s solid=%s; the animation and the effect disagree"
			% [car.are_doors_shut(), car.are_doors_solid()]
		)
	)

	# The boot overlay is one of two things that can be left covering the screen.
	var boot: HudBootCrt = prototype.get_node_or_null("Intro/HudBoot")
	_check(
		"[hud_boot] %s: nothing is left behind the glass" % label,
		boot == null or boot.get_node("Content").get_child_count() == 0,
		"HudBootCrt still holds the HUD inside its SubViewport"
	)
	var hud_binding: Node = prototype.get_node("Player/PlayerBody/UI/HudBinding")
	var hud: CanvasLayer = hud_binding.hud()
	_check(
		"[hud_boot] %s: the HUD is back on screen" % label,
		hud != null and hud.visible and hud.get_parent() == hud_binding,
		"the gameplay HUD did not come back out from behind the glass"
	)

	_check(
		"[press] %s: the arm is down" % label,
		is_zero_approx(rig.get_gesture_blend()),
		"the press gesture is still blended in at %.3f" % rig.get_gesture_blend()
	)
	_check(
		"[press] %s: the cutter is back" % label,
		rig.is_tool_visible(),
		"the tool was hidden for the shot and never shown again"
	)

	return {
		"monitor_alpha": monitor.shot_alpha,
		"monitor_visible": monitor.visible,
		"door_left_x": prototype.get_node("Intro/ElevatorCar/Doors/DoorLeft").position.x,
		"door_right_x": prototype.get_node("Intro/ElevatorCar/Doors/DoorRight").position.x,
		"doors_solid": car.are_doors_solid(),
		"hud_boot": prototype.get_node("Intro/HudBoot").power_on,
		"title_alpha": prototype.get_node("Intro/Hud/Title").modulate.a,
		"visor_energy": (prototype.get_node("Intro/Miners/MinerB") as MinerRig).visor_energy,
		"gesture_blend":
		(prototype.get_node("Intro/Miners/MinerB") as MinerRig).get_gesture_blend(),
		"strobe_energy": prototype.get_node("Intro/ElevatorCar/WarningStrobe").light_energy,
		"hud_online": effects.hud_online,
		"doors_unlocked": effects.doors_unlocked,
		"doors_locked": effects.doors_locked,
		"access_denied": effects.access_denied,
		"hud_settled": effects.hud_settled,
		"workday_begun": effects.workday_begun,
		"press_blend": rig.get_gesture_blend(),
		"rumble_gain": driver.get_rumble_gain(),
		"rig_position": rig.get_body().global_position,
		"rig_velocity": rig.velocity,
		"rig_angular_velocity": rig.angular_velocity,
		"head_camera_current": rig.get_head_camera().current,
	}


## Float and vector comparison with a tolerance, because a seek and a playthrough
## reach the same key by different arithmetic and need not agree bit for bit.
func _same(left: Variant, right: Variant) -> bool:
	if left is float:
		return absf(left - right) < 0.001
	if left is Vector3:
		return (left as Vector3).distance_to(right) < 0.001
	if left is Quaternion:
		return (left as Quaternion).angle_to(right) < 0.01
	return left == right


## Exactly one camera in the scene is current, and it is the expected one.
##
## Both halves matter. `current` on the right camera with a second one also set
## is a scene that renders correctly until node order changes underneath it.
func _check_current(phase: String, prototype: Node, expected: Camera3D) -> void:
	var live: Array[String] = []
	for camera: Camera3D in _cameras(prototype):
		if camera.current:
			live.append(camera.name)
	_check(
		"[camera] %s" % phase,
		live.size() == 1 and expected.current,
		"expected only %s, current cameras are %s" % [expected.name, live]
	)


func _cameras(node: Node) -> Array[Camera3D]:
	var found: Array[Camera3D] = []
	if node is Camera3D:
		found.append(node as Camera3D)
	for child in node.get_children():
		found.append_array(_cameras(child))
	return found


## Node type test that also knows script class_names.
##
## is_class() only walks the ENGINE hierarchy, so a node whose type comes from a
## class_name - QuotaScreen is an ElevatorScreen - reports as its base Node3D and
## the check above fails against a name that is perfectly correct. Weakening the
## table to "Node3D" would pass, and would also pass for a bare Node3D, which is
## the substitution this check exists to catch.
func _is_a(node: Node, expected: String) -> bool:
	if node.is_class(expected):
		return true
	var script := node.get_script() as Script
	while script != null:
		if String(script.get_global_name()) == expected:
			return true
		script = script.get_base_script()
	return false


func _class_of(node: Node) -> String:
	var script := node.get_script() as Script
	if script != null and String(script.get_global_name()) != "":
		return String(script.get_global_name())
	return node.get_class()


func _check(check_name: String, passed: bool, detail: String) -> void:
	_checks += 1
	if passed:
		print("  PASS  %s" % check_name)
		return
	_failures += 1
	printerr("  FAIL  %s: %s" % [check_name, detail])


func _report() -> void:
	print("%d checks, %d failures" % [_checks, _failures])
	if _checks == 0:
		printerr("nothing was actually verified")
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failures > 0 else 0)
