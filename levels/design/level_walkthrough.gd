class_name LevelWalkthrough
extends Node3D

## Puts a zero-G suit inside the carved blockout so the design can be flown.
##
## Not the game and not a prototype: there is no ore, no creature, no oxygen and
## no tether. It exists to answer the one question a plan and an elevation
## drawing cannot, which is whether the shape of the place reads from the inside.
##
## The suit is prototypes/navigation/zero_g_player.tscn, unchanged. It is the
## same flight model the tunnel prototype uses, so how the mines feel to move
## through is comparable with how that already felt.

## Metres before the fog starts. Close, so the rock right in front of you still
## reads as solid.
const FOG_BEGIN_METRES := 2.0

## How far past the fog the clip plane sits. Any less and geometry pops out of
## nothing before the fog has finished hiding it.
const CAMERA_FAR_MARGIN := 1.5

## Metres at which the fog has completely swallowed the rock.
##
## THE NUMBER THAT DECIDES HOW DISORIENTING THIS IS. The mines were laid out on
## the assumption you can only ever see a fraction of one drift, and at 20 m that
## is true. Wind it up to a few hundred to survey the layout and check the shape
## came out right; put it back to 20 to judge whether the layout works.
## Typed float explicitly rather than inferred: written without a decimal point
## this becomes an int, and the whole thing is fed to fog and clip distances.
@export_range(4.0, 400.0, 1.0, "suffix:m") var view_distance_metres: float = 100.0

## The blockout to walk. Point it at any design scene whose root is a MineLevel;
## nothing here is wired to a particular one.
@export var level_scene: PackedScene = preload("res://levels/design/level_mine_blockout.tscn")

## Draws the annotated graph - labels, colour coding, the lot - on top of the
## carved rock. The level's own drawing, switched on from here so that walking a
## different blockout does not mean editing that blockout's file.
@export var show_design_overlay := false

## The node that carves the rock. Left at its default it finds the one in this
## scene.
@export_node_path("Node3D") var geometry_path: NodePath = ^"LevelGeometry"

@export var player_scene: PackedScene = preload("res://prototypes/navigation/zero_g_player.tscn")


func _ready() -> void:
	_install_environment()
	var level := _mount_level()
	if level == null:
		return
	_carve(level)
	_spawn_suit(_entrance_position(level))
	_report(level)


## Instances the blockout under a fixed node name.
##
## Fixed, because the geometry builder addresses it by NodePath and the name of
## the root node varies from one blockout to the next.
func _mount_level() -> MineLevel:
	if level_scene == null:
		push_warning("LevelWalkthrough has no level_scene; there is nothing to walk.")
		return null
	var level := level_scene.instantiate() as MineLevel
	if level == null:
		push_warning("level_scene's root is not a MineLevel; there is nothing to walk.")
		return null
	level.name = "Level"
	level.draw_when_running = show_design_overlay
	add_child(level)
	return level


## Carves the rock, once the level exists to carve it from.
##
## The builder cannot do this on its own here: its _ready runs before this node's,
## and at that point the level has not been instanced yet. That is what
## build_on_ready is off for in this scene.
func _carve(level: MineLevel) -> void:
	var builder := get_node_or_null(geometry_path) as LevelGeometryBuilder
	if builder == null:
		push_warning("LevelWalkthrough found no builder at '%s'; no rock." % geometry_path)
		return
	builder.level_path = builder.get_path_to(level)
	builder.build()


## Total dark with fog, built here rather than saved in the scene so that
## view_distance_metres genuinely owns everything it touches.
func _install_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.05, 0.055, 0.07)
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_light_color = Color(0.02, 0.024, 0.03)
	environment.fog_light_energy = 0.6
	environment.fog_density = 1.0
	environment.fog_depth_begin = FOG_BEGIN_METRES
	environment.fog_depth_end = view_distance_metres

	var holder := WorldEnvironment.new()
	holder.name = "Void"
	holder.environment = environment
	add_child(holder)


## Where the suit starts: the level's entrance space, or its first space when it
## names no entrance.
func _entrance_position(level: MineLevel) -> Vector3:
	var entrance := level.get_node_or_null(level.entrance_space) as MineSpace
	if entrance != null:
		return entrance.global_position
	var spaces := level.spaces_in_level()
	if spaces.is_empty():
		return global_position
	return spaces[0].global_position


## Positions the suit BEFORE putting it in the tree.
##
## ZeroGPlayer captures its own spawn transform in _ready, and _ready runs inside
## add_child - so moving it afterwards would leave R respawning it back to
## wherever the scene file happened to leave it rather than to the entrance.
func _spawn_suit(where: Vector3) -> void:
	var suit := player_scene.instantiate() as ZeroGPlayer
	if suit == null:
		push_warning("player_scene is not a ZeroGPlayer; nobody spawned.")
		return
	suit.name = "Suit"
	suit.position = to_local(where)
	add_child(suit)
	# After add_child, because binding applies the optics to nodes that only
	# exist once the suit is ready.
	suit.bind_settings(_flight_settings())


func _flight_settings() -> NavigationSettings:
	var settings := NavigationSettings.new()
	settings.fog_depth_end = view_distance_metres
	settings.camera_far = view_distance_metres * CAMERA_FAR_MARGIN
	settings.helmet_lamp_range = view_distance_metres
	return settings


func _report(level: MineLevel) -> void:
	var graph := level.build_graph()
	print(
		(
			"%s: %d spaces, %d tunnels, %.0f m of centreline, seeing %.0f m."
			% [
				level.name,
				graph.spaces.size(),
				graph.tunnels.size(),
				graph.total_length(),
				view_distance_metres
			]
		)
	)
	print(
		(
			"WASD + space/ctrl to thrust, mouse to look, Q/E to roll, "
			+ "shift to stabilise, R to respawn, escape to release the mouse."
		)
	)
