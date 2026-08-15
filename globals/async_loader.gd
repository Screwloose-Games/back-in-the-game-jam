extends Node

## Loads resources on a background thread and reports how far along they are.
##
## Holds a strong reference to everything it finishes, because Godot's resource cache
## is weak: a level warmed while the player reads the main menu would otherwise be
## collected before they ever pressed Play.

signal load_completed(path: String, resource: Resource)
signal load_failed(path: String, status: int)
signal load_progress_changed(path: String, ratio: float)

var _loaded: Dictionary = {}
var _in_flight: Dictionary = {}
var _failed: Dictionary = {}


func _ready() -> void:
	# The pause menu leaves the tree paused on its way back to the menu, and a loader
	# that stops polling there would never finish what it started.
	process_mode = PROCESS_MODE_ALWAYS
	set_process(false)


func _process(_delta: float) -> void:
	poll()


## Starts a background load, or does nothing if the path is already loaded or running.
##
## A path already in Godot's cache finishes synchronously, so callers decide what to do
## with is_loaded() rather than by waiting for load_completed.
func request(path: String) -> void:
	if _loaded.has(path) or _in_flight.has(path):
		return
	_failed.erase(path)
	# Checked here rather than left to the worker: load_threaded_request accepts a path
	# that does not exist and only reports it a poll or two later, which would leave the
	# transition manager waiting on a level that is never coming.
	if not ResourceLoader.exists(path):
		_fail(path, ERR_FILE_NOT_FOUND)
		return
	if ResourceLoader.has_cached(path):
		_finish(path, ResourceLoader.load(path))
		return
	# use_sub_threads stays off: parallelising sub-resources buys little over moving the
	# load off the main thread at all, and has a history of deadlocking.
	var error := ResourceLoader.load_threaded_request(path, "", false)
	if error != OK:
		_fail(path, error)
		return
	_in_flight[path] = 0.0
	set_process(true)


func is_loaded(path: String) -> bool:
	return _loaded.has(path)


func has_failed(path: String) -> bool:
	return _failed.has(path)


func progress_of(path: String) -> float:
	if _loaded.has(path):
		return 1.0
	return _in_flight.get(path, 0.0)


## The finished resource, or null when it is not ready. Never blocks.
func take(path: String) -> Resource:
	return _loaded.get(path)


## Drops our reference so the engine can collect it. A load still in flight is left
## alone, because cancelling one is not something ResourceLoader offers.
func forget(path: String) -> void:
	_loaded.erase(path)
	_failed.erase(path)


## Advances every in-flight load one step. Called for you each frame; public so a test
## can step the machine without waiting on the clock.
func poll() -> void:
	# keys() is a copy, so _poll_one erasing from _in_flight mid-loop is safe.
	for path: String in _in_flight.keys():
		_poll_one(path)
	if _in_flight.is_empty():
		set_process(false)


func _poll_one(path: String) -> void:
	var progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(path, progress)
	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			var ratio: float = progress[0] if not progress.is_empty() else 0.0
			_in_flight[path] = ratio
			load_progress_changed.emit(path, ratio)
		ResourceLoader.THREAD_LOAD_LOADED:
			# Only ever called once the status says so: load_threaded_get blocks the
			# calling thread when the load is still running, which on web is the freeze
			# this whole system exists to avoid.
			_finish(path, ResourceLoader.load_threaded_get(path))
		_:
			_fail(path, status)


func _finish(path: String, resource: Resource) -> void:
	_in_flight.erase(path)
	_loaded[path] = resource
	load_progress_changed.emit(path, 1.0)
	load_completed.emit(path, resource)


func _fail(path: String, status: int) -> void:
	_in_flight.erase(path)
	_failed[path] = status
	push_warning("AsyncLoader could not load '%s' (status %d)." % [path, status])
	load_failed.emit(path, status)
