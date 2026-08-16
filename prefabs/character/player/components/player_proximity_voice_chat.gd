class_name PlayerProximityVoiceChat
extends Node3D

## One player's voice, in both directions: the microphone on the local copy of
## this prefab, and the spatialised speaker on every remote copy.
##
## Deliberately outside Godot's authority model. PlayerNetworkDriver hands the
## whole player subtree to peer 1, which would say the host owns everybody's
## microphone; nothing here is an RPC or a synchroniser, so local versus remote
## is decided the same way PlayerNetworkDriver decides it, by comparing peer ids.

const HULL_COLLISION_MASK := 1
const MIN_CUTOFF_HZ := 1.0
const MAX_CUTOFF_HZ := 20500.0
## The microphone node exists to hold the input device open, not to be heard. The
## bus path needs full amplitude because its AudioEffectCapture reads the mixed
## signal; the driver path does not, so it can be silenced at the source.
const MONITOR_SILENT_DB := -80.0
const MONITOR_AUDIBLE_DB := 0.0

var _controlled_peer_id := 1
var _is_local_controller := true
var _is_speaker := false
var _owns_bus := false
var _bus_index := -1
var _samples_per_frame := 320
var _ring_capacity := 0
var _target_queued := 0
var _peer_volume := 1.0
var _peer_muted := false
var _occluded := false
var _occlusion_blend := 0.0
var _ray_elapsed := 0.0
var _jitter: VoiceJitterBuffer
var _playback: AudioStreamGeneratorPlayback
var _filter: AudioEffectLowPassFilter
var _squelch: AudioStreamPlayer3D
var _squelch_on: AudioStreamWAV
var _squelch_off: AudioStreamWAV

@onready var _voice_output: AudioStreamPlayer3D = $VoiceOutput
@onready var _voice_input: AudioStreamPlayer = $VoiceInput


## Must run before MultiplayerSpawner inserts the prefab into SceneTree, which is
## why this takes ids rather than reading them from a node that is not there yet.
func configure(controlled_peer_id: int, local_peer_id: int) -> void:
	_controlled_peer_id = controlled_peer_id
	_is_local_controller = local_peer_id == controlled_peer_id


func set_microphone_active(active: bool, monitor_silent := true) -> void:
	if _voice_input == null:
		return
	_voice_input.volume_db = MONITOR_SILENT_DB if monitor_silent else MONITOR_AUDIBLE_DB
	if active and not _voice_input.playing:
		_voice_input.play()
	elif not active and _voice_input.playing:
		_voice_input.stop()


func receive_voice(packet: Dictionary) -> void:
	if _jitter == null or int(packet.get("codec_id", -1)) != VoicePacket.CODEC_ADPCM:
		return
	var samples := VoiceAdpcm.decode(
		packet["data"], int(packet["predictor"]), int(packet["step_index"]), _samples_per_frame
	)
	if samples.is_empty():
		return
	_jitter.push(int(packet["sequence"]), samples)


func reset_playout() -> void:
	if _jitter != null:
		_jitter.reset()


func set_listener_mix(volume: float, muted: bool) -> void:
	_peer_volume = clampf(volume, 0.0, 1.0)
	_peer_muted = muted
	_apply_bus_mix()


func _ready() -> void:
	var config: VoiceConfig = VoiceService.config
	_samples_per_frame = config.samples_per_frame()

	if _is_local_controller:
		VoiceService.register_local_voice(self)
		# Nothing to hear from your own avatar unless the loopback rig is on.
		if not VoiceService.loopback_enabled:
			_voice_output.queue_free()
			set_process(false)
			set_physics_process(false)
			return
	else:
		# A remote avatar has no business owning a node that can open this
		# machine's microphone, and two live ones would sum on the capture bus.
		_voice_input.queue_free()
		_voice_input = null

	_begin_playback(config)


func _exit_tree() -> void:
	if _is_local_controller:
		VoiceService.unregister_local_voice(self)
	if _is_speaker:
		VoiceService.unregister_speaker(_controlled_peer_id)


func _process(_delta: float) -> void:
	if _playback == null:
		return
	_drain_jitter_buffer()


## Occlusion rides the physics tick because the raycast needs the space state,
## and because AudioStreamPlayer3D recomputes its panning here anyway.
func _physics_process(delta: float) -> void:
	if _playback == null:
		return
	_step_occlusion(delta)


func _begin_playback(config: VoiceConfig) -> void:
	_jitter = VoiceJitterBuffer.new(config)
	var bus_name := VoiceService.register_speaker(_controlled_peer_id, self)
	_is_speaker = true
	_bus_index = AudioServer.get_bus_index(bus_name)
	_owns_bus = bus_name != VoiceService.SHARED_BUS and _bus_index >= 0
	if _owns_bus:
		_filter = _find_occlusion_filter(_bus_index)
		_build_squelch(bus_name)

	# Built here rather than in the .tscn so a single sub-resource cannot end up
	# shared between two players, and so VoiceConfig stays the only source.
	var generator := AudioStreamGenerator.new()
	generator.mix_rate_mode = AudioStreamGenerator.MIX_RATE_CUSTOM
	generator.mix_rate = config.sample_rate
	generator.buffer_length = 0.2

	_voice_output.stream = generator
	_voice_output.bus = bus_name
	# Required per node: web defaults to sample playback, which routes around the
	# engine mixer and so has no effect chain for the occlusion filter to live in.
	_voice_output.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	_voice_output.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_voice_output.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	_voice_output.max_distance = config.audible_radius
	_voice_output.unit_size = config.unit_size
	_voice_output.max_polyphony = 1

	# Started once and never stopped: creating and freeing players as speakers
	# cross the audible boundary clicks. A generator with nothing pushed into it
	# plays silence, so an idle speaker costs nothing.
	_voice_output.play()
	_playback = _voice_output.get_stream_playback() as AudioStreamGeneratorPlayback
	_target_queued = _samples_per_frame * maxi(config.jitter_target_frames, 1)
	_apply_bus_mix()


## Sought by type rather than taken from a fixed slot, because the radio chain
## sits ahead of it: occlusion has to run last or the distortion would put back
## the high end a wall is supposed to be taking away.
func _find_occlusion_filter(bus_index: int) -> AudioEffectLowPassFilter:
	for i in AudioServer.get_bus_effect_count(bus_index):
		var filter := AudioServer.get_bus_effect(bus_index, i) as AudioEffectLowPassFilter
		if filter != null:
			return filter
	return null


## Keying clicks play on the speaker's own bus, so they arrive spatialised and
## radio-filtered exactly like the voice they bracket.
func _build_squelch(bus_name: StringName) -> void:
	var config: VoiceConfig = VoiceService.config
	_squelch = AudioStreamPlayer3D.new()
	_squelch.name = "Squelch"
	_squelch.bus = bus_name
	# Sample playback would route around the mixer, and with it the radio chain.
	_squelch.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	_squelch.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_squelch.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	_squelch.max_distance = config.audible_radius
	_squelch.unit_size = config.unit_size
	_squelch.max_polyphony = 2
	add_child(_squelch)

	_squelch_on = VoiceSquelch.key_on()
	_squelch_off = VoiceSquelch.key_off()
	VoiceService.peer_started_speaking.connect(_on_peer_started_speaking)
	VoiceService.peer_stopped_speaking.connect(_on_peer_stopped_speaking)


func _on_peer_started_speaking(peer_id: int) -> void:
	_play_squelch(peer_id, _squelch_on)


func _on_peer_stopped_speaking(peer_id: int) -> void:
	_play_squelch(peer_id, _squelch_off)


func _play_squelch(peer_id: int, stream: AudioStreamWAV) -> void:
	if peer_id != _controlled_peer_id or _squelch == null or stream == null:
		return
	# A peer that stops speaking because it left takes its avatar with it.
	if not is_inside_tree():
		return
	_squelch.stream = stream
	_squelch.play()


## Paced against how fast the generator is draining, not against how much room
## it has. The ring holds 2047 frames against a 320-sample voice frame, so
## filling it would pop six frames on the first tick, and pop() treats a pop with
## nothing buffered as an underrun - which would fabricate concealment frames and
## retire the speaker a few milliseconds after it started talking.
func _drain_jitter_buffer() -> void:
	var room := _playback.get_frames_available()
	# The ring starts empty, so the first honest reading is its capacity. Taking
	# the maximum survives a first tick where the mixer has not run yet.
	_ring_capacity = maxi(_ring_capacity, room)
	var queued := _ring_capacity - room
	while queued < _target_queued and room >= _samples_per_frame:
		var frame := _jitter.pop()
		if frame.is_empty():
			return
		var stereo := PackedVector2Array()
		stereo.resize(frame.size())
		for i in frame.size():
			stereo[i] = Vector2(frame[i], frame[i])
		_playback.push_buffer(stereo)
		room -= _samples_per_frame
		queued += _samples_per_frame


func _step_occlusion(delta: float) -> void:
	if not _owns_bus:
		return
	var config: VoiceConfig = VoiceService.config
	_ray_elapsed += delta
	if _ray_elapsed >= 1.0 / maxf(config.occlusion_ray_hz, 1.0):
		_ray_elapsed = 0.0
		_occluded = _is_behind_geometry()

	var target := 1.0 if _occluded else 0.0
	if is_equal_approx(_occlusion_blend, target):
		return
	# Stepped from GDScript because the engine picks a cutoff change up once per
	# mix block and interpolates nothing, so writing the target straight in zips.
	_occlusion_blend = move_toward(
		_occlusion_blend, target, delta / maxf(config.occlusion_ramp_seconds, 0.001)
	)
	if _filter != null:
		# Geometric, not linear: a linear sweep spends most of its travel above
		# 4 kHz, where an 8 kHz codec has nothing left to filter.
		var octaves := lerpf(
			log(config.occlusion_clear_hz), log(config.occlusion_blocked_hz), _occlusion_blend
		)
		_filter.cutoff_hz = clampf(exp(octaves), MIN_CUTOFF_HZ, MAX_CUTOFF_HZ)
	_apply_bus_mix()


func _is_behind_geometry() -> bool:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return false
	var query := PhysicsRayQueryParameters3D.create(
		camera.global_position, global_position, HULL_COLLISION_MASK
	)
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _apply_bus_mix() -> void:
	if not _owns_bus:
		return
	var config: VoiceConfig = VoiceService.config
	var occlusion_db := lerpf(0.0, config.occlusion_blocked_db, _occlusion_blend)
	AudioServer.set_bus_mute(_bus_index, _peer_muted)
	AudioServer.set_bus_volume_db(
		_bus_index, linear_to_db(maxf(_peer_volume, 0.0001)) + occlusion_db
	)
