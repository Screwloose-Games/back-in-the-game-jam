class_name VoiceRateEstimator
extends RefCounted

## Measures the rate the microphone really delivers at, because the rate the
## driver reports is only a starting guess.
##
## Safari ignores the sample rate Godot asks its AudioContext for and can switch
## again when getUserMedia opens, so a stream resampled by the reported ratio comes
## out pitch-shifted by exactly however far the two disagree (spec section 6.2).

## Rates a capture device plausibly runs at. A measurement landing near one of
## these is almost certainly that one, so snapping beats trusting the arithmetic
## of a few seconds of frame counting.
const STANDARD_RATES := [
	8000, 11025, 16000, 22050, 24000, 32000, 44100, 48000, 88200, 96000, 176400, 192000
]
const MIN_RATE := 4000
const MAX_RATE := 384000
## Anything not near a standard rate is rounded onto this grid, so two windows can
## agree on it at all. Far finer than the deviation this is trying to catch.
const RATE_GRID := 100
## The device is still settling, the backlog has just been discarded, and on web
## the permission prompt may still be open, so the opening second proves nothing.
const WARMUP_SECONDS := 1.0
const WINDOW_SECONDS := 4.0
const SNAP_TOLERANCE := 0.02
## Below this the reported and measured rates agree well enough that correcting
## would be chasing noise.
const DEVIATION_TOLERANCE := 0.005
## A gap longer than this is a hitch or a backgrounded tab, and the samples that
## should have arrived during it were dropped by a ring buffer that overflowed.
const MAX_POLL_SECONDS := 0.5

var _reported := 0
var _applied := 0
var _observed := 0.0
var _candidate := 0
var _corrections := 0
var _warmup_left := WARMUP_SECONDS
var _window_seconds := 0.0
var _window_samples := 0


func _init(reported_rate: int) -> void:
	_reported = maxi(reported_rate, 1)
	_applied = _reported


func reported_rate() -> int:
	return _reported


func applied_rate() -> int:
	return _applied


## Zero until the first window closes.
func observed_rate() -> float:
	return _observed


func corrections() -> int:
	return _corrections


## Returns a rate to resample from instead, or zero to carry on unchanged.
func observe(sample_count: int, elapsed_seconds: float) -> int:
	if elapsed_seconds <= 0.0:
		return 0
	if elapsed_seconds > MAX_POLL_SECONDS:
		_discard_window()
		return 0
	if _warmup_left > 0.0:
		_warmup_left -= elapsed_seconds
		return 0

	_window_seconds += elapsed_seconds
	_window_samples += maxi(sample_count, 0)
	if _window_seconds < WINDOW_SECONDS:
		return 0

	_observed = float(_window_samples) / _window_seconds
	var measured := _quantise(_observed)
	_discard_window()
	return _consider(measured)


func _discard_window() -> void:
	_window_seconds = 0.0
	_window_samples = 0


## Two windows must agree before the stream is retuned, so neither one stalled
## frame nor a backgrounded tab's catch-up burst can move it on its own.
func _consider(measured: int) -> int:
	if measured <= 0 or measured != _candidate:
		_candidate = measured
		return 0
	if not _differs(measured, _applied):
		return 0
	_applied = measured
	_corrections += 1
	return measured


func _quantise(measured: float) -> int:
	if measured < MIN_RATE or measured > MAX_RATE:
		return 0
	for rate in STANDARD_RATES:
		if absf(measured - float(rate)) / float(rate) <= SNAP_TOLERANCE:
			return int(rate)
	return int(round(measured / float(RATE_GRID))) * RATE_GRID


static func _differs(rate: int, against: int) -> bool:
	if against <= 0:
		return true
	return absf(float(rate - against)) / float(against) > DEVIATION_TOLERANCE
