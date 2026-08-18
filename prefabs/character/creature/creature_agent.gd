class_name CreatureAgent
extends Node

## Step 9 of the tick contract: turns the planned route into the leash marker CrawlerBody
## chases, and puts the whole creature back to its spawn state on a level reset.

@export var body: CrawlerBody = null
@export var marker: Node3D = null
@export var navigation: CreatureNavigation = null
@export var perception: CreaturePerception = null
@export var suspicion: CreatureSuspicion = null
@export var behavior: CreatureBehavior = null

var _spawn_position: Vector3 = Vector3.ZERO
var _last_position: Vector3 = Vector3.ZERO


func _ready() -> void:
	# The only wiring between Perception and Suspicion, and nothing inside either module does
	# it -- CreatureBehavior listens to evidence for its own reasons but never forwards it.
	perception.evidence_observed.connect(suspicion.submit_evidence)
	perception.disconfirmation_observed.connect(suspicion.submit_disconfirmation)
	# Wherever the level placed the creature is where a reset puts it back, the same way
	# PlayerRespawn remembers the pose the player arrived with.
	_spawn_position = body.global_position
	# A top_level marker starts at the world origin whatever the creature was placed at, and
	# CrawlerBody ticks first, so it would leash toward the origin on frame one.
	_last_position = _spawn_position
	marker.global_position = _spawn_position


func _physics_process(delta: float) -> void:
	var at: Vector3 = body.global_position
	marker.global_position = _marker_target(at)
	var velocity: Vector3 = (at - _last_position) / maxf(delta, 0.0001)
	_last_position = at
	navigation.set_body_state(at, velocity, body.wanted_direction(), Vector3.UP)


## Back to where the level put it, believing nothing and going nowhere.
func reset() -> void:
	body.teleport(_spawn_position)
	marker.global_position = _spawn_position
	_last_position = _spawn_position
	navigation.clear_goal()
	navigation.inspection_completed()
	navigation.local_planner.reset_mode()
	navigation.set_body_state(_spawn_position, Vector3.ZERO, body.wanted_direction(), Vector3.UP)
	# An in-flight scan would otherwise finish and disconfirm a region the creature has left.
	perception.cancel_activity_scan()
	suspicion.reset()
	behavior.hfsm.reset_to(CreatureState.State.UNALERTED, behavior.context)


## The anchor pushed out by the leash's dead zone, so the body settles ON the anchor rather
## than `leash_slack` short of every waypoint -- which is short of every arrival test there is.
##
## With no route there is no plan to execute, and a marker left on the last anchor drives the
## body in a straight line out of the level for as long as the tree holds no goal.
func _marker_target(at: Vector3) -> Vector3:
	if not navigation.follower.has_route():
		return at
	var anchor: Vector3 = navigation.follower.current_anchor()
	var lead: Vector3 = anchor - at
	if lead.length_squared() < 0.0001:
		return anchor + body.wanted_direction() * body.leash_slack
	return anchor + lead.normalized() * body.leash_slack
