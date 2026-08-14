class_name HudPreview
extends Node

## The A/B harness: all four HUDs, one at a time, over a backdrop you can brighten.
##
## The comparison this is built to settle is legibility, not prettiness, which is why
## the backdrop cycles rather than sitting on one dark grey. HUD 01's terminal chrome
## and HUD 02-04's lit green behave very differently over a bright cavern wall, and
## that difference does not show up in the Figma file - every mockup there is
## composited over the same screenshot.
##
## Controls: 1-4 pick a variant, B cycles the backdrop, A hands the meters back to
## the demo driver after you have moved a slider, H hides this panel.

## HUDInterface_01 is not here: the designer renamed it "Don't Use - Test Variant" in
## Figma, so it was dropped rather than kept as a fourth thing to compare.
const VARIANT_SCENES := [
	preload("res://prefabs/ui/hud/prefab_hud_02.tscn"),
	preload("res://prefabs/ui/hud/prefab_hud_03.tscn"),
	preload("res://prefabs/ui/hud/prefab_hud_04.tscn"),
]

## Dark, mid and bright. The middle one is roughly the value of the lit rock in the
## mockups' backdrop; the bright one is the worst case a helmet lamp can produce.
const BACKDROPS: PackedColorArray = [
	Color(0.05, 0.06, 0.07),
	Color(0.33, 0.36, 0.30),
	Color(0.78, 0.80, 0.76),
]

const SLIDER_WIDTH := 180.0

var _variant_index := -1
var _backdrop_index := 0
var _hud: HudVariant
var _state: HudState
var _driver: HudDemoDriver
var _sliders := {}

@onready var _backdrop: ColorRect = $Backdrop
@onready var _slot: Node = $Slot
## Pinned to the middle of the right edge in the scene, that being the one region no
## variant puts anything in: HUD 02's face and HUD 04's radar take the top right,
## HUD 03's face the bottom right, and HUD 01's radar the bottom left.
@onready var _panel: PanelContainer = $Controls/Panel
@onready var _rows: VBoxContainer = $Controls/Panel/Margin/Rows
@onready var _title: Label = $Controls/Panel/Margin/Rows/Title


func _ready() -> void:
	_state = HudState.new()
	_state.name = "HudState"
	add_child(_state)

	_driver = HudDemoDriver.new()
	_driver.name = "HudDemoDriver"
	add_child(_driver)
	_driver.bind(_state)

	_build_controls()
	_apply_backdrop()
	show_variant(0)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_2, KEY_3, KEY_4:
			# Keyed by the variant's Figma number rather than by list position, so
			# [3] is always HUDInterface_03 however many variants survive.
			show_variant(key.keycode - KEY_2)
		KEY_B:
			_backdrop_index = (_backdrop_index + 1) % BACKDROPS.size()
			_apply_backdrop()
		KEY_A:
			_driver.enabled = true
			_title.text = _title_text()
		KEY_H:
			# For screenshots, and for judging a variant with nothing else on screen.
			_panel.visible = not _panel.visible


## Swaps the live HUD. The old one is freed rather than hidden, so nothing that
## survives the swap can be mistaken for something the new variant drew.
func show_variant(index: int) -> void:
	var wanted := clampi(index, 0, VARIANT_SCENES.size() - 1)
	if wanted == _variant_index:
		return
	_variant_index = wanted
	if _hud != null:
		_hud.queue_free()
	_hud = VARIANT_SCENES[_variant_index].instantiate()
	_slot.add_child(_hud)
	_hud.bind(_state)
	_title.text = _title_text()


func _title_text() -> String:
	var mode := "auto" if _driver.enabled else "manual"
	return (
		"HUD 0%d  [2-4] variant [B] backdrop [A] auto [H] hide  (%s)" % [_variant_index + 2, mode]
	)


func _apply_backdrop() -> void:
	_backdrop.color = BACKDROPS[_backdrop_index]


func _build_controls() -> void:
	_add_slider("power", "power", 1.0)
	_add_slider("oxygen", "oxygen", 1.0)
	_add_slider("tether", "tether m", 33.0, 0.0, 60.0, 1.0)
	_add_slider("contacts", "contacts", 5.0, 0.0, 8.0, 1.0)


func _add_slider(
	key: String,
	label: String,
	value: float,
	low: float = 0.0,
	high: float = 1.0,
	step: float = 0.01
) -> void:
	var row := HBoxContainer.new()
	var caption := Label.new()
	caption.text = label
	caption.custom_minimum_size.x = 74.0
	row.add_child(caption)

	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.value = value
	slider.custom_minimum_size.x = SLIDER_WIDTH
	# A focused HSlider eats ui_left/ui_right, and a focused anything eats ui_accept.
	# Same rule prototypes/AGENTS.md sets for the tuning panel, and the same reason.
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(_on_SliderChanged.bind(key))
	row.add_child(slider)

	_rows.add_child(row)
	_sliders[key] = slider


## Any slider movement takes the meters off the demo driver, because otherwise the
## driver overwrites the value on the very next frame and the slider looks broken.
func _on_SliderChanged(value: float, key: String) -> void:
	_driver.enabled = false
	match key:
		"power":
			_state.power = value
		"oxygen":
			_state.oxygen = value
		"tether":
			_state.tether_attached = value > 0.0
			_state.tether_metres = value
		"contacts":
			_state.contacts = _ring_of_contacts(int(value))
	_state.status = HudState.status_for(minf(_state.power, _state.oxygen))
	_title.text = _title_text()


func _ring_of_contacts(count: int) -> PackedVector2Array:
	var contacts := PackedVector2Array()
	for i in count:
		var angle := TAU * float(i) / float(maxi(count, 1))
		contacts.append(Vector2(cos(angle), sin(angle)) * (0.3 + 0.12 * float(i % 3)))
	return contacts
