class_name MineTunnelStub
extends Node3D

## The bit of mine beyond the doors, so that handing control back is something
## you can actually test rather than something you assert.
##
## Two spans - a straight run and a bend - generated the way every blockout in
## this repo is: union the solid hulls into one CSGCombiner3D, then subtract the
## void, and let use_collision give you the trimesh for free. A straight port of
## corridor_generator.gd's idea at a fraction of the size.
##
## THE COLLIDER IS NOT AVAILABLE THIS FRAME. CSGCombiner3D raises its geometry in
## its own _ready(), so anything that queries the collision world against this has
## to wait a frame - which is why the exit-marker check in cutscene_player.gd
## does. Documented in tentacle_crawler_chaser_prototype.gd and
## wall_navmesh_baker.gd, and it bites the same way here.

const MATERIAL: StandardMaterial3D = preload(
	"res://prototypes/elevator_cutscene/materials/tunnel_rock_material.tres"
)

## Layer 1 is `hull` in project.godot's [layer_names]. Mask 0: the walls need to
## be hit, they do not need to test against anything themselves.
const HULL_LAYER := 1

## Interior width and height of the tunnel, and how thick the rock around it is.
##
## WIDER THAN THE DOORWAY, because the player now leaves the car. The exit pose
## sits in front of the call panel on the pier, well outside the doorway's 2.04 m
## clear width, and a bore sized to the doorway puts the rig's hull inside this
## rock - which the cutscene's own exit check catches and warns about on every
## run. The real level opens onto a 10.5 m chamber; this greybox has to be at
## least as forgiving, so it is sized off ElevatorIntroKnobs.EXIT_POSITION.
const BORE := 4.4
const WALL := 1.2

## The centreline. Starts flush against the car's outer front face, runs out, then
## bends - a bend rather than a straight run so there is somewhere to fly TO, and
## so the fog has an edge to sit on.
const SPANS: Array[Vector3] = [
	Vector3(0.0, -0.55, -1.9),
	Vector3(0.0, -0.55, -12.0),
	Vector3(-7.5, -0.55, -19.0),
]

## How far the bore pokes back INTO the car past the mouth.
##
## Only the bore does this, and that asymmetry is the whole trick. Every span has
## to be overlength at its far end so consecutive boxes overlap through the bend -
## two that merely touch leave a wedge of solid rock on the inside of a turn,
## which reads as the tunnel being blocked. But overlength at the NEAR end of the
## first hull span would push rock backwards through the car's front wall and seal
## the doorway from outside. So the hull starts exactly at the mouth and the bore
## starts behind it. Carving air costs nothing: this is a different combiner from
## the car, so the subtraction cannot touch it.
const MOUTH_OVERSHOOT := 1.2


func _ready() -> void:
	var combiner := CSGCombiner3D.new()
	combiner.name = "TunnelCombiner"
	combiner.use_collision = true
	combiner.collision_layer = HULL_LAYER
	combiner.collision_mask = 0
	combiner.material_override = MATERIAL
	add_child(combiner)

	# Order matters: every hull unions into one solid first, then every bore
	# subtracts from the result. Interleaving them would let a later span's hull
	# re-fill the previous span's bore at the joint.
	var hull_width := BORE + WALL * 2.0
	for index in SPANS.size() - 1:
		combiner.add_child(
			_span(SPANS[index], SPANS[index + 1], hull_width, false, 0.0, hull_width)
		)
	for index in SPANS.size() - 1:
		var overshoot := MOUTH_OVERSHOOT if index == 0 else 0.0
		combiner.add_child(_span(SPANS[index], SPANS[index + 1], BORE, true, overshoot, BORE))

	_add_marker_light()


## One box spanning two points, square in cross-section, extended independently at
## each end. See MOUTH_OVERSHOOT for why the two ends cannot share a number.
func _span(
	from: Vector3, to: Vector3, width: float, is_bore: bool, extend_start: float, extend_end: float
) -> CSGBox3D:
	var axis := to - from
	var direction := axis.normalized()
	var start := from - direction * extend_start
	var end := to + direction * extend_end

	var box := CSGBox3D.new()
	box.size = Vector3(width, width, (end - start).length())
	box.operation = CSGShape3D.OPERATION_SUBTRACTION if is_bore else CSGShape3D.OPERATION_UNION
	# looking_at points local -Z at the target, so aiming it at -axis puts local
	# +Z along the span - which is the axis a box's depth runs down, so the long
	# side lands on the centreline with no second rotation.
	box.transform = Transform3D.IDENTITY.looking_at(-axis, Vector3.UP)
	box.position = (start + end) * 0.5
	return box


## Two dim lights down the tunnel.
##
## Without them the doors open onto pure black and there is nothing to fly toward,
## which reads as the level not being built rather than as a dark mine. One light
## at the far end was not enough: at this fog density it never reached the mouth,
## so the shot the doors reveal was a black rectangle.
func _add_marker_light() -> void:
	for position: Vector3 in [Vector3(0.0, -0.4, -4.2), Vector3(0.0, -0.4, -10.5)]:
		var light := OmniLight3D.new()
		light.position = position
		light.light_color = Color(0.62, 0.72, 0.85)
		light.light_energy = 2.2
		light.omni_range = 9.0
		# Off, like every other light here. A web build on GL Compatibility does
		# not have the budget, and a sealed shell with shadows on renders its own
		# interior at ambient only.
		light.shadow_enabled = false
		add_child(light)
