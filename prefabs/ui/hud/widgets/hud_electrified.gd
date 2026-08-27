@tool
class_name HudElectrified
extends HudWidget

## What a live arc looks like from inside the helmet: the glass crackling around the rim
## while the middle stays clear, because the one thing you still need while it has you is
## to see where you are going.

const DESIGN_SIZE := Vector2(1917.0, 1077.0)

## How much of the way to the screen edge is left alone, measured along each bolt's own
## direction rather than as a radius. That makes the clear zone an ELLIPSE matching the
## screen: a true circle on 16:9 lets the horizontal bolts reach twice as far in as the
## vertical ones, and the middle stops reading as clear.
const CLEAR_FRACTION := 0.58

## How much further in a bolt may start, so the inner ends do not all land on one ring.
const CLEAR_RAGGED := 0.18

## How often the pattern is redrawn. Electricity flickers -- it does not strobe at the
## frame rate, and it does not hold still either.
const CRACKLE_HZ := 18.0

const BOLT_COUNT := 18
const BOLT_SEGMENTS := 5
const BOLT_WANDER := 0.1
const BOLT_WIDTH := 2.6
const BOLT_COLOR := Color(0.72, 0.88, 1.0)

## The base glow, in the same four corner wedges Damage_Overlay and VisorDamage use, so
## the three overlays read as one system.
const REACH_ACROSS := 0.469329
const REACH_DOWN := 0.386145
const GLOW_COLOR := Color(0.36, 0.63, 1.0)
const GLOW_ALPHA := 0.34
const GLOW_PULSE_HZ := 7.0
const GLOW_PULSE_DEPTH := 0.35
const SPENT := Color(0.36, 0.63, 1.0, 0.0)

## Drives the draw in the editor, so the effect can be judged without standing in an arc.
@export var preview_electrified := false:
	set(value):
		preview_electrified = value
		if Engine.is_editor_hint():
			show_electrified(value)

var _active := false
var _elapsed := 0.0
var _phase := -1
var _rng := RandomNumberGenerator.new()


## Distance from the centre of a rect to its edge along `direction`.
static func edge_reach(direction: Vector2, half_extent: Vector2) -> float:
	var across := half_extent.x / maxf(absf(direction.x), 0.0001)
	var down := half_extent.y / maxf(absf(direction.y), 0.0001)
	return minf(across, down)


func _ready() -> void:
	super()
	set_process(false)


func bind(state: HudState) -> void:
	state.electrified_changed.connect(show_electrified)


func show_electrified(active: bool) -> void:
	_active = active
	if not active:
		_elapsed = 0.0
		_phase = -1
	set_process(active)
	queue_redraw()


func _process(delta: float) -> void:
	_elapsed += delta
	# Redraw on the crackle clock rather than every frame: at 144 Hz the per-frame
	# version reads as static rather than as electricity.
	var phase := int(_elapsed * CRACKLE_HZ)
	if phase == _phase:
		return
	_phase = phase
	queue_redraw()


func design_extent() -> Vector2:
	return DESIGN_SIZE


func _draw() -> void:
	if not _active or size.x <= 0.0 or size.y <= 0.0:
		return
	# Seeded off the crackle phase, so one pattern holds for a whole flicker and the next
	# one is unrelated to it.
	_rng.seed = maxi(_phase, 0) * 7919 + 13
	var pulse := 1.0 - GLOW_PULSE_DEPTH * (0.5 - 0.5 * cos(_elapsed * TAU * GLOW_PULSE_HZ))
	for corner in 4:
		_draw_glow(corner, GLOW_ALPHA * pulse)
	var centre := size * 0.5
	for i in BOLT_COUNT:
		# One bolt per slice with jitter inside it, so they ring the rim without clumping.
		var angle := TAU * (float(i) + _rng.randf()) / float(BOLT_COUNT)
		var direction := Vector2(cos(angle), sin(angle))
		var reach := edge_reach(direction, centre)
		var inset := CLEAR_FRACTION + _rng.randf() * CLEAR_RAGGED
		_draw_bolt(centre + direction * reach, centre + direction * reach * inset)


func _draw_glow(corner: int, alpha: float) -> void:
	var horizontal := corner % 2 == 0
	var vertical := corner < 2
	var origin := Vector2(0.0 if horizontal else size.x, 0.0 if vertical else size.y)
	var across := Vector2(size.x * REACH_ACROSS * (1.0 if horizontal else -1.0), 0.0)
	var down := Vector2(0.0, size.y * REACH_DOWN * (1.0 if vertical else -1.0))
	var points: PackedVector2Array = [origin, origin + across, origin + down]
	var colours: PackedColorArray = [Color(GLOW_COLOR, alpha), SPENT, SPENT]
	draw_polygon(points, colours)


## One jagged run from the rim inward, stopping short of the clear circle.
func _draw_bolt(from: Vector2, to: Vector2) -> void:
	var axis := to - from
	var reach := axis.length()
	if reach <= 0.0:
		return
	var side := Vector2(-axis.y, axis.x) / reach
	var points := PackedVector2Array()
	for s in BOLT_SEGMENTS + 1:
		var wander := 0.0
		# The ends stay put; only the middle wanders, so a bolt still reads as one run.
		if s > 0 and s < BOLT_SEGMENTS:
			wander = _rng.randf_range(-1.0, 1.0) * reach * BOLT_WANDER
		points.append(from + axis * (float(s) / float(BOLT_SEGMENTS)) + side * wander)
	draw_polyline(points, BOLT_COLOR, scaled(BOLT_WIDTH), true)
