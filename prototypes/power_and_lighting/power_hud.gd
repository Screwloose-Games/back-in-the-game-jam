class_name PowerHud
extends CanvasLayer

## Readouts for the power and lighting prototype.
##
## The movement and carry lines are the object carrying prototype's, because the
## suit is that prototype's suit and the same numbers are still the ones you need
## when a haul goes wrong. What is new is the power block, and the one thing it
## says that no gauge can is the RATE: a bar creeping down tells you the suit is
## draining, and only a signed number per second tells you whether the knob you
## just dragged made it better or worse.
##
## The power block and the suit bar are both dropped while PowerKnobs.POWER_ENABLED
## is off. Two readouts pinned at 100% would say only that this prototype has
## batteries in it somewhere.

## Seconds between refreshes. The readouts change smoothly and rebuilding the
## string every frame is cost for no legibility. The bar and the cube gauge are
## driven by charge_changed instead, so neither is on this clock.
const REFRESH_INTERVAL := 0.1

## How long a window the drain rate is measured over. Long enough to survive a
## single stuttering frame, short enough that dragging a slider shows up while
## your hand is still on it.
const RATE_WINDOW := 0.5

const MOVEMENT_LEGEND := """WASD thrust  SPACE/CTRL up-down
Q/E roll  R stabilizers  SHIFT sprint"""

## The grip line changes with the power switch, because the gesture does. With
## power off there is nothing to crank, so the root never takes F off the suit's
## own grab and the tap-hold split does not exist.
const GRIP_LEGEND_POWERED := "F tap grab-release  F hold crank"
const GRIP_LEGEND_UNPOWERED := "F grab-release"

const LINK_LEGEND := "T clip-unclip tether  TAB respawn  ESC free mouse"

## Nothing within reach.
const CROSSHAIR_IDLE_COLOR := Color(0.78, 0.88, 1, 0.55)
## Something grabbable under the crosshair.
const CROSSHAIR_READY_COLOR := Color(1, 0.78, 0.42, 0.85)
## Currently holding on.
const CROSSHAIR_HELD_COLOR := Color(0.55, 1, 0.7, 0.9)

var _prototype: PowerAndLightingPrototype
var _suit: CarrierSuit
var _power: PowerSystem
var _suit_store: PowerStore
var _cube_store: PowerStore

var _elapsed := 0.0

## Charge the suit had RATE_WINDOW ago, and how long ago that actually was.
var _rate_reference_charge := 0.0
var _rate_elapsed := 0.0
var _suit_rate := 0.0

@onready var _readout: Label = $Readout
@onready var _crosshair: ColorRect = $Crosshair
@onready var _suit_bar: PowerBar = $SuitPower
@onready var _tuning: PowerTuningPanel = $Tuning


func _process(delta: float) -> void:
	if _suit == null:
		return
	if PowerKnobs.POWER_ENABLED:
		_measure_suit_rate(delta)
		_suit_bar.set_charging(_power.is_charging())
	_crosshair.color = _pick_crosshair_color()

	_elapsed += delta
	if _elapsed < REFRESH_INTERVAL:
		return
	_elapsed = 0.0
	_refresh()


func bind(
	prototype: PowerAndLightingPrototype,
	suit: CarrierSuit,
	power: PowerSystem,
	suit_store: PowerStore,
	cube_store: PowerStore
) -> void:
	_prototype = prototype
	_suit = suit
	_power = power
	_suit_store = suit_store
	_cube_store = cube_store

	# The bar reads a store that cannot move with power switched off, so it would
	# sit pinned at full and say only that this prototype has a battery in it.
	_suit_bar.visible = PowerKnobs.POWER_ENABLED
	if PowerKnobs.POWER_ENABLED:
		_rate_reference_charge = suit_store.charge
		suit_store.charge_changed.connect(_suit_bar.show_fraction)
		_suit_bar.show_fraction(suit_store.get_fraction())
	_tuning.bind(prototype)


## Charge per second, signed, over a sliding window. Sampled here rather than
## reported by PowerStore because the number wanted is the NET rate - drain and
## tether charge together - which is the only one that answers "am I still
## losing".
func _measure_suit_rate(delta: float) -> void:
	_rate_elapsed += delta
	if _rate_elapsed < RATE_WINDOW:
		return
	_suit_rate = (_suit_store.charge - _rate_reference_charge) / _rate_elapsed
	_rate_reference_charge = _suit_store.charge
	_rate_elapsed = 0.0


func _refresh() -> void:
	var lines := PackedStringArray()
	if PowerKnobs.POWER_ENABLED:
		lines.append(
			(
				"suit   %3.0f%%  %+5.2f /s%s"
				% [_suit_store.get_fraction() * 100.0, _suit_rate, _describe_link()]
			)
		)
		lines.append("cube   %3.0f%%%s" % [_cube_store.get_fraction() * 100.0, _describe_crank()])
		lines.append("")
	var flight := (
		"%5.2f m/s  tumble %4.2f rad/s" % [_suit.get_drift_speed(), _suit.angular_velocity.length()]
	)
	var grip_legend := GRIP_LEGEND_POWERED if PowerKnobs.POWER_ENABLED else GRIP_LEGEND_UNPOWERED
	var flight_lines := PackedStringArray(
		[
			flight,
			"stabilizers %s" % ("ON" if _suit.stabilizers_engaged else "off"),
			_describe_grip(),
			_describe_tether(),
			"",
			MOVEMENT_LEGEND,
			grip_legend,
			LINK_LEGEND,
		]
	)
	lines.append_array(flight_lines)
	_readout.text = "\n".join(lines)


## Why the rate is what it is. An empty cube on a clipped tether reports
## CLIPPED rather than CHARGING, which is the answer you want at the exact moment
## you are wondering why the suit is still dying with the line attached.
func _describe_link() -> String:
	if _power.is_charging():
		return "  CHARGING"
	if _suit.get_tethered_object() != null:
		return "  clipped, nothing coming"
	return ""


func _describe_crank() -> String:
	if _power.is_cranking():
		return "  CRANKING"
	if _power.can_crank():
		return "  hold F to crank"
	return ""


func _describe_grip() -> String:
	var held_object := _suit.get_held_object()
	if held_object == null:
		return "grip %s" % ("READY" if _suit.get_targeted_object() != null else "empty")
	return (
		"grip HELD %.0f kg  strain %4.2f / %4.2f m"
		% [held_object.mass, _suit.get_grip_strain(), MovementKnobs.GRIP_BREAK_DISTANCE]
	)


func _describe_tether() -> String:
	if _suit.get_tethered_object() == null:
		return "tether %s" % ("READY" if _suit.get_targeted_object() != null else "unclipped")
	return (
		"tether CLIPPED  %4.2f / %4.2f m  taut %4.2f / %4.2f"
		% [
			_suit.get_tether_distance(),
			MovementKnobs.TETHER_LENGTH,
			_suit.get_tether_strain(),
			MovementKnobs.TETHER_BREAK_STRETCH,
		]
	)


func _pick_crosshair_color() -> Color:
	if _suit.get_held_object() != null:
		return CROSSHAIR_HELD_COLOR
	if _suit.get_targeted_object() != null:
		return CROSSHAIR_READY_COLOR
	return CROSSHAIR_IDLE_COLOR
