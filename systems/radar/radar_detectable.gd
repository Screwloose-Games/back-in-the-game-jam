class_name RadarDetectable
extends Area3D

## What a radar pulse can find. Hang one under anything that should show up on the
## radar and the pulse reports it; detectable and nothing else, so it monitors
## nothing, masks nothing, and rays cannot see it unless a query opts in.

## Layer 8, `radar_detectable` in project.godot. Bits 1-7 are all spoken for, and
## bit 5 `creature` is already in the player hull's mask -- reusing it would set the
## suit's own broadphase to work on a thing it must never collide with.
const LAYER := 1 << 7

## How anything hunting detectables finds them without a NodePath out of the prefab.
const GROUP := &"radar_detectable"

## The size of the return. The sphere is the contact surface, so this is what decides
## how early in a sweep the thing lights up.
@export_range(0.1, 20.0, 0.1, "suffix:m") var echo_radius: float = 2.0:
	set(value):
		echo_radius = maxf(value, 0.01)
		if _sphere != null:
			_sphere.radius = echo_radius

@export_flags_3d_physics var detectable_layers: int = LAYER

var _sphere: SphereShape3D


func _ready() -> void:
	collision_layer = detectable_layers
	# Found, never finding. `monitorable` is the half that lets a pulse see this;
	# `monitoring` off and an empty mask mean it never runs a query of its own.
	collision_mask = 0
	monitorable = true
	monitoring = false
	add_to_group(GROUP)
	_build_shape()


## Built rather than authored: a SphereShape3D saved in a .tscn is ONE resource shared
## by every instance of that scene, so two creatures would fight over one radius.
func _build_shape() -> void:
	_sphere = SphereShape3D.new()
	_sphere.radius = echo_radius
	var collider := CollisionShape3D.new()
	collider.shape = _sphere
	add_child(collider)
