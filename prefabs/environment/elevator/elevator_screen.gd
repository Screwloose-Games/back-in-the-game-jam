@tool
class_name ElevatorScreen
extends Node3D

## The elevator car's quota terminal: one quad for the whole plate, a SubViewport of
## real Controls for the readout, and elevator_screen.gdshader to erase the plate's
## baked text and composite the live one into the hole.
##
## Quota state is owned by the global Score object. This screen only presents it.

signal quota_met

const CONTENT_PARAM := "content_tex"

@export_group("Copy")
@export var crew_id := "EXTRACTION CREW 067":
	set = set_crew_id
@export var quota_caption := "OUTSTANDING QUOTA:"
@export var auth_caption := "DEPARTURE AUTHORIZATION:"
@export var denied_text := "DENIED"
@export var approved_text := "APPROVED"
@export var value_format := "%d CR"

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
	else:
		# Pushed, never authored. A ViewportTexture written into the .tscn resolves its
		# viewport_path against the scene it was saved in, so an instance either goes
		# black or borrows the first instance's readout. get_texture() cannot do either.
		_material.set_shader_parameter(CONTENT_PARAM, content.get_texture())

	_apply_copy()
	set_power_on(power_on)

	if not Engine.is_editor_hint():
		Score.ledger_changed.connect(refresh)
		refresh()

	# A frame late as well, because theme overrides and font metrics are not settled
	# during _ready and the first render would bake the wrong glyph widths.
	await get_tree().process_frame
	_redraw()


func _notification(what: int) -> void:
	# A viewport parked on UPDATE_DISABLED can come back cleared after a context loss.
	# A web tab restored from the background is the one that actually bites.
	if what == NOTIFICATION_APPLICATION_RESUMED:
		_redraw()


func get_readout() -> ElevatorScreenReadout:
	return _readout


## The picture the plate composites. The one seam anything outside this prefab
## should photograph, so nothing else has to know there is a SubViewport.
func get_content_texture() -> ViewportTexture:
	return content.get_texture()


## Whether the global quota is currently met.
##
## quota_met fires on the crossing rather than latching, so anything asking after the
## fact -- a door being pressed -- should query the authoritative Score state.
func is_quota_met() -> bool:
	return Score.is_quota_met()


## How many credits are still owed, which is the number on the glass.
func credits_short() -> int:
	return Score.credits_outstanding()


## Re-reads the ledger and repaints. Public so a tool or a scene that changed Score
## while this screen was not listening can bring the glass back in step.
func refresh() -> void:
	var owed := credits_short()
	var met := Score.is_quota_met()

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

	# The transition, not a latch: if the global ledger can lose score, the screen
	# must be able to return from APPROVED to DENIED.
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
## not read it back as "is a render pending".
func _redraw() -> void:
	if content == null:
		return

	content.render_target_update_mode = SubViewport.UPDATE_ONCE
