extends SceneTree

## Checks LevelGraph against a five-space graph whose every answer can be worked
## out on paper.
##
## The graph is shaped around the one thing the tool exists to show: space E sits
## 2 m from space A through solid rock and 318 m from it along the only tunnel
## joining them. A straight-line hearing check says those two are the same place.
##
## Run headless:
##   godot --headless --path <root> --script res://tools/level_design/test_level_graph.gd

const TOLERANCE := 0.001

var _failures := 0


func _initialize() -> void:
	var graph := _build_test_graph()

	_check_topology(graph)
	_check_noise_from_a_space(graph)
	_check_noise_from_inside_a_tunnel(graph)
	_check_graph_disagrees_with_straight_line(graph)

	if _failures == 0:
		print("test_level_graph: OK")
	else:
		printerr("test_level_graph: %d check(s) FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


## A --30m-- B --30m-- C --258m (the long way round)-- E, plus orphan D.
func _build_test_graph() -> LevelGraph:
	var graph := LevelGraph.new()

	graph.add_space(_make_space(&"a_room", Vector3(0, 0, 0), 5.0, LevelGraph.SpaceKind.ROOM))
	graph.add_space(_make_space(&"b_corner", Vector3(0, 0, 30), 0.0, LevelGraph.SpaceKind.JUNCTION))
	graph.add_space(_make_space(&"c_room", Vector3(0, 0, 60), 7.0, LevelGraph.SpaceKind.ROOM))
	graph.add_space(_make_space(&"e_pocket", Vector3(2, 0, 0), 3.0, LevelGraph.SpaceKind.DEAD_END))
	graph.add_space(_make_space(&"d_orphan", Vector3(5, 0, 0), 2.0, LevelGraph.SpaceKind.ROOM))

	graph.add_tunnel(
		_make_tunnel(
			&"ab", &"a_room", &"b_corner", 10.0, PackedVector3Array([_at(0, 0, 0), _at(0, 0, 30)])
		)
	)
	graph.add_tunnel(
		_make_tunnel(
			&"bc", &"b_corner", &"c_room", 8.0, PackedVector3Array([_at(0, 0, 30), _at(0, 0, 60)])
		)
	)
	# 100 + 60 + 98 = 258 m, ending 2 m from where it started.
	graph.add_tunnel(
		_make_tunnel(
			&"ce",
			&"c_room",
			&"e_pocket",
			4.0,
			PackedVector3Array([_at(0, 0, 60), _at(100, 0, 60), _at(100, 0, 0), _at(2, 0, 0)])
		)
	)
	return graph


func _check_topology(graph: LevelGraph) -> void:
	_expect_near("total_length", graph.total_length(), 318.0)
	_expect_equal("degree(a_room)", graph.degree(&"a_room"), 1)
	_expect_equal("degree(b_corner)", graph.degree(&"b_corner"), 2)
	_expect_equal("degree(d_orphan)", graph.degree(&"d_orphan"), 0)
	_expect_near("tunnel ce length", graph.find_tunnel(&"ce").length(), 258.0)
	_expect_equal(
		"point_at(100) on ce", graph.find_tunnel(&"ce").point_at(100.0), Vector3(100, 0, 60)
	)

	var orphans := graph.unreachable_from(&"a_room")
	_expect_equal("orphan count", orphans.size(), 1)
	_expect_equal("orphan is d_orphan", orphans[0] if orphans.size() > 0 else &"", &"d_orphan")

	# The creature fits down the 10 m and 8 m tunnels but not the 4 m one.
	_expect_equal("passable at 6.4 m", graph.passable_tunnel_ids(6.4).size(), 2)
	_expect_equal("passable at 3.0 m", graph.passable_tunnel_ids(3.0).size(), 3)


## A 70 m noise made in a_room: 70 left there, 40 at b_corner, 10 at c_room, and
## nothing survives the 258 m run out to e_pocket.
func _check_noise_from_a_space(graph: LevelGraph) -> void:
	var field := graph.propagate_from_space(&"a_room", 70.0)

	_expect_near("remaining at a_room", field.remaining_at_space.get(&"a_room", 0.0), 70.0)
	_expect_near("remaining at b_corner", field.remaining_at_space.get(&"b_corner", 0.0), 40.0)
	_expect_near("remaining at c_room", field.remaining_at_space.get(&"c_room", 0.0), 10.0)
	_expect_equal("e_pocket cannot hear", field.can_hear_space(&"e_pocket"), false)
	_expect_equal("d_orphan cannot hear", field.can_hear_space(&"d_orphan"), false)

	# b_corner holds 40 m and tunnel bc is 30 m, so bc is lit end to end.
	_expect_equal("bc heard throughout", field.can_hear_throughout_tunnel(&"bc", 30.0), true)
	# Only the first 10 m of the 258 m tunnel out of c_room hears it.
	_expect_near("covered length of ce", field.covered_length(&"ce"), 10.0)
	_expect_equal("ce not heard throughout", field.can_hear_throughout_tunnel(&"ce", 258.0), false)


## A 20 m noise made 15 m along the 30 m tunnel ab lights the WHOLE tunnel: it
## reaches 20 m in both directions from the middle.
##
## Regression test. Measuring reach inward from the two endpoints alone would
## report 5 m at each end and call the middle 20 m silent - the exact stretch the
## noise was made in.
func _check_noise_from_inside_a_tunnel(graph: LevelGraph) -> void:
	var field := graph.propagate_from_tunnel(&"ab", 15.0, 20.0)

	_expect_near("covered length of ab", field.covered_length(&"ab"), 30.0)
	_expect_equal("ab heard throughout", field.can_hear_throughout_tunnel(&"ab", 30.0), true)
	_expect_near("remaining at a_room", field.remaining_at_space.get(&"a_room", 0.0), 5.0)
	_expect_near("remaining at b_corner", field.remaining_at_space.get(&"b_corner", 0.0), 5.0)
	_expect_equal("c_room cannot hear", field.can_hear_space(&"c_room"), false)
	_expect_equal("origin position", field.origin_position, Vector3(0, 0, 15))


## The finding the tool exists to surface: e_pocket is 2 m away through rock and
## 318 m away through tunnel. The straight-line model hears it, the graph does not.
func _check_graph_disagrees_with_straight_line(graph: LevelGraph) -> void:
	var through_tunnels := graph.propagate_from_space(&"a_room", 70.0)
	var through_rock := graph.straight_line_audible_space_ids(Vector3.ZERO, 70.0)

	_expect_equal(
		"graph says e_pocket is silent", through_tunnels.can_hear_space(&"e_pocket"), false
	)
	_expect_equal("straight line says e_pocket is audible", &"e_pocket" in through_rock, true)
	_expect_equal("straight line reaches every space", through_rock.size(), 5)
	_expect_equal("graph reaches three spaces", through_tunnels.remaining_at_space.size(), 3)


func _make_space(
	space_id: StringName, position: Vector3, radius: float, kind: LevelGraph.SpaceKind
) -> LevelGraph.Space:
	var space := LevelGraph.Space.new()
	space.id = space_id
	space.position = position
	space.radius = radius
	space.kind = kind
	return space


func _make_tunnel(
	tunnel_id: StringName,
	from_id: StringName,
	to_id: StringName,
	width: float,
	polyline: PackedVector3Array
) -> LevelGraph.Tunnel:
	var tunnel := LevelGraph.Tunnel.new()
	tunnel.id = tunnel_id
	tunnel.from_id = from_id
	tunnel.to_id = to_id
	tunnel.width = width
	tunnel.polyline = polyline
	return tunnel


func _at(x_metres: float, y_metres: float, z_metres: float) -> Vector3:
	return Vector3(x_metres, y_metres, z_metres)


func _expect_near(label: String, actual: float, expected: float) -> void:
	if absf(actual - expected) > TOLERANCE:
		_failures += 1
		printerr("  FAIL %s: expected %.3f, got %.3f" % [label, expected, actual])


func _expect_equal(label: String, actual: Variant, expected: Variant) -> void:
	if actual != expected:
		_failures += 1
		printerr("  FAIL %s: expected %s, got %s" % [label, expected, actual])
