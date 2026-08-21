class_name ElevatorCutsceneHud
extends CanvasLayer

## The prototype's screen overlay: the helmet HUD the cutscene fades up, the
## gameplay crosshair, a debug readout and the skip prompt.
##
## THIS SCRIPT DOES NOT OWN HelmetHud.modulate. The animation does, as a value
## track, so the fade is seek-safe and a scrub to any time yields exactly the
## right alpha. Two authorities on "is the HUD showing" is how one of them ends
## up stale after a skip. The one exception is set_helmet_online(), which asserts
## the FINAL state at CLEANUP - by which point the animation has stopped and is
## no longer writing.
##
## THE TUNING PANEL IS NOT PART OF THE GAMEPLAY HUD and is not hidden during
## playback. The spec's "hide HUD" on cutscene enter means the crosshair and the
## helmet overlay; the panel is the director's live surface, and hiding it for
## the nineteen seconds you are trying to tune would defeat the point of having
## it. set_gameplay_visible() touches the crosshair only.

@onready var _helmet_hud: Control = $HelmetHud
@onready var _debt_line: Label = $HelmetHud/DebtLine
@onready var _quota_line: Label = $HelmetHud/QuotaLine
@onready var _begin_workday: Label = $HelmetHud/BeginWorkday
@onready var _crosshair: ColorRect = $Crosshair
@onready var _readout: Label = $Readout
@onready var _skip_prompt: Label = $SkipPrompt
@onready var _monitor_shot: ElevatorMonitorShot = $MonitorShot


func _ready() -> void:
	# Copy comes from the knobs file rather than the .tscn, because it is the
	# thing most likely to change and it should change in one place.
	_debt_line.text = ElevatorCutsceneKnobs.HUD_DEBT
	_quota_line.text = ElevatorCutsceneKnobs.HUD_QUOTA
	_begin_workday.text = ElevatorCutsceneKnobs.HUD_TITLE
	_skip_prompt.text = ElevatorCutsceneKnobs.HUD_SKIP_PROMPT


## Shows or hides the parts of the overlay that belong to gameplay rather than
## to the cutscene.
func set_gameplay_visible(is_visible: bool) -> void:
	_crosshair.visible = is_visible


## Forces the helmet overlay to its end state, at CLEANUP.
##
## Alpha rather than `visible`, so there is still exactly one property deciding
## whether the overlay shows. A `visible` bool track would be seek-safe too, but
## then two things would answer the same question and only one of them would be
## right after a skip.
func set_helmet_online(is_online: bool) -> void:
	_helmet_hud.modulate.a = 1.0 if is_online else 0.0
	# The title card is a beat, not a state: it has finished by the end of the
	# clip whether you watched it or skipped it.
	_begin_workday.modulate.a = 0.0


## Forces the opening monitor shot off, at CLEANUP.
##
## Belt and braces over the shot_alpha keyframe, which skip()'s seek already lands
## at zero. A stuck full-screen opaque overlay is the worst failure this file has,
## and it costs one line to make it unreachable. verify_elevator_cutscene.gd checks
## the keyframe separately, so this cannot mask a deleted one.
func set_monitor_shot_visible(is_visible: bool) -> void:
	_monitor_shot.shot_alpha = 1.0 if is_visible else 0.0


## How much of the terminal's glass the opening shot holds. Pushed through here so
## the prototype root has one HUD to talk to rather than reaching past it.
func set_monitor_framing(distance: float, fov: float) -> void:
	_monitor_shot.set_framing(distance, fov)


func set_skip_prompt_visible(is_visible: bool) -> void:
	_skip_prompt.visible = is_visible


func set_readout(text: String) -> void:
	_readout.text = text
