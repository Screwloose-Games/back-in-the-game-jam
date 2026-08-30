extends Node3D

## Renders the quota terminal at chosen states so it can be LOOKED AT rather than
## asserted. Ghosting under the live text, a halo that clips instead of spreading,
## and a screen_rect landing on the bevel highlight are all obvious in a PNG and
## none of them is reachable by a check.
##
##     "D:/Godot_v4.7.1-stable_win64.exe" --path <root> --resolution 1280x720 \
##       res://prefabs/environment/elevator/tools/preview_elevator_screen.tscn
##
## NOT --headless: the dummy renderer produces no image.

const SCREEN_SCENE := "res://prefabs/environment/elevator/prefab_elevator_screen.tscn"
const OUT_DIR := "user://screen_preview"

## The tube animates on TIME, so a capture on frame one photographs the boot raster.
const WARMUP_FRAMES := 8

## power_on, collected, name.
const SAMPLES := [
	[0.0, 0, "p00_dead"],
	[0.35, 0, "p35_raster"],
	[1.0, 0, "on_denied_zero"],
	[1.0, 20000, "on_denied_part"],
	[1.0, 47559, "on_denied_one_short"],
	[1.0, 47560, "on_approved_exact"],
	[1.0, 90000, "on_approved_over"],
]


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var screen: ElevatorScreen = load(SCREEN_SCENE).instantiate()
	add_child(screen)
	for _i in WARMUP_FRAMES:
		await get_tree().process_frame

	for sample in SAMPLES:
		screen.set_power_on(sample[0])
		Score.score = sample[1]
		screen.refresh()
		await _capture("%s" % sample[2])

	# Three frames apart in time, so the roll band and a tear show up as motion.
	screen.set_power_on(1.0)
	Score.score = 0
	screen.refresh()
	for i in 3:
		await get_tree().create_timer(0.4).timeout
		await _capture("motion_%d" % i)

	print("wrote %d frames to %s" % [SAMPLES.size() + 3, ProjectSettings.globalize_path(OUT_DIR)])
	get_tree().quit()


func _capture(name: String) -> void:
	# Two process frames so the SubViewport's UPDATE_ONCE has actually drawn before
	# the 3D pass samples it, then one post-draw so the backbuffer is complete.
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("%s/%s.png" % [OUT_DIR, name])
