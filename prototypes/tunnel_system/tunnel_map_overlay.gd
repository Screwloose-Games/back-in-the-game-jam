class_name TunnelMapOverlay
extends Control

## The network drawn twice: a plan view down the Y axis, and an elevation across
## it.
##
## TWO projections, because one is a lie in this level. Plan alone cannot tell
## the entrance shaft from the 75 m deep shaft it sits above - they are the same
## dot - and elevation alone folds the east and west trunks onto each other. The
## pair is the minimum that makes a 200 m cube legible on a flat screen.
##
## Line thickness carries bore, so the trunks the creature can follow read
## differently from the branches it cannot at a glance.

const PANEL_SIZE := 190.0
const PANEL_GAP := 8.0
const BACKGROUND := Color(0.04, 0.05, 0.06, 0.72)
const BORDER := Color(0.36, 0.44, 0.52, 0.55)
const TIGHT_COLOR := Color(0.45, 0.62, 0.78, 0.85)
const TRUNK_COLOR := Color(0.85, 0.62, 0.35, 0.9)
const JUNCTION_COLOR := Color(0.95, 0.95, 0.98, 0.8)
const PLAYER_COLOR := Color(0.4, 1.0, 0.55, 1.0)

var _network: TunnelNetwork
var _player: Node3D


func _draw() -> void:
	if _network == null:
		return
	_draw_panel(Vector2.ZERO, true)
	_draw_panel(Vector2(0.0, PANEL_SIZE + PANEL_GAP), false)


func bind(network: TunnelNetwork, player: Node3D) -> void:
	_network = network
	_player = player
	custom_minimum_size = Vector2(PANEL_SIZE, PANEL_SIZE * 2.0 + PANEL_GAP)
	queue_redraw()


## `plan` picks the projection: true is looking down (X across, Z up the panel),
## false is looking side-on (X across, depth down the panel).
func _draw_panel(origin: Vector2, plan: bool) -> void:
	draw_rect(Rect2(origin, Vector2(PANEL_SIZE, PANEL_SIZE)), BACKGROUND)
	draw_rect(Rect2(origin, Vector2(PANEL_SIZE, PANEL_SIZE)), BORDER, false, 1.0)

	for route: Dictionary in _network.routes:
		var points: PackedVector3Array = route["points"]
		var radii: PackedFloat32Array = route["radii"]
		var wide := radii[0] >= TunnelKnobs.BORE_CONNECTOR
		var color := TRUNK_COLOR if wide else TIGHT_COLOR
		var width := 2.4 if wide else 1.0
		for i: int in points.size() - 1:
			draw_line(
				origin + _project(points[i], plan),
				origin + _project(points[i + 1], plan),
				color,
				width
			)

	for index: int in _network.junctions.size():
		if _network.junction_degree(index) < 3:
			continue
		draw_circle(origin + _project(_network.junctions[index], plan), 2.5, JUNCTION_COLOR)

	if _player != null:
		var here := origin + _project(_player.global_position, plan)
		draw_circle(here, 3.5, PLAYER_COLOR)
		draw_arc(here, 6.0, 0.0, TAU, 16, PLAYER_COLOR, 1.0)


## World metres to panel pixels. X always runs across; the vertical axis is Z for
## the plan view and depth for the elevation. Both are flipped so that "up the
## panel" means +Z / shallower, which is what a reader expects.
func _project(point: Vector3, plan: bool) -> Vector2:
	var half := TunnelKnobs.WORLD_EXTENT * 0.5
	var across := (point.x + half) / TunnelKnobs.WORLD_EXTENT
	var down := (
		(half - point.z) / TunnelKnobs.WORLD_EXTENT if plan else -point.y / TunnelKnobs.WORLD_EXTENT
	)
	return Vector2(clampf(across, 0.0, 1.0) * PANEL_SIZE, clampf(down, 0.0, 1.0) * PANEL_SIZE)
