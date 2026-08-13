class_name SuspicionDebugPanel
extends PanelContainer

## The text half of the belief overlay:
##
##     SUSPICION       t= 12.40s
##     overall:        0.63
##     evidence:       4    searches: 1
##
##     HOTSPOTS
##     #2  .63  r= 4.2m  at (5.1, 2.0, -1.3)  searched 18%  <- Player1 .88
##     #3  .21  r=11.8m  at (-7.0, 2.0, 6.4)  searched  0%
##
##     PLAYERS
##     Player1  susp .71  conf .88
##
##     EVENTS
##     + hotspot 2
##     ~ overall 0.63
##
## The column that earns its place is `searched`. "The creature is standing in the
## hotspot doing nothing" and "the creature has checked 90% of the hotspot and the last
## 10% is behind it" look identical on screen, and are completely different bugs.

const MAX_LOG_LINES: int = 10

@export var suspicion: CreatureSuspicion = null
@export var debug_draw: SuspicionDebugDraw = null

var _label: RichTextLabel = null
var _log: Array[String] = []


func _ready() -> void:
	_label = RichTextLabel.new()
	_label.bbcode_enabled = false
	_label.fit_content = true
	_label.custom_minimum_size = Vector2(460, 0)
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	add_child(_label)

	if suspicion != null:
		suspicion.hotspot_created.connect(func(id: int) -> void: _append("+ hotspot %d" % id))
		suspicion.hotspot_resolved.connect(
			func(id: int) -> void: _append("- hotspot %d resolved" % id)
		)
		suspicion.overall_suspicion_changed.connect(
			func(value: float) -> void: _append("~ overall %.2f" % value)
		)
		suspicion.player_suspicion_changed.connect(_on_player_changed)


func _process(_delta: float) -> void:
	if not visible or suspicion == null:
		return
	_label.text = _compose()


func _compose() -> String:
	var state: Dictionary = suspicion.debug_state()
	var lines: Array[String] = [
		"SUSPICION       t=%6.2fs" % float(state["clock"]),
		"",
		"overall:        %.2f" % float(state["overall"]),
		(
			"evidence:       %-4d searches: %d"
			% [int(state["evidence"]), int(state["disconfirmations"])]
		),
		"",
		"HOTSPOTS",
	]
	var hotspots: Array = state["hotspots"]
	if hotspots.is_empty():
		lines.append("  (none)")
	for entry: Dictionary in hotspots:
		lines.append(_hotspot_line(entry))

	lines.append("")
	lines.append("PLAYERS")
	var players: Array = state["players"]
	if players.is_empty():
		lines.append("  (nobody in particular)")
	for entry: Dictionary in players:
		lines.append(
			(
				"  %-10s susp %.2f  conf %.2f"
				% [entry["player"], float(entry["suspicion"]), float(entry["source_confidence"])]
			)
		)

	lines.append("")
	lines.append("EVENTS")
	lines.append_array(_log)
	return "\n".join(lines)


func _hotspot_line(entry: Dictionary) -> String:
	var position: Vector3 = entry["position"]
	var blamed: String = ""
	if float(entry["source_confidence"]) > 0.0:
		blamed = "  <- %.2f" % float(entry["source_confidence"])
	return (
		"  #%-3d %.2f r=%5.1fm (%5.1f,%5.1f,%5.1f) searched %3d%%%s"
		% [
			int(entry["id"]),
			float(entry["suspicion"]),
			float(entry["radius"]),
			position.x,
			position.y,
			position.z,
			int(float(entry["investigation_progress"]) * 100.0),
			blamed,
		]
	)


func _on_player_changed(player: Node, value: float) -> void:
	var who: String = player.name if is_instance_valid(player) else "<gone>"
	_append("~ %s %.2f" % [who, value])


func _append(line: String) -> void:
	_log.append(line)
	if _log.size() > MAX_LOG_LINES:
		_log.remove_at(0)
