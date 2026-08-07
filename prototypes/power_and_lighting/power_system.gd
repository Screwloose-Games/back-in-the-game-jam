class_name PowerSystem
extends Node

## The rules about where power goes. The two batteries themselves know none of
## this - see power_store.gd.
##
## There are exactly two ways charge moves, and they run in opposite directions:
##
##   TETHER  cube -> suit, automatically, whenever the line is clipped on.
##   CRANK   nothing -> cube, while the crank is engaged.
##
## Cranking is told to this node rather than read off the keyboard by it. F is
## one key doing two jobs - tap to grip, hold to crank - and only the prototype
## root can tell which one is happening, because that depends on how long the key
## has been down and on nothing this node can see.
##
## The suit's own drain is not here. It is the suit store's idle drain, because
## it happens whatever this node thinks, including while the suit is charging -
## the tether has to out-pay the drain rather than pause it, which is what makes
## SUIT_CHARGE_PER_SECOND against SUIT_DRAIN_PER_SECOND a real ratio instead of
## two independent numbers.
##
## THE TETHER IS THE ONLY CHARGE LINK. Holding the cube in both hands does
## nothing for the suit battery, and that is the point: the grip is how you move
## the cube and the tether is how you live off it, so clipping in is a decision
## with a cost (a 10 m leash) rather than a thing that happens for free whenever
## the cube is nearby.

## Charge per second the suit pulls from a tethered cube. Seeded from PowerKnobs
## and moved by the tuning panel.
var charge_per_second := PowerKnobs.SUIT_CHARGE_PER_SECOND

## Charge per second cranking puts into the cube.
var crank_per_second := PowerKnobs.CRANK_PER_SECOND

var _suit: CarrierSuit
var _cube: RigidBody3D
var _suit_store: PowerStore
var _cube_store: PowerStore

## What actually happened last frame, for the HUD. Recomputed every frame rather
## than inferred from the input, so "CHARGING" appears only when charge really
## moved - a tether clipped to a flat cube reports nothing, which is the answer
## you want at the moment you are wondering why the suit is still dying.
var _charged_this_frame := 0.0
var _cranked_this_frame := 0.0

## Whether the root's grip-or-crank gesture has settled on cranking.
var _crank_engaged := false


func _process(delta: float) -> void:
	_charged_this_frame = 0.0
	_cranked_this_frame = 0.0
	if _suit == null or _cube == null:
		return
	_run_tether_charge(delta)
	_run_crank(delta)


func bind(
	suit: CarrierSuit, cube: RigidBody3D, suit_store: PowerStore, cube_store: PowerStore
) -> void:
	_suit = suit
	_cube = cube
	_suit_store = suit_store
	_cube_store = cube_store


## True while the suit is actually taking charge off the cube this frame.
func is_charging() -> bool:
	return _charged_this_frame > 0.0


## True while cranking is actually putting charge into the cube this frame.
func is_cranking() -> bool:
	return _cranked_this_frame > 0.0


## Told by the root each frame whether its grip-or-crank gesture has settled on
## cranking.
func set_crank_engaged(engaged: bool) -> void:
	_crank_engaged = engaged


## Whether the cube is close enough to crank: under the crosshair within the
## suit's own grab reach, or already in your hands.
##
## This is what decides whether holding F becomes a crank at all, so it
## deliberately says nothing about how full the cube is. A full cube is still
## something you are plainly trying to crank, and treating it as though it were
## not would drop the gesture back to a grab and leave you carrying the cube you
## meant to top up.
func is_cube_in_reach() -> bool:
	if _suit == null or _cube == null:
		return false
	return _suit.get_targeted_object() == _cube or _suit.get_held_object() == _cube


## Whether cranking would actually put anything in. The HUD prompts on this, so
## the prompt stops as soon as the cube is full rather than inviting a hold that
## achieves nothing.
func can_crank() -> bool:
	return is_cube_in_reach() and _cube_store.get_fraction() < 1.0


## Moves charge out of the cube and into the suit, losing none of it on the way.
##
## Spend first, store second, and hand back whatever the suit could not take. A
## transfer written the other way round - store what you hoped for, then spend
## it - quietly creates charge when the cube is nearly empty and destroys it when
## the suit is nearly full.
func _run_tether_charge(delta: float) -> void:
	if _suit.get_tethered_object() != _cube:
		return
	var drawn := _cube_store.spend(charge_per_second * delta)
	if drawn <= 0.0:
		return
	var accepted := _suit_store.store(drawn)
	_cube_store.store(drawn - accepted)
	_charged_this_frame = accepted


## can_crank is re-tested here even though the root only engages the crank when
## the cube is in reach: the gesture stays engaged until the key comes up, and in
## between you can swim away from the cube or fill it. Neither should go on
## putting charge in.
func _run_crank(delta: float) -> void:
	if not _crank_engaged:
		return
	if not can_crank():
		return
	_cranked_this_frame = _cube_store.store(crank_per_second * delta)
