class_name VoiceCapture
extends RefCounted

## The seam between the microphone and everything downstream of it.
##
## This base class is also the null implementation: it starts, reports itself
## inactive and returns no frames, so the editor, the automated tests and a player
## who denied microphone permission all take the same path. It also owns the
## resample-measure-and-frame plumbing that both real backends share.

var _config: VoiceConfig
var _resampler: VoiceResampler
var _assembler: VoiceFrameAssembler
var _estimator: VoiceRateEstimator
var _reported_rate := 0
var _last_poll_usec := 0


func _init(config: VoiceConfig) -> void:
	_config = config


func config() -> VoiceConfig:
	return _config


func start() -> Error:
	return OK


func stop() -> void:
	pass


func is_active() -> bool:
	return false


## Empty while the capture is idle or unavailable; never an error.
func poll() -> Array[PackedFloat32Array]:
	return []


## Player-facing explanation of why capture is unavailable, or an empty string.
func unavailable_reason() -> String:
	return ""


## The rate frames are really resampled from, which is the measured one once the
## estimator has enough evidence to disagree with the driver.
func source_rate() -> int:
	return _config.sample_rate if _resampler == null else _resampler.source_rate()


## What the driver claimed at open, kept so the two can be compared in a log.
func reported_rate() -> int:
	return _reported_rate


func observed_rate() -> float:
	return 0.0 if _estimator == null else _estimator.observed_rate()


func rate_corrections() -> int:
	return 0 if _estimator == null else _estimator.corrections()


func _begin_stream(reported_rate: int) -> void:
	_reported_rate = maxi(reported_rate, 1)
	_resampler = VoiceResampler.new(_reported_rate, _config.sample_rate)
	_assembler = VoiceFrameAssembler.new(_config.samples_per_frame())
	_estimator = VoiceRateEstimator.new(_reported_rate)
	_last_poll_usec = Time.get_ticks_usec()


func _end_stream() -> void:
	_resampler = null
	_assembler = null
	_estimator = null
	_last_poll_usec = 0


func _ingest(mono: PackedFloat32Array) -> Array[PackedFloat32Array]:
	if _resampler == null or _assembler == null:
		return []
	_track_rate(mono.size())
	return _assembler.push(_resampler.process(mono))


## Counts what really arrived against the wall clock, so a driver that misreports
## its rate is corrected rather than believed. The clock advances even when the
## estimator is switched off, so switching it on mid-session sees an honest gap.
func _track_rate(sample_count: int) -> void:
	var now := Time.get_ticks_usec()
	var elapsed := float(now - _last_poll_usec) / 1_000_000.0
	_last_poll_usec = now
	if _estimator == null or not _config.adaptive_capture_rate:
		return
	var corrected := _estimator.observe(sample_count, elapsed)
	if corrected <= 0:
		return
	push_warning(
		(
			"Voice: capture reports %d Hz but delivers about %d Hz; resampling from the measured rate."
			% [_reported_rate, corrected]
		)
	)
	_resampler.retune(corrected)
