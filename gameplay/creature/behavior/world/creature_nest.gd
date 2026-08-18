@tool
class_name CreatureNest
extends Marker3D

## A place the alien is willing to be when it is not interested in you (behavior.md
## section 24).
##
## A marker and nothing else. Nests are how the creature's ambient movement stays
## territorial rather than becoming a patrol route -- the alien goes between places it
## likes, in an order weighted by distance and recent use, so watching it for a minute does
## not tell you where it will be in the next one.
##
## THE NEST DOES NOT KNOW ABOUT THE CREATURE, and there is no registry object. Behavior
## reads positions out of these once and keeps its own memory, so the whole nest system is a
## PackedVector3Array as far as the HFSM is concerned and the tests need no scene at all.

## Nests found by group when a CreatureBehavior is not given an explicit list.
const GROUP: StringName = &"creature_nests"


func _ready() -> void:
	add_to_group(GROUP)
