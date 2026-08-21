@tool
class_name ElevatorScreenReadout
extends Control

## The quota terminal's picture, as Controls: the rails furniture plus five lines
## of copy, laid out against DESIGN and scaled to whatever is rendering it.
##
## Knows nothing about SubViewports, shaders or 3D. Nothing here arms a redraw -
## whoever owns the viewport decides when a frame is worth spending, which is what
## keeps verify_elevator_screen.gd's [idle] check honest.

## The size everything below is laid out against. fit_to() scales to the target.
const DESIGN := Vector2(512.0, 320.0)

## The tightest box the authored copy occupies, in DESIGN units. Read by the
## cutscene's [framing] check, which has to know what a crop may not eat.
const CONTENT_BOUNDS := Rect2(0.0, 20.0, 512.0, 272.0)

@onready var _rails: ElevatorScreenRails = $Rails
@onready var _crew: Label = $CrewLine
@onready var _quota_caption: Label = $QuotaLabel
@onready var _quota_value: Label = $QuotaValue
@onready var _auth_caption: Label = $AuthLabel
@onready var _auth_value: Label = $AuthValue


func fit_to(pixels: Vector2i) -> void:
	scale = Vector2(pixels) / DESIGN


func set_crew_text(value: String) -> void:
	_crew.text = value


func set_quota_caption(value: String) -> void:
	_quota_caption.text = value


func set_auth_caption(value: String) -> void:
	_auth_caption.text = value


func set_quota_value(value: String) -> void:
	_quota_value.text = value


func set_auth_value(value: String, color: Color) -> void:
	_auth_value.text = value
	_auth_value.add_theme_color_override("font_color", color)


func apply_palette(label: Color, value: Color, warn: Color) -> void:
	_crew.add_theme_color_override("font_color", label)
	_quota_caption.add_theme_color_override("font_color", label)
	_quota_value.add_theme_color_override("font_color", value)
	_auth_caption.add_theme_color_override("font_color", label)
	_rails.rail_color = Color(label, 0.85)
	_rails.warn_color = warn


func set_alarming(on: bool) -> void:
	_rails.set_alarming(on)
