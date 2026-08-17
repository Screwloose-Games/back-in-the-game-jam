class_name VoiceConfig
extends Resource

## Every tunable in the voice pipeline, in one place.
##
## Passed into the core objects rather than read by them, so the pure layer stays
## testable against hand-built values. Spec section 7.3 owns these numbers.

## Godot's resampler pulls 128 source frames per call and zero-fills below that,
## so a playout frame shorter than this would stutter no matter how well buffered.
const JITTER_MIN_SAMPLES := 128

@export var sample_rate: int = 8000
@export var frame_ms: int = 40
## Resample from the rate capture is measured to deliver at rather than the one the
## driver reports. Off restores the old behaviour of believing the driver.
@export var adaptive_capture_rate: bool = true
@export var vad_open_dbfs: float = -45.0
@export var vad_hysteresis_db: float = 7.0
@export var vad_hangover_ms: int = 200
@export var jitter_target_frames: int = 3
@export var jitter_max_frames: int = 6
@export var jitter_reset_gap: int = 32
@export var audible_radius: float = 30.0
@export var unit_size: float = 6.0
@export var occlusion_clear_hz: float = 20000.0
@export var occlusion_blocked_hz: float = 700.0
@export var occlusion_blocked_db: float = -6.0
@export var occlusion_ray_hz: float = 8.0
@export var occlusion_ramp_seconds: float = 0.05
@export var send_buffer_limit_bytes: int = 65536


func samples_per_frame() -> int:
	return (sample_rate * frame_ms) / 1000


## Sample 0 rides in the packet header as the predictor, so only the rest are coded.
func code_count() -> int:
	return samples_per_frame() - 1


func payload_bytes() -> int:
	return (code_count() + 1) / 2


func frame_seconds() -> float:
	return frame_ms / 1000.0


func vad_close_dbfs() -> float:
	return vad_open_dbfs - vad_hysteresis_db


func vad_hangover_frames() -> int:
	return int(ceil(float(vad_hangover_ms) / float(frame_ms)))
