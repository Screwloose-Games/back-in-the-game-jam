class_name NoiseEvent
extends RefCounted

## One noise the world actually emitted, before any creature has heard it.
##
## THIS IS WORLD STATE, NOT PERCEPTION. `loudness` is what the drill produced, not
## what anything received -- distance, obstruction and creature sensitivity are
## applied later by CreatureHearing (perception.md section 11). Emitters therefore
## never need to know a creature exists, and two creatures at different distances
## receive different strengths from one event.

var position: Vector3 = Vector3.ZERO
## Raw emitted loudness, nominally 0..1. Not attenuated.
var loudness: float = 1.0
## Whatever made the noise. May be a prop, a door, or a player's tool.
var source: Node = null
## The player responsible, when one is. Null for world noises (rockfall, machinery).
var source_player: Node = null
## Free-form tag: &"drill", &"footstep", &"impact". Perception passes it through
## untouched; Suspicion is what decides whether a drill matters more than a footstep.
var category: StringName = &""


## Named factory rather than a six-argument `_init`. `_init` with required args
## takes `new()` away entirely, which every test fixture and every DTO copy wants.
static func make(
	p_position: Vector3,
	p_loudness: float,
	p_category: StringName = &"",
	p_source: Node = null,
	p_source_player: Node = null
) -> NoiseEvent:
	var event := NoiseEvent.new()
	event.position = p_position
	event.loudness = p_loudness
	event.category = p_category
	event.source = p_source
	event.source_player = p_source_player
	return event


func to_dictionary() -> Dictionary:
	return {
		"position": position,
		"loudness": loudness,
		"category": category,
		"has_source": source != null,
		"has_source_player": source_player != null,
	}
