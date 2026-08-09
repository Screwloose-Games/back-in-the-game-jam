class_name MineralCave
extends Node3D

## Builds the greybox chamber the deposits live in, plus the mooring buoy the
## player starts tethered to.
##
## It is a hollow box with a few deliberate occluders - two pillars, an overhang
## over the dark alcove, a shelf you have to climb, and a ledge deep in the room.
## Those are not decoration: each one is what turns a deposit in MineralLayout
## from "visible from spawn" into "you have to go and look", which is the
## reachability half of the grid this prototype tests. Precise placement is why
## this is a handcrafted box and not the voxel asteroid.
##
## Every surface is on the hull layer so the tether rope collides with it and the
## suit can brace against it. The buoy is a frozen RigidBody on the carryable
## layer: frozen so it holds station as an anchor, carryable so the suit's tether
## ray can clip to it, and heavy so going taut reels the player back rather than
## towing the buoy.

## Physics layer bitmasks, matching project.godot's named layers.
const HULL_LAYER_BIT := 1 << 0
const CARRYABLE_LAYER_BIT := 1 << 3

## Half-height of the interior, floor to ceiling centre. Blocks are sized off the
## same few numbers so the shell stays sealed.
const INTERIOR := {"x": 12.0, "y": 6.0, "front_z": 7.0, "back_z": -14.0, "wall": 0.5}

var _env_material: StandardMaterial3D
var _deposits: Array[DepositNode] = []
var _buoy: RigidBody3D


## Constructs the whole cave under this node. Called by the prototype root once it
## has built the two shared materials.
func build(env_material: StandardMaterial3D, deposit_material: StandardMaterial3D) -> void:
	_env_material = env_material
	_build_shell()
	_build_occluders()
	_build_buoy()
	_place_deposits(deposit_material)


## The anchor the suit moors to. Null only before build().
func get_buoy() -> RigidBody3D:
	return _buoy


## Every deposit built, in layout order. Mined-out ones stay in the list; ask the
## deposit whether it is spent.
func get_deposits() -> Array[DepositNode]:
	return _deposits


func _build_shell() -> void:
	var span_z: float = INTERIOR["front_z"] - INTERIOR["back_z"]
	var mid_z: float = (INTERIOR["front_z"] + INTERIOR["back_z"]) * 0.5
	var width: float = INTERIOR["x"] * 2.0
	var height: float = INTERIOR["y"] * 2.0
	var wall: float = INTERIOR["wall"]
	# Floor, ceiling, both side walls, back and front - a sealed box.
	_add_block(Vector3(width, wall, span_z), Vector3(0.0, -INTERIOR["y"], mid_z))
	_add_block(Vector3(width, wall, span_z), Vector3(0.0, INTERIOR["y"], mid_z))
	_add_block(Vector3(wall, height, span_z), Vector3(-INTERIOR["x"], 0.0, mid_z))
	_add_block(Vector3(wall, height, span_z), Vector3(INTERIOR["x"], 0.0, mid_z))
	_add_block(Vector3(width, height, wall), Vector3(0.0, 0.0, INTERIOR["back_z"]))
	_add_block(Vector3(width, height, wall), Vector3(0.0, 0.0, INTERIOR["front_z"]))


func _build_occluders() -> void:
	var height: float = INTERIOR["y"] * 2.0
	# Two floor-to-ceiling pillars that break the sightline from spawn, so the
	# deposits behind them read only once you fly around.
	_add_block(Vector3(1.2, height, 1.2), Vector3(-3.0, 0.0, -1.5))
	_add_block(Vector3(1.2, height, 1.2), Vector3(4.0, 0.0, -4.5))
	# An overhang that throws the left alcove into shadow - the "hidden until the
	# lamp points in" pocket sits under it.
	_add_block(Vector3(6.0, 0.5, 5.0), Vector3(-8.0, 1.5, -3.0))
	# A shelf the shaft cluster sits above, so reaching it means climbing.
	_add_block(Vector3(4.0, 0.5, 4.0), Vector3(5.0, 2.0, -2.0))
	# A ledge deep in the room that the far premium cluster rests on.
	_add_block(Vector3(5.0, 0.5, 4.0), Vector3(0.0, -3.0, -6.0))


func _build_buoy() -> void:
	_buoy = RigidBody3D.new()
	_buoy.name = "MooringBuoy"
	_buoy.position = MineralKnobs.BUOY_SPAWN
	_buoy.mass = MovementKnobs.CARRY_OBJECT_MASS
	# Frozen so it holds station as a fixed anchor; the tether still reels the
	# suit toward it because the suit side of the link is what moves.
	_buoy.freeze = true
	_buoy.collision_layer = CARRYABLE_LAYER_BIT
	_buoy.collision_mask = HULL_LAYER_BIT

	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.35
	sphere.height = 0.7
	mesh.mesh = sphere
	mesh.material_override = _make_buoy_material()
	_buoy.add_child(mesh)

	var shape := CollisionShape3D.new()
	var collision := SphereShape3D.new()
	# Wider than the mesh so the start-of-run auto-moor ray reliably catches the
	# buoy under the crosshair whatever the exact helmet-camera offset is.
	collision.radius = 0.6
	shape.shape = collision
	_buoy.add_child(shape)
	add_child(_buoy)


## A cold, self-lit look so the buoy reads as your equipment and never gets
## confused with ore under the lamp.
func _make_buoy_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.6, 0.75)
	material.emission_enabled = true
	material.emission = Color(0.25, 0.7, 0.85)
	material.emission_energy_multiplier = 1.5
	return material


func _place_deposits(deposit_material: StandardMaterial3D) -> void:
	for entry: Dictionary in MineralLayout.DEPOSITS:
		var deposit := DepositNode.new()
		deposit.setup(entry["tier"], entry["formation"], deposit_material)
		deposit.position = entry["position"]
		_orient_to_normal(deposit, entry["normal"])
		add_child(deposit)
		_deposits.append(deposit)


## Turns the deposit so its +Z (the face its formation pokes out of) points along
## the layout's normal, seating the ore against its wall.
func _orient_to_normal(node: Node3D, normal: Vector3) -> void:
	var forward := normal.normalized()
	if forward.is_zero_approx():
		return
	var up := Vector3.UP
	if absf(forward.dot(up)) > 0.99:
		up = Vector3.RIGHT
	var right := up.cross(forward).normalized()
	var basis_up := forward.cross(right).normalized()
	node.basis = Basis(right, basis_up, forward)


func _add_block(size: Vector3, block_position: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = HULL_LAYER_BIT
	body.collision_mask = 0
	body.position = block_position

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _env_material
	body.add_child(mesh)

	var shape := CollisionShape3D.new()
	var collision := BoxShape3D.new()
	collision.size = size
	shape.shape = collision
	body.add_child(shape)
	add_child(body)
