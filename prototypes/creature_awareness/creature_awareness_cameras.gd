class_name CreatureAwarenessCameras
extends Node3D

## Three ways to watch the cave, and one of them is the reason this prototype is legible.
##
##     FREE_FLY   the zero-g player's head camera, inside the cave, first person
##     ANT_FARM   the whole level at once, in cutaway
##     FOLLOW     a chase camera on the creature
##
## HOW THE ANT FARM WORKS, because it looks like it must be a shader and is not. The cave is
## ONE CSG block with the caverns and tunnels subtracted out of it, so the cavern walls ARE
## that block's interior surfaces. Draw the block with its FRONT faces culled and the near
## rock disappears while the far interior stays -- every chamber and bore, open to the
## camera, at once. That is a `cull_mode` on a plain `StandardMaterial3D`, which matters:
## this project renders on GL Compatibility, where anything cleverer is a liability.
##
## Depth still behaves. With the near rock culled the nearest surviving surface is a
## chamber's far wall, so the creature and the stimulus markers inside a chamber render in
## front of it rather than being swallowed by rock that is no longer drawn.
##
## SOLID PILLARS RENDER AS HOLLOW SHELLS FROM THIS CAMERA, and there is no fixing it without
## giving up the effect -- face culling cannot know which solids you wanted kept. It reads
## fine: a column shows you its far inside face, in the right place, at the right size.
##
## ORTHOGRAPHIC, because perspective on a 140 m map puts the near cavern three times the
## size of the far one and the comparison the ant farm exists to support -- where is the
## alien versus where did I ping -- gets harder the moment scale varies across the frame.
##
## THE PICK CHANGES MEANING WITH THE CAMERA and that is handled in
## `creature_awareness_stimulus.gd`, not here. Worth knowing it exists: from this camera the
## cursor is outside the rock entirely, so the first thing any ray hits is the OUTER hull.

enum View { FREE_FLY, ANT_FARM, FOLLOW }

const VIEW_COUNT: int = 3

@export var settings: CreatureAwarenessSettings = null

var _map: CreatureAwarenessMap = null
var _target: Node3D = null
var _free_fly: Camera3D = null
var _ant_farm: Camera3D = null
var _follow: Camera3D = null
var _view: View = View.ANT_FARM
var _solid_material: StandardMaterial3D = null
var _cutaway_material: StandardMaterial3D = null


static func view_name(value: View) -> String:
	match value:
		View.FREE_FLY:
			return "free fly"
		View.ANT_FARM:
			return "ant farm"
		View.FOLLOW:
			return "follow"
	return "?"


## `free_fly` is the player's own camera, which this node does not own and must not reparent
## -- the player drives it.
func setup(map: CreatureAwarenessMap, free_fly: Camera3D, target: Node3D) -> void:
	_map = map
	_free_fly = free_fly
	_target = target
	_solid_material = CreatureAwarenessMap.rock_material()
	_cutaway_material = CreatureAwarenessMap.rock_material()
	# The whole ant farm, in one property.
	_cutaway_material.cull_mode = BaseMaterial3D.CULL_FRONT
	_build_ant_farm()
	_build_follow()
	select(View.ANT_FARM)


func view() -> View:
	return _view


func active() -> Camera3D:
	match _view:
		View.FREE_FLY:
			return _free_fly
		View.FOLLOW:
			return _follow
	return _ant_farm


func select(value: View) -> void:
	_view = value
	var camera: Camera3D = active()
	if camera != null:
		camera.current = true
	_apply_cutaway(value == View.ANT_FARM)


func cycle() -> void:
	select((int(_view) + 1) % VIEW_COUNT)


func _process(delta: float) -> void:
	if _view != View.FOLLOW or _follow == null or _target == null:
		return
	var wanted: Vector3 = (
		_target.global_position
		+ Vector3(0.0, CreatureAwarenessKnobs.FOLLOW_HEIGHT, CreatureAwarenessKnobs.FOLLOW_DISTANCE)
	)
	# Trails rather than snaps, so a leap does not whip the camera across the room.
	var blend: float = clampf(CreatureAwarenessKnobs.FOLLOW_LERP * delta, 0.0, 1.0)
	_follow.global_position = _follow.global_position.lerp(wanted, blend)
	_follow.look_at(_target.global_position, Vector3.UP)


## Applies the tunable half. Called by the prototype whenever settings change; must not
## write back into settings.
func apply_settings() -> void:
	if _ant_farm == null or settings == null:
		return
	_ant_farm.size = settings.ant_farm_size


func _apply_cutaway(cutaway: bool) -> void:
	if _map == null:
		return
	var hull: CSGCombiner3D = _map.hull()
	if hull == null:
		return
	hull.material_override = _cutaway_material if cutaway else _solid_material


func _build_ant_farm() -> void:
	_ant_farm = Camera3D.new()
	_ant_farm.name = "AntFarmCamera"
	_ant_farm.projection = Camera3D.PROJECTION_ORTHOGONAL
	_ant_farm.size = CreatureAwarenessKnobs.ANT_FARM_SIZE
	_ant_farm.far = CreatureAwarenessKnobs.CAMERA_FAR
	# Orthographic near-plane clipping is measured from the camera, and the camera sits well
	# outside the map, so this has to be generous or the front of the cave is sliced off.
	_ant_farm.near = 0.05
	var region: AABB = CreatureAwarenessMap.bounds()
	var middle: Vector3 = region.get_center()
	add_child(_ant_farm)
	_ant_farm.global_position = middle + CreatureAwarenessKnobs.ANT_FARM_OFFSET
	_ant_farm.look_at(middle, Vector3.UP)


func _build_follow() -> void:
	_follow = Camera3D.new()
	_follow.name = "FollowCamera"
	_follow.far = CreatureAwarenessKnobs.CAMERA_FAR
	add_child(_follow)
	if _target != null:
		_follow.global_position = _target.global_position + Vector3(0.0, 6.0, 14.0)
