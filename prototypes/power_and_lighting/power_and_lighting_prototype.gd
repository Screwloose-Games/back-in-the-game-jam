class_name PowerAndLightingPrototype
extends Node3D

## Root of the power and lighting prototype.
##
## Assembles the borrowed halves - the chamber, the cube, the suit - hangs a
## battery off the suit and another inside the cube, and puts every optical value
## in power_knobs.gd onto the scene, so the .tscn never holds a second copy of a
## number that could drift.
##
##   godot --path <root> res://prototypes/power_and_lighting/power_and_lighting_prototype.tscn
##
## Name the scene. The project's main scene is the main menu, so anything that
## does not name a scene boots that instead.
##
## This is also the single owner of every live setter the tuning panel calls.
## They are here rather than on the things they touch because most of them have
## an invariant to keep that no one node can see - the view distance moves three
## properties on two different nodes, and the lamp response owns a base energy
## the light itself is overwritten from every frame.
##
## What any of those setters is allowed to reach, and which of them the panel
## still offers, is decided by the switches in PowerKnobs' What is switched on
## region. The wiring below is always assembled and always runs; the switches
## decide what it does.

const SUIT_SCENE := preload("res://prototypes/power_and_lighting/imported/carrier_suit.tscn")

## F does both jobs: tap it to take hold of the cube or let go of it, hold it to
## crank. The whole gesture is owned here, on one action, and the suit's own
## `grab` is driven from it.
const GRIP_OR_CRANK_ACTION := "grip_or_crank"
const GRIP_OR_CRANK_KEY := KEY_F

## The suit's grab action, which this scene takes over. See _register_input.
const GRAB_ACTION := "grab"

## Number keys 1 and 2, one per lamp mode in enum order. Registered on the running
## InputMap like GRIP_OR_CRANK_ACTION is, and nothing is written back to
## project.godot - see _register_input.
const LAMP_MODE_ACTION_PREFIX := "lamp_mode_"
const LAMP_MODE_KEYS := [KEY_1, KEY_2]

## Pushes the suit's _physics_process after this node's.
##
## LOAD-BEARING, not tidiness. The gesture synthesises a `grab` press inline, and
## Input.is_action_just_pressed is only true for whoever asks during the same
## tick it was set - so a suit that polled first would miss every tap and the
## cube would simply never be picked up. Tree order alone would give the right
## answer today, since the suit is a child added from here, but it is not stated
## anywhere that it must stay one, and the failure is silent.
const SUIT_PHYSICS_PRIORITY := 1

var _suit: CarrierSuit
var _cube: RigidBody3D
var _suit_store: PowerStore
var _cube_store: PowerStore
var _suit_lamp: LampPowerResponse
var _cube_lamp: LampPowerResponse
var _power: PowerSystem
var _cube_gauge: CubePowerGauge

## How long F has been down, and whether it has been down long enough to have
## become a crank rather than a grab.
var _grip_or_crank_held := 0.0
var _crank_engaged := false

## Where the fog is asked to start, before it is held below where it ends. Kept
## because the view distance can be dragged under it, and a clamped value that
## was not remembered would never come back when the room is opened up again.
var _fog_begin := PowerKnobs.FOG_DEPTH_BEGIN

## The cube's emission, which two sliders share: its colour is the lamp's colour
## and its strength is its own. Kept here because either can move without the
## other and the material needs both.
var _cube_light_color := PowerKnobs.CUBE_LIGHT_COLOR
var _cube_glow := PowerKnobs.CUBE_GLOW

## Charge fraction across, fraction of _cube_glow up. The cube's third response
## curve, alongside the two its lamp already has, and it lives here rather than on
## LampPowerResponse because what it drives is the cube's MATERIAL - and the
## colour of that material is already this node's, tied to the lamp's colour by
## set_cube_light_color. Splitting the emission between two owners is how the hue
## and the energy end up disagreeing about which frame they are in.
##
## A Curve for the same reason the lamps' are: the panel edits this resource in
## place while the game runs and it is sampled every frame, so a drag needs
## nothing pushed anywhere to take effect.
var _cube_glow_curve: Curve

## Which of PowerKnobs.LampMode's two settings the helmet lamp is in.
var _lamp_mode: int = PowerKnobs.LAMP_START_MODE

## What the helmet lamp and the suit battery do with the lamp ON.
##
## Held rather than read back off the light, because THREE different setters feed
## these - the beam section's brightness slider, the view distance, and the power
## section's drain - and switching the lamp back on has to restore the latest value
## of each rather than whatever it happened to be when it went out. Without them,
## turning the lamp off and on would quietly restore a brightness that was dragged
## away twenty seconds earlier.
var _suit_lamp_energy_base := PowerKnobs.HELMET_LAMP_ENERGY
var _suit_lamp_throw_base := PowerKnobs.HELMET_LAMP_RANGE
var _suit_drain_base := PowerKnobs.SUIT_DRAIN_PER_SECOND

## True for the one physics tick after a tap has synthesised a `grab` press,
## which is when it has to be released again. See _fire_grab.
var _synthetic_grab_pending := false

@onready var _chamber: TestChamberGenerator = $Chamber
@onready var _world_environment: WorldEnvironment = $WorldEnvironment
@onready var _hud: PowerHud = $Hud


func _ready() -> void:
	_register_input()
	# The chamber built the cube in its own _ready, which has already run - a
	# child's _ready runs before its parent's.
	_cube = _chamber.get_carry_object()
	if _cube == null:
		push_error("chamber produced no cube; there is nothing to power")
		return
	_spawn_suit()
	_build_power()
	# After both lamps exist, and from here rather than from either of the two
	# functions above. These answer the renderer rather than any one light, so
	# letting the suit and the cube each apply their own half is how they end up
	# holding different values and the fix gets judged on one wall at a time.
	set_shadow_artefact_knobs(PowerKnobs.SHADOW_NORMAL_BIAS, PowerKnobs.SHADOW_REVERSE_CULL)
	_apply_environment()
	_hud.bind(self, _suit, _power, _suit_store, _cube_store)
	_report()


## The cube's glow is recomputed from its battery every frame, for the reason
## LampPowerResponse gives for doing the same to the lamps: this node is the
## single owner of the cube's emission, and an owner that wrote only when the
## charge moved would leave a glow slider's value standing untouched until it
## next did.
func _process(_delta: float) -> void:
	if _cube != null:
		_apply_cube_emission()


func _physics_process(delta: float) -> void:
	if _power == null or not PowerKnobs.POWER_ENABLED:
		return
	if _synthetic_grab_pending:
		Input.action_release(GRAB_ACTION)
		_synthetic_grab_pending = false
	_update_grip_or_crank(delta)


## Tab resets the whole experiment, not just the suit. The suit handles its own
## respawn in its own _input and does not mark the event handled, so this runs
## alongside it rather than instead of it.
func _input(event: InputEvent) -> void:
	_handle_lamp_mode_input(event)
	if event.is_action_pressed("reset_player"):
		_chamber.reset_carry_object()
		# Left full with power switched off. _build_power put both stores at 1.0
		# and took the drain off them, and putting them back to their starting
		# fractions here would half-empty batteries that are supposed to be
		# bottomless.
		if PowerKnobs.POWER_ENABLED:
			set_store_fractions(PowerKnobs.SUIT_START_FRACTION, PowerKnobs.CUBE_START_FRACTION)


## Sets how far you can see, in metres, and moves everything that governs it.
##
## ONE NUMBER, THREE PROPERTIES. Moving the fog alone changes nothing you can
## perceive - past the lamp's throw the room is lit by ambient alone and reads as
## black however clear the air is - and a clip plane inside the fog pops geometry
## out before the fog has hidden it.
##
## The throw goes onto the lamp RESPONSE, not onto the light. The response
## rewrites spot_range every frame from its own base, so a value written straight
## to the light would survive exactly one frame.
func set_view_distance(metres: float) -> void:
	var distance := clampf(metres, PowerKnobs.VIEW_DISTANCE_MIN, PowerKnobs.VIEW_DISTANCE_MAX)
	_world_environment.environment.fog_depth_end = distance
	_apply_fog_begin()
	# The throw goes into the mode's base rather than onto the lamp, because the
	# mode multiplies it - see _apply_lamp_mode, which is the only thing that
	# writes base_range.
	_suit_lamp_throw_base = distance + PowerKnobs.VIEW_LAMP_MARGIN
	if _suit_lamp == null:
		return
	_apply_lamp_mode()
	_head_camera().far = distance + PowerKnobs.VIEW_CLIP_MARGIN


## Puts the helmet lamp into one of PowerKnobs.LampMode's settings.
func set_lamp_mode(mode: int) -> void:
	if mode < 0 or mode >= PowerKnobs.LAMP_MODE_NAMES.size():
		return
	_lamp_mode = mode
	_apply_lamp_mode()


## What the lamp is currently set to, for the HUD to say out loud.
func get_lamp_mode_name() -> String:
	return PowerKnobs.LAMP_MODE_NAMES[_lamp_mode]


## What the helmet lamp is worth at full charge, before its battery gets a say.
## Goes into the lamp's base for the reason set_view_distance's throw does.
func set_suit_lamp_energy(energy: float) -> void:
	_suit_lamp_energy_base = energy
	_apply_lamp_mode()


## The two controls that answer the renderer's shadow striping: how far a lookup
## is pushed along the surface normal before it is tested, in shadow-map texels,
## and whether back faces rather than front faces go into the shadow map.
##
## BOTH KNOBS ON BOTH LAMPS, in one call. Neither says anything about a
## particular light - what they answer is the same artefact on every surface in
## the room - so letting the lamps hold different values would mean judging a fix
## on one wall while an untreated lamp goes on striping the wall beside it.
func set_shadow_artefact_knobs(normal_bias: float, reverse_cull: bool) -> void:
	for lamp: Light3D in [_helmet_lamp(), _cube_lamp_light()]:
		lamp.shadow_normal_bias = normal_bias
		lamp.shadow_reverse_cull_face = reverse_cull


## The light level everything away from the lamp falls to. Small numbers: this is
## the difference between rock you cannot see and rock that is not there.
func set_ambient_energy(energy: float) -> void:
	_world_environment.environment.ambient_light_energy = energy


## How thick the murk gets between where the fog begins and where it ends.
func set_fog_density(density: float) -> void:
	_world_environment.environment.fog_density = density


## Where the fog starts to close in. Held below the view distance - see
## _apply_fog_begin.
func set_fog_begin(metres: float) -> void:
	_fog_begin = metres
	_apply_fog_begin()


## The two lamp responses, so the panel can drive them.
##
## Nearly everything the panel does to a lamp goes through one of these rather
## than through a setter here: what a light looks like is the response's, because
## the response is already rewriting its brightness and its range every frame. See
## LampPowerResponse.set_color. What is left on this node is what no single lamp
## can see - the view distance, which moves three properties on two nodes; the
## shadow artefact knobs, which answer the renderer and go to both lamps; and the
## cube's colour, which is also the colour of the cube.
##
## The whole node rather than a getter per curve, and that is not laziness: the
## curve editors mutate those Curve resources in place and the response samples
## them every frame, so a pair of getters would hand out the same two references
## through a wider door.
func get_suit_lamp() -> LampPowerResponse:
	return _suit_lamp


func get_cube_lamp() -> LampPowerResponse:
	return _cube_lamp


## The cube's glow curve, live, for the panel's editor to mutate in place - the
## same arrangement the two lamp curves have, and handed over for the same reason:
## it is sampled every frame, so the editor and the sampler share one resource
## rather than keeping two copies of a shape in step.
func get_cube_glow_curve() -> Curve:
	return _cube_glow_curve


## The cube's lamp and the glow on the cube's own faces are ONE colour, and this
## is where that is kept true.
##
## It is the one piece of a lamp's look that is not the response's, because it is
## not only the lamp's: a cube glowing a different colour to the light coming off
## it stops reading as the source of that light and starts reading as a box
## someone else is lighting.
func set_cube_light_color(color: Color) -> void:
	_cube_light_color = color
	if _cube_lamp != null:
		_cube_lamp.set_color(color)
	_apply_cube_emission()


## How brightly the cube's own faces glow AT FULL CHARGE. Throws no light on
## anything - the lamp does that - it only keeps the cube from reading as a dark
## box sitting in the middle of a room it is supposed to be lighting.
##
## The top of the range the glow curve scales, so this is the value the cube shows
## at a full battery rather than the value it always shows. See _current_cube_glow.
func set_cube_glow(energy: float) -> void:
	_cube_glow = energy
	_apply_cube_emission()


func set_suit_capacity(capacity: float) -> void:
	_suit_store.set_capacity(capacity)


## The drain with the lamp ON. What the battery actually loses is this or nothing,
## so dragging this slider while the lamp is out moves the number that will apply
## when it comes back rather than the number on the battery now.
func set_suit_drain(per_second: float) -> void:
	_suit_drain_base = per_second
	_apply_lamp_mode()


func set_charge_rate(per_second: float) -> void:
	_power.charge_per_second = per_second


func set_cube_capacity(capacity: float) -> void:
	_cube_store.set_capacity(capacity)


func set_crank_rate(per_second: float) -> void:
	_power.crank_per_second = per_second


## Puts the batteries straight into a state worth looking at. A fraction below
## zero leaves that store alone, so a button can move one without disturbing the
## other.
func set_store_fractions(suit_fraction: float, cube_fraction: float) -> void:
	if suit_fraction >= 0.0:
		_suit_store.set_fraction(suit_fraction)
	if cube_fraction >= 0.0:
		_cube_store.set_fraction(cube_fraction)


## Takes F off the suit's `grab` and puts it on this scene's own action.
##
## THE SUIT'S grab IS LEFT WITH NO KEY ON IT, ON PURPOSE. `grab` fires on press,
## and a gesture that has to tell a tap from a hold cannot know which it is until
## the key comes back up - so if the hardware still reached `grab`, every attempt
## to crank would grab the cube on the way down. Unbinding it and driving it from
## here is what makes the delay possible without touching imported/carrier_suit.gd.
##
## Both changes are to the running process's InputMap only. Nothing is written
## back to project.godot, and every other prototype starts from a fresh copy of
## it, so `grab` is still F everywhere else.
##
## None of it happens with power switched off. The gesture exists to make room
## for cranking, cranking puts charge into a battery, and with no battery to fill
## the only thing the takeover would buy is a pickup that waits for the key to
## come back up. F is left as the suit's own grab.
func _register_input() -> void:
	# Before the power gate below, because the modes do not need batteries: with
	# power off they still change what the lamp looks like, and only the drain each
	# one implies goes quiet.
	_register_lamp_mode_actions()
	if not PowerKnobs.POWER_ENABLED:
		return
	InputMap.action_erase_events(GRAB_ACTION)

	if InputMap.has_action(GRIP_OR_CRANK_ACTION):
		return
	InputMap.add_action(GRIP_OR_CRANK_ACTION)
	var key := InputEventKey.new()
	# Physical, so the binding is the key in that position rather than the letter
	# printed on it, which is what every other action in this project uses.
	key.physical_keycode = GRIP_OR_CRANK_KEY
	InputMap.action_add_event(GRIP_OR_CRANK_ACTION, key)


## One action per lamp mode, on the number keys, added to the running InputMap.
##
## Physical keycodes like every other binding in this project, so it is the key in
## that position rather than the character printed on it - which matters more here
## than elsewhere, because the number row is exactly where keyboard layouts differ.
## Nothing is written back to project.godot and every other prototype starts from a
## fresh copy of it.
func _register_lamp_mode_actions() -> void:
	if not PowerKnobs.LAMP_MODES_ENABLED:
		return
	for mode: int in LAMP_MODE_KEYS.size():
		var action := _lamp_mode_action(mode)
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var key := InputEventKey.new()
		key.physical_keycode = LAMP_MODE_KEYS[mode]
		InputMap.action_add_event(action, key)


func _lamp_mode_action(mode: int) -> String:
	return LAMP_MODE_ACTION_PREFIX + PowerKnobs.LAMP_MODE_NAMES[mode]


func _handle_lamp_mode_input(event: InputEvent) -> void:
	if not PowerKnobs.LAMP_MODES_ENABLED:
		return
	for mode: int in LAMP_MODE_KEYS.size():
		if event.is_action_pressed(_lamp_mode_action(mode)):
			set_lamp_mode(mode)
			return


## Writes the lamp's setting onto the three things it governs: how bright the
## helmet lamp is at full charge, how far it throws there, and what the suit loses
## per second.
##
## THE SINGLE OWNER OF ALL THREE, which is why the setters above feed a base and
## call this rather than writing what they own directly. Two writers for
## base_energy is how switching the lamp back on silently restores a brightness
## that was dragged away, and nothing shows it until someone presses a key a minute
## later.
##
## It goes on running with LAMP_MODES_ENABLED off, because the lamp is then simply
## always ON and every value it writes is the one the knobs asked for - the same
## arrangement LampPowerResponse keeps with responds_to_charge off. A switch that
## changed WHO writes a value rather than what gets written is how the value
## survives exactly one frame.
##
## The lamp is HIDDEN when it is out rather than left emitting nothing, so that off
## is off: LampPowerResponse goes on writing light_energy every frame whatever the
## setting is, and a spot light costs a shadow map every frame whatever its energy
## is. The throw is left alone - nothing reads the range of a hidden light, and
## zeroing it would only cost the restore on the way back.
func _apply_lamp_mode() -> void:
	if _suit_lamp == null:
		return
	var lamp_on := not PowerKnobs.LAMP_MODES_ENABLED or _lamp_mode == PowerKnobs.LampMode.ON
	_suit_lamp.base_energy = _suit_lamp_energy_base if lamp_on else 0.0
	_suit_lamp.base_range = _suit_lamp_throw_base
	_helmet_lamp().visible = lamp_on
	if _suit_store != null:
		_suit_store.idle_drain_per_second = _suit_drain_base if lamp_on else 0.0


## Tap to grip, hold to crank.
##
## The hold only becomes a crank when there is something to crank - the cube
## under the crosshair or already in your hands. Held anywhere else the gesture
## stays a grip however long you lean on it, so pressing F at nothing and
## thinking better of it does not silently arm a different verb.
##
## A full cube still counts as something to crank. It is in reach, so a hold on
## it is unambiguously a crank that happens to achieve nothing - and the
## alternative, falling through to a grab, means holding F on a cube you meant to
## top up leaves you carrying it instead.
func _update_grip_or_crank(delta: float) -> void:
	if Input.is_action_just_pressed(GRIP_OR_CRANK_ACTION):
		_grip_or_crank_held = 0.0
		_crank_engaged = false

	if Input.is_action_pressed(GRIP_OR_CRANK_ACTION):
		_grip_or_crank_held += delta
		if _grip_or_crank_held >= PowerKnobs.CRANK_HOLD_TIME and _power.is_cube_in_reach():
			_crank_engaged = true

	if Input.is_action_just_released(GRIP_OR_CRANK_ACTION):
		if not _crank_engaged:
			_fire_grab()
		_grip_or_crank_held = 0.0
		_crank_engaged = false

	_power.set_crank_engaged(_crank_engaged)


## Presses the suit's `grab` for exactly one physics tick.
##
## Synthesised input rather than a call into the suit, because the only public
## way in is release_grip() - there is no public "take hold", and adding one
## would mean editing borrowed code. Going through the action means taking hold
## and letting go stay one code path, with one set of rules about range and about
## what is grabbable.
##
## Input.action_press sets the state inline, so the suit only sees it if the suit
## polls AFTER this node does - which is exactly what SUIT_PHYSICS_PRIORITY
## guarantees. Routing it through Input.parse_input_event instead would not need
## that guarantee, but the event is buffered and flushed between frames, and it
## measured five physics ticks of lag before the grab landed. Eighty milliseconds
## on top of a pickup that already waits for the key to come up is too much to
## pay for not having to think about ordering.
func _fire_grab() -> void:
	Input.action_press(GRAB_ACTION)
	_synthetic_grab_pending = true


## The suit is instantiated and POSITIONED BEFORE being added to the tree, not
## placed as a node in the .tscn.
##
## CarrierSuit captures its respawn pose in its own _ready, and a child's _ready
## runs before its parent's - so moving it from here afterwards would leave Tab
## teleporting the suit back to wherever the .tscn happened to put it. Setting the
## transform first means add_child triggers _ready on a suit already in the right
## place, and the spawn stays a single value in power_knobs.gd.
##
## Nothing about the helmet lamp is set here, though the suit scene belongs to the
## object carrying prototype and applied THAT prototype's knobs to it in its own
## _ready. _build_suit_lamp_response overwrites every one of them a moment later,
## which is the only place they should be written from.
func _spawn_suit() -> void:
	_suit = SUIT_SCENE.instantiate() as CarrierSuit
	_suit.name = "CarrierSuit"
	_suit.position = PowerKnobs.SUIT_SPAWN
	_suit.process_physics_priority = SUIT_PHYSICS_PRIORITY
	add_child(_suit)


## Hangs a battery off each body, wires the lamps to them, and puts the gauge on
## the cube.
##
## BOTH BATTERIES ARE BUILT EVEN WITH POWER SWITCHED OFF. They sit full and
## drainless instead, which costs two floats and means everything downstream goes
## on reading a store: the lamp response asks one for a fraction every frame, the
## HUD binds to one, and PowerSystem holds one at each end. A second code path for
## the case where the stores do not exist would be a lot of null-guarding for a
## state that is meant to be temporary.
func _build_power() -> void:
	var powered := PowerKnobs.POWER_ENABLED
	_suit_store = _make_store(
		_suit,
		"SuitPower",
		PowerKnobs.SUIT_CAPACITY,
		PowerKnobs.SUIT_START_FRACTION if powered else 1.0,
		PowerKnobs.SUIT_DRAIN_PER_SECOND if powered else 0.0
	)
	_cube_store = _make_store(
		_cube,
		"CubePower",
		PowerKnobs.CUBE_CAPACITY,
		PowerKnobs.CUBE_START_FRACTION if powered else 1.0,
		PowerKnobs.CUBE_IDLE_DRAIN_PER_SECOND if powered else 0.0
	)
	# The drain the modes take a share of, matching the store above - so a mode
	# cannot put a leak into a battery that is meant to be bottomless.
	_suit_drain_base = PowerKnobs.SUIT_DRAIN_PER_SECOND if powered else 0.0

	_suit_lamp = _build_suit_lamp_response()
	# After the response exists, which is what _apply_lamp_mode writes through.
	_apply_lamp_mode()
	# Before _apply_cube_optics, which is the first thing to ask what the glow
	# should currently be.
	_cube_glow_curve = LampPowerResponse.build_curve(PowerKnobs.CUBE_GLOW_POINTS, 1.0)
	_apply_cube_optics()
	if PowerKnobs.CUBE_LIGHT_ENABLED:
		_cube_lamp = _build_cube_lamp_response()

	# The gauge is a battery readout, so it goes with the batteries. A row of
	# segments pinned at full would say nothing and would still be one more lit
	# surface in a room being kept dark on purpose.
	if powered:
		_build_cube_gauge()

	_power = PowerSystem.new()
	_power.name = "PowerSystem"
	add_child(_power)
	_power.bind(_suit, _cube, _suit_store, _cube_store)


func _build_cube_gauge() -> void:
	_cube_gauge = CubePowerGauge.new()
	_cube_gauge.name = "PowerGauge"
	_cube.add_child(_cube_gauge)
	_cube_gauge.build(MovementKnobs.CARRY_OBJECT_SIZE)
	_cube_store.charge_changed.connect(_cube_gauge.show_fraction)
	_cube_gauge.show_fraction(_cube_store.get_fraction())


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


## The two lamps run the same code on different numbers, and the numbers are set
## as fields rather than passed to a shared builder: the argument list would run
## to ten positional floats, which is exactly the shape of call that gets a pair
## transposed and then reads as a mis-tuned curve rather than as a typo.
##
## The curves are built here, from the seed points, and then belong to the
## response. The panel edits those same two resources in place, so what the knobs
## hold is a starting shape rather than the live one.
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
	response.responds_to_charge = PowerKnobs.LAMP_RESPONDS_TO_POWER
	add_child(response)
	response.bind(_helmet_lamp(), _suit_store)

	# After bind, which is what gives the response its light to write to.
	response.set_color(PowerKnobs.HELMET_LAMP_COLOR)
	response.set_shadows(PowerKnobs.HELMET_LAMP_SHADOWS)
	response.set_distance_falloff(PowerKnobs.HELMET_LAMP_ATTENUATION)
	response.set_cone(PowerKnobs.HELMET_LAMP_ANGLE)
	response.set_edge_falloff(PowerKnobs.HELMET_LAMP_ANGLE_ATTENUATION)
	return response


func _build_cube_lamp_response() -> LampPowerResponse:
	var response := LampPowerResponse.new()
	response.name = "CubeLampResponse"
	response.base_energy = PowerKnobs.CUBE_LIGHT_ENERGY
	response.base_range = PowerKnobs.CUBE_LIGHT_RANGE
	response.min_range_fraction = PowerKnobs.CUBE_LAMP_MIN_RANGE_FRACTION
	response.dim_curve = LampPowerResponse.build_curve(PowerKnobs.CUBE_DIM_POINTS, 1.0)
	response.flicker_curve = LampPowerResponse.build_curve(
		PowerKnobs.CUBE_FLICKER_POINTS, PowerKnobs.FLICKER_RATE_MAX
	)
	response.flicker_scale = PowerKnobs.CUBE_FLICKER_SCALE
	response.responds_to_charge = PowerKnobs.LAMP_RESPONDS_TO_POWER
	add_child(response)
	response.bind(_cube_lamp_light(), _cube_store)

	response.set_color(PowerKnobs.CUBE_LIGHT_COLOR)
	response.set_shadows(PowerKnobs.CUBE_LIGHT_SHADOWS)
	response.set_distance_falloff(PowerKnobs.CUBE_LIGHT_ATTENUATION)
	return response


## Owns the CUBE_LIGHT_ENABLED switch, both halves of it. The lamp and the glow go
## out together, or the cube goes on being a lit box in a room with no light in
## it, which is a worse answer than either.
##
## Everything else about the cube's lamp - colour, falloff, shadows, brightness,
## throw - belongs to _build_cube_lamp_response. This runs first and touches only
## the two things that are not properties of the light.
func _apply_cube_optics() -> void:
	_cube_lamp_light().visible = PowerKnobs.CUBE_LIGHT_ENABLED
	if not PowerKnobs.CUBE_LIGHT_ENABLED:
		_cube_glow = 0.0
	_apply_cube_emission()


## What the cube's faces should be glowing at this frame: the base the slider
## holds, scaled by where the curve puts the cube's current charge.
##
## Parked at the base with LAMP_RESPONDS_TO_POWER off, exactly as the two lamps
## park at their base energy, so the switch means one thing across the prototype
## rather than one thing per light.
func _current_cube_glow() -> float:
	if not PowerKnobs.LAMP_RESPONDS_TO_POWER or _cube_glow_curve == null or _cube_store == null:
		return _cube_glow
	return _cube_glow * clampf(_cube_glow_curve.sample(_cube_store.get_fraction()), 0.0, 1.0)


func _apply_cube_emission() -> void:
	var glow := _current_cube_glow()
	# The generator gave the mesh its own duplicated material, so this is safe to
	# write to - it is not the shared .tres.
	for child: Node in _cube.get_children():
		var mesh := child as MeshInstance3D
		if mesh == null:
			continue
		var material := mesh.material_override as StandardMaterial3D
		if material == null:
			continue
		material.emission_enabled = glow > 0.0
		material.emission = _cube_light_color
		material.emission_energy_multiplier = glow


func _apply_environment() -> void:
	var environment := _world_environment.environment
	environment.ambient_light_energy = PowerKnobs.AMBIENT_ENERGY
	environment.fog_density = PowerKnobs.FOG_DENSITY
	set_view_distance(PowerKnobs.FOG_DEPTH_END)


## Fog that begins past where it ends is not a look, so the begin is held under
## the end here rather than at either slider. Both sliders can reach the crossing
## point and the one that gets there second should not be the one that decides.
func _apply_fog_begin() -> void:
	var environment := _world_environment.environment
	environment.fog_depth_begin = minf(_fog_begin, environment.fog_depth_end)


func _head_camera() -> Camera3D:
	return _suit.get_node("HeadCamera") as Camera3D


func _helmet_lamp() -> SpotLight3D:
	return _suit.get_node("HeadCamera/HelmetLamp") as SpotLight3D


func _cube_lamp_light() -> OmniLight3D:
	return _cube.get_node("ModuleLamp") as OmniLight3D


## Seconds of light left in a full suit, and how long a full cube could keep
## refilling it. Printed rather than the raw capacities because the capacities on
## their own say nothing - the whole question is how long you get.
##
## With power off it prints what is switched off instead, so a run that behaves
## nothing like the README says it should has the reason in its first line of
## output rather than in a constant three files away.
func _report() -> void:
	if not PowerKnobs.POWER_ENABLED:
		print(
			(
				"power and lighting: lighting only - power off, %s lamp response, %s cube light"
				% [
					"live" if PowerKnobs.LAMP_RESPONDS_TO_POWER else "flat",
					"on" if PowerKnobs.CUBE_LIGHT_ENABLED else "off",
				]
			)
		)
		return
	var suit_endurance := PowerKnobs.SUIT_CAPACITY / maxf(PowerKnobs.SUIT_DRAIN_PER_SECOND, 0.0001)
	var refills := PowerKnobs.CUBE_CAPACITY / PowerKnobs.SUIT_CAPACITY
	print(
		(
			"power and lighting: suit lasts %.0f s from full, cube holds %.1f suit charges"
			% [suit_endurance, refills]
		)
	)
	if PowerKnobs.LAMP_MODES_ENABLED:
		print("lamp switch: 1 out, 2 on. Out costs nothing and lasts forever.")
