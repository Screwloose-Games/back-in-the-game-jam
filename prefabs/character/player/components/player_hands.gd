class_name PlayerHands
extends Node

## Arbitrates the one pair of hands. The design's rule is that carrying loot
## occupies you — no digging and no throwing light while your hands are full —
## so every capability that needs the hands asks here first.

signal slot_changed(slot: Slot)

## What the hands are doing. They can only be doing one of these.
enum Slot {
	EMPTY,
	## Holding a carryable: a shared box, an ore chunk, a derelict part.
	CARRYING,
	## Holding the mining laser, ready to fire.
	TOOL,
}

var _slot: Slot = Slot.EMPTY

@onready var grab: PlayerGrab = %Grab


func _ready() -> void:
	grab.took_hold.connect(_on_took_hold)
	grab.let_go.connect(_on_let_go)


func slot() -> Slot:
	return _slot


func is_empty() -> bool:
	return _slot == Slot.EMPTY


## Whether the grab component may take hold of something right now.
func can_take_hold() -> bool:
	return _slot != Slot.CARRYING


## Whether the mining laser may fire. The rule the design states outright.
func can_mine() -> bool:
	return _slot != Slot.CARRYING


## Whether a light may be thrown or held out. Same rule, same reason.
func can_throw_light() -> bool:
	return _slot != Slot.CARRYING


## Claims the hands for the tool. Refused while something is being carried.
func take_tool() -> bool:
	if _slot == Slot.CARRYING:
		return false
	_set_slot(Slot.TOOL)
	return true


## Puts the tool away, if it was out.
func stow_tool() -> void:
	if _slot == Slot.TOOL:
		_set_slot(Slot.EMPTY)


func _on_took_hold(_object: RigidBody3D) -> void:
	_set_slot(Slot.CARRYING)


func _on_let_go(_object: RigidBody3D) -> void:
	_set_slot(Slot.EMPTY)


func _set_slot(new_slot: Slot) -> void:
	if new_slot == _slot:
		return
	_slot = new_slot
	slot_changed.emit(_slot)
