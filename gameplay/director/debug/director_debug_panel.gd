class_name DirectorDebugPanel
extends PanelContainer

## director.md's debug requirement, which is a sentence rather than a layout:
##
## > The debug panel shows menace and lull as bars, the phase, the current target with its
## > margin over the runner-up, and the reason string for whatever the Director is currently
## > forcing. "The alien left" is not a bug report; "the alien left, SATED, menace 1.00 at
## > t+47" is.
##
##     DIRECTOR        t= 79.10s   encounter 1
##     menace          [##########----------] 0.52
##     lull            [############--------] 0.61
##     phase           relief   4.2s   cooldown 15.8s
##     target          Player1  +0.31 over Player2
##     lethality       LETHAL   grace spent
##     forcing         DISENGAGE sated  NO-HUNT  bias -0.40 roam -0.80
##     creature        hunting  12.4s
##
##     DIRECTOR EVENTS
##     build -> peak
##     peak -> relief (sated)
##
## THE `forcing:` LINE IS THE ONE THAT EARNS ITS PLACE, for the same reason
## BehaviorDebugPanel's `fired:` line does. An alien that walks away mid-chase looks broken
## until you can read SATED on screen and know the Director ended it on purpose.
##
## THE `creature` LINE IS DELIBERATELY DUPLICATED from BehaviorDebugPanel. The single most
## important thing this panel shows is the DISAGREEMENT -- the alien HUNTING while the
## Director is in RELIEF and wants it to stop -- and reading that off two panels in opposite
## corners loses it.
##
## Bars are ASCII rather than ProgressBars. Nothing under gameplay/ authors a Control, there
## is no theme, and a styled widget here would be the first and only one.

const MAX_LOG_LINES: int = 8
const BAR_WIDTH: int = 20

@export var director: EncounterDirector = null
## Which creature's track to show. Null means the first one registered, which is every
## single-alien level.
@export var creature: Node = null
## Optional, and only for the bottom line: the creature's own state and running action.
@export var behavior: CreatureBehavior = null

var _label: RichTextLabel = null
var _log: Array[String] = []


func _ready() -> void:
	_label = RichTextLabel.new()
	_label.bbcode_enabled = false
	_label.fit_content = true
	_label.custom_minimum_size = Vector2(520, 0)
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	add_child(_label)

	if director == null:
		return
	director.encounter_phase_changed.connect(_on_phase_changed)
	director.target_changed.connect(_on_target_changed)
	director.disengage_requested.connect(_on_disengage)
	director.lethality_changed.connect(_on_lethality)


func _process(_delta: float) -> void:
	if not visible:
		return
	if director == null:
		_label.text = "DIRECTOR\nno director assigned"
		return
	_label.text = "\n".join(_lines())


func _lines() -> PackedStringArray:
	var track: EncounterTrack = _track()
	var lines := PackedStringArray()
	if track == null:
		lines.append("DIRECTOR        t=%6.2fs" % director.clock)
		lines.append("no creature registered")
		return lines
	lines.append(
		"DIRECTOR        t=%6.2fs   encounter %d" % [director.clock, track.encounter_index]
	)
	lines.append("menace          %s" % _bar(track.menace))
	lines.append("lull            %s" % _bar(director.lull))
	lines.append("phase           %s" % _phase_line(track))
	lines.append("target          %s" % _target_line(track))
	lines.append("lethality       %s" % _lethality_line(track))
	lines.append("forcing         %s" % _forcing_line(track))
	lines.append("creature        %s" % _creature_line())
	lines.append("")
	lines.append("DIRECTOR EVENTS")
	lines.append_array(PackedStringArray(_log))
	return lines


static func _bar(value: float) -> String:
	var filled: int = clampi(int(round(clampf(value, 0.0, 1.0) * BAR_WIDTH)), 0, BAR_WIDTH)
	return "[%s%s] %.2f" % ["#".repeat(filled), "-".repeat(BAR_WIDTH - filled), value]


func _track() -> EncounterTrack:
	if creature != null:
		return director.track_for(creature)
	var found: Array = director.tracks()
	return found[0] if not found.is_empty() else null


## The cooldown is shown only while one is running, because a line reading "cooldown 0.0s"
## for the whole of every QUIET trains the eye to skip the row.
func _phase_line(track: EncounterTrack) -> String:
	var line: String = EncounterDirective.phase_name(track.phase)
	if track.phase == EncounterDirective.Phase.RELIEF:
		line += "   %.1fs   cooldown %.1fs" % [track.relief_elapsed, track.cooldown_remaining]
	elif track.is_hunting():
		line += "   hunt %.1fs of %.0f" % [track.hunt_elapsed, _config().hunt_max_duration_s]
	return line


## The margin over the runner-up is the number that says whether an arbitration was close.
## "It is hunting Player 1" is not a bug report; "Player 1, +0.03 over Player 2" is.
func _target_line(track: EncounterTrack) -> String:
	if not EncounterPacing.is_live(track.target):
		return "--"
	var line: String = str(track.target.name)
	if EncounterPacing.is_live(track.runner_up):
		line += "  %+.2f over %s" % [track.runner_up_margin, track.runner_up.name]
	else:
		line += "  (unopposed)"
	return line


func _lethality_line(track: EncounterTrack) -> String:
	var value: String = (
		"GRACE" if track.lethality == EncounterDirective.Lethality.GRACE else "LETHAL"
	)
	if track.grace_consumed:
		return "%s   grace spent this encounter" % value
	return value


func _forcing_line(track: EncounterTrack) -> String:
	var directive: EncounterDirective = track.directive
	var parts := PackedStringArray()
	if directive.force_disengage:
		parts.append("DISENGAGE %s" % EncounterDirective.reason_name(directive.disengage_reason))
	parts.append("hunt" if directive.permit_hunt else "NO-HUNT")
	parts.append("bias %+.2f roam %+.2f" % [directive.escalation_bias, directive.roam_bias])
	return "  ".join(parts)


## The disagreement, on the same panel as the thing it disagrees with. See the class docstring.
func _creature_line() -> String:
	if behavior == null:
		return "--"
	return (
		"%s  %.1fs  %s"
		% [
			CreatureState.state_name(behavior.state()),
			behavior.hfsm.time_in_state,
			behavior.running_action(),
		]
	)


func _config() -> DirectorConfig:
	return director.config if director.config != null else DirectorConfig.new()


func _on_phase_changed(
	_creature: Node, from: EncounterDirective.Phase, to: EncounterDirective.Phase
) -> void:
	_append("%s -> %s" % [EncounterDirective.phase_name(from), EncounterDirective.phase_name(to)])


func _on_target_changed(_creature: Node, from: Node, to: Node) -> void:
	_append("target %s -> %s" % [_name_of(from), _name_of(to)])


func _on_disengage(_creature: Node, reason: EncounterDirective.Reason) -> void:
	var track: EncounterTrack = _track()
	var menace: float = track.menace if track != null else 0.0
	_append(
		(
			"DISENGAGE %s at t+%.1f, menace %.2f"
			% [EncounterDirective.reason_name(reason), director.clock, menace]
		)
	)


func _on_lethality(_creature: Node, value: EncounterDirective.Lethality) -> void:
	_append(
		"lethality -> %s" % ("grace" if value == EncounterDirective.Lethality.GRACE else "lethal")
	)


## A freed node is still TYPE_OBJECT, so `name` on one is an error rather than a blank.
static func _name_of(node: Node) -> String:
	return str(node.name) if EncounterPacing.is_live(node) else "--"


func _append(line: String) -> void:
	_log.append(line)
	while _log.size() > MAX_LOG_LINES:
		_log.remove_at(0)
