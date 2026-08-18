class_name BehaviorDebugPanel
extends PanelContainer

## fsm.md's one debug line, and the transition log that gives it context:
##
##     BEHAVIOR        t= 31.20s
##     investigating  12.4s  search_area
##     fired:          hotspot  0.31 vs 0.25
##     goal:           (5.1, 2.0, -1.3)
##     directive:      quiet  bias +0.30  roam +0.60  hunt
##     report:         route 8.4m  reachable  seen  LURKING
##
##     TRANSITIONS
##     unalerted -> investigating (hotspot)
##     investigating -> hunting (candidate)
##
## THE `fired:` LINE IS THE ONE THAT EARNS ITS PLACE. "The alien left" is not a bug report.
## "The alien left, hotspot 0.31 against a threshold of 0.25" says whether the creature was
## wrong or the number was, and those are completely different afternoons.
##
## `directive:` is the other half. An alien that will not hunt looks broken until you can see
## `NO-HUNT` on screen and know the Director is holding it back on purpose.

const MAX_LOG_LINES: int = 10

@export var behavior: CreatureBehavior = null

var _label: RichTextLabel = null
var _log: Array[String] = []


func _ready() -> void:
	_label = RichTextLabel.new()
	_label.bbcode_enabled = false
	_label.fit_content = true
	_label.custom_minimum_size = Vector2(460, 0)
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	add_child(_label)

	if behavior != null:
		behavior.state_changed.connect(_on_state_changed)


func _process(_delta: float) -> void:
	if behavior == null:
		_label.text = "BEHAVIOR\nno creature assigned"
		return
	_label.text = "\n".join(_lines())


func _lines() -> PackedStringArray:
	var report: EncounterReport = behavior.build_report()
	var directive: EncounterDirective = behavior.directive
	var lines := PackedStringArray()
	lines.append("BEHAVIOR        t=%6.2fs" % behavior.clock)
	lines.append(
		(
			"%-14s %5.1fs  %s"
			% [
				CreatureState.state_name(behavior.state()),
				behavior.hfsm.time_in_state,
				behavior.running_action()
			]
		)
	)
	lines.append("fired:          %s" % _fired())
	lines.append("goal:           %s" % _goal())
	(
		lines
		. append(
			(
				"directive:      %s  bias %+.2f  roam %+.2f  %s"
				% [
					EncounterDirective.phase_name(directive.phase),
					directive.escalation_bias,
					directive.roam_bias,
					"hunt" if directive.permit_hunt else "NO-HUNT",
				]
			)
		)
	)
	lines.append("report:         %s" % _report_line(report))
	lines.append("")
	lines.append("TRANSITIONS")
	lines.append_array(PackedStringArray(_log))
	return lines


## Route distance is INF until navigation has one, and printing that verbatim reads as a
## bug rather than as "no goal".
func _report_line(report: EncounterReport) -> String:
	var distance: String = (
		"route --" if is_inf(report.route_distance) else "route %.1fm" % report.route_distance
	)
	var reach: String = "reachable" if report.target_reachable else "UNREACHABLE"
	var seen: String = "seen" if report.has_visual_contact else "unseen"
	# The two the Director prices attack and lurk pressure from. Printed only when true: a
	# line that reads "-- --" for the whole of UNALERTED trains the eye to skip it.
	var hunt: String = ""
	if report.attack_window_open:
		hunt += "  IN-REACH"
	if report.lurking_at_tunnel_mouth:
		hunt += "  LURKING"
	return "%s  %s  %s%s" % [distance, reach, seen, hunt]


func _fired() -> String:
	var transition: BehaviorTransition = behavior.hfsm.last_transition
	if transition == null:
		return "--"
	return "%s  %.2f vs %.2f" % [transition.reason, transition.value, transition.threshold]


func _goal() -> String:
	if not behavior.goal.has_goal():
		return "--"
	var at: Vector3 = behavior.goal.committed()
	return "(%.1f, %.1f, %.1f)" % [at.x, at.y, at.z]


func _on_state_changed(
	from: CreatureState.State, to: CreatureState.State, reason: StringName
) -> void:
	_append(
		"%s -> %s (%s)" % [CreatureState.state_name(from), CreatureState.state_name(to), reason]
	)


func _append(line: String) -> void:
	_log.append(line)
	while _log.size() > MAX_LOG_LINES:
		_log.remove_at(0)
