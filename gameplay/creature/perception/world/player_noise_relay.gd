class_name PlayerNoiseRelay
extends Node

## Turns what a player is doing into NoiseEvents the creature can hear.
##
## NOTHING IN THIS PROJECT EMITTED A NoiseEvent BEFORE THIS FILE. Both creature sandboxes say
## so and call `receive_noise` by hand; `PlayerNoiseEmitter` computes exactly the right thing
## and publishes it to nobody, and its `to_stimulus()` is commented out around a reference to
## an `AlienPerception` class that was never built. This is the missing wire.
##
## DUCK-TYPED ON THE SIGNAL, so nothing under gameplay/ gains a dependency on
## prefabs/character/player/. Anything that emits
## `noise_emitted(strength: float, at: Vector3, source: int)` will drive it, which is what
## lets a sandbox stand-in and the real prefab use the same relay.
##
## ONE CHANNEL PER EMITTER, and the reason is that a player is not one noise source.
## PlayerNoiseEmitter reports the loudest thing happening at the body; PlayerBeamNoiseEmitter
## reports the mining cut out at the end of the beam, which can be six metres away through a
## different wall. A single latest-wins slot made those two overwrite each other, so whichever
## announced last was the only one the creature ever heard -- and two PLAYERS in a session hit
## the same bug. Each channel carries its own strength, position and interval.
##
## It lives in `world/` for the reason `behavior/world/creature_nest.gd` does: it is the
## level-side attachment point of a creature module rather than part of the creature.

## Indexed by PlayerNoise.Source, whose order is THRUST, MINING, IMPACT. The tags are
## free-form and pass through Perception untouched -- Suspicion is what decides whether a
## drill matters more than a footstep.
const CATEGORIES: Array[StringName] = [&"thrust", &"mining", &"impact"]
## The group PlayerNoiseEmitter puts itself in.
const EMITTER_GROUP: StringName = &"noise_emitter"

@export var perception: CreaturePerception = null
## Explicit wiring wins; the group is the fallback, the same way nests and targets work.
@export var emitters: Array[Node] = []

## Strength that maps to a loudness of 1.0.
##
## PlayerSettings.mining_noise_strength is 10.0 and thrust_noise_strength is 6.0, so at this
## scale drilling arrives as 1.0 and thrusting as 0.6 -- straddling the hand-tuned
## QUIET_LOUDNESS 0.25 / LOUD_LOUDNESS 1.0 pair both existing sandboxes already use.
## NoiseEvent.loudness is nominally 0..1 and the player scale is 0..20, so something has to
## convert, and doing it here keeps PlayerSettings free of the creature's units.
@export_range(0.1, 40.0, 0.1) var noise_scale: float = 10.0
## How often a held noise is re-announced while it continues.
##
## LOAD-BEARING RATHER THAN POLITE, and it is a rate limit in BOTH directions.
##
## Upward: `CreaturePerception.receive_noise` has no throttle of its own and every call
## writes a record into a ring capped at SuspicionConfig.max_evidence_count (64). A relay
## firing at the frame rate would evict a minute of real evidence with its own duplicates
## inside a second -- the same storm BehaviorConfig.search_cooldown_s exists to prevent.
## Enforced PER CHANNEL, so adding an emitter adds a trickle rather than removing the limit.
##
## Downward: PlayerNoiseEmitter only re-announces on a CHANGE_EPSILON (0.05) LEVEL CHANGE, so
## a player holding the drill announces once and then goes silent. A drill is a repeating
## noise, and a creature that heard the first second of one and nothing after would lose the
## trail while the player was still making it.
@export_range(0.05, 5.0, 0.05, "suffix:s") var emit_interval_s: float = 0.5

## The relay's own clock, from the delta it is handed. Never a wall clock.
var clock: float = 0.0

var _channels: Dictionary = {}


func _ready() -> void:
	bind_all()


func _physics_process(delta: float) -> void:
	advance(delta)


## The tick entry point, public so a test or a headless tool can drive it exactly.
func advance(delta: float) -> void:
	clock += delta
	if perception == null:
		return
	var stale: Array[int] = []
	for key: int in _channels:
		var channel: NoiseChannel = _channels[key]
		# An emitter can be freed under a live level -- a player disconnecting, a prefab
		# reloaded. Its channel would otherwise go on announcing its last known noise from
		# its last known position for the rest of the session.
		if not is_instance_valid(channel.emitter):
			stale.append(key)
			continue
		if channel.strength <= 0.0 or clock < channel.next_emit_at:
			continue
		channel.next_emit_at = clock + emit_interval_s
		perception.receive_noise(
			NoiseEvent.make(
				channel.at,
				_loudness(channel.strength),
				_category(channel.source),
				channel.player,
				channel.player
			)
		)
	for key: int in stale:
		_channels.erase(key)


## Explicit emitters, then the group. Idempotent, so it is safe to call after spawning.
func bind_all() -> void:
	for node: Node in emitters:
		bind(node)
	if not emitters.is_empty() or not is_inside_tree():
		return
	for node: Node in get_tree().get_nodes_in_group(EMITTER_GROUP):
		bind(node)


## Connects one emitter. Anything with the signal will do; nothing is type-checked, so a
## sandbox stand-in and the real PlayerNoiseEmitter drive this identically.
func bind(emitter: Node) -> void:
	if emitter == null or not emitter.has_signal(&"noise_emitted"):
		return
	var key: int = emitter.get_instance_id()
	if _channels.has(key):
		return
	var channel := NoiseChannel.new()
	channel.emitter = emitter
	_channels[key] = channel
	emitter.connect(&"noise_emitted", _on_noise_emitted.bind(emitter))


## Everything the debug panel or a test wants, without growing an accessor per field.
##
## The single-value keys describe the LOUDEST live channel, which is what the old one-slot
## relay reported and what a one-line readout wants; `channels` is how you tell that from a
## relay that has only ever bound one emitter.
func debug_state() -> Dictionary:
	var loudest: NoiseChannel = _loudest_channel()
	var strength: float = loudest.strength if loudest != null else 0.0
	var source: int = loudest.source if loudest != null else 0
	var next_at: float = loudest.next_emit_at if loudest != null else clock
	return {
		"clock": clock,
		"strength": strength,
		"loudness": _loudness(strength),
		"category": _category(source),
		"bound": _channels.size(),
		"channels": _channels.size(),
		"next_emit_in": maxf(next_at - clock, 0.0),
	}


## Clamped, because a NoiseEvent's loudness is nominally 0..1 and Hearing attenuates from
## there. A player scale that ran past the cap would arrive as a noise louder than any the
## perception config was tuned against.
func _loudness(strength: float) -> float:
	return clampf(strength / maxf(noise_scale, 0.001), 0.0, 1.0)


func _category(source: int) -> StringName:
	return CATEGORIES[source] if source >= 0 and source < CATEGORIES.size() else &""


func _loudest_channel() -> NoiseChannel:
	var best: NoiseChannel = null
	for key: int in _channels:
		var channel: NoiseChannel = _channels[key]
		if best == null or channel.strength > best.strength:
			best = channel
	return best


## Held rather than emitted on the spot. The emitter announces on a LEVEL CHANGE and the
## relay announces on an INTERVAL, so the two rate limits compose instead of fighting: a
## change that arrives mid-interval updates what the next event will say without adding one.
func _on_noise_emitted(strength: float, at: Vector3, source: int, emitter: Node) -> void:
	var channel: NoiseChannel = _channels.get(emitter.get_instance_id())
	if channel == null:
		return
	var was_silent: bool = channel.strength <= 0.0
	channel.strength = strength
	channel.at = at
	channel.source = source
	# Resolved per announcement rather than at bind time: a component's `body` is an @onready
	# and is null for the frame the relay may have bound it on.
	channel.player = _body_of(emitter)
	# A noise STARTING is heard now, not up to emit_interval_s later. A drill spun up the
	# instant after a scheduled emit would otherwise be inaudible for half a second, which is
	# long enough to walk out of the room that heard nothing.
	if was_silent and strength > 0.0:
		channel.next_emit_at = clock


## Who the noise is attributed to, which is what lets Suspicion build a player candidate
## rather than only a hotspot.
##
## PlayerNoiseEmitter is a COMPONENT and holds its CharacterBody3D as `body`; a sandbox
## stand-in is usually the player node itself. Preferring `body`, then the parent, then the
## emitter covers all three without the relay knowing which it has.
static func _body_of(emitter: Node) -> Node:
	var body: Node = emitter.get(&"body") as Node
	if body != null:
		return body
	return emitter.get_parent() if emitter.get_parent() != null else emitter


## One emitter's held noise. Two emitters on one player -- the body and the beam endpoint --
## are two of these, and so are two players.
class NoiseChannel:
	extends RefCounted

	var emitter: Node = null
	var strength: float = 0.0
	var at: Vector3 = Vector3.ZERO
	var source: int = 0
	var player: Node = null
	var next_emit_at: float = 0.0
