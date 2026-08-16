extends GutTest

## Shared fixture for the two suites that exercise the behavior tree framework alone.
##
## Not collected as a test script itself -- GUT's prefix is `test_`, and this file
## deliberately does not have it.
##
## NOTHING HERE NAMES A CREATURE SUBSYSTEM, on purpose. `tree/` is domain-free and
## `tools/verify_behavior_static.gd` fails the build if that stops being true, so the suite
## that proves the framework works has to be provable without an alien. The stub context
## carries the one field the framework actually reads -- `clock`, for BtCooldown -- and the
## stub goal is enough to show the ownership handshake without a navigator.
##
## The full assembled-creature fixture is `behavior_test_case.gd`.


## The framework reads `ctx` duck-typed, so this is the entire contract it depends on.
class StubContext:
	extends RefCounted

	var clock: float = 0.0
	var goal: StubGoal = null

	func _init() -> void:
		goal = StubGoal.new()


## BehaviorGoal's ownership rule, in miniature: release only works for the current holder.
class StubGoal:
	extends RefCounted

	var holder: BtNode = null
	var position: Vector3 = Vector3.ZERO
	var releases: int = 0

	func request(owner: BtNode, at: Vector3) -> void:
		holder = owner
		position = at

	func release(owner: BtNode) -> void:
		releases += 1
		if holder == owner:
			holder = null
			position = Vector3.ZERO


## A leaf whose status the test dictates, counting its own ticks and aborts.
class StubLeaf:
	extends BtAction

	var status: BtNode.Status = BtNode.Status.SUCCESS
	var ticks: int = 0
	var aborts: int = 0
	var claims_goal: bool = false
	var goal_position: Vector3 = Vector3.ZERO

	func _init(p_name: StringName, p_status: BtNode.Status) -> void:
		super(p_name)
		status = p_status

	func abort(ctx) -> void:
		aborts += 1
		if claims_goal:
			ctx.goal.release(self)

	func _run(ctx) -> Status:
		ticks += 1
		if claims_goal:
			ctx.goal.request(self, goal_position)
		return status


## A condition whose answer the test dictates, counting how often it was asked.
class StubCondition:
	extends BtCondition

	var answer: bool = true
	var checks: int = 0

	func _init(p_name: StringName, p_answer: bool) -> void:
		node_name = p_name
		answer = p_answer

	func _check(_ctx) -> bool:
		checks += 1
		return answer


var _ctx: StubContext = null


func before_each() -> void:
	_ctx = StubContext.new()


func _leaf(named: StringName, status: BtNode.Status) -> StubLeaf:
	return StubLeaf.new(named, status)


func _running(named: StringName = &"running") -> StubLeaf:
	return StubLeaf.new(named, BtNode.Status.RUNNING)


func _condition(named: StringName, answer: bool) -> StubCondition:
	return StubCondition.new(named, answer)


func _selector(nodes: Array[BtNode]) -> BtSelector:
	return BtSelector.new(&"selector", nodes)


func _sequence(nodes: Array[BtNode]) -> BtSequence:
	return BtSequence.new(&"sequence", nodes)


## One tick of a bare root, without the BehaviorTree wrapper.
func _tick(node: BtNode) -> BtNode.Status:
	return node.tick(_ctx)


## Simulated seconds on the injected clock. Never a wall clock -- the framework has no
## other time, which is what lets a cooldown be tested in microseconds.
func _elapse(seconds: float) -> void:
	_ctx.clock += seconds
