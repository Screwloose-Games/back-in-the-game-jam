class_name LampCurveEditor
extends Control

## An editable Curve, drawn and dragged while the game is running.
##
## Godot's own curve editor is part of the editor and does not exist in a running
## game, so this is the stand-in: click empty space to add a point, drag a point
## to move it, right-click one to drop it. Any number of points, which is the
## whole reason it exists - the shapes worth arguing about are the ones no single
## exponent can make.
##
## IT EDITS THE Curve RESOURCE IN PLACE, and that is what keeps it this small.
## LampPowerResponse samples the same resource every frame, so there is no signal
## to wire, nothing to push back, and no second copy of the shape to keep in step.
## Whoever hands a curve to bind() is handing over the live one on purpose.
##
## FOCUS_NONE like every other control on this panel - see PowerTuningPanel, which
## explains what a focused control does to the flight controls.
##
## Nothing here is saved. The panel's print button is how a shape leaves a
## session, because a curve cannot be read off a label the way a slider can.

const BACKGROUND_COLOR := Color(0.06, 0.07, 0.09, 0.85)
const GRID_COLOR := Color(0.28, 0.34, 0.42, 0.3)
const LINE_COLOR := Color(0.55, 0.85, 1.0, 0.95)
const POINT_COLOR := Color(1.0, 0.82, 0.45)
const TEXT_COLOR := Color(0.62, 0.74, 0.86, 0.75)
const TEXT_SIZE := 9

## Grid divisions each way. Quarters: enough to judge a point's height against
## without turning the panel into graph paper.
const GRID_DIVISIONS := 4

## How near a point a click counts as grabbing it, in pixels. Deliberately wider
## than the dot it grabs - the dot is a target on a 190-pixel-wide panel, and a
## missed grab silently adds a point instead, which is the worse failure.
const GRAB_RADIUS := 9.0
const POINT_RADIUS := 3.5

## How many samples the drawn line is built from. One per two pixels at this
## width, past which nothing more would show.
const DRAW_SAMPLES := 96

## A curve with one point is a constant and cannot be dragged back into a shape,
## so removal stops here.
const MINIMUM_POINTS := 2

var _curve: Curve

## What the values are counted in, for the labels. Empty means a bare fraction.
var _units := ""

## Index of the point being dragged, or -1. Reassigned on every move: a drag past
## a neighbour reorders the curve's points underneath it.
var _dragging := -1


## PASS rather than the default STOP, so events this widget does not accept carry
## on up the tree. It handles clicks and drags and nothing else, and a control on
## STOP ends the walk upwards for every button event including the wheel - which
## would leave a scroll view above it dead everywhere one of these is on screen.
func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND_COLOR)
	_draw_grid()
	if _curve == null:
		return
	_draw_curve()
	_draw_points()
	_draw_labels()


func _gui_input(event: InputEvent) -> void:
	if _curve == null:
		return
	var button := event as InputEventMouseButton
	if button != null:
		_handle_button(button)
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _dragging >= 0:
		_move_point(motion.position)


## Hands over the live curve to edit and what its values are counted in.
func bind(curve: Curve, units: String) -> void:
	_curve = curve
	_units = units
	queue_redraw()


func _handle_button(button: InputEventMouseButton) -> void:
	if button.button_index == MOUSE_BUTTON_RIGHT:
		if button.pressed:
			_remove_point_at(button.position)
		return
	if button.button_index != MOUSE_BUTTON_LEFT:
		return
	if not button.pressed:
		_dragging = -1
		queue_redraw()
		return

	_dragging = _point_at(button.position)
	if _dragging < 0:
		# A click on empty space adds a point and starts dragging it, so placing
		# one and then placing it accurately is a single gesture.
		_dragging = _curve.add_point(
			_to_curve(button.position), 0.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR
		)
	queue_redraw()


func _move_point(at: Vector2) -> void:
	var point := _to_curve(at)
	_curve.set_point_value(_dragging, point.y)
	# set_point_offset returns the point's index AFTER any reorder its new offset
	# caused. Dropping that return is how dragging a point past its neighbour ends
	# up dragging the neighbour instead.
	_dragging = _curve.set_point_offset(_dragging, point.x)
	queue_redraw()


func _remove_point_at(at: Vector2) -> void:
	if _curve.point_count <= MINIMUM_POINTS:
		return
	var index := _point_at(at)
	if index < 0:
		return
	_curve.remove_point(index)
	_dragging = -1
	queue_redraw()


## The nearest point within GRAB_RADIUS, or -1. Nearest rather than first, so two
## points close together still each have a side of the gap between them.
func _point_at(at: Vector2) -> int:
	var found := -1
	var nearest := GRAB_RADIUS
	for index: int in _curve.point_count:
		var distance := _to_screen(_curve.get_point_position(index)).distance_to(at)
		if distance <= nearest:
			found = index
			nearest = distance
	return found


func _to_screen(point: Vector2) -> Vector2:
	var span := maxf(_curve.max_value - _curve.min_value, 0.0001)
	var height := (point.y - _curve.min_value) / span
	return Vector2(point.x * size.x, size.y - height * size.y)


func _to_curve(at: Vector2) -> Vector2:
	var span := _curve.max_value - _curve.min_value
	var height := clampf(1.0 - at.y / size.y, 0.0, 1.0)
	return Vector2(clampf(at.x / size.x, 0.0, 1.0), _curve.min_value + height * span)


func _draw_grid() -> void:
	for step: int in GRID_DIVISIONS + 1:
		var along := float(step) / GRID_DIVISIONS
		draw_line(Vector2(along * size.x, 0.0), Vector2(along * size.x, size.y), GRID_COLOR)
		draw_line(Vector2(0.0, along * size.y), Vector2(size.x, along * size.y), GRID_COLOR)


## Drawn by sampling rather than by joining the points, so what is on screen is
## what LampPowerResponse will read - if the two ever disagreed, the drawing is
## the one that would be believed.
func _draw_curve() -> void:
	var line := PackedVector2Array()
	for step: int in DRAW_SAMPLES + 1:
		var along := float(step) / DRAW_SAMPLES
		line.append(_to_screen(Vector2(along, _curve.sample(along))))
	draw_polyline(line, LINE_COLOR, 1.5)


func _draw_points() -> void:
	for index: int in _curve.point_count:
		var radius := POINT_RADIUS + (1.5 if index == _dragging else 0.0)
		draw_circle(_to_screen(_curve.get_point_position(index)), radius, POINT_COLOR)


## The axis top, and the point being dragged. The bottom of the axis is always
## zero on both curves, so it is left off rather than stated.
func _draw_labels() -> void:
	_draw_text(Vector2(3.0, TEXT_SIZE + 2.0), "%.2f%s" % [_curve.max_value, _units])
	if _dragging < 0:
		return
	var point := _curve.get_point_position(_dragging)
	_draw_text(
		Vector2(3.0, size.y - 3.0), "%.0f%% charge  %.2f%s" % [point.x * 100.0, point.y, _units]
	)


func _draw_text(at: Vector2, text: String) -> void:
	draw_string(
		get_theme_default_font(), at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE, TEXT_COLOR
	)
