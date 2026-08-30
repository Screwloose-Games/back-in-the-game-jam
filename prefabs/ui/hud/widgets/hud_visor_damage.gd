@tool
class_name HudVisorDamage
extends HudWidget

## Frost and cracking creeping in from the edges as the suit loses integrity. The
## same wedge geometry Damage_Overlay flashes, held rather than flashed, so an injury
## and the blow that caused it read as one system instead of two effects.

const DESIGN_SIZE := Vector2(1917.0, 1077.0)

## How far one wedge reaches along each screen edge. Damage_Overlay's own numbers, so
## the sustained and the transient occupy exactly the same corners.
const REACH_ACROSS := 0.469329
const REACH_DOWN := 0.386145

## The far end of the fill, where the gradient has run out.
const SPENT := Color(0.72, 0.85, 0.92, 0.0)

## Nothing shows above this. A scratch should not dress the visor.
const SHOWS_BELOW := 0.75

## Corner alpha at zero health. Never opaque -- you still have to fly home.
const PEAK_ALPHA := 0.55

## Cold at first, hot at the end: hurt reads as frost, critical reads as blood.
const FROST := Color(0.72, 0.85, 0.92)

## Where the cracks sit, fixed rather than random -- a pattern reshuffled every frame
## is noise, not damage.
const CRACK_COUNT := 4
const CRACK_ORIGIN: Array[float] = [0.10, 0.19, 0.14, 0.24]
const CRACK_SPREAD: Array[float] = [0.78, 0.41, 0.86, 0.30]
const CRACK_WIDTH := 2.4

## The breathing pulse, which runs only once health is critical.
const PULSE_HZ := 0.55
const PULSE_DEPTH := 0.22

## Drives the draw in the editor, so the look can be judged without running the game.
@export_range(0.0, 1.0, 0.01) var preview_health := 1.0:
	set(value):
		preview_health = value
		if Engine.is_editor_hint():
			show_health(value)

var _health := 1.0
var _elapsed := 0.0


## How far past the onset the suit is: 0 at SHOWS_BELOW and 1 at zero health.
static func severity_for(health: float) -> float:
	if health >= SHOWS_BELOW:
		return 0.0
	return clampf(inverse_lerp(SHOWS_BELOW, 0.0, health), 0.0, 1.0)


func _ready() -> void:
	super()
	set_process(false)


func bind(state: HudState) -> void:
	state.health_changed.connect(show_health)


func show_health(fraction: float) -> void:
	_health = clampf(fraction, 0.0, 1.0)
	# The pulse is the only thing here that costs a frame, so a merely hurt suit stops
	# processing entirely and a healthy one never started.
	var critical := _health < HudState.CRITICAL_BELOW
	if not critical:
		_elapsed = 0.0
	set_process(critical)
	queue_redraw()


func _process(delta: float) -> void:
	_elapsed += delta
	queue_redraw()


func design_extent() -> Vector2:
	return DESIGN_SIZE


func _draw() -> void:
	var severity := severity_for(_health)
	if severity <= 0.0:
		return
	var alpha := PEAK_ALPHA * severity
	if _health < HudState.CRITICAL_BELOW:
		alpha *= 1.0 - PULSE_DEPTH * (0.5 - 0.5 * cos(_elapsed * TAU * PULSE_HZ))
	var tint := FROST.lerp(HudPalette.ALERT, severity)
	for corner in 4:
		_draw_corner(corner, alpha, tint, severity)


## One corner's wedge and the cracks running out of it, mirrored into place.
func _draw_corner(corner: int, alpha: float, tint: Color, severity: float) -> void:
	var horizontal := corner % 2 == 0
	var vertical := corner < 2
	var origin := Vector2(0.0 if horizontal else size.x, 0.0 if vertical else size.y)
	var across := Vector2(size.x * REACH_ACROSS * (1.0 if horizontal else -1.0), 0.0)
	var down := Vector2(0.0, size.y * REACH_DOWN * (1.0 if vertical else -1.0))
	var points: PackedVector2Array = [origin, origin + across, origin + down]
	var colours: PackedColorArray = [Color(tint, alpha), SPENT, SPENT]
	draw_polygon(points, colours)

	for i in mini(ceili(severity * CRACK_COUNT), CRACK_COUNT):
		var start := origin + (across + down) * CRACK_ORIGIN[i]
		var finish := origin + across * CRACK_SPREAD[i] + down * (1.0 - CRACK_SPREAD[i])
		draw_line(start, finish, Color(tint, alpha), scaled(CRACK_WIDTH), true)
