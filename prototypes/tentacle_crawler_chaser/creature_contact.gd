class_name CreatureContact
extends Area3D

## The only part of the creature you can actually touch.
##
## CrawlerBody has no collider anywhere, and that is deliberate over in the
## tentacle crawler prototype - the body is kinematic, it depenetrates itself
## against raycasts, and giving it a physics shape would put it in an argument
## with its own solver. The consequence here is that the creature swims straight
## through the player and the prototype has no fail state and no clock.
##
## So the catch is an Area rather than a body: it reports the arrival without
## being something to collide with. Two properties keep it out of everything
## else's way - `monitorable` is off, so nothing can detect IT, and areas are
## invisible to intersect_ray unless a query opts in, which means neither the
## creature's own probes nor the player's surface contact resolution can see it.
##
## Layer 3 is the bit the tentacle crawler reserved for the creature and
## deliberately left unoccupied, so that the next person would find out the body
## was kinematic on purpose. This is what it was being kept for.

signal caught(body: Node3D)

@export var catch_radius: float = ChaseKnobs.CATCH_RADIUS
## Set false while the player is being put back, so one arrival does not fire
## again every frame the creature spends sitting on the corpse.
@export var armed: bool = true

var _catch_count: int = 0
var _sphere: SphereShape3D


func _ready() -> void:
	collision_layer = ChaseKnobs.CATCH_LAYER
	collision_mask = ChaseKnobs.CATCH_MASK
	monitorable = false

	_sphere = SphereShape3D.new()
	_sphere.radius = catch_radius
	var collider := CollisionShape3D.new()
	collider.shape = _sphere
	add_child(collider)

	body_entered.connect(_on_body_entered)


## Resizes the catch sphere in place.
##
## The shape is built once in _ready, so writing catch_radius on its own moves
## the number and not the sphere - the reach would go on being whatever it was at
## startup while the panel claimed otherwise. Keeping the shape reference is what
## makes the slider mean anything mid-chase.
func set_catch_radius(metres: float) -> void:
	catch_radius = metres
	if _sphere != null:
		_sphere.radius = metres


func catch_count() -> int:
	return _catch_count


func _on_body_entered(body: Node3D) -> void:
	if not armed:
		return
	armed = false
	_catch_count += 1
	caught.emit(body)
