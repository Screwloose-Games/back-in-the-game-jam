class_name SuspicionHotspotField
extends RefCounted

## Turns a pile of individual observations into the handful of PLACES the creature
## currently cares about (suspicion.md, "Suspicion Hotspots").
##
## Rebuilt from the live evidence every update, with one thing carried across the
## rebuild: the id. Clusters are matched to existing hotspots by shared contributing
## evidence, so a hotspot that grows, shrinks and drifts is still the same hotspot.
## Without that, `hotspot_created` and `hotspot_resolved` would fire several times a
## second for a single unchanging suspicion, and no consumer could tell "the creature
## has a new lead" from "the creature recomputed".
##
## HOW MUCH OF A HOTSPOT HAS BEEN SEARCHED IS NOT STORED ANYWHERE. It is answered by
## sampling: each piece of evidence's own uncertainty kernel is weighed against the
## disconfirmation records covering that volume, so searching one end of a wide,
## vague noise hotspot suppresses only the part actually swept. A stored per-sample
## "resolved" mark would have to be migrated every time the hotspot moved, and the
## spec's whole point is that hotspots move.

## Fibonacci-sphere increment, PI * (3 - sqrt(5)). Gives an even spread of directions
## from a plain integer index, with no RNG -- which matters because two creatures, or
## the same creature twice, must sample identically or the tests cannot assert where it
## searches next. Written as a literal because sqrt() is not a constant expression.
const GOLDEN_ANGLE: float = 2.399963229728653
## Additive low-discrepancy sequence for the radial coordinate. Pairing it with the
## angular sequence keeps depth and direction from correlating -- share one index for
## both and every sample near the top of the sphere is also near its centre.
const RADIAL_INCREMENT: float = 0.6180339887498949
## Below this the kernel-weighted suppression average is meaningless, and the record's
## own position is the honest answer.
const MIN_KERNEL_MASS: float = 0.000001

var config: SuspicionConfig = null
## Optional Vector3 -> int. See CreatureSuspicion.region_resolver.
var region_resolver: Callable = Callable()

var hotspots: Array[SuspicionHotspot] = []

var _next_id: int = 1


## Recompute the whole field. Returns `{created, updated, resolved}`, each an
## Array[int] of hotspot ids, for the facade to turn into signals -- emitting from in
## here would let a listener re-enter the field mid-rebuild.
func rebuild(memory: SuspicionEvidenceMemory, now: float) -> Dictionary:
	var created: Array[int] = []
	var updated: Array[int] = []
	var resolved: Array[int] = []
	if config == null:
		return {"created": created, "updated": updated, "resolved": resolved}

	var clusters: Array = _cluster(memory.live_records(now))
	var claimed: Dictionary = {}
	var surviving: Array[SuspicionHotspot] = []

	for cluster: Array in clusters:
		var existing: SuspicionHotspot = _match_existing(cluster, claimed)
		var hotspot: SuspicionHotspot = existing
		if hotspot == null:
			hotspot = SuspicionHotspot.new()
			hotspot.created_at = now
		else:
			claimed[hotspot.id] = true
		_apply_cluster(hotspot, cluster, memory, now, existing == null)

		if hotspot.suspicion < config.resolved_hotspot_threshold:
			# Below the threshold it is not a hotspot. An existing one has just been
			# resolved; a would-be new one is never announced at all, because a
			# created/resolved pair in the same tick is noise, not news.
			if existing != null:
				resolved.append(hotspot.id)
			continue
		if existing == null:
			hotspot.id = _next_id
			_next_id += 1
			claimed[hotspot.id] = true
			created.append(hotspot.id)
		else:
			updated.append(hotspot.id)
		surviving.append(hotspot)

	for hotspot: SuspicionHotspot in hotspots:
		if not claimed.has(hotspot.id):
			resolved.append(hotspot.id)
	hotspots = surviving
	return {"created": created, "updated": updated, "resolved": resolved}


func find(id: int) -> SuspicionHotspot:
	for hotspot: SuspicionHotspot in hotspots:
		if hotspot.id == id:
			return hotspot
	return null


func strongest() -> SuspicionHotspot:
	var best: SuspicionHotspot = null
	for hotspot: SuspicionHotspot in hotspots:
		if best == null or hotspot.suspicion > best.suspicion:
			best = hotspot
	return best


func above(minimum_suspicion: float) -> Array[SuspicionHotspot]:
	var found: Array[SuspicionHotspot] = []
	for hotspot: SuspicionHotspot in hotspots:
		if hotspot.suspicion >= minimum_suspicion:
			found.append(hotspot)
	found.sort_custom(
		func(a: SuspicionHotspot, b: SuspicionHotspot) -> bool: return a.suspicion > b.suspicion
	)
	return found


## Where inside this hotspot the creature has the most reason to look, given
## everywhere it has already checked. This is the spec's "best unresolved location".
func best_unresolved_point(
	hotspot: SuspicionHotspot, memory: SuspicionEvidenceMemory, now: float
) -> Vector3:
	var best_point: Vector3 = hotspot.position
	var best_value: float = -1.0
	for point: Vector3 in sample_points(hotspot):
		var value: float = memory.unresolved_at(point, now)
		if value > best_value:
			best_value = value
			best_point = point
	return best_point


## A deterministic cloud of points filling the hotspot -- the spec's sample diagram,
## generated rather than stored.
##
## The centre is always sample 0, so the answer degrades to "the middle of the
## hotspot" rather than to an arbitrary offset point when the count is 1 or the radius
## is 0.
func sample_points(hotspot: SuspicionHotspot) -> PackedVector3Array:
	var points := PackedVector3Array([hotspot.position])
	if config == null or hotspot.radius <= 0.0:
		return points
	for index: int in maxi(config.hotspot_sample_count - 1, 0):
		var t: float = (float(index) + 0.5) / float(maxi(config.hotspot_sample_count - 1, 1))
		var height: float = 1.0 - 2.0 * t
		var ring: float = sqrt(maxf(1.0 - height * height, 0.0))
		var angle: float = float(index) * GOLDEN_ANGLE
		var direction := Vector3(cos(angle) * ring, height, sin(angle) * ring)
		# Cube root, so the points fill the VOLUME evenly. A linear radius crowds them
		# into the centre and the outer shell of a wide hotspot goes unsearched.
		var depth: float = fposmod(float(index + 1) * RADIAL_INCREMENT, 1.0)
		points.append(hotspot.position + direction * hotspot.radius * pow(depth, 1.0 / 3.0))
	return points


func clear() -> void:
	hotspots.clear()


# ----- clustering -----


## Single-link agglomeration at hotspot_merge_distance. Records arrive strongest-first
## from live_records(), so the strongest observation seeds each cluster and the result
## does not depend on the order things were perceived in.
func _cluster(live: Array[SuspicionEvidenceRecord]) -> Array:
	var clusters: Array = []
	for record: SuspicionEvidenceRecord in live:
		var joined: bool = false
		for cluster: Array in clusters:
			if _belongs_to(record, cluster):
				cluster.append(record)
				joined = true
				break
		if not joined:
			clusters.append([record] as Array)
	return clusters


func _belongs_to(record: SuspicionEvidenceRecord, cluster: Array) -> bool:
	for member: SuspicionEvidenceRecord in cluster:
		if member.position.distance_to(record.position) > config.hotspot_merge_distance:
			continue
		if _same_region(member.position, record.position):
			return true
	return false


## The thin-cave-wall rule. Off by default and a no-op without a resolver, so this
## costs nothing until Spatial Memory (or a level) supplies one -- and Suspicion never
## has to touch physics to ask the question.
func _same_region(a: Vector3, b: Vector3) -> bool:
	if not config.require_same_spatial_region_for_merge or not region_resolver.is_valid():
		return true
	return int(region_resolver.call(a)) == int(region_resolver.call(b))


## The existing hotspot sharing the most evidence with this cluster. Overlap rather
## than proximity: a hotspot that has drifted five metres is still the same belief,
## and two hotspots that happen to be close are not.
func _match_existing(cluster: Array, claimed: Dictionary) -> SuspicionHotspot:
	var best: SuspicionHotspot = null
	var best_overlap: int = 0
	for hotspot: SuspicionHotspot in hotspots:
		if claimed.has(hotspot.id):
			continue
		var overlap: int = 0
		for record: SuspicionEvidenceRecord in cluster:
			if hotspot.contributing_evidence_ids.has(record.id):
				overlap += 1
		if overlap > best_overlap:
			best_overlap = overlap
			best = hotspot
	return best


# ----- per-hotspot maths -----


func _apply_cluster(
	hotspot: SuspicionHotspot,
	cluster: Array,
	memory: SuspicionEvidenceMemory,
	now: float,
	is_new: bool
) -> void:
	var total: float = 0.0
	var centroid := Vector3.ZERO
	var confidence: float = 0.0
	var ids: Array[int] = []
	for record: SuspicionEvidenceRecord in cluster:
		var strength: float = record.effective_strength(now)
		total += strength
		centroid += record.position * strength
		confidence += record.confidence * strength
		ids.append(record.id)

	if total <= 0.0:
		hotspot.suspicion = 0.0
		hotspot.contributing_evidence_ids = ids
		return

	# Read BEFORE last_updated_at is overwritten -- this is how long the attribution
	# below has had to move.
	var elapsed: float = 0.0 if is_new else maxf(now - hotspot.last_updated_at, 0.0)

	var target: Vector3 = centroid / total
	# Smoothed, so a new loud noise DRAGS the hotspot toward itself over a few updates
	# rather than teleporting it -- which is what makes a fleeing player produce a
	# hotspot that follows them instead of a sequence of unrelated ones.
	hotspot.position = (
		target if is_new else hotspot.position.lerp(target, config.hotspot_position_smoothing)
	)
	hotspot.radius = _radius_for(hotspot.position, cluster)
	hotspot.confidence = clampf(confidence / total, 0.0, 1.0)
	hotspot.contributing_evidence_ids = ids
	hotspot.last_updated_at = now

	var unresolved: float = _unresolved_total(hotspot, cluster, memory, now)
	hotspot.suspicion = config.saturate(unresolved, config.hotspot_saturation_rate)
	hotspot.investigation_progress = clampf(1.0 - unresolved / total, 0.0, 1.0)
	_associate_source(hotspot, cluster, elapsed, is_new)


## Big enough to contain everywhere the contributing evidence says the activity might
## have been -- distance to the record PLUS that record's own uncertainty. A hotspot
## sized to the evidence positions alone would tell Behavior to search a point when
## what perception actually reported was a twelve-metre sphere.
func _radius_for(centre: Vector3, cluster: Array) -> float:
	var radius: float = 0.0
	for record: SuspicionEvidenceRecord in cluster:
		radius = maxf(radius, centre.distance_to(record.position) + record.uncertainty_radius)
	return clampf(radius, SuspicionEvidenceRecord.MIN_KERNEL_RADIUS, config.hotspot_max_radius)


## Suspicion still unaccounted for, after everywhere the creature has searched.
##
## Each record is suppressed by the average disconfirmation over ITS OWN kernel, not
## by the disconfirmation at its reported position. That distinction is the spec's
## central example: one sweep at the centre of a vague twelve-metre noise has checked
## a small fraction of where the player might be, and must not be allowed to clear the
## whole record.
func _unresolved_total(
	hotspot: SuspicionHotspot, cluster: Array, memory: SuspicionEvidenceMemory, now: float
) -> float:
	var points: PackedVector3Array = sample_points(hotspot)
	var suppression := PackedFloat32Array()
	for point: Vector3 in points:
		suppression.append(memory.suppression_at(point, now))

	var unresolved: float = 0.0
	for record: SuspicionEvidenceRecord in cluster:
		var mass: float = 0.0
		var weighted: float = 0.0
		for index: int in points.size():
			var kernel: float = record.spatial_weight(points[index])
			mass += kernel
			weighted += kernel * suppression[index]
		var checked: float = (
			weighted / mass
			if mass > MIN_KERNEL_MASS
			else memory.suppression_at(record.position, now)
		)
		unresolved += record.effective_strength(now) * (1.0 - clampf(checked, 0.0, 1.0))
	return unresolved


## Move the hotspot's belief about WHO toward whichever contributor is most confidently
## attributed, so an anonymous hotspot can become "probably Player 1" once a sighting
## lands in it -- the spec's worked example under "Player Suspicion".
func _associate_source(
	hotspot: SuspicionHotspot, cluster: Array, elapsed: float, is_new: bool
) -> void:
	# A player who left the game must not keep a hotspot named after them, and reading
	# any property off the freed node would take the creature down with it.
	if not is_instance_valid(hotspot.likely_source):
		hotspot.likely_source = null
		hotspot.source_confidence = 0.0

	var best: SuspicionEvidenceRecord = _best_attributed(cluster)
	# Nothing in the cluster still names this player: the attribution fades rather than
	# being dropped outright, so one update without a sighting does not un-identify a
	# player the creature has been chasing. A better-attributed rival replaces them
	# immediately; a worse one does not.
	if (
		best == null
		or (
			hotspot.likely_source != best.source_player
			and best.source_confidence <= hotspot.source_confidence
		)
	):
		hotspot.source_confidence *= exp(-config.source_association_decay * elapsed)
		if hotspot.source_confidence < 0.01:
			hotspot.likely_source = null
			hotspot.source_confidence = 0.0
		return

	if hotspot.likely_source != best.source_player:
		hotspot.likely_source = best.source_player
		hotspot.source_confidence = 0.0
	if is_new:
		hotspot.source_confidence = best.source_confidence
		return
	var approach: float = 1.0 - exp(-config.source_association_gain * maxf(elapsed, 0.0))
	hotspot.source_confidence += (best.source_confidence - hotspot.source_confidence) * approach


func _best_attributed(cluster: Array) -> SuspicionEvidenceRecord:
	var best: SuspicionEvidenceRecord = null
	for record: SuspicionEvidenceRecord in cluster:
		if record.source_confidence <= 0.0 or not is_instance_valid(record.source_player):
			continue
		if best == null or record.source_confidence > best.source_confidence:
			best = record
	return best
