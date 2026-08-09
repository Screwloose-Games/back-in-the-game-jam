class_name DrillChamberGenerator
extends Node3D

## Carves one open room out of solid hull with CSG.
##
## Deliberately plain: the question this prototype asks is what drilling feels
## like, not whether you can navigate. The pillars are here only so there is
## something to judge your own drift against - in an empty box with no landmarks
## a suit that is moving looks identical to one that is not.
##
## Brush order is what makes the CSG work: the room is hollowed out of the hull
## first, then the pillars are added back into the empty space.
##
## The carryable module and its lamp were dropped from the copy this came from.
## Nothing is carried in this prototype, and the ore nodes are placed by the
## prototype root rather than by the chamber.

const HULL_MATERIAL := preload("res://prototypes/drill_and_mining/materials/hull_material.tres")

const HULL_LAYER := 1


func _ready() -> void:
	_assemble_combiner()


func _assemble_combiner() -> void:
	var combiner := CSGCombiner3D.new()
	combiner.name = "HullCombiner"
	combiner.use_collision = true
	combiner.collision_layer = HULL_LAYER
	combiner.collision_mask = 0
	combiner.material_override = HULL_MATERIAL
	add_child(combiner)

	var wall_padding := Vector3.ONE * DrillKnobs.WALL_THICKNESS * 2.0
	combiner.add_child(
		_make_brush(
			Vector3.ZERO, DrillKnobs.CHAMBER_SIZE + wall_padding, CSGShape3D.OPERATION_UNION
		)
	)
	combiner.add_child(
		_make_brush(Vector3.ZERO, DrillKnobs.CHAMBER_SIZE, CSGShape3D.OPERATION_SUBTRACTION)
	)

	for pillar: Dictionary in DrillKnobs.PILLARS:
		var pillar_center: Vector3 = pillar["center"]
		var pillar_size: Vector3 = pillar["size"]
		combiner.add_child(_make_brush(pillar_center, pillar_size, CSGShape3D.OPERATION_UNION))


func _make_brush(
	brush_center: Vector3, brush_size: Vector3, operation: CSGShape3D.Operation
) -> CSGBox3D:
	var brush := CSGBox3D.new()
	brush.size = brush_size
	brush.operation = operation
	brush.position = brush_center
	return brush
