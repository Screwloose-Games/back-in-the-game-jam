extends SceneTree

## Does the hoist frame actually fit the car it is built around?
##
##   D:\Godot_v4.7.1-stable_win64.exe --headless --path <root> \
##     --script res://prefabs/environment/elevator/tools/verify_elevator_shaft.gd
##
## MEASURED OFF THE ART, NOT OFF THE KNOBS. Every number here comes from an
## imported mesh's AABB or from a generated collider, so a re-export that widens a
## column or a recipe change that shortens a cross member fails here, by name,
## instead of leaving the car clipping through its own frame in one shot nobody
## looks at closely. Comparing ElevatorShaft's constants against ElevatorCar's
## constants would pass forever and prove nothing - the same trap
## ElevatorCar._assert_door_invariant was rewritten to escape.
##
## Headless because none of it is about rendering. The render check is
## tools/preview_elevator_shaft.tscn, which cannot run headless at all.

const SHAFT_SCENE := "res://prefabs/environment/elevator/prefab_elevator_shaft.tscn"
const CAR_SCENE := "res://prefabs/environment/elevator/prefab_elevator_car.tscn"
const CAR_SHELL_MESH := "car_shell"

## Metres of air wanted between the car and a column, each side. The recipe
## authors 0.12; half of it is the margin a rebuild may eat before this complains.
const BORE_CLEARANCE := 0.06

## The car's doorway lintel. Nothing structural may cross the opening below it.
const DOORWAY_TOP := 2.4

var _failures := 0
var _checks := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame

	var shaft: ElevatorShaft = load(SHAFT_SCENE).instantiate()
	var car: Node3D = load(CAR_SCENE).instantiate()
	root.add_child(shaft)
	root.add_child(car)
	await process_frame

	var hull := _car_hull(car)
	_verify_bore(shaft, hull)
	_verify_rings(shaft, hull)
	_verify_hood(shaft)
	_verify_colliders(shaft)
	_report()


## The car's outer shell, in the car's own space - which is the shaft's space too,
## because both prefabs put their origin on the plane the car stands on.
func _car_hull(car: Node3D) -> AABB:
	var found := car.find_children(CAR_SHELL_MESH, "MeshInstance3D", true, false)
	if found.is_empty():
		_fail("[car] no mesh named '%s'; the car model was re-exported" % CAR_SHELL_MESH)
		return AABB()
	return (found[0] as MeshInstance3D).get_aabb()


func _verify_bore(shaft: ElevatorShaft, hull: AABB) -> void:
	var bore := shaft.clear_bore()
	var widest := maxf(hull.size.x, hull.size.z)
	_check(
		"[bore] the car fits between the columns",
		bore - widest >= BORE_CLEARANCE * 2.0,
		(
			"clear bore is %.3f m and the car is %.3f m across: %.3f m a side, wanted %.3f"
			% [bore, widest, (bore - widest) * 0.5, BORE_CLEARANCE]
		)
	)
	# The columns stand at the corners of a square, so the diagonal is not the
	# thing to check - but the car is square too, and a car longer than it is wide
	# would foul a column the plan view says it clears.
	_check(
		"[bore] the car is square in plan, as the bore assumes",
		is_equal_approx(hull.size.x, hull.size.z),
		(
			"the car is %.3f x %.3f m; a rectangular car needs a rectangular frame"
			% [hull.size.x, hull.size.z]
		)
	)


func _verify_rings(shaft: ElevatorShaft, hull: AABB) -> void:
	var rings := shaft.beam_ring_heights()
	_check(
		"[rings] the frame carries at least one beam ring",
		not rings.is_empty(),
		(
			"beam_spacing %.2f over a %.2f m shaft produced none"
			% [shaft.beam_spacing, shaft.shaft_height]
		)
	)
	var roof := hull.position.y + hull.size.y
	var lowest := rings[0] if not rings.is_empty() else INF
	_check(
		"[rings] no ring crosses the car",
		lowest >= roof,
		"the lowest ring is at %.2f m and the car reaches %.2f m" % [lowest, roof]
	)
	_check(
		"[rings] no ring crosses the doorway",
		lowest >= DOORWAY_TOP,
		"the lowest ring is at %.2f m, below the %.2f m lintel" % [lowest, DOORWAY_TOP]
	)
	for at: float in rings:
		if at > shaft.shaft_height:
			_fail("[rings] a ring at %.2f m sits above the %.2f m frame" % [at, shaft.shaft_height])
			return
	_pass()


## The collar has to overhang the frame on every side, or the seam it exists to
## hide is visible through the gap it leaves.
func _verify_hood(shaft: ElevatorShaft) -> void:
	var hood: MeshInstance3D = shaft.get_node_or_null("Hood")
	if hood == null:
		_fail("[hood] no Hood was generated")
		return
	var skirt := hood.mesh.get_aabb().size
	var frame := shaft.clear_bore() + _column_width(shaft) * 2.0
	_check(
		"[hood] the collar overhangs the frame",
		skirt.x > frame and skirt.z > frame,
		"the collar is %.2f m over a %.2f m frame" % [skirt.x, frame]
	)
	_check(
		"[hood] the collar sits on the frame, not above it",
		shaft.hood_height <= shaft.shaft_height,
		"hood_height %.2f m is above the %.2f m frame" % [shaft.hood_height, shaft.shaft_height]
	)


func _verify_colliders(shaft: ElevatorShaft) -> void:
	var body: StaticBody3D = shaft.get_node_or_null("ShaftBody")
	if body == null:
		_fail("[collision] no ShaftBody was generated")
		return
	var shapes := body.find_children("*", "CollisionShape3D", true, false)
	# Four columns, four members a ring, the collar and the pad.
	var wanted := 4 + shaft.beam_ring_heights().size() * 4 + 2
	_check(
		"[collision] every part of the frame is solid",
		shapes.size() == wanted,
		"%d shapes for %d parts" % [shapes.size(), wanted]
	)
	for shape: CollisionShape3D in shapes:
		var box := shape.shape as BoxShape3D
		if (
			box == null
			or box.size.min_axis_index() < 0
			or box.size[box.size.min_axis_index()] <= 0.0
		):
			_fail("[collision] %s has no usable box" % shape.name)
			return
	_pass()
	_check(
		"[collision] the frame is hull, and reacts to nothing",
		body.collision_layer == ElevatorShaft.HULL_LAYER and body.collision_mask == 0,
		"layer %d mask %d" % [body.collision_layer, body.collision_mask]
	)


func _column_width(shaft: ElevatorShaft) -> float:
	var posts: MultiMeshInstance3D = shaft.get_node_or_null("Posts")
	if posts == null or posts.multimesh == null or posts.multimesh.mesh == null:
		return 0.0
	return posts.multimesh.mesh.get_aabb().size.x


func _check(label: String, passed: bool, detail: String) -> void:
	_checks += 1
	if passed:
		print("  OK    %s" % label)
		return
	_failures += 1
	printerr("  FAIL  %s: %s" % [label, detail])


func _pass() -> void:
	_checks += 1


func _fail(detail: String) -> void:
	_checks += 1
	_failures += 1
	printerr("  FAIL  %s" % detail)


func _report() -> void:
	if _failures > 0:
		printerr("%d of %d checks failed" % [_failures, _checks])
		quit(1)
		return
	print("elevator shaft: %d checks OK" % _checks)
	quit(0)
