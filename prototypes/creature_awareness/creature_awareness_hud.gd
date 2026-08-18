class_name CreatureAwarenessHud
extends CanvasLayer

## The selectors and the readout.
##
## THE READOUT IS THE ONLY PLACE THE WHOLE CHAIN IS VISIBLE AT ONCE. Every link fails in a
## way that looks like the same symptom -- the alien does not come -- and the line that is
## missing tells you which one:
##
##     heard nothing            too far, or too quiet: nothing reaches evidence at all
##     evidence but no hotspot  heard, but under the strength a single pulse needs; HOLD it
##     hotspot below threshold  believed, but not enough to leave a nest for yet
##     investigating            the chain worked
##
## EVERY CONTROL IS FOCUS_NONE, and that is not a style preference. A focused Button eats
## `ui_accept`, which is space, which is thrust up; a focused HSlider eats `ui_left` and
## `ui_right`, which are A and D. It reads as broken flight controls rather than as a UI
## bug, and it costs an hour to find.

const CONTROL_LEGEND := """LMB hold  perform the selected activity   drag to move it
Tab cycle camera   1 free fly  2 ant farm  3 follow
Q/E thrust activity   R rebake   Esc release mouse
F1 world graph   F2 locomotion   F3 belief"""

var _behaviour: CreatureAwarenessBehaviour = null
var _navigation: CreatureNavigation = null
var _perception: CreaturePerception = null
var _suspicion: CreatureSuspicion = null
var _stimulus: CreatureAwarenessStimulus = null
var _cameras: CreatureAwarenessCameras = null
var _camera_buttons: Array[Button] = []
var _stimulus_buttons: Array[Button] = []
var _heard: String = "nothing heard yet"

@onready var _readout: Label = $Readout
@onready var _selectors: VBoxContainer = $Selectors


func bind(
	behaviour: CreatureAwarenessBehaviour,
	navigation: CreatureNavigation,
	perception: CreaturePerception,
	suspicion: CreatureSuspicion,
	stimulus: CreatureAwarenessStimulus,
	cameras: CreatureAwarenessCameras
) -> void:
	_behaviour = behaviour
	_navigation = navigation
	_perception = perception
	_suspicion = suspicion
	_stimulus = stimulus
	_cameras = cameras
	if _perception != null:
		_perception.noise_evaluated.connect(_on_noise_evaluated)
	_build_selectors()
	_sync_selectors()


## Built in code rather than in the .tscn so the button set cannot drift from the enums it
## selects between -- adding a stimulus is one entry in one place.
func _build_selectors() -> void:
	if _selectors == null:
		return
	for child: Node in _selectors.get_children():
		child.queue_free()
	_camera_buttons.clear()
	_stimulus_buttons.clear()

	_selectors.add_child(_heading("CAMERA"))
	var cameras_row := HBoxContainer.new()
	_selectors.add_child(cameras_row)
	for index: int in range(CreatureAwarenessCameras.VIEW_COUNT):
		var button := _button(CreatureAwarenessCameras.view_name(index))
		button.pressed.connect(_on_camera_pressed.bind(index))
		cameras_row.add_child(button)
		_camera_buttons.append(button)

	_selectors.add_child(_heading("ACTIVITY"))
	var stimulus_row := HBoxContainer.new()
	_selectors.add_child(stimulus_row)
	for kind: int in [CreatureAwarenessStimulus.Kind.THRUST, CreatureAwarenessStimulus.Kind.MINING]:
		var button := _button(CreatureAwarenessStimulus.kind_name(kind))
		button.pressed.connect(_on_stimulus_pressed.bind(kind))
		stimulus_row.add_child(button)
		_stimulus_buttons.append(button)


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	return label


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	# See the class docstring. A focused control eats the flight keys.
	button.focus_mode = Control.FOCUS_NONE
	return button


func _on_camera_pressed(index: int) -> void:
	if _cameras != null:
		_cameras.select(index)
	_sync_selectors()


func _on_stimulus_pressed(kind: int) -> void:
	if _stimulus != null:
		_stimulus.set_kind(kind)
	_sync_selectors()


func _sync_selectors() -> void:
	if _cameras != null:
		for index: int in range(_camera_buttons.size()):
			_camera_buttons[index].button_pressed = index == int(_cameras.view())
	if _stimulus != null:
		for index: int in range(_stimulus_buttons.size()):
			_stimulus_buttons[index].button_pressed = index == int(_stimulus.kind)


## Every noise, including the ones that were not heard.
##
## THIS IS THE MOST USEFUL SIGNAL IN THE WHOLE PROTOTYPE and it is easy to miss that it
## exists. `receive_noise` returns nothing and fails silently in four different ways;
## `noise_evaluated` fires for all of them, with the distance and the obstruction that
## decided it, and a null evidence when the answer was "not heard".
func _on_noise_evaluated(
	_event: NoiseEvent, evidence: SuspicionEvidence, distance: float, obstruction: float
) -> void:
	if evidence == null:
		_heard = "NOT heard  (%.0f m, obstruction %.2f)" % [distance, obstruction]
		return
	_heard = (
		"heard  %.0f m  strength %.2f  confidence %.2f  uncertainty %.1f m"
		% [distance, evidence.strength, evidence.confidence, evidence.uncertainty_radius]
	)


func refresh() -> void:
	if _readout == null:
		return
	_sync_selectors()
	_readout.text = "\n".join(_lines()) + "\n\n" + CONTROL_LEGEND


func _lines() -> Array[String]:
	var lines: Array[String] = []
	lines.append(_graph_line())

	if _behaviour != null:
		var goal: Vector3 = _behaviour.goal()
		lines.append(
			(
				"behaviour: %s   goal (%.0f, %.0f, %.0f)"
				% [
					CreatureAwarenessBehaviour.state_name(_behaviour.state()),
					goal.x,
					goal.y,
					goal.z
				]
			)
		)

	lines.append("last noise: " + _heard)

	if _perception != null:
		lines.append("alertness: %.2f" % _perception.get_alertness())

	if _suspicion != null:
		lines.append("overall suspicion: %.2f" % _suspicion.get_overall_suspicion())
		var hotspots: Array[SuspicionHotspot] = _suspicion.get_hotspots()
		if hotspots.is_empty():
			lines.append("hotspots: none")
		for hotspot: SuspicionHotspot in hotspots:
			var mark: String = (
				" <-- investigating"
				if _behaviour != null and hotspot.id == _behaviour.current_hotspot_id()
				else ""
			)
			lines.append(
				(
					"  #%d  suspicion %.2f  confidence %.2f  radius %.1f m  searched %d%%%s"
					% [
						hotspot.id,
						hotspot.suspicion,
						hotspot.confidence,
						hotspot.radius,
						int(hotspot.investigation_progress * 100.0),
						mark
					]
				)
			)
	return lines


func _graph_line() -> String:
	if _navigation == null:
		return "navigation: unbound"
	if _navigation.is_baking():
		return "baking %d%%" % int(_navigation.bake_progress() * 100.0)
	if _navigation.graph == null:
		return "no graph"
	var route: NavRoute = _navigation.route
	var status: String = route.status_name().to_lower() if route != null else "none"
	return (
		"graph: %d nodes, %d edges   route: %s"
		% [_navigation.graph.node_count(), _navigation.graph.edge_count(), status]
	)
