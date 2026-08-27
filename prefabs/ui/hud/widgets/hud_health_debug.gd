@tool
class_name HudHealthDebug
extends HudWidget

## The numeric readout the visor deliberately does not give you. Gated on DebugMode
## like every other readout in the game, so F3 shows it beside the creature panels.

const TEXT_SIZE := 16
const BASELINE := Vector2(0.0, 16.0)

var _state: HudState


func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		return
	DebugMode.changed.connect(_apply_debug_mode)
	# Built long after the autoload settled on a value, so the first sync is explicit.
	_apply_debug_mode(DebugMode.enabled)


func bind(state: HudState) -> void:
	_state = state
	state.health_changed.connect(_on_value_changed)
	state.oxygen_changed.connect(_on_value_changed)
	state.power_changed.connect(_on_value_changed)


## Drawn in screen pixels rather than design space; a debug string does not scale.
func design_extent() -> Vector2:
	return size


func _draw() -> void:
	if _state == null:
		return
	var line := (
		"HEALTH %5.1f  (%d%%)   O2 %d%%   PWR %d%%"
		% [
			_state.health_points,
			roundi(_state.health * 100.0),
			roundi(_state.oxygen * 100.0),
			roundi(_state.power * 100.0),
		]
	)
	draw_string(
		ThemeDB.fallback_font,
		BASELINE,
		line,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		TEXT_SIZE,
		HudPalette.CHROME
	)


func _apply_debug_mode(enabled: bool) -> void:
	visible = enabled
	queue_redraw()


func _on_value_changed(_fraction: float) -> void:
	if visible:
		queue_redraw()
