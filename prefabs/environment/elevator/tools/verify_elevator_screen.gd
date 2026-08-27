extends Node

## Headless-ish checks for the quota terminal. Run it as a SCENE, with a real
## renderer, because two of these are about what the SubViewport actually did:
##
##     "D:/Godot_v4.7.1-stable_win64.exe" --path <root> \
##       res://prefabs/environment/elevator/tools/verify_elevator_screen.tscn
##
## The check that earns its keep is [locality]: without resource_local_to_scene on
## the ShaderMaterial, two screens in one level share a material, therefore share
## content_tex, therefore show one readout twice.

const SCREEN_SCENE := "res://prefabs/environment/elevator/prefab_elevator_screen.tscn"
const PLATE_PNG := "res://assets/art/environment/elevator_car/screen/t_elevator_screen_plate.png"

## Luminance above which a plate texel counts as part of the baked readout.
const BAKED_LUMA := 0.25

var _failures := 0
var _checks := 0


func _ready() -> void:
	await _verify_content_texture()
	await _verify_locality()
	_verify_quota_rules()
	await _verify_signal()
	await _verify_idle()
	_verify_screen_rect()
	_report()


func _verify_content_texture() -> void:
	var screen: ElevatorScreen = await _spawn()
	var material := screen.plate.material_override as ShaderMaterial
	_check(
		"[content] the readout texture is pushed from code",
		material != null and material.get_shader_parameter("content_tex") is ViewportTexture,
		"content_tex is %s; it must be assigned in _ready, never authored in the .tscn"
	)
	_check(
		"[locality] the material is local to the scene",
		material != null and material.resource_local_to_scene,
		"resource_local_to_scene is off, so every screen in a level shares one readout"
	)
	screen.queue_free()
	await get_tree().process_frame


## Two screens must not share a material or a texture. They MUST share a number:
## the ledger is global, and a screen with its own copy is the bug this removed.
func _verify_locality() -> void:
	var a: ElevatorScreen = await _spawn()
	var b: ElevatorScreen = await _spawn()
	Score.quota_target = 1000
	Score.score = 0
	a.refresh()
	b.refresh()
	var mat_a := a.plate.material_override as ShaderMaterial
	var mat_b := b.plate.material_override as ShaderMaterial
	_check(
		"[locality] two screens hold two materials",
		mat_a != mat_b,
		"both instances resolved to the same ShaderMaterial"
	)
	_check(
		"[locality] two screens hold two readouts",
		mat_a.get_shader_parameter("content_tex") != mat_b.get_shader_parameter("content_tex"),
		"both instances resolved to the same ViewportTexture"
	)
	_check(
		"[locality] but the two of them agree about the quota",
		is_equal_approx(mat_a.get_shader_parameter("alarm"), mat_b.get_shader_parameter("alarm")),
		"two screens reading one ledger disagreed about whether the quota is met"
	)
	a.queue_free()
	b.queue_free()
	await get_tree().process_frame


func _verify_quota_rules() -> void:
	var target := 47560
	var wrong := PackedStringArray()
	Score.quota_target = target
	for collected: int in [0, target - 1, target, target + 1]:
		Score.score = collected
		var owed := Score.credits_outstanding()
		var expected := maxi(target - collected, 0)
		if owed != expected:
			wrong.append("collected %d owed %d, expected %d" % [collected, owed, expected])
	Score.score = target
	if not Score.is_quota_met():
		wrong.append("exactly the target did not read as met")
	Score.score = target - 1
	if Score.is_quota_met():
		wrong.append("one short read as met")
	_check("[quota] the outstanding-credits rule", wrong.is_empty(), "; ".join(wrong))


func _verify_signal() -> void:
	var screen: ElevatorScreen = await _spawn()
	Score.quota_target = 1000
	# Below the target BEFORE connecting, so the latch starts where the test assumes.
	Score.score = 0
	screen.refresh()
	var fired := [0]
	screen.quota_met.connect(func() -> void: fired[0] += 1)
	Score.score = Score.quota_target - 1
	_check("[signal] quota_met stays quiet below the target", fired[0] == 0, "fired early")
	Score.score = Score.quota_target
	Score.score = Score.quota_target + 5000
	_check(
		"[signal] quota_met fires once on the crossing",
		fired[0] == 1,
		"fired %d times; it must be a transition, not a per-call emit" % fired[0]
	)
	# A ledger that can lose minerals must be able to take the screen back off
	# APPROVED, and then report the next crossing.
	Score.score = 0
	Score.score = Score.quota_target
	_check(
		"[signal] quota_met re-arms after dropping back under",
		fired[0] == 2,
		"fired %d times; the latch never reset" % fired[0]
	)
	screen.queue_free()
	await get_tree().process_frame


## The viewport draws when it is armed, and not otherwise.
##
## BEHAVIOURAL, NOT BY PROPERTY. render_target_update_mode still reads UPDATE_ONCE
## after the render in Godot 4.7 - the once-then-stop is bookkept inside the
## RenderingServer and never written back to the node - so asserting the property
## would test Godot's accounting rather than this prefab's claim. Changing the
## words behind the prefab's back and watching the pixels not move is the claim.
func _verify_idle() -> void:
	var screen: ElevatorScreen = await _spawn()
	# Its own quota, and high enough that the two scores below owe different numbers:
	# the ledger is global now, so a check that inherits the last one's target can end
	# up comparing one rendering of "0 CR" against another.
	Score.quota_target = 100000
	Score.score = 1234
	screen.refresh()
	_check(
		"[idle] a text change arms one render",
		screen.content.render_target_update_mode == SubViewport.UPDATE_ONCE,
		"the readout changed without arming the viewport"
	)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var drawn := screen.content.get_texture().get_image().get_data()

	# Through the readout's own API rather than a node path: set_quota_value writes
	# a Label and deliberately does not arm the viewport, which is the claim.
	screen.get_readout().set_quota_value("-99999 CR")
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_check(
		"[idle] the viewport does not redraw unasked",
		screen.content.get_texture().get_image().get_data() == drawn,
		"the readout moved without being armed, so the SubViewport is drawing every frame"
	)

	Score.score = 4321
	screen.refresh()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_check(
		"[idle] arming it draws again",
		screen.content.get_texture().get_image().get_data() != drawn,
		"the readout never updated, so a quota change would never reach the glass"
	)
	screen.queue_free()
	await get_tree().process_frame


## Every baked texel of the concept readout falls inside screen_rect.
##
## GLASS ONLY. A whole-image version of this would fail on the bezel's hazard
## stripes, which are legitimately brighter than the threshold.
func _verify_screen_rect() -> void:
	var image := Image.load_from_file(ProjectSettings.globalize_path(PLATE_PNG))
	if image == null:
		_check("[rect] the plate is readable", false, "could not load %s" % PLATE_PNG)
		return
	var probe: ElevatorScreen = load(SCREEN_SCENE).instantiate()
	var mesh: MeshInstance3D = probe.get_node("Plate")
	var material := mesh.material_override as ShaderMaterial
	var rect: Vector4 = material.get_shader_parameter("screen_rect")
	probe.free()
	var size := Vector2(image.get_size())
	var origin := Vector2(rect.x, rect.y) * size
	var extent := Vector2(rect.z, rect.w) * size
	var worst := extent.x
	for y in range(int(origin.y), int(origin.y + extent.y), 3):
		for x in range(int(origin.x), int(origin.x + extent.x), 3):
			var pixel := image.get_pixel(x, y)
			if pixel.get_luminance() < BAKED_LUMA:
				continue
			worst = minf(
				worst,
				minf(
					minf(float(x) - origin.x, origin.x + extent.x - float(x)),
					minf(float(y) - origin.y, origin.y + extent.y - float(y))
				)
			)
	_check(
		"[rect] the baked readout sits inside screen_rect",
		worst > 0.0,
		"baked content reaches the rect edge; re-run tools/measure_screen_rect.py"
	)


func _spawn() -> ElevatorScreen:
	var screen: ElevatorScreen = load(SCREEN_SCENE).instantiate()
	add_child(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	return screen


func _check(check_name: String, passed: bool, detail: String) -> void:
	_checks += 1
	if passed:
		print("  PASS  %s" % check_name)
		return
	_failures += 1
	printerr("  FAIL  %s: %s" % [check_name, detail])


func _report() -> void:
	print("%d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
