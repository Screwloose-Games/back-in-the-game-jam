class_name LevelMinimap
extends Control

## Top-down plan of the blockout being walked, with the suit drawn on it.
##
## Built from the level graph, not from the carved rock: every space already
## knows its world position and radius and every tunnel its polyline and width,
## so this is a few hundred 2D draw calls over a snapshot taken once. No second
## camera, no SubViewport, no extra pass over the geometry - which matters on the
## GL Compatibility renderer, where rendering the world from above would cost
## roughly a second full draw of the level.
##
## DEPTH IS A FADE, NOT A CUT. These levels stack - the hive is stratified, the
## ravine is a tall slot - so a flat plan piles unrelated layers on top of each
## other. Everything is drawn, but anything far above or below the suit thins and
## dims towards DIM_FLOOR. The layer being flown stays legible without hiding
## what it is stacked on.
##
## A DESIGN TOOL, NOT THE GAME'S MAP. The whole level shows from the first frame,
## including places never visited, because the question being answered is whether
## the layout came out as intended.

## Metres above or below the suit at which a space or tunnel has faded all the
## way out. Roughly the vertical gap between hive strata, so one stratum reads as
## solid and its neighbours as ghosts.
const FADE_OVER_METRES := 25.0

## How visible the most distant layer still is. Not zero: a stratum you cannot
## see at all is one you forget the level has.
const DIM_FLOOR := 0.12

const KEY_TOGGLE_MAP := KEY_M
const KEY_TOGGLE_NAMES := KEY_N
const KEY_ZOOM_IN := KEY_EQUAL
const KEY_ZOOM_OUT := KEY_MINUS
const ZOOM_STEP := 1.3
const ZOOM_MIN := 1.0
const ZOOM_MAX := 12.0

const MARGIN_PIXELS := 16.0
const PADDING_PIXELS := 10.0
const SUIT_MARKER_PIXELS := 7.0
const MIN_LINE_PIXELS := 1.0
const MIN_SPACE_PIXELS := 2.0

## Widest a tunnel is ever drawn. Bores here run to 9 m against chambers of 10 m,
## so at a fitted zoom a true-to-scale tunnel is as fat as the rooms it joins and
## the map reads as a mass of corridor. Capped, relative width still reads.
const MAX_LINE_PIXELS := 6.0

## Below this many pixels across, a space is too small to hold its own name.
const NAME_THRESHOLD_PIXELS := 7.0

## How much of the level's longest side the fitted view leaves as margin.
const FIT_MARGIN := 1.08

const COLOR_PANEL := Color(0.03, 0.04, 0.06, 0.72)
const COLOR_BORDER := Color(0.45, 0.55, 0.7, 0.5)
const COLOR_SUIT := Color(1.0, 0.95, 0.5)
const COLOR_ENTRANCE := Color(0.4, 1.0, 0.6)
const COLOR_TEXT := Color(0.8, 0.86, 0.95)

@export var panel_size := Vector2(340.0, 340.0)

## Metres of level across the panel at zoom 1.0. Zero fits the whole level.
@export var visible_span_metres := 0.0

## Names on every space, toggled live with N.
##
## Off, because a stratum of the hive is fifty chambers inside ninety metres and
## every one of them labelled is a wall of overlapping text. Which space the suit
## is in is always on the readout regardless; this is for when the question is
## about some OTHER space.
@export var show_space_names := false

var _level: MineLevel = null
var _suit: Node3D = null
var _spaces: Array[MappedSpace] = []
var _segments: Array[MappedSegment] = []
var _entrance_position := Vector3.ZERO
var _has_entrance := false
var _fitted_span_metres := 1.0
var _zoom := 1.0

## Set once per _draw so the projection helpers do not each recompute it.
var _pixels_per_metre := 1.0
var _view_centre := Vector3.ZERO
var _suit_height := 0.0


func _ready() -> void:
	# A focused control eats ui_accept and ui_left/ui_right, which here are thrust
	# up and strafe - it reads as broken flight rather than as a UI bug.
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Chambers at the edge of the view, and names hanging off them, otherwise draw
	# straight across the rest of the screen.
	clip_contents = true
	_anchor_top_right()


func _process(_delta: float) -> void:
	if visible and _suit != null:
		queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_TOGGLE_MAP:
			visible = not visible
		KEY_TOGGLE_NAMES:
			show_space_names = not show_space_names
		KEY_ZOOM_IN:
			_zoom = clampf(_zoom * ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
		KEY_ZOOM_OUT:
			_zoom = clampf(_zoom / ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)


## Points the map at a level and the suit flying it, and takes its snapshot.
##
## Snapshot rather than a live read because a blockout does not move while it is
## being walked, so the per-frame cost is projection and drawing alone.
func watch(level: MineLevel, suit: Node3D) -> void:
	_level = level
	_suit = suit
	_snapshot_level()


## Reads the level into flat records in the map's own terms.
##
## Colours come from the level's own colour mode, so the map agrees with the
## design overlay and with the editor viewport rather than inventing a scheme.
func _snapshot_level() -> void:
	_spaces.clear()
	_segments.clear()
	if _level == null:
		return

	# Forces the level to recompute before any colour is asked for. In SOUND mode
	# the colour of a space is read from the sound field, which is only built when
	# the level's own _process has run at least once - and that is a frame later
	# than this.
	_level.current_sound_field()

	for space: MineSpace in _level.spaces_in_level():
		var mapped := MappedSpace.new()
		mapped.label = space.name
		mapped.centre = space.global_position
		mapped.radius = space.radius
		mapped.color = _level.color_for_space(space)
		_spaces.append(mapped)

	for tunnel: MineTunnel in _level.tunnels_in_level():
		if not tunnel.describe_problem().is_empty():
			continue
		var color := _level.color_for_tunnel(tunnel)
		var points := tunnel.build_polyline()
		for index: int in maxi(points.size() - 1, 0):
			var segment := MappedSegment.new()
			segment.start = points[index]
			segment.finish = points[index + 1]
			segment.width = tunnel.width
			segment.color = color
			_segments.append(segment)

	var entrance := _level.get_node_or_null(_level.entrance_space) as MineSpace
	_has_entrance = entrance != null
	if _has_entrance:
		_entrance_position = entrance.global_position

	_measure_fitted_span()


## The span that shows the whole level, so zoom 1.0 means "all of it".
func _measure_fitted_span() -> void:
	var box := _level.build_graph().bounds()
	_fitted_span_metres = maxf(maxf(box.size.x, box.size.z) * FIT_MARGIN, 1.0)


func _draw() -> void:
	if _suit == null:
		return
	_prepare_projection()

	draw_rect(Rect2(Vector2.ZERO, size), COLOR_PANEL)
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BORDER, false, 1.0)

	# Two passes rather than a depth sort: distant geometry is drawn first so the
	# layer the suit is in lands on top of it, and within a pass the overlap order
	# does not read because everything in it is nearly transparent anyway.
	_draw_tunnels(false)
	_draw_tunnels(true)
	_draw_spaces(false)
	_draw_spaces(true)

	if _has_entrance:
		_draw_entrance()
	_draw_suit()
	_draw_readout()


## Fixes the metres-to-pixels scale and what the panel is centred on.
##
## The centre is the level itself while the whole level fits, and the suit once
## zoomed past that: a fitted map that slid around under the suit would be harder
## to read a layout from, and a zoomed one that did not follow would lose it.
func _prepare_projection() -> void:
	var span := (visible_span_metres if visible_span_metres > 0.0 else _fitted_span_metres) / _zoom
	var shortest_side := minf(size.x, size.y) - PADDING_PIXELS * 2.0
	_pixels_per_metre = shortest_side / maxf(span, 0.001)
	_suit_height = _suit.global_position.y
	if span >= _fitted_span_metres:
		var box := AABB()
		if not _spaces.is_empty():
			box = _level.build_graph().bounds()
		_view_centre = box.get_center()
	else:
		_view_centre = _suit.global_position


## World to panel. X runs across and Z runs down, so a heading of Vector3.FORWARD
## points up the map.
func _project(world: Vector3) -> Vector2:
	var offset := Vector2(world.x - _view_centre.x, world.z - _view_centre.z)
	return size * 0.5 + offset * _pixels_per_metre


## How present something at this height is, from DIM_FLOOR to 1.0.
##
## Squared, so the stratum the suit is in separates sharply from the one above it
## rather than the two shading into each other.
func _depth_presence(world_height: float) -> float:
	var gap := absf(world_height - _suit_height)
	var nearness := 1.0 - clampf(gap / FADE_OVER_METRES, 0.0, 1.0)
	return lerpf(DIM_FLOOR, 1.0, nearness * nearness)


## Whether something at this height belongs to the near pass.
func _is_near(world_height: float) -> bool:
	return _depth_presence(world_height) > 0.5


func _draw_tunnels(near_pass: bool) -> void:
	for segment: MappedSegment in _segments:
		var height := (segment.start.y + segment.finish.y) * 0.5
		if _is_near(height) != near_pass:
			continue
		var presence := _depth_presence(height)
		var thickness := clampf(
			segment.width * _pixels_per_metre * presence, MIN_LINE_PIXELS, MAX_LINE_PIXELS
		)
		draw_line(
			_project(segment.start),
			_project(segment.finish),
			_faded(segment.color, presence),
			thickness
		)


func _draw_spaces(near_pass: bool) -> void:
	for space: MappedSpace in _spaces:
		if _is_near(space.centre.y) != near_pass:
			continue
		var presence := _depth_presence(space.centre.y)
		var middle := _project(space.centre)
		var radius := maxf(space.radius * _pixels_per_metre, MIN_SPACE_PIXELS)
		draw_circle(middle, radius, _faded(space.color, presence * 0.35))
		draw_circle(middle, radius, _faded(space.color, presence), false, MIN_LINE_PIXELS)
		if show_space_names and near_pass and radius >= NAME_THRESHOLD_PIXELS:
			_draw_text(String(space.label), middle + Vector2(radius + 3.0, 3.0), presence)


func _draw_entrance() -> void:
	var middle := _project(_entrance_position)
	var presence := _depth_presence(_entrance_position.y)
	var arm := SUIT_MARKER_PIXELS * 0.8
	var color := _faded(COLOR_ENTRANCE, presence)
	draw_line(middle - Vector2(arm, arm), middle + Vector2(arm, arm), color, MIN_LINE_PIXELS)
	draw_line(middle - Vector2(arm, -arm), middle + Vector2(arm, -arm), color, MIN_LINE_PIXELS)


## The suit, over a dark copy of itself.
##
## The backing is not decoration: a chamber the suit is inside is drawn in the
## same bright end of the palette the marker is, and without something dark
## between them the one thing on the map that has to be findable at a glance is
## the one thing that disappears.
func _draw_suit() -> void:
	var middle := _project(_suit.global_position)
	var heading := _suit_heading()
	draw_colored_polygon(_suit_points(middle, heading, 1.7), Color(0.0, 0.0, 0.0, 0.8))
	draw_colored_polygon(_suit_points(middle, heading, 1.0), COLOR_SUIT)


func _suit_points(middle: Vector2, heading: Vector2, scale: float) -> PackedVector2Array:
	var across := Vector2(-heading.y, heading.x)
	var reach := SUIT_MARKER_PIXELS * scale
	return PackedVector2Array(
		[
			middle + heading * reach,
			middle - heading * reach * 0.6 + across * reach * 0.6,
			middle - heading * reach * 0.6 - across * reach * 0.6,
		]
	)


## Which way the suit is pointing, flattened onto the map.
##
## Looking straight up or down leaves the forward axis with no horizontal part at
## all, and the marker would spin on the noise in it. The head's up axis is the
## one that still says which way the body is aimed in that case.
func _suit_heading() -> Vector2:
	var orientation := _suit.global_transform.basis
	var forward := -orientation.z
	var flattened := Vector2(forward.x, forward.z)
	if flattened.length() < 0.05:
		var up_axis := orientation.y * (-1.0 if forward.y > 0.0 else 1.0)
		flattened = Vector2(up_axis.x, up_axis.z)
	if flattened.length() < 0.001:
		return Vector2.UP
	return flattened.normalized()


## Where the suit is in the level's own terms, plus the map's scale and keys.
func _draw_readout() -> void:
	var lines := PackedStringArray()
	lines.append("%s   %.0f m deep" % [_describe_location(), -_suit.global_position.y])
	lines.append(
		(
			"%.0f m across   %s"
			% [(size.x - PADDING_PIXELS * 2.0) / _pixels_per_metre, "M map  N names  -/= zoom"]
		)
	)
	var baseline := size.y - PADDING_PIXELS - float(lines.size() - 1) * 13.0
	for line: String in lines:
		_draw_text(line, Vector2(PADDING_PIXELS, baseline), 1.0)
		baseline += 13.0


## The space the suit is inside, or the nearest one when it is in a tunnel.
func _describe_location() -> String:
	var here := _suit.global_position
	var closest: MappedSpace = null
	var closest_gap := INF
	for space: MappedSpace in _spaces:
		var gap := here.distance_to(space.centre)
		if gap < closest_gap:
			closest_gap = gap
			closest = space
	if closest == null:
		return "nowhere"
	if closest_gap <= closest.radius:
		return String(closest.label)
	return "%.0f m from %s" % [closest_gap - closest.radius, closest.label]


func _draw_text(text: String, where: Vector2, presence: float) -> void:
	draw_string(
		ThemeDB.fallback_font,
		where,
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		11,
		_faded(COLOR_TEXT, presence)
	)


func _faded(color: Color, presence: float) -> Color:
	return Color(color.r, color.g, color.b, presence)


func _anchor_top_right() -> void:
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -panel_size.x - MARGIN_PIXELS
	offset_right = -MARGIN_PIXELS
	offset_top = MARGIN_PIXELS
	offset_bottom = MARGIN_PIXELS + panel_size.y


## One space, reduced to what drawing it needs.
class MappedSpace:
	extends RefCounted

	var label := &""
	var centre := Vector3.ZERO
	var radius := 0.0
	var color := Color.WHITE


## One straight run of one tunnel. Tunnels are split at their bends here so that
## a tunnel crossing strata fades along its length rather than all at once.
class MappedSegment:
	extends RefCounted

	var start := Vector3.ZERO
	var finish := Vector3.ZERO
	var width := 0.0
	var color := Color.WHITE
