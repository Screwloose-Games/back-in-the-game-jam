class_name TunnelHud
extends CanvasLayer

## Readouts and the network map.
##
## The map is not a nicety. A 200 m branching network with no up, no down, no
## horizon and a twelve-metre draw distance is disorienting by design, and the
## point of the prototype is to find out whether the TUNNELS are good - not to
## find out that people get lost, which is already known.

## Seconds between refreshes. The readouts change smoothly and redrawing the map
## every frame is pure cost for no legibility.
const REFRESH_INTERVAL := 0.1

var _prototype: TunnelSystemPrototype
var _player: ZeroGPlayer
var _elapsed := 0.0

@onready var _readout: Label = $Readout
@onready var _map: TunnelMapOverlay = $Map
@onready var _tuning: TunnelTuningPanel = $Tuning


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < REFRESH_INTERVAL:
		return
	_elapsed = 0.0
	if _player == null or _prototype == null:
		return
	_refresh()


func bind(prototype: TunnelSystemPrototype, player: ZeroGPlayer) -> void:
	_prototype = prototype
	_player = player
	_map.bind(prototype.network, player)
	_tuning.bind(prototype)


func _refresh() -> void:
	var position := _player.global_position
	var network := _prototype.network

	# field() is negative inside the bore, and because it is a distance function
	# its magnitude IS the distance to the nearest wall. No extra raycast needed.
	var field := network.field(position)
	var clearance := -field if field < 0.0 else 0.0
	var buried := field > 0.0

	var lines := PackedStringArray(
		[
			"depth        %6.1f m" % -position.y,
			"speed        %6.2f m/s" % _player.get_drift_speed(),
			"clearance    %6.2f m%s" % [clearance, "  <-- INSIDE ROCK" if buried else ""],
			"tunnel       %s" % network.nearest_route_name(position),
			"to entrance  %6.1f m" % position.distance_to(TunnelKnobs.SPAWN_POSITION),
			"",
			"WASD + space/ctrl thrust - mouse look - Q/E roll",
			"shift stabilise - R respawn - ESC release mouse",
		]
	)
	_readout.text = "\n".join(lines)
	_map.queue_redraw()
