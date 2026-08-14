class_name HudPreview
extends Node

const VARIANT_SCENES := [
	preload("res://prefabs/ui/hud/prefab_hud_02.tscn"),
	preload("res://prefabs/ui/hud/prefab_hud_03.tscn"),
	preload("res://prefabs/ui/hud/prefab_hud_04.tscn"),
]

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
	_add_slider("contact_range", "contact m", 12.0, 0.0, 40.0, 1.0)
	_add_slider("contact_height", "contact up", 0.0, -40.0, 40.0, 1.0)


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
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(_on_SliderChanged.bind(key))
	row.add_child(slider)

	_rows.add_child(row)
	_sliders[key] = slider


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
		"contact_range", "contact_height":
			_state.contacts = _placed_contact()
	_state.status = HudState.status_for(minf(_state.power, _state.oxygen))
	_title.text = _title_text()


func _placed_contact() -> PackedVector3Array:
	var reach: float = _sliders["contact_range"].value
	var height: float = _sliders["contact_height"].value
	return PackedVector3Array([Vector3(0.0, height, -reach)])
