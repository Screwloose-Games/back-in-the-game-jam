extends CanvasLayer

## Debug overlay for the chase prototype: enough readout to tune the values in
## chase_knobs.gd without guessing, plus the control legend.
##
## The two numbers worth watching are the distance to the creature and the length
## of the path it is walking. Straight-line distance shrinking while path length
## stays put means the divider is between you and it, and that is the prototype
## working; both shrinking together in a straight room is the chase itself.

const CONTROL_LEGEND := """WASD thrust  SPACE/CTRL up-down
Q/E roll  SHIFT stabilizers
F grab-release  T clip-unclip tether
R respawn  ESC free mouse
F1 navmesh  F2 camera"""

const FLASH_DURATION := 0.9

@export var player: CarrierPlayer
@export var crawler: CrawlerBody
@export var follower: ChaseTargetFollower
@export var chase_target: ChaseTarget
@export var baker: WallNavmeshBaker
@export var contact: CreatureContact

var _since_caught: float = -1.0

@onready var _readout: Label = $Readout
@onready var _flash: ColorRect = $CatchFlash


func _ready() -> void:
	_flash.modulate.a = 0.0
	if contact != null:
		contact.caught.connect(_on_caught)


func _process(delta: float) -> void:
	if _since_caught >= 0.0:
		_since_caught += delta

	var lines := PackedStringArray()
	lines.append(_describe_player())
	lines.append(_describe_creature())
	lines.append(_describe_follower())
	lines.append(_describe_navmesh())
	lines.append(_describe_catches())
	lines.append("")
	lines.append(CONTROL_LEGEND)
	_readout.text = "\n".join(lines)


func _describe_player() -> String:
	if player == null:
		return "player -"
	return "drift %5.2f m/s" % player.get_drift_speed()


## Distance first, because in fog this thick it is often the only thing telling
## you the creature is there at all.
func _describe_creature() -> String:
	if crawler == null or player == null:
		return "creature -"
	var gap := crawler.global_position.distance_to(player.global_position)
	return "creature %6.1f m away  %5.2f m/s" % [gap, crawler.current_speed()]


func _describe_follower() -> String:
	if follower == null:
		return "marker -"
	if not follower.enabled:
		return "marker WAITING FOR BAKE"

	var state := follower.debug_state()
	var standoff := chase_target.standoff() if chase_target != null else 0.0
	return (
		"marker %5.2f m/s  path %6.1f m over %d corners  wall %4.1f m off you"
		% [state["speed"], state["path_length"], state["corners"], standoff]
	)


func _describe_navmesh() -> String:
	if baker == null:
		return "navmesh -"
	var stats := baker.stats()
	var quads: int = stats["quads"]
	if quads == 0:
		return "navmesh not baked"
	var leaked: bool = stats["leaked"]
	return (
		"navmesh %d quads over %d cells%s" % [quads, stats["cells"], "  LEAKED" if leaked else ""]
	)


func _describe_catches() -> String:
	if contact == null:
		return "caught -"
	if _since_caught < 0.0:
		return "caught never"
	return "caught %d  last %5.1f s ago" % [contact.catch_count(), _since_caught]


func _on_caught(_body: Node3D) -> void:
	_since_caught = 0.0
	_flash.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_property(_flash, "modulate:a", 0.0, FLASH_DURATION)
