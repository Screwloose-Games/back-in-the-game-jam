class_name PlayerVisibility
extends Node

## Decides what a player sees of their own suit. Multiplayer is networked, so
## this instance is either the local player — whose camera culls their own body —
## or a remote player, drawn in full like any other object in the world.

signal self_view_changed(view: SelfView)

## What the local player's camera does with their own suit.
enum SelfView {
	## Nothing of your own suit is drawn, the held tool included — it hangs off the
	## rig, so it goes with the rest.
	HIDE_WHOLE_MODEL,
	## Only the meshes named in parts_hidden_from_self vanish.
	HIDE_LISTED_PARTS,
	## Draw everything, as a remote player sees you.
	SHOW_EVERYTHING,
}

## False on the instances that represent other peers. Set it from the spawner or
## from multiplayer authority before the prefab enters the tree, or call
## set_local_player() after.
@export var is_local_player: bool = true:
	set = set_local_player

## Applied while the local player is in first person. A third-person camera
## calls set_first_person(false) and the whole suit is drawn. HIDE_WHOLE_MODEL was
## the default while the head was welded into the body mesh and could not be culled
## on its own; it is a separate mesh now, so you keep your suit and your tool.
@export var self_view: SelfView = SelfView.HIDE_LISTED_PARTS:
	set = set_self_view

## Mesh node names to hide from the local player, used by HIDE_LISTED_PARTS.
## Names rather than paths, so re-importing the model does not break them. The
## camera sits inside both the head and the visor, so both have to go.
@export var parts_hidden_from_self: Array[StringName] = [
	&"player_character_head", &"player_character_helmet"
]

## Mesh node names only the local player sees — first-person arms, a held tool's
## near model. Hidden outright on a remote instance.
@export var parts_only_visible_to_self: Array[StringName] = []

## Mesh node names of the tool in the local player's own hands. Drawn and lit as
## normal, but on their own layer so their own lamp can skip them when it casts
## shadows. See PlayerLamp.
@export var parts_on_own_tool_layer: Array[StringName] = [&"cutter_body"]

var _first_person := true

@onready var rig: Node3D = %Rig
@onready var camera: Camera3D = %HeadCamera


func _ready() -> void:
	apply()


func set_local_player(value: bool) -> void:
	is_local_player = value
	if is_node_ready():
		apply()


func set_self_view(value: SelfView) -> void:
	self_view = value
	if is_node_ready():
		apply()
		self_view_changed.emit(self_view)


## Third-person and spectator cameras draw the whole suit whatever self_view says.
func set_first_person(value: bool) -> void:
	if value == _first_person:
		return
	_first_person = value
	if is_node_ready():
		apply()


func is_first_person() -> bool:
	return _first_person


## Writes the layers and the cull mask. Done in code rather than saved on the
## meshes because they live inside an instanced glTF scene, where property
## overrides need editable children and do not survive a re-import.
func apply() -> void:
	camera.cull_mask = PlayerRenderLayers.local_camera_cull_mask()
	for node: Node in rig.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var is_viewmodel := parts_only_visible_to_self.has(mesh.name)
		# A remote peer's viewmodel would hang in the world with nobody to look
		# down it, so it is switched off rather than given a layer.
		mesh.visible = is_local_player or not is_viewmodel
		mesh.layers = layers_for(mesh.name)


## The layers one mesh belongs on, by name. Public so a test can ask without a
## camera or a rig.
func layers_for(mesh_name: StringName) -> int:
	if not is_local_player:
		return _peer_layers_for(mesh_name)
	if parts_only_visible_to_self.has(mesh_name):
		return PlayerRenderLayers.own_viewmodel_mask()
	if not _first_person or self_view == SelfView.SHOW_EVERYTHING:
		return PlayerRenderLayers.world_mask()
	var hidden := self_view == SelfView.HIDE_WHOLE_MODEL or parts_hidden_from_self.has(mesh_name)
	if hidden:
		return PlayerRenderLayers.own_body_mask()
	if parts_on_own_tool_layer.has(mesh_name):
		return PlayerRenderLayers.own_tool_mask()
	return PlayerRenderLayers.world_mask()


## A remote peer is drawn whole, so this is a lighting split rather than a hiding
## one: their lamp sits inside their visor and beside their laser exactly as yours
## does, and the layer their own lamp skips is what keeps their beam alive.
func _peer_layers_for(mesh_name: StringName) -> int:
	if parts_hidden_from_self.has(mesh_name) or parts_on_own_tool_layer.has(mesh_name):
		return PlayerRenderLayers.peer_suit_mask()
	return PlayerRenderLayers.world_mask()
