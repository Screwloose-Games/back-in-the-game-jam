class_name SuspicionPlayerBeliefs
extends RefCounted

## How much of what the creature has perceived it attributes to each particular player
## (suspicion.md, "Player Suspicion").
##
## Deliberately NOT derived from the hotspots. A hotspot belongs to a place, and the
## same player can be responsible for three of them; conversely a hotspot can be
## strong and completely anonymous. The Director asks "who", the HFSM asks "where",
## and collapsing the two answers into one number loses whichever the caller needed.
##
## Entries are keyed by INSTANCE ID, not by the Node. A player who disconnects mid-run
## leaves a freed object behind, and a freed object sitting in a Dictionary as a key is
## a crash waiting for the next iteration. An id is just an int: it goes stale, which
## is checked, rather than dangling.
##
## Two axes are tracked separately because the Director needs both. "I am sure Player 2
## is behind all this faint noise" and "something alarming happened and it might be
## Player 1" are different situations that a single blended number cannot express.

var config: SuspicionConfig = null

var _entries: Dictionary = {}


## Fold one attributed record into its player's belief. Records with no attribution are
## ignored here entirely -- they still make the creature suspicious, just not of anyone
## in particular, which is the "hotspot .74, likely_source unknown" case in the spec.
func observe(record: SuspicionEvidenceRecord, now: float) -> Node:
	if config == null or record == null:
		return null
	if record.source_confidence <= 0.0 or not is_instance_valid(record.source_player):
		return null
	var id: int = record.source_player.get_instance_id()
	var first_sighting: bool = not _entries.has(id)
	var entry: PlayerEntry = _entry_for(record.source_player)
	entry.support += record.effective_strength(now) * record.source_confidence
	entry.target_confidence = maxf(entry.target_confidence, record.source_confidence)
	entry.last_evidence_at = now
	# source_association_gain governs how attribution STRENGTHENS, not how long it takes
	# to notice someone at all. With no prior belief there is nothing to ramp from, and
	# ramping anyway means the creature spends the first second after seeing a player
	# clearly reporting that it is not sure who that was.
	if first_sighting:
		entry.confidence = record.source_confidence
	return record.source_player


## Age every belief. Called from the facade's tick, and the only place time enters.
func advance(delta: float) -> void:
	if config == null or delta <= 0.0:
		return
	var fade: float = exp(-config.source_association_decay * delta)
	var approach: float = 1.0 - exp(-config.source_association_gain * delta)
	for id: int in _entries.keys():
		if not is_instance_valid(instance_from_id(id)):
			_entries.erase(id)
			continue
		var entry: PlayerEntry = _entries[id]
		entry.support *= fade
		entry.confidence += (entry.target_confidence - entry.confidence) * approach
		entry.target_confidence *= fade
		if entry.support < 0.001 and entry.confidence < 0.01:
			_entries.erase(id)


func get_suspicion(player: Node) -> float:
	var entry: PlayerEntry = _find(player)
	if entry == null:
		return 0.0
	return config.saturate(entry.support, config.player_suspicion_saturation_rate)


func get_source_confidence(player: Node) -> float:
	var entry: PlayerEntry = _find(player)
	return 0.0 if entry == null else clampf(entry.confidence, 0.0, 1.0)


## The player the creature is most suspicious of, or null. A CANDIDATE, not a target:
## stickiness, retarget thresholds and encounter pacing are all the Director's, and
## Suspicion knows nothing about any of them.
func get_best_candidate() -> PlayerSuspicionCandidate:
	var best: PlayerSuspicionCandidate = null
	for candidate: PlayerSuspicionCandidate in get_candidates():
		if best == null or candidate.suspicion > best.suspicion:
			best = candidate
	return best


## Every tracked player, strongest first.
func get_candidates() -> Array[PlayerSuspicionCandidate]:
	var candidates: Array[PlayerSuspicionCandidate] = []
	if config == null:
		return candidates
	for id: int in _entries:
		var player := instance_from_id(id) as Node
		if not is_instance_valid(player):
			continue
		var entry: PlayerEntry = _entries[id]
		candidates.append(
			PlayerSuspicionCandidate.make(
				player,
				config.saturate(entry.support, config.player_suspicion_saturation_rate),
				clampf(entry.confidence, 0.0, 1.0),
				entry.last_evidence_at
			)
		)
	candidates.sort_custom(
		func(a: PlayerSuspicionCandidate, b: PlayerSuspicionCandidate) -> bool:
			return a.suspicion > b.suspicion
	)
	return candidates


func clear() -> void:
	_entries.clear()


func _entry_for(player: Node) -> PlayerEntry:
	var id: int = player.get_instance_id()
	if not _entries.has(id):
		_entries[id] = PlayerEntry.new()
	return _entries[id]


func _find(player: Node) -> PlayerEntry:
	if config == null or not is_instance_valid(player):
		return null
	var id: int = player.get_instance_id()
	return _entries[id] if _entries.has(id) else null


## One player's accumulated attribution. `support` is unbounded and saturates on read;
## `confidence` is 0..1 and chases the best recent attribution.
class PlayerEntry:
	extends RefCounted

	var support: float = 0.0
	var confidence: float = 0.0
	## Best attribution seen recently, which `confidence` climbs toward. Fades on its
	## own so a single old sighting cannot hold confidence up forever.
	var target_confidence: float = 0.0
	var last_evidence_at: float = 0.0
