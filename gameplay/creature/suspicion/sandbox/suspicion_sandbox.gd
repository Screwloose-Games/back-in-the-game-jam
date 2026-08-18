class_name SuspicionSandbox
extends Node3D

## The perception sandbox, with the belief layer bolted on top of it.
##
## It instantiates `perception_sandbox.tscn` WHOLE and attaches a CreatureSuspicion to
## the CreaturePerception inside it, rather than rebuilding the room. That is not
## laziness: the claim perception/README.md makes about this module is that connecting
## the two is a four-line adapter, and the honest way to check that claim is to write
## exactly those four lines against the untouched scene. If Suspicion ever needs the
## sandbox changed to accommodate it, the coupling has grown and this file stops
## building.
##
## It also closes the loop nothing else exercises: overall suspicion is fed back to
## Perception as alertness, so the creature looks harder because it is worried. That
## feedback changes HOW HARD it looks and never WHAT it finds -- if toggling it ever
## changes what a sense reports, the separation has broken.
##
##     WASD / QE   move the stand-in player          (inner sandbox)
##     1 / 2       emit a quiet / loud noise         (inner sandbox)
##     3 / 4       request an activity / geometry scan at the player
##     V / G       toggle vision / geometry          (inner sandbox)
##     [ / ]       lower / raise alertness manually  (inner sandbox)
##     Tab         toggle the perception overlay     (inner sandbox)
##
##     5           SEARCH WHERE SUSPICION SAYS -- the Behavior loop, by hand
##     L           toggle the alertness feedback loop
##     R           forget everything
##     Y           toggle this overlay
##
## Key 5 is the one worth pressing. It asks Suspicion for the best unresolved location,
## sends Perception to look there, and lets the resulting disconfirmation come back --
## which is the entire investigate cycle with Behavior's part played by a keystroke.

const INNER_SANDBOX: String = "res://gameplay/creature/perception/sandbox/perception_sandbox.tscn"
## Half-extent of the search box key 5 requests, around the point Suspicion named.
const SEARCH_HALF_EXTENT: float = 4.0

@export var feedback_alertness: bool = true

var suspicion: CreatureSuspicion = null

var _perception: CreaturePerception = null
var _overlay: SuspicionDebugDraw = null
var _panel: SuspicionDebugPanel = null


func _ready() -> void:
	var packed: PackedScene = load(INNER_SANDBOX)
	if packed == null:
		push_error("SuspicionSandbox could not load %s" % INNER_SANDBOX)
		return
	var inner: Node = packed.instantiate()
	inner.name = "PerceptionSandbox"
	add_child(inner)
	_perception = inner.get_node_or_null("CreaturePerception") as CreaturePerception
	if _perception == null:
		push_error("SuspicionSandbox found no CreaturePerception in the perception sandbox")
		return

	suspicion = CreatureSuspicion.new()
	suspicion.name = "CreatureSuspicion"
	suspicion.config = SuspicionConfig.new()
	add_child(suspicion)

	# The whole coupling between the two modules, in the two lines the README promises.
	_perception.evidence_observed.connect(suspicion.submit_evidence)
	_perception.disconfirmation_observed.connect(suspicion.submit_disconfirmation)

	_build_debug()


func _process(_delta: float) -> void:
	if feedback_alertness and _perception != null and suspicion != null:
		# Read-only context. It changes scan frequency and whether vision runs at all,
		# and must never change what a sense reports for identical input.
		_perception.set_alertness_context(suspicion.get_overall_suspicion())


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or suspicion == null:
		return
	match key.keycode:
		KEY_5:
			_search_where_suspicion_says()
		KEY_L:
			feedback_alertness = not feedback_alertness
		KEY_R:
			suspicion.reset()
		KEY_Y:
			_overlay.visible = not _overlay.visible
			_panel.visible = _overlay.visible


## Behavior's half of the investigate loop, played by hand. Note what it does NOT do:
## it never tells Suspicion the area is clear. It sends the creature to look, and
## whatever Perception reports back is what changes the belief.
func _search_where_suspicion_says() -> void:
	var hotspot: SuspicionHotspot = suspicion.get_strongest_hotspot()
	if hotspot == null:
		print("[sandbox] nothing to investigate")
		return
	var target: Vector3 = suspicion.get_best_unresolved_location(hotspot.id)
	print(
		(
			"[sandbox] investigating hotspot %d (%.2f) at %v, %d%% searched"
			% [hotspot.id, hotspot.suspicion, target, int(hotspot.investigation_progress * 100.0)]
		)
	)
	_perception.request_activity_scan(
		AABB(target - Vector3.ONE * SEARCH_HALF_EXTENT, Vector3.ONE * SEARCH_HALF_EXTENT * 2.0), 1.0
	)


func _build_debug() -> void:
	_overlay = SuspicionDebugDraw.new()
	_overlay.suspicion = suspicion
	add_child(_overlay)

	var layer := CanvasLayer.new()
	add_child(layer)
	_panel = SuspicionDebugPanel.new()
	_panel.suspicion = suspicion
	_panel.debug_draw = _overlay
	# Right-hand side: the perception sandbox's own panel already owns the top left, and
	# two overlapping readouts is worse than either alone.
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.position = Vector2(-12, 12)
	layer.add_child(_panel)
