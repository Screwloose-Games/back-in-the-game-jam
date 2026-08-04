extends SceneTree

## Generates paths/tunnel_paths.tscn from the layout table in tunnel_knobs.gd.
##
##   godot --headless --path <root> --script res://prototypes/tunnel_system/tools/build_tunnel_paths.gd
##
## THIS IS A SCAFFOLD, AND THE OUTPUT IS NOT READ-ONLY. Unlike
## tentacle_crawler/tools/build_corridor_run.gd, whose output must never be
## hand-edited, the scene this writes is meant to be opened and dragged around:
## the baker reads the Path3D curves in that scene, not the table below. Running
## this tool again is a deliberate "reset to the authored layout" and throws away
## those edits.
##
## Waypoints in the table are joined by CATMULL-ROM BEZIER HANDLES rather than by
## straight lines, so a tunnel bows between its waypoints. The curve still passes
## exactly through every waypoint, which is what keeps the shared junction
## constants exact - a route that only approximated its endpoint would weld into
## a separate node and quietly disconnect the network.

const CHAMBER_RADIUS_META := "chamber_radius"

## Metres of rock two unrelated routes should keep between their bores. Below
## this they have effectively merged into one passage, which is not a crash but
## is a shortcut nobody authored - so it is reported rather than enforced.
const MIN_ROCK_THICKNESS := 3.0


func _initialize() -> void:
	var root := Node3D.new()
	root.name = "TunnelPaths"
	var paths_root := Node3D.new()
	paths_root.name = "Paths"
	_adopt(paths_root, root, root)
	var chambers_root := Node3D.new()
	chambers_root.name = "Chambers"
	_adopt(chambers_root, root, root)

	for route: Dictionary in TunnelKnobs.ROUTES:
		var path := _build_path(route)
		if path != null:
			_adopt(path, paths_root, root)

	for index: int in TunnelKnobs.CHAMBERS.size():
		var chamber: Dictionary = TunnelKnobs.CHAMBERS[index]
		var marker := Marker3D.new()
		marker.name = "chamber_%02d" % index
		marker.position = chamber["center"]
		marker.set_meta(CHAMBER_RADIUS_META, chamber["radius"] as float)
		_adopt(marker, chambers_root, root)

	var network := TunnelNetwork.from_scene(paths_root, chambers_root)

	var complaints := _validate(paths_root, network)
	if not complaints.is_empty():
		for line: String in complaints:
			printerr("REFUSING TO EMIT: %s" % line)
		quit(1)
		return
	for line: String in _proximity_warnings(network):
		print("warning: %s" % line)

	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		printerr("pack() failed")
		quit(1)
		return
	var out_path := _res("../paths/tunnel_paths.tscn")
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	if ResourceSaver.save(packed, out_path) != OK:
		printerr("save(%s) failed" % out_path)
		quit(1)
		return
	_relativise(out_path)

	print(
		(
			"wrote %s: %d routes, %d chambers, %d junctions, %.0f m of centreline"
			% [
				out_path,
				network.routes.size(),
				network.chamber_centers.size(),
				network.junctions.size(),
				network.total_length(),
			]
		)
	)
	quit(0)


func _build_path(route: Dictionary) -> Path3D:
	var waypoints: Array = route["points"]
	if waypoints.size() < 2:
		printerr("route '%s' has fewer than two waypoints" % route["name"])
		return null

	var curve := Curve3D.new()
	for point: Vector3 in waypoints:
		curve.add_point(point)
	_fit_handles(curve, waypoints)

	var path := Path3D.new()
	path.name = route["name"]
	path.curve = curve
	path.set_meta(
		TunnelNetwork.RADII_META, _taper_radii(waypoints, route["bore_start"], route["bore_end"])
	)
	return path


## Catmull-Rom tangents expressed as bezier handles: the tangent at an interior
## point is half the chord across its neighbours, and a cubic bezier reproduces
## that tangent with handles at a third of it.
func _fit_handles(curve: Curve3D, waypoints: Array) -> void:
	var last := waypoints.size() - 1
	for i: int in waypoints.size():
		var tangent: Vector3
		if i == 0:
			tangent = (waypoints[1] as Vector3) - (waypoints[0] as Vector3)
		elif i == last:
			tangent = (waypoints[last] as Vector3) - (waypoints[last - 1] as Vector3)
		else:
			tangent = ((waypoints[i + 1] as Vector3) - (waypoints[i - 1] as Vector3)) * 0.5
		var handle := tangent / 3.0
		# An endpoint's outward handle is left at zero so the curve does not
		# overshoot past the junction it is supposed to terminate on.
		curve.set_point_in(i, Vector3.ZERO if i == 0 else -handle)
		curve.set_point_out(i, Vector3.ZERO if i == last else handle)


## One radius per waypoint, lerped from bore_start to bore_end by ARC LENGTH
## rather than by waypoint index - an uneven polyline would otherwise put the
## midpoint of the taper wherever the waypoints happened to fall.
func _taper_radii(waypoints: Array, bore_start: float, bore_end: float) -> PackedFloat32Array:
	var cumulative := PackedFloat32Array([0.0])
	var total := 0.0
	for i: int in waypoints.size() - 1:
		total += (waypoints[i] as Vector3).distance_to(waypoints[i + 1] as Vector3)
		cumulative.append(total)

	var radii := PackedFloat32Array()
	for i: int in waypoints.size():
		var t := 0.0 if total <= 0.0 else cumulative[i] / total
		radii.append(lerpf(bore_start, bore_end, t))
	return radii


## Everything that would make an unplayable or physically broken network. Refuse
## to emit rather than emit and hope, the same posture as build_corridor_run.gd.
func _validate(paths_root: Node3D, network: TunnelNetwork) -> PackedStringArray:
	var complaints := PackedStringArray()

	var limit := TunnelKnobs.WORLD_EXTENT * 0.5 - TunnelKnobs.WORLD_INSET
	var floor_y := -TunnelKnobs.WORLD_EXTENT + TunnelKnobs.WORLD_INSET
	for route: Dictionary in network.routes:
		for point: Vector3 in route["points"] as PackedVector3Array:
			if absf(point.x) > limit or absf(point.z) > limit:
				complaints.append(
					"route '%s' leaves the box laterally at %v" % [route["name"], point]
				)
				break
			if point.y > 0.0 or point.y < floor_y:
				complaints.append(
					"route '%s' leaves the box vertically at %v" % [route["name"], point]
				)
				break

	# The field is `distance_to_segment - lerp(radius)`, which is only a true
	# distance function while the radius changes slowly. Past BORE_MAX_SLOPE the
	# gradient magnitude drifts far enough from 1.0 that the surface-nets edge
	# crossing lands in the wrong place, and the bore bakes out visibly narrower
	# or wider than the number that was authored.
	for route: Dictionary in network.routes:
		var points: PackedVector3Array = route["points"]
		var radii: PackedFloat32Array = route["radii"]
		for i: int in points.size() - 1:
			var span := points[i].distance_to(points[i + 1])
			if span <= 0.0:
				continue
			var slope := absf(radii[i + 1] - radii[i]) / span
			if slope > TunnelKnobs.BORE_MAX_SLOPE:
				complaints.append(
					(
						"route '%s' tapers at %.2f m/m near %v, above the %.2f limit"
						% [route["name"], slope, points[i], TunnelKnobs.BORE_MAX_SLOPE]
					)
				)
				break

	for route: Dictionary in network.routes:
		var radii: PackedFloat32Array = route["radii"]
		for radius: float in radii:
			if radius < TunnelKnobs.PLAYER_RADIUS + TunnelKnobs.CLEARANCE_MARGIN:
				complaints.append(
					(
						"route '%s' has a %.2f m bore radius, too narrow for a %.2f m player"
						% [route["name"], radius, TunnelKnobs.PLAYER_RADIUS]
					)
				)
				break

	var orphans := network.unreachable_routes(TunnelKnobs.SPAWN_POSITION)
	if not orphans.is_empty():
		(
			complaints
			. append(
				(
					"routes unreachable from spawn: %s (check their endpoints use the shared junction constants)"
					% ", ".join(orphans)
				)
			)
		)

	if paths_root.get_child_count() != TunnelKnobs.ROUTES.size():
		complaints.append(
			(
				"built %d Path3D nodes from %d routes"
				% [paths_root.get_child_count(), TunnelKnobs.ROUTES.size()]
			)
		)

	return complaints


## Pairs of routes whose bores come close enough to have merged. Reported, not
## enforced: a merge is sometimes what the bowed curves were always going to do,
## and the person reading this is the one who can say whether it is a shortcut
## they want. Routes that share a junction are skipped - they are supposed to meet.
func _proximity_warnings(network: TunnelNetwork) -> PackedStringArray:
	var warnings := PackedStringArray()
	var edges := network.route_edges()
	for a: int in network.routes.size():
		for b: int in range(a + 1, network.routes.size()):
			if _shares_junction(edges[a], edges[b]):
				continue
			var gap := _route_gap(network.routes[a], network.routes[b])
			if gap < MIN_ROCK_THICKNESS:
				warnings.append(
					(
						"'%s' and '%s' leave only %.2f m of rock between them"
						% [network.routes[a]["name"], network.routes[b]["name"], gap]
					)
				)
	return warnings


func _shares_junction(a: Vector2i, b: Vector2i) -> bool:
	return a.x == b.x or a.x == b.y or a.y == b.x or a.y == b.y


## Smallest rock thickness between two routes: the closest approach of their
## centrelines, less both bores. Measured point-to-point on the resampled
## centrelines, which at SEGMENT_STEP overstates the gap by at most half a step -
## fine for a warning, and far cheaper than a segment-to-segment solve.
func _route_gap(a: Dictionary, b: Dictionary) -> float:
	var a_points: PackedVector3Array = a["points"]
	var a_radii: PackedFloat32Array = a["radii"]
	var b_points: PackedVector3Array = b["points"]
	var b_radii: PackedFloat32Array = b["radii"]
	var best := INF
	for i: int in a_points.size():
		for j: int in b_points.size():
			var gap := a_points[i].distance_to(b_points[j]) - a_radii[i] - b_radii[j]
			best = minf(best, gap)
	return best


## add_child THEN set owner. Setting owner on a node that is not yet a descendant
## of the owner fails silently, and PackedScene.pack() then drops it - producing a
## scene that saves without error and contains almost nothing.
func _adopt(node: Node, parent: Node, root: Node) -> void:
	parent.add_child(node)
	node.owner = root


## ResourceSaver writes absolute res:// paths and FLAG_RELATIVE_PATHS still does
## nothing to text scenes in 4.7.1. Derived from this script's own location, never
## written down - a hardcoded prefix quietly becomes a no-op when the folder moves.
func _relativise(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		printerr("could not reopen %s to relativise its paths" % path)
		return
	var text := file.get_as_text()
	file.close()
	text = text.replace(_res("..") + "/", "../")
	var out := FileAccess.open(path, FileAccess.WRITE)
	out.store_string(text)
	out.close()


func _res(relative_path: String) -> String:
	var dir: String = (get_script() as Script).resource_path.get_base_dir()
	return dir.path_join(relative_path).simplify_path()
