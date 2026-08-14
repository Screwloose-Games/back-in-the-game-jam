@tool
class_name LevelGeometryBuilder
extends Node3D

## Carves the level graph out of solid rock, so the design can be flown through.
##
## Every span of every tunnel contributes two brushes: a solid one the size of
## the hull, and a narrower one that hollows the bore out of it. ALL the hull
## brushes union first, then ALL the bore brushes subtract from the result. A
## bore brush is always strictly narrower than its own hull brush, so a span can
## never carve through to the outside whatever angle it sits at - which is what
## makes the six-way junctions in the mines safe. There are no seams to line up,
## only overlapping volumes.
##
## The technique comes from prototypes/core_loop/core_loop_tunnels.gd. What is
## new is that it reads a LevelGraph rather than a hand-written route table, so
## the space you fly through and the graph the sound and AI models run on are the
## same description.
##
## THIS IS A BLOCKOUT, NOT SHIPPING GEOMETRY. Carving the whole asteroid takes
## about 300 ms, which is fine for walking the level and is not fine for a web
## build; baking the result to static meshes is the way out of that when it
## matters.

## Segments on a chamber sphere. These are rock, so a chamber wants to read as
## quarried rather than as a machined dome - but a twelve-segment ball at the 20 m
## radii the hive uses reads as an error, not as a facet.
const CHAMBER_SEGMENTS := 16
const CHAMBER_RINGS := 8

## Sides on a round bore, for the same reason.
const ROUND_BORE_SIDES := 16

## Where the carved result is parked, so a rebuild can find and drop the old one.
const COMBINER_NAME := "HullCombiner"

## Metres a span reaches past a joint on top of its mitre, so the brushes meeting
## there overlap rather than merely touch.
const MIN_JOINT_OVERRUN := 0.25

## Turn angle past which the mitre stops growing. The mitre is a half-angle
## tangent, which runs away towards a half turn, and a hairpin does not need an
## unbounded brush to close.
const MAX_MITRED_TURN := PI * 2.0 / 3.0

## How close two span ends must be to count as meeting at the same joint, in
## metres. Ends that genuinely share a space are bit-identical; this is only here
## so a recomputed point on a split centreline still lands with its neighbour.
const JOINT_WELD := 0.05

## The level to carve. Its MineSpace radii become chambers and its MineTunnel
## widths become bores.
@export_node_path("Node3D") var level_path: NodePath:
	set(value):
		level_path = value
		update_configuration_warnings()

## Metres of rock left around every bore. Also how far a hull brush overruns its
## own span, which is what welds one tunnel into the next at a junction.
@export_range(0.25, 5.0, 0.25, "suffix:m") var wall_thickness := 1.0

## Tunnels carrying any of these tags get a round bore; every other tunnel gets a
## square one. The mines were cut by machine and the natural tunnels were not,
## and from the inside that difference is most of what tells you which one you
## are in. The hive was dug, so it rounds too - a square-edged slab reads as
## something with a plan, which is the one thing the hive is not.
##
## The ravine is split rather than listed whole: its side network was worn out of
## the rock and rounds, while the chasm runs stay square because the flat floor
## and the flat walls are what make the chasm read as a chasm.
@export var round_profile_tags: Array[StringName] = [
	&"natural", &"hive", &"winding", &"warren", &"biome_link"
]

## The rock. Left unset, a plain grey material is built instead, so this scene
## depends on nothing outside levels/.
@export var hull_material: Material = null

@export_flags_3d_physics var hull_layer := 1

## Carve on load. Turn it off when something else wants to drive build() at a
## moment of its own choosing.
@export var build_on_ready := true

@export_tool_button("Carve now") var carve_action := build
@export_tool_button("Clear") var clear_action := clear_geometry

var _overrun_by_tunnel: Dictionary = {}


## Carving in the editor is opt-in, through the Inspector button.
##
## The result is a couple of hundred CSG nodes, which is a lot to meet every time
## you happen to open the scene - and this is a @tool script only so that the
## button and the warnings work at all.
func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if build_on_ready:
		build()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not is_inside_tree():
		return warnings
	if get_node_or_null(level_path) as MineLevel == null:
		warnings.append("level_path does not point at a MineLevel, so there is nothing to carve.")
	return warnings


## Replaces the carved geometry with a fresh carve of the level as it stands.
func build() -> void:
	clear_geometry()
	_overrun_by_tunnel.clear()
	if not is_inside_tree():
		return
	var level := get_node_or_null(level_path) as MineLevel
	if level == null:
		push_warning(
			"LevelGeometryBuilder found no MineLevel at '%s'; nothing carved." % level_path
		)
		return

	var graph := level.build_graph()
	var combiner := CSGCombiner3D.new()
	combiner.name = COMBINER_NAME
	combiner.use_collision = true
	combiner.collision_layer = hull_layer
	# Nothing here moves, so nothing needs to detect anything. A mask costs
	# broadphase work for a query that is never asked.
	combiner.collision_mask = 0
	combiner.material_override = hull_material if hull_material != null else _default_material()
	add_child(combiner)

	var spans := _collect_spans(graph)
	var joints := _map_joints(spans)

	# Order is the whole trick: every hull, then every bore. Interleaving them
	# would let one tunnel's hull refill a bore already cut through it.
	for is_hull: bool in [true, false]:
		for index: int in spans.size():
			combiner.add_child(_span_brush(spans[index], index, joints, is_hull))
		for space: LevelGraph.Space in graph.spaces:
			var chamber := _chamber_brush(space, is_hull)
			if chamber != null:
				combiner.add_child(chamber)


func clear_geometry() -> void:
	var previous := get_node_or_null(NodePath(COMBINER_NAME))
	if previous == null:
		return
	remove_child(previous)
	previous.queue_free()


## How many brushes the last carve produced, for the walkthrough's console line.
func brush_count() -> int:
	var combiner := get_node_or_null(NodePath(COMBINER_NAME))
	return 0 if combiner == null else combiner.get_child_count()


## How far each run's bore reached past one of its own joints in the last carve,
## by tunnel id.
##
## Worth reporting because it is the number that decides whether a bend looks like
## a bend: everything a span carves past its own junction lands outside the level,
## and on a tall slot in a gentle turn it used to be most of the slot's height.
func overruns_by_tunnel() -> Dictionary:
	return _overrun_by_tunnel.duplicate()


## Every straight run in the level, in this node's own space.
##
## Flattened out of the graph up front because a span's shape depends on what it
## meets at either end, and a tunnel cannot see the tunnels arriving at the space
## it stops in.
func _collect_spans(graph: LevelGraph) -> Array[Dictionary]:
	var spans: Array[Dictionary] = []
	for tunnel: LevelGraph.Tunnel in graph.tunnels:
		var is_round := _wants_round_bore(tunnel)
		var points := tunnel.polyline
		for index: int in maxi(points.size() - 1, 0):
			# The graph speaks global coordinates; the brushes hang off this node.
			var start := to_local(points[index])
			var finish := to_local(points[index + 1])
			if start.is_equal_approx(finish):
				continue
			(
				spans
				. append(
					{
						"id": tunnel.id,
						"start": start,
						"finish": finish,
						"direction": (finish - start).normalized(),
						"width": tunnel.width,
						"height": tunnel.bore_height(),
						"round": is_round,
					}
				)
			)
	return spans


## Every span end gathered by where it lands, as the direction it leaves that
## point in. Two spans meeting at a joint turn through the angle between the paths
## that arrive and leave along them, which is what the mitre is measured from.
func _map_joints(spans: Array[Dictionary]) -> Dictionary:
	var joints := {}
	for index: int in spans.size():
		var span: Dictionary = spans[index]
		_record_joint(joints, span["start"], span["direction"], index)
		_record_joint(joints, span["finish"], -span["direction"], index)
	return joints


func _record_joint(joints: Dictionary, point: Vector3, away: Vector3, span_index: int) -> void:
	var key := Vector3i((point / JOINT_WELD).round())
	var arriving: Array = joints.get(key, [])
	arriving.append({"away": away, "span": span_index})
	joints[key] = arriving


## One span's brush. `is_hull` picks which of the pair, because the two differ
## only in size and operation and writing them apart invites them to drift.
##
## THE OVERRUN IS MITRED, NOT CONSTANT. A span reaches past a joint far enough
## that its own cross-section covers the corner and no further, which for a
## rectangular bore turning through an angle is exactly half its extent across the
## bend times the tangent of the half angle. Measuring it on the widest face
## instead - as this did - overruns a tall slot by half its HEIGHT even when the
## bend is a gentle one in plan, and the ravine's 3 m by 24 m chasm runs then
## carved twelve-metre spurs of air out through the wall at every station.
func _span_brush(
	span: Dictionary, span_index: int, joints: Dictionary, is_hull: bool
) -> CSGPrimitive3D:
	var width: float = span["width"]
	var height: float = span["height"]
	var direction: Vector3 = span["direction"]
	var bore := LevelGraph.bore_basis(direction)

	var start_overrun := _overrun_at(
		joints, span["start"], direction, span_index, bore, width, height, is_hull
	)
	var finish_overrun := _overrun_at(
		joints, span["finish"], -direction, span_index, bore, width, height, is_hull
	)
	if not is_hull:
		var tunnel_id := String(span["id"])
		var reach := maxf(start_overrun, finish_overrun)
		_overrun_by_tunnel[tunnel_id] = maxf(_overrun_by_tunnel.get(tunnel_id, 0.0), reach)

	var from_point: Vector3 = span["start"] - direction * start_overrun
	var to_point: Vector3 = span["finish"] + direction * finish_overrun

	var across := width + wall_thickness * 2.0 if is_hull else width
	var tall := height + wall_thickness * 2.0 if is_hull else height
	var length := from_point.distance_to(to_point)
	var midpoint := (from_point + to_point) * 0.5
	var operation := CSGShape3D.OPERATION_UNION if is_hull else CSGShape3D.OPERATION_SUBTRACTION

	if span["round"]:
		var tube := CSGCylinder3D.new()
		tube.radius = across * 0.5
		tube.height = length
		tube.sides = ROUND_BORE_SIDES
		tube.operation = operation
		# A CSGCylinder3D runs along its own Y and is circular, so an oval bore is
		# a circular one squashed across the up-ish axis bore_basis picks out.
		tube.transform = Transform3D(
			bore * Basis.from_scale(Vector3(1.0, 1.0, tall / maxf(across, 0.001))), midpoint
		)
		return tube

	var box := CSGBox3D.new()
	# looking_at puts the run on Z, the width on X and the height on Y.
	box.size = Vector3(across, tall, length)
	box.operation = operation
	box.transform = Transform3D(Basis.looking_at(direction, _reference_up(direction)), midpoint)
	return box


## How far this span has to reach past one of its own ends.
##
## `away` points out of the joint along this span. A terminus - a span end nothing
## else arrives at - keeps the old generous reach, because there is nothing there
## for it to poke through and a dead end wants the depth.
func _overrun_at(
	joints: Dictionary,
	point: Vector3,
	away: Vector3,
	span_index: int,
	bore: Basis,
	width: float,
	height: float,
	is_hull: bool
) -> float:
	var widest_turn := -1.0
	var turning_towards := Vector3.ZERO
	for arriving: Dictionary in joints.get(Vector3i((point / JOINT_WELD).round()), []):
		if arriving["span"] == span_index:
			continue
		var other: Vector3 = arriving["away"]
		var turn := PI - acos(clampf(away.dot(other), -1.0, 1.0))
		if turn > widest_turn:
			widest_turn = turn
			turning_towards = other

	# The reach this had before it was mitred, and still the ceiling. A mitre is a
	# half-angle tangent, so it grows without bound as a joint approaches a hairpin
	# and would carve further than the blunt reach it replaced - on a 20 m hive bore
	# doubling back, nearly twice as far. The mitre exists to take overrun away.
	var reach := maxf(width, height) * 0.5
	if widest_turn < 0.0:
		# A terminus: nothing meets it, so nothing is poked through, and a dead end
		# wants the depth the reach gives it.
		return reach + wall_thickness if is_hull else reach

	# The bend opens towards whatever of the other span is not along this one, so
	# that is the direction the cross-section has to be measured across.
	var sideways := turning_towards - away * away.dot(turning_towards)
	var half := reach
	if not sideways.is_zero_approx():
		var across_axis := sideways.normalized()
		half = (
			absf(across_axis.dot(bore.x)) * width * 0.5
			+ absf(across_axis.dot(bore.z)) * height * 0.5
		)

	var mitred := half * tan(minf(widest_turn, MAX_MITRED_TURN) * 0.5)
	var overrun := clampf(mitred, MIN_JOINT_OVERRUN, reach)
	return overrun + wall_thickness if is_hull else overrun


## A chamber at a space, or null where the space is a bare corner with no room.
##
## Null on both passes or neither: skipping only the bore would leave the hull
## standing as a plug of solid rock across the junction.
##
## THE TWO SEMI-AXES GROW BY THE WALL SEPARATELY. Scaling a hull sphere as a unit
## would leave only `wall_thickness * vertical_scale` of rock above a flat chamber,
## so a stratum of them would carve through to whatever sits above.
func _chamber_brush(space: LevelGraph.Space, is_hull: bool) -> CSGSphere3D:
	if space.radius <= 0.0:
		return null
	var horizontal := space.radius
	var vertical := space.radius * space.vertical_scale
	if is_hull:
		horizontal += wall_thickness
		vertical += wall_thickness

	var brush := CSGSphere3D.new()
	brush.radius = horizontal
	brush.radial_segments = CHAMBER_SEGMENTS
	brush.rings = CHAMBER_RINGS
	brush.operation = CSGShape3D.OPERATION_UNION if is_hull else CSGShape3D.OPERATION_SUBTRACTION
	# Exactly the identity at vertical_scale 1.0, which is what leaves every
	# spherical chamber in the mines and the ravine where it was.
	brush.transform = Transform3D(
		Basis.from_scale(Vector3(1.0, vertical / horizontal, 1.0)), to_local(space.position)
	)
	return brush


func _wants_round_bore(tunnel: LevelGraph.Tunnel) -> bool:
	for tag: StringName in round_profile_tags:
		if tunnel.tags.has(tag):
			return true
	return false


## Basis.looking_at fails when its up vector is parallel to the direction it is
## given, and the cavern shafts and the winzes here are exactly vertical.
func _reference_up(direction: Vector3) -> Vector3:
	if absf(direction.dot(Vector3.UP)) > 0.99:
		return Vector3.BACK
	return Vector3.UP


func _default_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.34, 0.35, 0.37)
	material.metallic = 0.1
	material.metallic_specular = 0.3
	material.roughness = 0.85
	return material
