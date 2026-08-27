class_name PlayerInteractor
extends Area3D

## The suit's reach: which Interactable you are addressing, and the primary interaction
## gesture on it. Tap and hold are told apart here rather than in PlayerInput, because
## only this component knows whether what you are pointed at has two verbs at all.

## The Interactable now being addressed, or null. One signal rather than a pair, so a
## prompt is one connection and can never end up showing two things at once.
signal focus_changed(interactable: Interactable)

signal interacted(interactable: Interactable)
signal hold_started(interactable: Interactable)
signal hold_progressed(fraction: float)
signal hold_completed(interactable: Interactable)
signal hold_cancelled

## One press, from the key going down to it coming back up.
enum Gesture {
	## Nothing is pressed.
	IDLE,
	## Down, and not yet long enough to have become a hold.
	PRESSED,
	## Down past the threshold, on something that supports holding.
	HOLDING,
	## Down but already spent -- the tap fired, the hold completed, or the press found
	## nothing. Waits for the key to come up so one press cannot fire twice.
	SPENT,
}

## After Tether (-30) and well after Locomotion (-80), so the head transform read here is
## the one this frame's flight already settled.
const PHYSICS_PRIORITY := -20

@export var settings: PlayerSettings

## A network driver owns this while true; see PlayerNetworkGameplay.
var externally_driven := false

var _candidates: Array[Interactable] = []
var _focused: Interactable
var _gesture: Gesture = Gesture.IDLE
var _gesture_target: Interactable
var _held_seconds := 0.0
var _pending_press := false
var _pending_release := false
var _seeded := false
var _sphere: SphereShape3D

@onready var body: CharacterBody3D = get_parent()
@onready var head: Node3D = %Head
@onready var input: PlayerInput = %Input
@onready var grab: PlayerGrab = %Grab
@onready var visibility: PlayerVisibility = %Visibility


func _ready() -> void:
	process_physics_priority = PHYSICS_PRIORITY
	if settings == null:
		settings = PlayerSettings.new()
		push_warning("PlayerInteractor has no settings; running on PlayerSettings defaults.")
	# A remote peer's copy has no prompt to draw and no business opening doors. The same
	# gate PlayerRadarDetector puts on the pulse and PlayerSfx on the helmet cues.
	if not visibility.is_local_player:
		monitoring = false
		set_physics_process(false)
		return
	# Reaching, never reachable. Masked to interactables alone, so the sphere never tests
	# against a wall.
	collision_layer = 0
	collision_mask = settings.interactable_layers
	monitorable = false
	monitoring = true
	_build_reach()
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)
	input.interact_pressed.connect(_on_interact_pressed)
	input.interact_released.connect(_on_interact_released)


## Physics rather than idle: overlaps are recomputed once per physics step, and hold time
## measured on the render clock would be frame-rate dependent.
func _physics_process(delta: float) -> void:
	if externally_driven:
		return
	# Seeded once as well as tracked by signal. Both paths are idempotent, and between
	# them nothing already overlapping at spawn can be missed -- which matters because
	# the level parks the life support cube about a metre and a half from PlayerSpawn.
	if not _seeded:
		_seeded = true
		_seed_candidates()
	# A cutscene or a pause takes the key away without ever sending a release.
	if not input.enabled:
		_cancel_gesture()
		_set_focus(null)
		return
	_drop_stale_candidates()
	# Focus is FROZEN for the length of a gesture. A twitch mid-hold must not be able to
	# finish that hold on a different object.
	if _gesture == Gesture.IDLE:
		_set_focus(_preferred_candidate())
	_step_gesture(delta)


func focused() -> Interactable:
	return _focused


## What a prompt should read, or "" when nothing is in reach.
func prompt() -> String:
	return "\n".join(prompt_lines())


func prompt_lines() -> PackedStringArray:
	return _focused.prompt_lines() if _focused != null else PackedStringArray()


func is_hold_active() -> bool:
	return _gesture == Gesture.HOLDING


func hold_fraction() -> float:
	if _gesture != Gesture.HOLDING or not is_instance_valid(_gesture_target):
		return 0.0
	return _gesture_target.hold_fraction()


func is_carrying() -> bool:
	return grab.is_holding()


## Puts a body in this player's hands, or puts it down when it is already there.
func toggle_carry(object: RigidBody3D, at: Vector3) -> void:
	if grab.is_holding():
		grab.release()
		return
	var hands := body.get_node_or_null("Hands") as PlayerHands
	if hands != null and not hands.can_take_hold():
		return
	grab.take_hold_of(object, at)


## Latched rather than acted on here: a tap that begins and ends between two physics
## frames would be invisible to a sampled boolean, and that is the window a tap lives in.
func _on_interact_pressed() -> void:
	_pending_press = true


func _on_interact_released() -> void:
	_pending_release = true


func _on_area_entered(area: Area3D) -> void:
	var interactable := area as Interactable
	if interactable == null or _candidates.has(interactable):
		return
	_candidates.append(interactable)


## The SAME cast as _on_area_entered, deliberately. The design this is ported from
## filtered on the class going in and on a group nothing ever joined coming out, so
## nothing was ever removed and the list filled with stale and freed entries.
func _on_area_exited(area: Area3D) -> void:
	var interactable := area as Interactable
	if interactable == null:
		return
	_candidates.erase(interactable)


func _seed_candidates() -> void:
	for area: Area3D in get_overlapping_areas():
		_on_area_entered(area)


## area_exited is not enough on its own: a freed parent, or a level torn down under a
## queue_free, retires an overlap without one ever arriving.
func _drop_stale_candidates() -> void:
	var index := _candidates.size() - 1
	while index >= 0:
		var candidate := _candidates[index]
		if not is_instance_valid(candidate) or not candidate.is_available():
			_candidates.remove_at(index)
		index -= 1


## What is in your hands outranks what is merely in reach, so one rule covers the whole
## carry: tap puts it down, hold works it, and the elevator waits until you have.
func _preferred_candidate() -> Interactable:
	var carried := _carried_candidate()
	return carried if carried != null else _best_candidate()


func _carried_candidate() -> Interactable:
	var held := grab.held_object()
	if held == null:
		return null
	for candidate: Interactable in _candidates:
		if held == candidate or held.is_ancestor_of(candidate):
			return candidate
	return null


func _best_candidate() -> Interactable:
	if _candidates.is_empty():
		return null
	var points := PackedVector3Array()
	for candidate: Interactable in _candidates:
		points.append(candidate.global_position)
	var index := InteractionFocus.best_candidate(
		head.global_transform,
		points,
		settings.interact_range,
		settings.interact_min_facing,
		settings.interact_facing_weight,
		_candidates.find(_focused),
		settings.interact_focus_stickiness
	)
	return _candidates[index] if index >= 0 else null


func _set_focus(next: Interactable) -> void:
	if next == _focused:
		return
	if is_instance_valid(_focused):
		_focused.unfocus(self)
	_focused = next
	if _focused != null:
		_focused.focus(self)
	focus_changed.emit(_focused)


func _step_gesture(delta: float) -> void:
	if _pending_press:
		_pending_press = false
		_begin_press()
	var released := _pending_release
	_pending_release = false
	if _gesture == Gesture.IDLE:
		return
	_held_seconds += delta
	if not _gesture_survives():
		_cancel_gesture()
		return
	_advance_press()
	# `not interact_held` is the fail-safe for a release edge that never arrived --
	# PlayerInput.clear() drops the key without emitting one.
	if released or not input.interact_held:
		_end_press()


## A press with nothing focused arms nothing: leaning on the key at empty space must not
## silently become a verb when something drifts into reach.
func _begin_press() -> void:
	_held_seconds = 0.0
	_gesture_target = _focused
	if _gesture_target == null or not _gesture_target.is_available():
		_gesture = Gesture.SPENT
		return
	_gesture = Gesture.PRESSED
	# Nothing with a single verb waits for the key to come up. The disambiguation delay
	# is paid only where there is actually something to disambiguate.
	if not _gesture_target.supports_hold():
		_fire_tap()
		_gesture = Gesture.SPENT


func _advance_press() -> void:
	if _gesture == Gesture.SPENT:
		return
	var threshold: float = settings.interact_hold_threshold
	if _gesture == Gesture.PRESSED:
		if not InteractionHold.is_hold(_held_seconds, threshold):
			return
		if not _gesture_target.begin_hold(self):
			_gesture = Gesture.SPENT
			return
		_gesture = Gesture.HOLDING
		hold_started.emit(_gesture_target)
	# The target ended it itself -- a latch that filled up. Spent rather than cancelled,
	# because the player is still holding the key and did nothing wrong.
	if not _gesture_target.is_holding():
		_gesture = Gesture.SPENT
		return
	var duration := _gesture_target.hold_duration()
	# A latch has no bar, so it publishes no progress -- one signal per frame saying zero
	# is noise a listener would only have to filter back out.
	if duration <= 0.0:
		return
	_gesture_target.report_hold(InteractionHold.progress(_held_seconds, threshold, duration))
	hold_progressed.emit(_gesture_target.hold_fraction())
	if not InteractionHold.is_complete(_held_seconds, threshold, duration):
		return
	# Fires the moment the bar fills, not on release: the hatch opens when it opens.
	if _gesture_target.complete_hold(self):
		hold_completed.emit(_gesture_target)
	_gesture = Gesture.SPENT


func _end_press() -> void:
	match _gesture:
		Gesture.PRESSED:
			_fire_tap()
		Gesture.HOLDING:
			_release_hold()
	_reset_gesture()


func _fire_tap() -> void:
	if _gesture_target == null or not _gesture_target.interact(self):
		return
	interacted.emit(_gesture_target)


## A gesture lives only while its target is alive, still available, and still in reach.
## Focus is frozen for the duration, but walking away still cancels.
func _gesture_survives() -> bool:
	if _gesture == Gesture.SPENT:
		return true
	if not is_instance_valid(_gesture_target):
		return false
	if not _gesture_target.is_available():
		return false
	return _candidates.has(_gesture_target)


func _cancel_gesture() -> void:
	if _gesture == Gesture.HOLDING:
		_release_hold()
	_reset_gesture()


## The interactable is told only when it is still there to tell; this component's own
## signal fires either way, so anything drawing progress always sees it come back down.
func _release_hold() -> void:
	if is_instance_valid(_gesture_target):
		_gesture_target.cancel_hold()
	hold_cancelled.emit()


func _reset_gesture() -> void:
	_gesture = Gesture.IDLE
	_gesture_target = null
	_held_seconds = 0.0


## Built rather than authored: a SphereShape3D saved in a .tscn is ONE resource shared by
## every instance of that scene, so two players would share one reach.
func _build_reach() -> void:
	_sphere = SphereShape3D.new()
	_sphere.radius = settings.interact_range
	var collider := CollisionShape3D.new()
	collider.shape = _sphere
	add_child(collider)
