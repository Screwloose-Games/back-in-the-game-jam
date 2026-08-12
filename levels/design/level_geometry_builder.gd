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

## Segments on a chamber sphere. Low: these are rock, and a chamber that reads as
## a faceted ball is closer to right than one that reads as a machined dome.
const CHAMBER_SEGMENTS := 12
const CHAMBER_RINGS := 6

## Sides on a round bore, for the same reason.
const ROUND_BORE_SIDES := 10

## Where the carved result is parked, so a rebuild can find and drop the old one.
const COMBINER_NAME := "HullCombiner"

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
## are in.
@export var round_profile_tags: Array[StringName] = [&"natural"]

## The rock. Left unset, a plain grey material is built instead, so this scene
## depends on nothing outside levels/.
@export var hull_material: Material = null

@export_flags_3d_physics var hull_layer := 1

## Carve on load. Turn it off when something else wants to drive build() at a
## moment of its own choosing.
@export var build_on_ready := true

@export_tool_button("Carve now") var carve_action := build
@export_tool_button("Clear") var clear_action := clear_geometry


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

	# Order is the whole trick: every hull, then every bore. Interleaving them
	# would let one tunnel's hull refill a bore already cut through it.
	for is_hull: bool in [true, false]:
		for tunnel: LevelGraph.Tunnel in graph.tunnels:
			_add_span_brushes(combiner, tunnel, is_hull)
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


func _add_span_brushes(combiner: CSGCombiner3D, tunnel: LevelGraph.Tunnel, is_hull: bool) -> void:
	var is_round := _wants_round_bore(tunnel)
	var points := tunnel.polyline
	for index: int in maxi(points.size() - 1, 0):
		# The graph speaks global coordinates; the brushes hang off this node.
		var start := to_local(points[index])
		var finish := to_local(points[index + 1])
		if start.is_equal_approx(finish):
			continue
		combiner.add_child(
			_span_brush(start, finish, tunnel.width, tunnel.bore_height(), is_round, is_hull)
		)


## One span's brush. `is_hull` picks which of the pair, because the two differ
## only in size and operation and writing them apart invites them to drift.
##
## The overruns are what make a junction seamless. A hull brush runs half its own
## width plus the wall past each end, so the hulls of two tunnels meeting at a
## space always overlap; a bore brush runs half its width past each end, which is
## far enough for adjoining bores to meet and short enough that it can never
## reach past its own hull.
func _span_brush(
	start: Vector3, finish: Vector3, width: float, height: float, is_round: bool, is_hull: bool
) -> CSGPrimitive3D:
	var across := width + wall_thickness * 2.0 if is_hull else width
	var tall := height + wall_thickness * 2.0 if is_hull else height
	# The overrun is measured on the widest face, so a hull always reaches at
	# least as far as the bore it has to contain however flat that bore is.
	var reach := maxf(width, height) * 0.5
	var overrun := reach + wall_thickness if is_hull else reach
	var span := start.distance_to(finish) + overrun * 2.0
	var operation := CSGShape3D.OPERATION_UNION if is_hull else CSGShape3D.OPERATION_SUBTRACTION
	var direction := (finish - start).normalized()
	var midpoint := (start + finish) * 0.5

	if is_round:
		var tube := CSGCylinder3D.new()
		tube.radius = across * 0.5
		tube.height = span
		tube.sides = ROUND_BORE_SIDES
		tube.operation = operation
		# A CSGCylinder3D runs along its own Y and is circular, so an oval bore is
		# a circular one squashed across the up-ish axis bore_basis picks out.
		var shaped := (
			LevelGraph.bore_basis(direction)
			* Basis.from_scale(Vector3(1.0, 1.0, tall / maxf(across, 0.001)))
		)
		tube.transform = Transform3D(shaped, midpoint)
		return tube

	var box := CSGBox3D.new()
	# looking_at puts the run on Z, the width on X and the height on Y.
	box.size = Vector3(across, tall, span)
	box.operation = operation
	box.transform = Transform3D(Basis.looking_at(direction, _reference_up(direction)), midpoint)
	return box


## A chamber at a space, or null where the space is a bare corner with no room.
##
## Null on both passes or neither: skipping only the bore would leave the hull
## standing as a plug of solid rock across the junction.
func _chamber_brush(space: LevelGraph.Space, is_hull: bool) -> CSGSphere3D:
	if space.radius <= 0.0:
		return null
	var brush := CSGSphere3D.new()
	brush.radius = space.radius + wall_thickness if is_hull else space.radius
	brush.radial_segments = CHAMBER_SEGMENTS
	brush.rings = CHAMBER_RINGS
	brush.operation = CSGShape3D.OPERATION_UNION if is_hull else CSGShape3D.OPERATION_SUBTRACTION
	brush.position = to_local(space.position)
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
