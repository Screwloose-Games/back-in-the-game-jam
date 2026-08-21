@tool
class_name ElevatorScreen
extends Node3D

## The elevator car's quota terminal: one quad for the whole plate, a SubViewport of
## real Controls for the readout, and elevator_screen.gdshader to erase the plate's
## baked text and composite the live one into the hole.
##
## The quota rules live here as static functions rather than as maths in the shader,
## so the thing that encodes "quota met" is the thing a test can call.

signal quota_met

## Instanced screens join this so PlayerHudBinding can hand them the local player's
## HudState without the level knowing about the screen or the screen about the level.
const GROUP := &"quota_screen"

const CONTENT_PARAM := "content_tex"

@export_group("Copy")
@export var crew_id := "EXTRACTION CREW 067":
	set = set_crew_id
@export var quota_caption := "OUTSTANDING QUOTA:"
@export var auth_caption := "DEPARTURE AUTHORIZATION:"
@export var denied_text := "DENIED"
@export var approved_text := "APPROVED"
@export var value_format := "%d CR"

@export_group("Quota")

## Credits owed at zero minerals. Positive; the readout shows it negated.
@export var quota_target := 47560

## Credits earned per point of mineral score.
@export var credits_per_point := 1.0

@export_group("Colors")
@export var label_color := Color(0.62, 0.95, 0.85)
@export var value_color := Color(0.95, 0.85, 0.35)
@export var denied_color := Color(1.0, 0.22, 0.18)
@export var approved_color := Color(0.35, 1.0, 0.55)

@export_group("Tube")
@export_range(0.0, 1.0) var power_on := 1.0:
	set = set_power_on
@export var spill_energy := 1.2

var _material: ShaderMaterial
var _collected := 0
var _met := false

@onready var content: SubViewport = $Content
@onready var plate: MeshInstance3D = $Plate
@onready var spill: OmniLight3D = $Spill
@onready var _readout: ElevatorScreenReadout = $Content/Readout


func _ready() -> void:
	_readout.fit_to(content.size)
	_material = plate.material_override as ShaderMaterial
	if _material == null:
		push_warning("ElevatorScreen has no ShaderMaterial on Plate; the tube will not light.")
		return
	# Pushed, never authored. A ViewportTexture written into the .tscn resolves its
	# viewport_path against the scene it was saved in, so an instance either goes
	# black or borrows the first instance's readout. get_texture() cannot do either.
	_material.set_shader_parameter(CONTENT_PARAM, content.get_texture())
	if not Engine.is_editor_hint():
		add_to_group(GROUP)
	_apply_copy()
	set_power_on(power_on)
	show_collected(_collected)
	# A frame late as well, because theme overrides and font metrics are not settled
	# during _ready and the first render would bake the wrong glyph widths.
	await get_tree().process_frame
	_redraw()


func _notification(what: int) -> void:
	# A viewport parked on UPDATE_DISABLED can come back cleared after a context loss.
	# A web tab restored from the background is the one that actually bites.
	if what == NOTIFICATION_APPLICATION_RESUMED:
		_redraw()


## Credits still owed, floored at zero.
static func credits_outstanding(target: int, collected: int, per_point: float) -> int:
	return maxi(target - int(round(float(collected) * per_point)), 0)


static func is_met(target: int, collected: int, per_point: float) -> bool:
	return credits_outstanding(target, collected, per_point) <= 0


func get_readout() -> ElevatorScreenReadout:
	return _readout


## The picture the plate composites. The one seam anything outside this prefab
## should photograph, so nothing else has to know there is a SubViewport.
func get_content_texture() -> ViewportTexture:
	return content.get_texture()


## Mirrors the HUD widget convention, so whatever owns a HudState feeds this the same
## way it feeds HudMineralScore. HudState.announce_all() then pushes the opening
## value without a second call.
func bind(state: HudState) -> void:
	state.mineral_score_changed.connect(show_collected)


func show_collected(score: int) -> void:
	_collected = score
	var owed := credits_outstanding(quota_target, _collected, credits_per_point)
	var met := owed <= 0
	_readout.set_quota_value(value_format % -owed)
	_readout.set_auth_value(
		approved_text if met else denied_text, approved_color if met else denied_color
	)
	_readout.set_alarming(not met)
	# The words are written above the guard, not below it: a screen with no
	# material is a screen with no tube, not a screen with stale copy.
	if _material != null:
		_material.set_shader_parameter("alarm", 0.0 if met else 1.0)
	_redraw()
	if met == _met:
		return
	# The transition, not a latch: a ledger that can lose minerals must be able to
	# take the screen back off APPROVED.
	_met = met
	if met:
		quota_met.emit()


func set_power_on(value: float) -> void:
	power_on = clampf(value, 0.0, 1.0)
	if _material != null:
		_material.set_shader_parameter("power_on", power_on)
	if spill != null:
		spill.light_energy = spill_energy * power_on
	_redraw()


func set_crew_id(value: String) -> void:
	crew_id = value
	if _readout != null:
		_readout.set_crew_text(crew_id)
		_redraw()


func _apply_copy() -> void:
	_readout.set_crew_text(crew_id)
	_readout.set_quota_caption(quota_caption)
	_readout.set_auth_caption(auth_caption)
	_readout.apply_palette(label_color, value_color, denied_color)


## One frame of SubViewport render, and only when the words changed. Every moving
## part of the tube is TIME in the shader, so the viewport is idle the rest of the
## run.
##
## The property goes on reading UPDATE_ONCE afterwards - Godot 4.7 bookkeeps the
## once-then-stop inside the RenderingServer and never writes it back here - so do
## not read it back as "is a render pending". verify_elevator_screen.tscn proves
## the idling by pixels instead.
func _redraw() -> void:
	if content == null:
		return
	content.render_target_update_mode = SubViewport.UPDATE_ONCE
