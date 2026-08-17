class_name MiningLaserBeam
extends Node3D

## Draws the mining laser's beam from its muzzle to wherever the cut landed, throws
## light of the same colour on what it lands on, and makes the noise that goes with
## it. It owns no raycast of its own: PlayerMiningTool already casts along the aim,
## and a second cast from the muzzle would stop the beam short of what you are
## actually pointing at.
##
## THE AUDIO STATE MACHINE LIVES HERE rather than in a component listening to
## PlayerMiningTool.started_firing, because this file already holds both edges:
## `fire_at` is level-triggered every frame the beam is on, `hold_fire` is the off
## edge, and PlayerMiningTool calls both -- including on replicas, through
## apply_network_presentation. One latch over those two is the whole machine.
##
## TWO VOICES, NOT ONE, and the split matches the noise the creature hears. The cut
## happens where the beam lands, so the loud loop is out at the impact point; the
## tool in your hands is the quieter half. See PlayerBeamNoiseEmitter, which reports
## the same two positions to CreaturePerception at the same ratio.

## The recordings shipped with the project and had never been referenced.
const START_CLIP: AudioStream = preload("res://assets/sfx/tool/Mining_Tool_Start_01.wav")
const ACTIVE_CLIP: AudioStream = preload("res://assets/sfx/tool/Mining_Tool_Active_Loop_01.wav")
const STOP_CLIP: AudioStream = preload("res://assets/sfx/tool/Mining_Tool_Stop_01.wav")
## Where the voices go when the host project has no bus by the configured name.
const FALLBACK_BUS: StringName = &"Master"

@export var settings: PlayerSettings

@export_group("Audio")
## Falls back to Master with a warning rather than going silent, so the prefab still
## sounds in a project that has never heard of this bus.
@export var audio_bus: StringName = &"SFX"
## Metres at which the beam has faded to nothing. AudioStreamPlayer3D attenuates
## BEFORE the bus, so this is what decides whether the creature's chamber hears you.
@export_range(1.0, 200.0, 1.0, "suffix:m") var audio_max_distance: float = 60.0
@export_range(-60.0, 6.0, 0.5, "suffix:dB") var muzzle_volume_db: float = -16.0
@export_range(-60.0, 6.0, 0.5, "suffix:dB") var impact_volume_db: float = -8.0
@export_range(-60.0, 6.0, 0.5, "suffix:dB") var sting_volume_db: float = -10.0

## True between the first fire_at and the hold_fire that ends it. `hold_fire` is
## called from _ready(), and without this the laser would cough a stop sting on spawn.
var _sounding := false

@onready var muzzle: Node3D = $sm_mining_laser/muzzle_point
@onready var beam: Node3D = $Beam
@onready var beam_mesh: MeshInstance3D = $Beam/BeamMesh
@onready var impact_light: OmniLight3D = $Beam/ImpactLight
@onready var muzzle_audio: AudioStreamPlayer3D = $MuzzleAudio
@onready var impact_audio: AudioStreamPlayer3D = $ImpactAudio
@onready var sting_audio: AudioStreamPlayer3D = $StingAudio


func _ready() -> void:
	if settings == null:
		settings = PlayerSettings.new()
		push_warning("MiningLaserBeam has no settings; running on PlayerSettings defaults.")
	_apply_settings()
	_apply_audio_settings()
	hold_fire()


## Shows the beam running from the muzzle to a world position.
func fire_at(point: Vector3) -> void:
	var origin := muzzle.global_position
	var reach := point - origin
	var length := reach.length()
	if length < 0.001:
		hold_fire()
		return
	beam.visible = true
	beam_mesh.global_transform = _span(origin, reach / length, length)
	impact_light.global_position = point
	# The loud voice sits on the rock, not on the gun, which is why it is top_level.
	impact_audio.global_position = point
	_start_sounding()


func hold_fire() -> void:
	beam.visible = false
	_stop_sounding()


## The cylinder runs along its own +Y, so the basis puts that axis down the beam
## at full length and the beam's radius on the other two.
func _span(origin: Vector3, direction: Vector3, length: float) -> Transform3D:
	var up := Vector3.UP if absf(direction.y) < 0.99 else Vector3.RIGHT
	var side := up.cross(direction).normalized()
	var radius := settings.mining_beam_radius
	var span := Basis(side * radius, direction * length, side.cross(direction) * radius)
	return Transform3D(span, origin + direction * length * 0.5)


func _apply_settings() -> void:
	var material := beam_mesh.material_override as StandardMaterial3D
	if material != null:
		material.albedo_color = settings.mining_beam_color
	impact_light.light_color = settings.mining_beam_color
	impact_light.light_energy = settings.mining_light_energy
	impact_light.omni_range = settings.mining_light_range


func _apply_audio_settings() -> void:
	var bus := audio_bus
	if AudioServer.get_bus_index(bus) < 0:
		push_warning('MiningLaserBeam: no audio bus named "%s"; falling back to Master.' % bus)
		bus = FALLBACK_BUS
	var loop := _looping(ACTIVE_CLIP)
	_configure(muzzle_audio, loop, bus, muzzle_volume_db)
	_configure(impact_audio, loop, bus, impact_volume_db)
	_configure(sting_audio, null, bus, sting_volume_db)


func _configure(
	voice: AudioStreamPlayer3D, stream: AudioStream, bus: StringName, volume_db: float
) -> void:
	voice.stream = stream
	voice.bus = bus
	voice.volume_db = volume_db
	voice.max_distance = audio_max_distance


## The loop clip ships with `edit/loop_mode=0` in its .import sidecar, so played as
## imported it runs once and stops. Flipped on a DUPLICATE rather than on the clip
## itself: the preloaded resource is shared with every other user of that file, and
## mutating it would turn a one-shot into an endless tone somewhere else.
func _looping(clip: AudioStream) -> AudioStream:
	var wav := clip as AudioStreamWAV
	if wav == null:
		return clip
	var copy := wav.duplicate() as AudioStreamWAV
	copy.loop_mode = AudioStreamWAV.LOOP_FORWARD
	copy.loop_begin = 0
	# loop_end is in FRAMES and the sidecar's -1 comes through the duplicate. Derived
	# from length rather than from `data.size()` because this clip imports as QOA
	# (compress/mode=2), so its byte count is not its frame count.
	copy.loop_end = int(round(copy.get_length() * float(copy.mix_rate)))
	return copy


func _start_sounding() -> void:
	if _sounding:
		return
	_sounding = true
	sting_audio.stream = START_CLIP
	sting_audio.play()
	muzzle_audio.play()
	impact_audio.play()


func _stop_sounding() -> void:
	if not _sounding:
		return
	_sounding = false
	muzzle_audio.stop()
	impact_audio.stop()
	sting_audio.stream = STOP_CLIP
	sting_audio.play()
