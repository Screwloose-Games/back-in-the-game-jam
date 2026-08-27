class_name ClingerEars
extends Node

## The clinger's whole perception: the same noise stream the stalker reads, and nothing
## else. It binds every emitter carrying `noise_emitted` and HOLDS what each last said,
## because an emitter only re-announces on a level change -- a held drill announces once
## and then goes silent, so a listener that treats the signal as a stream hears nothing.
##
## Deliberately deaf to `world_noise`. The clinger emits into that group, and one that
## also listened to it would spend the run hunting its own leap.

## The loudest thing it can currently hear, once per tick while there is one.
signal heard(at: Vector3, strength: float)

## How often a held noise re-reads where it is actually coming from. Without it a player
## flying at a constant throttle announces once and the clinger walks to where they were.
const REFRESH_INTERVAL := 0.4

@export var settings: PlayerSettings

## Explicit wiring wins and the group is the fallback, the same way PlayerNoiseRelay does
## it -- a sandbox stand-in and the real prefab then drive this identically.
@export var emitters: Array[Node] = []

var _channels: Dictionary = {}
var _refresh_left := 0.0


func _ready() -> void:
	bind_all()
	# The level spawns the player after its own _ready, so a clinger authored into a scene
	# readies with nothing to bind. Watching the tree is what makes placement order stop
	# mattering; bind() is idempotent, so the group scan and this cannot fight.
	get_tree().node_added.connect(_on_node_added)


## Explicit emitters first, then the group. Safe to call again at any time.
func bind_all() -> void:
	for node: Node in emitters:
		bind(node)
	if not emitters.is_empty() or not is_inside_tree():
		return
	for node: Node in get_tree().get_nodes_in_group(PlayerNoiseEmitter.EMITTER_GROUP):
		bind(node)


## Connects one emitter. Anything with the signal will do; nothing is type-checked.
func bind(emitter: Node) -> void:
	if emitter == null or not emitter.has_signal(&"noise_emitted"):
		return
	var key := emitter.get_instance_id()
	if _channels.has(key):
		return
	_channels[key] = {"emitter": emitter, "at": Vector3.ZERO, "strength": 0.0, "age": INF}
	emitter.connect(&"noise_emitted", _on_noise_emitted.bind(emitter))


## Ages every channel, refreshes the live ones, and reports the loudest audible noise.
func advance(delta: float, listener: Vector3) -> void:
	_refresh_left -= delta
	var refresh := _refresh_left <= 0.0
	if refresh:
		_refresh_left = REFRESH_INTERVAL

	var best: Dictionary = {}
	var loudest := 0.0
	for key: int in _channels.keys():
		var channel: Dictionary = _channels[key]
		if not is_instance_valid(channel["emitter"]):
			_channels.erase(key)
			continue
		channel["age"] = (channel["age"] as float) + delta
		if (channel["age"] as float) > settings.clinger_forget_seconds:
			continue
		if refresh:
			channel["at"] = _live_position(channel)
		var strength: float = channel["strength"]
		if strength <= loudest:
			continue
		if not ClingerState.hears(
			strength,
			channel["at"],
			listener,
			settings.clinger_wake_strength,
			settings.noise_metres_per_unit,
			settings.clinger_hearing_range
		):
			continue
		loudest = strength
		best = channel

	if not best.is_empty():
		heard.emit(best["at"], loudest)


func debug_state() -> Dictionary:
	return {"channels": _channels.size(), "refresh_left": _refresh_left}


## Where a held noise is coming from NOW. A beam reports its own endpoint, which can be
## six metres away through a different wall; anything else is coming from its own body.
func _live_position(channel: Dictionary) -> Vector3:
	var emitter: Node = channel["emitter"]
	if emitter.has_method(&"position_of_noise"):
		return emitter.call(&"position_of_noise")
	var body := emitter.get_parent() as Node3D
	return body.global_position if body != null else channel["at"]


func _on_noise_emitted(strength: float, at: Vector3, _source: int, emitter: Node) -> void:
	var channel: Dictionary = _channels.get(emitter.get_instance_id(), {})
	if channel.is_empty():
		return
	channel["strength"] = strength
	channel["at"] = at
	channel["age"] = 0.0


func _on_node_added(node: Node) -> void:
	# On the signal rather than on the group: a node is announced as it enters the tree,
	# and PlayerNoiseEmitter does not join its group until _ready, one step later.
	if node.has_signal(&"noise_emitted"):
		bind(node)
