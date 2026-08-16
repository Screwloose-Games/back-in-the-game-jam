class_name ShaderWarmup
extends Node

## Holds a set of nodes drawn for a few frames so the renderer compiles their
## shader variants while a loading screen is still covering them. Nothing in
## Godot precompiles a variant on request under GL Compatibility — drawing it is
## the only way to have it, and the web export has no shader cache to fall back on.

signal finished

## Two frames would draw it; the third is slack for a frame the engine drops.
const DEFAULT_FRAMES := 3

## Runs after every gameplay component. Not defensive: PlayerRigAnimation rewrites
## the tool model's visibility from its own _process every frame, so a warm-up that
## ran before it would assert visibility that was overwritten before the draw.
const LATE_PRIORITY := 1000

var _hold := Callable()
var _release := Callable()
var _frames_left := 0
var _active := false


func _ready() -> void:
	process_priority = LATE_PRIORITY
	set_process(false)


func _process(_delta: float) -> void:
	step()


## Holds whatever `hold` turns on for `frames` drawn frames, then calls `release`.
func run(hold: Callable, release: Callable, frames: int = DEFAULT_FRAMES) -> void:
	_hold = hold
	_release = release
	_frames_left = maxi(frames, 1)
	_active = true
	set_process(true)


## Whether a warm-up is still holding nodes visible.
func is_running() -> bool:
	return _active and _frames_left > 0


## Advances one frame. Called for you each frame; public so a test can step the
## machine without waiting on the clock.
func step() -> void:
	if not _active:
		return
	if _frames_left <= 0:
		_active = false
		set_process(false)
		var release := _release
		_release = Callable()
		_hold = Callable()
		if release.is_valid():
			release.call()
		finished.emit()
		return
	# Asserted every frame rather than set once: this runs last, so this is the
	# value the renderer sees however many components wrote it earlier.
	if _hold.is_valid():
		_hold.call()
	_frames_left -= 1
