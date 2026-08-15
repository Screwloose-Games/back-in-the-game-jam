class_name PlayerCollisionResponse
extends Node

## Advances the body and resolves what it hit — restitution, friction, scrape,
## and the spin a glancing blow imparts. It owns the `move_and_slide` call
## because the bounce has to be computed from the pre-move velocity, which is
## the one thing `move_and_slide` destroys.

## How hard the body hit something, in metres per second of closing speed.
signal impacted(closing_speed: float, at: Vector3)

## Runs last, after every link has had its say on velocity.
const PHYSICS_PRIORITY := 100

@export var settings: PlayerSettings

var _was_touching_surface := false

@onready var body: CharacterBody3D = get_parent()
@onready var locomotion: PlayerLocomotion = %Locomotion


func _ready() -> void:
	process_physics_priority = PHYSICS_PRIORITY
	if settings == null:
		settings = PlayerSettings.new()
		push_warning("PlayerCollisionResponse has no settings; running on PlayerSettings defaults.")


func _physics_process(delta: float) -> void:
	var approach_velocity := body.velocity
	body.move_and_slide()
	_resolve_surface_contact(delta, approach_velocity)


## Forgets that the body was touching anything, so the next contact counts as a
## fresh impact rather than a scrape.
func clear_contact() -> void:
	_was_touching_surface = false


## Immovable hull and loose bodies need different answers, so the frame's
## contacts are split before either is resolved.
func _resolve_surface_contact(delta: float, approach_velocity: Vector3) -> void:
	var contact_count := body.get_slide_collision_count()
	if contact_count == 0:
		_was_touching_surface = false
		return

	var was_already_touching := _was_touching_surface
	_was_touching_surface = true

	var held_object := _held_object()
	var hull_normal := Vector3.ZERO
	var hull_point := Vector3.ZERO
	var hull_contact_count := 0
	var loose_contacts: Array[KinematicCollision3D] = []

	for index in contact_count:
		var contact := body.get_slide_collision(index)
		var collider := contact.get_collider()
		if collider is RigidBody3D:
			# A held object is already governed by the grip spring; running the
			# exchange on it too would double-count the contact and fight it.
			if collider != held_object:
				loose_contacts.append(contact)
		else:
			hull_normal += contact.get_normal()
			hull_point += contact.get_position()
			hull_contact_count += 1

	if hull_contact_count > 0:
		_resolve_hull_contact(
			delta,
			approach_velocity,
			hull_normal,
			hull_point / hull_contact_count,
			was_already_touching
		)

	for contact in loose_contacts:
		_shove_loose_body(contact, approach_velocity, was_already_touching)


## Only the frame an impact begins gets a bounce. Re-applying restitution every
## frame would buzz you off a wall you are deliberately thrusting against.
func _resolve_hull_contact(
	delta: float,
	approach_velocity: Vector3,
	summed_normal: Vector3,
	contact_point: Vector3,
	was_already_touching: bool
) -> void:
	if was_already_touching:
		body.velocity = PlayerContact.scrape(body.velocity, settings.scrape_friction, delta)
		return

	# Normals that cancel mean opposing surfaces — wedged, with nowhere to bounce
	# to. Dump the speed rather than pick a meaningless direction.
	if summed_normal.length_squared() < 0.0001:
		body.velocity = Vector3.ZERO
		return
	var contact_normal := summed_normal.normalized()

	var closing_speed := approach_velocity.dot(contact_normal)
	if closing_speed >= 0.0:
		return

	body.velocity = PlayerContact.hull_bounce(
		approach_velocity,
		contact_normal,
		settings.collision_restitution,
		settings.collision_friction
	)
	_apply_impact_spin(
		PlayerContact.along_surface(approach_velocity, contact_normal), contact_point
	)
	impacted.emit(closing_speed, contact_point)


## A two-body momentum exchange, so the same hit both redirects the player and
## sends the object tumbling. `move_and_slide` has already stripped the closing
## speed out of velocity, so the exchange runs off the pre-move approach.
func _shove_loose_body(
	contact: KinematicCollision3D, approach_velocity: Vector3, was_already_touching: bool
) -> void:
	var loose_body := contact.get_collider() as RigidBody3D
	if loose_body == null or loose_body.mass <= 0.0:
		return

	var contact_normal := contact.get_normal()
	var contact_point := contact.get_position()
	var relative_velocity := approach_velocity - loose_body.linear_velocity
	var closing_speed := relative_velocity.dot(contact_normal)
	if closing_speed >= 0.0:
		return

	# Bounce only as contact begins, so you can shoulder something out of the way
	# instead of pinballing off it.
	var restitution := 0.0 if was_already_touching else settings.collision_restitution
	var pair_mass := PlayerContact.reduced_mass(settings.player_mass, loose_body.mass)
	var impulse := PlayerContact.impulse_magnitude(closing_speed, restitution, pair_mass)

	body.velocity += contact_normal * (impulse / settings.player_mass)
	loose_body.apply_impulse(-contact_normal * impulse, contact_point - loose_body.global_position)

	var mass_ratio := loose_body.mass / (loose_body.mass + settings.player_mass)
	var along := PlayerContact.along_surface(relative_velocity, contact_normal)
	_apply_impact_spin(along * mass_ratio, contact_point)
	impacted.emit(closing_speed, contact_point)


## Friction acts where the body touched, not at its centre, so it applies a
## torque proportional to that offset. A square-on hit has no lever.
func _apply_impact_spin(along_surface: Vector3, contact_point: Vector3) -> void:
	if is_zero_approx(settings.collision_spin_transfer):
		return
	locomotion.add_spin_from_impulse(
		-along_surface * settings.collision_friction,
		contact_point,
		settings.collision_spin_transfer
	)


func _held_object() -> RigidBody3D:
	var grab := get_parent().get_node_or_null("Grab") as PlayerGrab
	if grab == null:
		return null
	return grab.held_object()
