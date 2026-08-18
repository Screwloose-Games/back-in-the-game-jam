class_name BtSearchArea
extends BtAction

## Asks Perception to sweep the area, and then stays out of the way.
##
## THE ALIEN DOES NOT DECIDE WHAT IT FINDS. A scan that turns up nothing emits a
## disconfirmation on its own, which suppresses the belief and eventually drops the hotspot;
## a scan that finds something emits evidence instead and suspicion goes UP. Both arrive
## through Perception, and neither is this file's to choose. Nothing here writes belief --
## that is the rule the whole design rests on, and it is enforced by the static verifier
## rather than by review.
##
## EDGE-TRIGGERED, BECAUSE THE REQUEST CAN COMPLETE INSIDE ITSELF. `request_activity_scan`
## finishes synchronously when Perception has no config, an unbound probe, or a zero-volume
## region -- so `is_activity_scan_active()` is already false when the call returns. An action
## that polled that flag blind would re-request every frame, and every request writes a
## zero-strength disconfirmation into a ring capped at 48 records: the storm would evict real
## search results with junk. This node tracks its own request, and the tree wraps it in a
## BtCooldown as the second line of defence.
##
## THE REGION MUST ENCLOSE A REAL VOLUME. A degenerate AABB aborts the scan, and an aborted
## scan reports a ZERO-STRENGTH disconfirmation that suppresses nothing -- so the alien
## arrives, searches, and the hotspot never resolves. It looks like disconfirmation is
## broken when it is the region that is.
##
## TYPED AGAINST `SearchMemory` RATHER THAN AGAINST EITHER STATE. INVESTIGATING searches a
## hotspot's unresolved location and HUNTING searches around the last credible target
## position (behavior.md section 28); this node is the same sweep either way and there must
## not be two of it. The interface was widened rather than the fields duplicated, because a
## value refreshed every tick and stored twice under two names drifts the first time one
## refresh path is added and the other is not.

## Below this the region is not a volume Perception can sample.
const MINIMUM_HALF_EXTENT: float = 0.5

var memory: SearchMemory = null

var _requested: bool = false


func _init(p_memory: SearchMemory) -> void:
	super(&"search_area")
	memory = p_memory


## Cancels the sweep as well as forgetting it. A scan left running after the creature has
## walked away later reports a disconfirmation for a region it is no longer in -- the alien
## clears a place it never actually checked, which is the one thing searching must not do.
func abort(ctx) -> void:
	if _requested and ctx.perception != null:
		ctx.perception.cancel_activity_scan()
	_requested = false


func _run(ctx) -> Status:
	if memory == null or not memory.has_search_centre() or ctx.perception == null:
		return Status.FAILURE

	if not _requested:
		_requested = true
		ctx.perception.request_activity_scan(
			_region(memory.search_centre(), ctx.config), ctx.config.search_thoroughness
		)
		# Deliberately falls through rather than returning: a synchronous completion has
		# already happened by now, and reporting RUNNING would cost a frame for nothing.

	if ctx.perception.is_activity_scan_active():
		return Status.RUNNING

	_requested = false
	if ctx.perception.activity_scan_aborted():
		# "Never looked" is not "checked and found nothing". Succeeding here would let the
		# state treat an unbounded region or an unbound probe as a completed search.
		return Status.FAILURE
	return Status.SUCCESS


static func _region(centre: Vector3, config: BehaviorConfig) -> AABB:
	var half: float = maxf(config.search_half_extent, MINIMUM_HALF_EXTENT)
	return AABB(centre - Vector3.ONE * half, Vector3.ONE * half * 2.0)
