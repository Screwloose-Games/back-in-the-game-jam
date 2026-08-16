class_name PlayerRenderLayers
extends RefCounted

## Which render layers a player's meshes sit on. Multiplayer is networked, so
## each machine draws exactly one camera and the only question a mesh has to
## answer is "am I the local player's own body". Layer names are in
## project.godot under layer_names/3d_render.

## Everything the local camera should draw, including every remote player.
const WORLD_LAYER := 1

## The local player's own suit. Their camera is the only camera in the world and
## it culls this, so nobody has to coordinate layers between machines.
const OWN_BODY_LAYER := 11

## First-person-only geometry — arms, a held tool's near model. Drawn by the
## local camera; a remote instance never puts anything here.
const OWN_VIEWMODEL_LAYER := 12

## The tool in the local player's own hands. Drawn like the world, and lit like
## it, but kept out of their own lamp's shadow casters — a laser held a hand's
## width from the visor otherwise throws its shadow across everything you dig.
const OWN_TOOL_LAYER := 13

## A remote player's own visor, head and tool. Drawn like the world, but kept out
## of that player's own lamp's shadow casters: their visor encloses their lamp,
## so it would otherwise swallow their beam entirely and you would see no light.
const PEER_SUIT_LAYER := 14

## Godot has 20 render layers.
const ALL_LAYERS := 0xFFFFF


## The mask bit for a 1-based layer number.
static func bit(layer_number: int) -> int:
	return 1 << (layer_number - 1)


static func world_mask() -> int:
	return bit(WORLD_LAYER)


static func own_body_mask() -> int:
	return bit(OWN_BODY_LAYER)


static func own_viewmodel_mask() -> int:
	return bit(OWN_VIEWMODEL_LAYER)


static func own_tool_mask() -> int:
	return bit(OWN_TOOL_LAYER)


static func peer_suit_mask() -> int:
	return bit(PEER_SUIT_LAYER)


## What the local player's own lamp may cast shadows from. Their own tool and the
## visor around the lamp are not in it; a remote peer's suit is, so an ally you
## light still throws a shadow.
static func own_lamp_shadow_caster_mask() -> int:
	return ALL_LAYERS & ~(own_tool_mask() | own_body_mask())


## What a remote player's lamp may cast shadows from. The same rule seen from the
## other side: their own suit is dropped, yours and the asteroid are not.
static func peer_lamp_shadow_caster_mask() -> int:
	return ALL_LAYERS & ~peer_suit_mask()


## Everything except the local player's own body. Remote players stay on the
## world layer, so they are drawn without any per-peer bookkeeping.
static func local_camera_cull_mask() -> int:
	return (ALL_LAYERS & ~own_body_mask()) & ALL_LAYERS


## Whether a camera with this cull mask draws a mesh on these layers.
static func is_visible_to(mesh_layers: int, cull_mask: int) -> bool:
	return (mesh_layers & cull_mask) != 0
