extends Node

signal on_scene_changed
signal faded_out
signal faded_in


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS


func change_scene(scene: PackedScene):
	get_tree().change_scene_to_packed(scene)
	get_tree().tree_changed.connect(trigger_scene_changed_signal)


func change_scene_with_transition(scene: PackedScene, transition: PackedScene):
	var transition_instance: Transition = transition.instantiate()

	transition_instance.on_fade_out.connect(_on_fade_out.bind(scene, transition_instance))
	transition_instance.on_fade_in.connect(_on_fade_in.bind(transition_instance))

	add_child(transition_instance)


## Fades out, holds a loading screen over the black until the scene is in memory, then
## swaps to it and fades back in.
##
## Takes a path rather than a PackedScene because that is the whole point: reading a
## PackedScene off SceneManager is what loads it, and this needs to decide when.
func change_scene_to_path(path: String, transition: PackedScene) -> void:
	var transition_instance: Transition = transition.instantiate()

	transition_instance.on_fade_out.connect(_on_load_fade_out.bind(path, transition_instance))
	transition_instance.on_fade_in.connect(_on_fade_in.bind(transition_instance))

	add_child(transition_instance)


func _on_load_fade_out(path: String, transition_instance: Transition) -> void:
	faded_out.emit()
	# The warm case: something already loaded this, so there is nothing to wait behind
	# and a loading screen would only be a flash of one.
	if not AsyncLoader.is_loaded(path):
		await _load_behind_screen(path)
	var scene: PackedScene = AsyncLoader.take(path)
	if scene == null:
		# The threaded load failed. Falling back to a blocking load costs a hitch but
		# still gets the player into the game, which beats a black screen forever.
		scene = load(path)
	change_scene(scene)
	transition_instance.fade_in()


## Shows the loading screen until the path is in memory. The screen is parented to this
## autoload, the same trick the transition uses to survive change_scene_to_packed.
func _load_behind_screen(path: String) -> void:
	var screen: LoadingScreen = SceneManager.loading_screen.instantiate()
	add_child(screen)
	AsyncLoader.request(path)
	# Leaves on failure as well as success, so a path that cannot load cannot hang here.
	while not AsyncLoader.is_loaded(path) and not AsyncLoader.has_failed(path):
		screen.set_progress(AsyncLoader.progress_of(path))
		await get_tree().process_frame
	await screen.complete()
	screen.queue_free()


func _on_fade_out(new_scene: PackedScene, transition_instance: Transition):
	faded_out.emit()
	change_scene(new_scene)
	transition_instance.fade_in()


func _on_fade_in(transition_instance: Transition):
	faded_in.emit()
	transition_instance.queue_free()


func trigger_scene_changed_signal():
	on_scene_changed.emit()
	get_tree().tree_changed.disconnect(trigger_scene_changed_signal)
