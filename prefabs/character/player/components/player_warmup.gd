class_name PlayerWarmup
extends Node

## Draws the mining laser and the tether rope for a few frames at spawn, behind
## the loading screen, so neither pays to compile its shaders mid-game. The
## impact light is the expensive one: it is the level's first omni, and every
## material it reaches recompiles when it arrives.

## How far ahead the impact light goes when the aim finds nothing. Short, so the
## light is inside the tunnel it has to light either way — an omni over open
## space warms no material at all.
const FALLBACK_REACH := 2.0

var _warm_point := Vector3.ZERO

@onready var mining_tool: PlayerMiningTool = %MiningTool
@onready var tether: PlayerTether = %Tether
@onready var rope_view: MeshInstance3D = %TetherRopeView
@onready var aim: RayCast3D = %GrabRay
@onready var warmup: ShaderWarmup = $ShaderWarmup


## Draws everything once and returns when the frames have been rendered.
func warm() -> void:
	_warm_point = _impact_point()
	tether.build_warmup_span()
	warmup.run(_hold_drawn, _release)
	await warmup.finished


func _hold_drawn() -> void:
	if mining_tool.tool_model != null:
		mining_tool.tool_model.visible = true
	var laser := mining_tool.laser_beam()
	if laser != null:
		laser.fire_at(_warm_point)
	rope_view.visible = true


func _release() -> void:
	var laser := mining_tool.laser_beam()
	if laser != null:
		laser.hold_fire()
	rope_view.visible = false
	if mining_tool.tool_model != null:
		mining_tool.tool_model.visible = false


## Where the aim lands, or a short way down it when nothing is in range. Also
## pays for the first ray query against the level, which is its own first-use cost.
func _impact_point() -> Vector3:
	var hit := mining_tool.query_beam_hit()
	if not hit.is_empty():
		return hit["position"] as Vector3
	return aim.global_position - aim.global_transform.basis.z * FALLBACK_REACH
