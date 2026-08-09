class_name MineralDiscoveryPrototype
extends Node3D

## Root of the mineral discovery prototype - the playable testbed for issue #40.
##
##   godot --path <root> res://prototypes/mineral_discovery/mineral_discovery_prototype.tscn
##
## Name the scene. The project's main scene is the main menu, so anything that
## does not name a scene boots that instead.
##
## It borrows the suit, the tether and the power/lamp stack from the other
## prototypes and adds three things of its own: two shared, live-tunable materials
## (the ore and the rock, for Q1), a handcrafted cave of deposits laid out on a
## visibility x reachability grid (Q2/Q3), and a hold-to-mine interaction with
## proximity markers (Q4). The pressure is the tether: you start moored to a buoy
## that charges the suit, and reaching a far deposit means unclipping and
## watching the battery - and the lamp - fall.
##
## This node is the single owner of the live setters. _apply_settings pushes the
## panel's values onto the two shared materials and never writes back.

const SUIT_SCENE := preload("res://prototypes/power_and_lighting/imported/carrier_suit.tscn")

## Left mouse holds to mine. Registered on the running InputMap only; nothing is
## written back to project.godot, and no existing action uses the button.
const MINE_ACTION := "mine_extract"

## The suit's own tether toggle, which the start-of-run auto-moor drives once.
const TETHER_ACTION := "toggle_tether"

## Pushes the suit's _physics_process after this node's, so the synthesised
## tether press is visible to the suit on the same frame. Same reason the power
## prototype does it for its grab press.
const SUIT_PHYSICS_PRIORITY := 1

## How many physics frames the auto-moor keeps pulsing toggle_tether before it
## gives up. At spawn the suit sits still aimed at the buoy, so a clip lands in
## the first frame or two; the cap only stops it pulsing forever if the player
## swims off before it takes.
const AUTO_MOOR_FRAME_LIMIT := 20

@export var settings: MineralSettings

var _suit: CarrierSuit
var _buoy: RigidBody3D
var _suit_store: PowerStore
var _buoy_store: PowerStore
var _suit_lamp: LampPowerResponse
var _power: PowerSystem
var _deposit_material: StandardMaterial3D
var _env_material: StandardMaterial3D
var _targeted_deposit: DepositNode
var _mining_target: DepositNode
var _extract_progress := 0.0
var _collected_count := 0
var _collected_value := 0
var _auto_moor_done := false
var _auto_moor_frames := 0

@onready var _cave: MineralCave = $Cave
@onready var _hud: MineralHud = $Hud
@onready var _tuning_panel: PrototypeTuningPanel = $Hud/Tuning


func _ready() -> void:
	if settings == null:
		settings = MineralSettings.new()
		push_warning("No mineral_settings.tres wired; running on mineral_knobs.gd defaults.")
	_build_materials()
	_cave.build(_env_material, _deposit_material)
	_buoy = _cave.get_buoy()
	_spawn_suit()
	_build_power()
	_register_input()
	settings.changed.connect(_apply_settings)
	_apply_settings()
	_hud.bind(self)
	_tuning_panel.bind(settings)


func _physics_process(delta: float) -> void:
	_run_auto_moor()
	_update_mining(delta)


## Tab respawns the suit (the suit handles that in its own _input); re-arm the
## auto-moor and top the batteries back up so a reset returns the whole
## experiment to its starting state, not just the pose.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("reset_player"):
		_auto_moor_done = false
		_auto_moor_frames = 0
		_suit_store.set_fraction(PowerKnobs.SUIT_START_FRACTION)
		_buoy_store.set_fraction(1.0)


# --- Getters the HUD reads -------------------------------------------------


func get_suit() -> CarrierSuit:
	return _suit


func get_head_camera() -> Camera3D:
	return _suit.get_node("HeadCamera") as Camera3D


func get_suit_power_fraction() -> float:
	return _suit_store.get_fraction()


func is_moored() -> bool:
	return _suit != null and _suit.get_tethered_object() == _buoy


func get_deposits() -> Array[DepositNode]:
	return _cave.get_deposits()


func get_buoy_position() -> Vector3:
	return _buoy.global_position


func get_targeted_deposit() -> DepositNode:
	return _targeted_deposit


func get_extract_fraction() -> float:
	if _extract_progress <= 0.0:
		return 0.0
	return clampf(_extract_progress / maxf(settings.extract_time, 0.0001), 0.0, 1.0)


func get_collected_count() -> int:
	return _collected_count


func get_collected_value() -> int:
	return _collected_value


func get_settings() -> MineralSettings:
	return settings


# --- Setup -----------------------------------------------------------------


## The two shared materials. Every deposit uses the first and every cave surface
## the second, so one slider retunes all of them at once - the mechanism Q1 is
## tested through.
func _build_materials() -> void:
	_deposit_material = StandardMaterial3D.new()
	_env_material = StandardMaterial3D.new()


func _spawn_suit() -> void:
	_suit = SUIT_SCENE.instantiate() as CarrierSuit
	_suit.name = "CarrierSuit"
	# Positioned before add_child: the suit captures its respawn pose in its own
	# _ready, which runs during add_child.
	_suit.position = MineralKnobs.SUIT_SPAWN
	_suit.process_physics_priority = SUIT_PHYSICS_PRIORITY
	add_child(_suit)


## Hangs a battery on the suit and a big one in the buoy, wires the helmet lamp
## to the suit battery, and lets the tether carry charge from the buoy - so
## mooring tops you up and unclipping starves you. Mirrors the power prototype's
## assembly.
func _build_power() -> void:
	_suit_store = _make_store(
		_suit,
		"SuitPower",
		PowerKnobs.SUIT_CAPACITY,
		PowerKnobs.SUIT_START_FRACTION,
		PowerKnobs.SUIT_DRAIN_PER_SECOND
	)
	_buoy_store = _make_store(_buoy, "BuoyPower", PowerKnobs.CUBE_CAPACITY, 1.0, 0.0)

	_suit_lamp = _build_suit_lamp_response()

	var lamp := _helmet_lamp()
	lamp.shadow_normal_bias = PowerKnobs.SHADOW_NORMAL_BIAS
	lamp.shadow_reverse_cull_face = PowerKnobs.SHADOW_REVERSE_CULL

	_power = PowerSystem.new()
	_power.name = "PowerSystem"
	add_child(_power)
	_power.bind(_suit, _buoy, _suit_store, _buoy_store)


func _make_store(
	owner_node: Node,
	store_name: String,
	capacity: float,
	start_fraction: float,
	drain_per_second: float
) -> PowerStore:
	var store := PowerStore.new()
	store.name = store_name
	owner_node.add_child(store)
	store.configure(capacity, start_fraction, drain_per_second)
	return store


func _build_suit_lamp_response() -> LampPowerResponse:
	var response := LampPowerResponse.new()
	response.name = "SuitLampResponse"
	response.base_energy = PowerKnobs.HELMET_LAMP_ENERGY
	response.base_range = PowerKnobs.HELMET_LAMP_RANGE
	response.min_range_fraction = PowerKnobs.SUIT_LAMP_MIN_RANGE_FRACTION
	response.dim_curve = LampPowerResponse.build_curve(PowerKnobs.SUIT_DIM_POINTS, 1.0)
	response.flicker_curve = LampPowerResponse.build_curve(
		PowerKnobs.SUIT_FLICKER_POINTS, PowerKnobs.FLICKER_RATE_MAX
	)
	response.responds_to_charge = MineralKnobs.LAMP_RESPONDS_TO_POWER
	add_child(response)
	response.bind(_helmet_lamp(), _suit_store)

	response.set_color(PowerKnobs.HELMET_LAMP_COLOR)
	response.set_shadows(PowerKnobs.HELMET_LAMP_SHADOWS)
	response.set_distance_falloff(PowerKnobs.HELMET_LAMP_ATTENUATION)
	response.set_cone(PowerKnobs.HELMET_LAMP_ANGLE)
	response.set_edge_falloff(PowerKnobs.HELMET_LAMP_ANGLE_ATTENUATION)
	return response


func _register_input() -> void:
	if InputMap.has_action(MINE_ACTION):
		return
	InputMap.add_action(MINE_ACTION)
	var button := InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event(MINE_ACTION, button)


# --- Live tuning -----------------------------------------------------------


## Pushes the panel's values onto the two shared materials. Colour is authored in
## HSV so lightness stays its own slider; emission colour tracks the albedo so a
## glowing deposit reads as the same material lit from within, not a second hue.
## Never writes back to settings - that would re-enter changed.
func _apply_settings() -> void:
	_paint_material(
		_deposit_material,
		Color.from_hsv(
			settings.deposit_hue, settings.deposit_saturation, settings.deposit_lightness
		),
		settings.deposit_emission_energy,
		settings.deposit_roughness,
		settings.deposit_specular
	)
	_paint_material(
		_env_material,
		Color.from_hsv(settings.env_hue, settings.env_saturation, settings.env_lightness),
		0.0,
		settings.env_roughness,
		settings.env_specular
	)


func _paint_material(
	material: StandardMaterial3D,
	albedo: Color,
	emission_energy: float,
	roughness: float,
	specular: float
) -> void:
	material.albedo_color = albedo
	material.roughness = roughness
	material.metallic_specular = specular
	material.emission_enabled = emission_energy > 0.0
	material.emission = albedo
	material.emission_energy_multiplier = emission_energy


# --- Per-frame -------------------------------------------------------------


## Clips the tether to the buoy at the start of the run. Pulses toggle_tether -
## press one frame, release the next - until the suit is moored, then stops. The
## suit reads the press as just-pressed the same frame because it runs after this
## node (SUIT_PHYSICS_PRIORITY). Pulsing rather than a single press means a frame
## where the aim ray has not settled on the buoy yet just retries instead of
## silently failing, and stopping the instant is_moored() turns true keeps it a
## single clip, never a clip-then-unclip.
func _run_auto_moor() -> void:
	if _auto_moor_done:
		return
	if is_moored() or _auto_moor_frames >= AUTO_MOOR_FRAME_LIMIT:
		Input.action_release(TETHER_ACTION)
		_auto_moor_done = true
		return
	_auto_moor_frames += 1
	if _auto_moor_frames % 2 == 1:
		Input.action_press(TETHER_ACTION)
	else:
		Input.action_release(TETHER_ACTION)


func _update_mining(delta: float) -> void:
	_targeted_deposit = _raycast_deposit()
	if _targeted_deposit != _mining_target:
		_mining_target = _targeted_deposit
		_extract_progress = 0.0

	if _targeted_deposit == null or not Input.is_action_pressed(MINE_ACTION):
		_extract_progress = 0.0
		return

	_extract_progress += delta
	if _extract_progress >= settings.extract_time:
		_collect(_targeted_deposit)
		_extract_progress = 0.0
		_mining_target = null


## The deposit under the crosshair within extract range, or null. A separate ray
## from the suit's grab ray: it is masked to the mineral layer, so it sees ore
## and nothing else, and the grab ray sees carryables and never ore.
func _raycast_deposit() -> DepositNode:
	var camera := get_head_camera()
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * settings.extract_range
	var query := PhysicsRayQueryParameters3D.create(from, to, MineralKnobs.MINERAL_LAYER_BIT)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var deposit := (hit["collider"] as Node).get_parent() as DepositNode
	if deposit == null or deposit.is_mined():
		return null
	return deposit


func _collect(deposit: DepositNode) -> void:
	deposit.deplete()
	_collected_count += 1
	_collected_value += deposit.get_value()


func _helmet_lamp() -> SpotLight3D:
	return _suit.get_node("HeadCamera/HelmetLamp") as SpotLight3D
