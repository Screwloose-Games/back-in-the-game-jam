class_name DirectorSandbox
extends Node3D

## director.md's pacing cycle, running over a real creature, with the whole of it on screen.
##
##     QUIET  ->  BUILD  ->  PEAK  ->  RELIEF  ->  QUIET
##
## THE ENCOUNTER SANDBOX ALREADY SHOWS THE CREATURE DECIDING. What it cannot show is anything
## deciding about the ENCOUNTER: every hunt there ends `retreating (lost)` -- suspicion
## starvation -- because nothing is pricing the scene. There is no earned exit, no cooldown,
## no first-encounter grace, and no reason for a bored alien to drift toward the party. This
## scene is the same cave with a Director attached, and the difference is the whole point.
##
##     WASD / QE      move the player
##     LMB (held)     mine -- the loudest thing a player can do, and the fastest way to be found
##     RMB (held)     thrust -- quieter, and the noise you cannot avoid making
##     1 / 2          a single quiet / loud noise, for when you have no mouse
##     3              fill the lull, to skip three minutes of dead air
##     4              cycle the Director's clock: 1x / 4x / 16x
##     5              fill menace to the peak, to see the earned exit now
##     G / F          navigation graph / scored crawl fan
##     Tab            every overlay and panel at once
##     R              put the creature, the player and the nests back
##
## THE MOUSE KEYS ARE THE REAL MECHANIC, not a debug shortcut. The project's `mine` action IS
## left mouse button, `PlayerNoiseEmitter` computes noise from exactly `thrust_fraction` and
## `is_firing()`, and `PlayerNoiseRelay` converts what comes out into NoiseEvents the creature
## hears. Holding LMB here makes the same noise holding LMB makes in the game, at the same
## strength, through the same arithmetic -- this scene is the first thing in the project that
## joins the two halves up.
##
## THE DIRECTOR'S CLOCK IS SCALED AND ITS CONFIG IS NOT. `DirectorConfig` ships the slow,
## spec-calibrated cadence -- 200 s to fill a lull, 20 s of cooldown -- and a sandbox that
## quietly swapped in fast numbers would prove only that SOME config works, which is the trap
## `navigation_sandbox.gd` names. So `4` multiplies the delta the Director integrates and
## nothing else: the creature, the cave and the shipped numbers are untouched, and what you
## are watching is the real curve at a watchable speed.
##
## IT REUSES EncounterSandboxGeometry rather than building a third cave, and consumes its
## constants without editing them. That geometry already supplies everything the Director
## needs to demonstrate itself: 60 m of chase floor for proximity pressure, a pillar for
## avoidance, three nests for roam bias, and a 1 m slot into a refuge the alien can see into
## and never enter -- which is how you produce lurk pressure and a STALLED exit on demand.

const CAMERA_HEIGHT: float = 52.0
const PLAYER_SPEED: float = 7.0
const QUIET_LOUDNESS: float = 0.25
const LOUD_LOUDNESS: float = 1.0
## What `4` cycles through. The lull is 200 s at 1x and about twelve at 16x.
const TIME_SCALES: Array[float] = [1.0, 4.0, 16.0]
## How far a near-miss throws the player. Far enough to read as a stagger, not so far that it
## breaks the chase -- the alien overshoots and comes back.
const GRACE_KNOCKBACK_M: float = 5.0
const COLOR_NEST := Color(0.30, 0.85, 0.80, 1.0)
const COLOR_GOAL := Color(1.0, 0.55, 0.15, 1.0)
const COLOR_CAVE := Color(0.62, 0.64, 0.78, 1.0)
const COLOR_PLAYER := Color(0.95, 0.75, 0.25, 1.0)
const COLOR_HURT := Color(0.95, 0.25, 0.20, 1.0)
const COLOR_CREATURE := Color(0.55, 0.25, 0.60, 1.0)

var behavior: CreatureBehavior = null
var director: EncounterDirector = null

var _creature: CreaturePerception = null
var _suspicion: CreatureSuspicion = null
var _navigation: CreatureNavigation = null
var _player: Node3D = null
var _player_skin: MeshInstance3D = null
var _emitter: _StandInEmitter = null
var _relay: PlayerNoiseRelay = null
var _nests: Array[CreatureNest] = []
var _goal_marker: MeshInstance3D = null
var _graph_overlay: NavigationDebugDraw = null
var _locomotion_overlay: NavigationLocomotionDraw = null
var _director_panel: DirectorDebugPanel = null
var _perception_panel: PerceptionDebugPanel = null
var _suspicion_panel: SuspicionDebugPanel = null
var _behavior_panel: BehaviorDebugPanel = null
var _navigation_panel: NavigationDebugPanel = null
var _perception_overlay: PerceptionDebugDraw = null
var _suspicion_overlay: SuspicionDebugDraw = null
var _forward: Vector3 = Vector3.RIGHT
var _command: NavMotionCommand = null
var _time_scale: int = 0
var _hurt_until: float = 0.0
var _debug_visible: bool = true


func _ready() -> void:
	# The creature BEFORE the cave. CreaturePerception._ready() walks its parent's descendants
	# to build the RID list it excludes from its own line-of-sight rays; build the room first
	# and every wall lands on that list, so the alien sees through solid rock.
	_build_creature()
	EncounterSandboxGeometry.build(self)
	_draw_cave()
	_build_player()
	_plant_nests()
	_build_belief()
	_build_camera()

	# Colliders added this frame are not queryable until the physics server has stepped, and a
	# bake that runs before it produces a graph filling the cave, walls included.
	await get_tree().physics_frame
	await get_tree().physics_frame

	_build_navigation()
	_build_director()
	_build_behavior()
	_build_debug()


func _process(delta: float) -> void:
	_drive_player(delta)
	_poll_noise()
	_fade_hurt()
	if behavior == null or _goal_marker == null:
		return
	var showing: bool = _debug_visible and behavior.goal.has_goal()
	_goal_marker.visible = showing
	if showing:
		_goal_marker.global_position = behavior.goal.committed() + Vector3.UP * 1.5


func _physics_process(delta: float) -> void:
	_drive(delta)
	if _relay != null:
		_relay.advance(delta)
	# THE DIRECTOR IS DRIVEN FROM HERE RATHER THAN BY ITS OWN _physics_process, and that is the
	# only reason its `set_physics_process(false)` is called in _build_director. Scaling the
	# delta is what `4` does; scaling Engine.time_scale instead would speed up the creature,
	# the cave and the motor as well, and the thing worth watching is the Director's curve
	# against a creature behaving at its real speed.
	if director != null:
		director.advance(delta * TIME_SCALES[_time_scale])


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_1:
			_emit_once(QUIET_LOUDNESS, &"footstep")
		KEY_2:
			_emit_once(LOUD_LOUDNESS, &"drill")
		KEY_3:
			_fill_lull()
		KEY_4:
			_cycle_time_scale()
		KEY_5:
			_fill_menace()
		KEY_G:
			_graph_overlay.draw_graph = not _graph_overlay.draw_graph
			_graph_overlay.refresh_graph()
		KEY_F:
			_locomotion_overlay.draw_crawl_fan = not _locomotion_overlay.draw_crawl_fan
		KEY_TAB:
			_toggle_debug()
		KEY_R:
			_reset()


# ----- the motor, which is step 9 of the tick contract -----


## Consumes `navigation.command` for real, exactly as `encounter_sandbox.gd` does and for the
## reasons its `_drive` docstring gives at length: seed the input half, report the APPLIED
## basis back rather than `preferred_forward`, clamp the turn here because only the surface
## crawler slews, and act on `command.abort` by holding still rather than nudging.
##
## Kept as a copy rather than shared, because a stand-in for a system that does not exist yet
## is not an abstraction worth extracting. When Movement lands, both scenes delete theirs.
func _drive(delta: float) -> void:
	if _navigation == null or _creature == null or _command == null:
		return
	if not _navigation.follower.has_route():
		_step(Vector3.ZERO, delta)
		return
	if _command.is_stalled() or _command.desired_speed <= 0.0:
		_step(Vector3.ZERO, delta)
		return
	var wanted: Vector3 = _command.desired_direction.normalized()
	var profile: LocomotionProfile = _navigation.config.locomotion_profile
	_forward = _turn_toward(_forward, wanted, profile.orientation_slew_rate * delta)
	_step(wanted * _command.desired_speed * delta, delta)


func _step(travel: Vector3, delta: float) -> void:
	_creature.global_position += travel
	var flat := Vector3(_forward.x, 0.0, _forward.z)
	if not flat.is_zero_approx():
		_creature.global_rotation = Vector3(0.0, atan2(-flat.x, -flat.z), 0.0)
	var velocity: Vector3 = travel / maxf(delta, 0.0001)
	_navigation.set_body_state(_creature.global_position, velocity, _forward, Vector3.UP)


## `from` turned toward `to` by at most `max_radians`, in three dimensions because the crawler
## works in the tangent plane rather than in yaw.
static func _turn_toward(from: Vector3, to: Vector3, max_radians: float) -> Vector3:
	var angle: float = from.angle_to(to)
	if angle <= max_radians or angle < 0.0001:
		return to
	if angle > PI - 0.001:
		return from.rotated(Vector3.UP, max_radians)
	return from.slerp(to, max_radians / angle).normalized()


func _on_motion_planned(command: NavMotionCommand) -> void:
	_command = command


# ----- interaction -----


func _drive_player(delta: float) -> void:
	if _player == null:
		return
	var move := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		move += Vector3.FORWARD
	if Input.is_physical_key_pressed(KEY_S):
		move += Vector3.BACK
	if Input.is_physical_key_pressed(KEY_A):
		move += Vector3.LEFT
	if Input.is_physical_key_pressed(KEY_D):
		move += Vector3.RIGHT
	if Input.is_physical_key_pressed(KEY_E):
		move += Vector3.UP
	if Input.is_physical_key_pressed(KEY_Q):
		move += Vector3.DOWN
	if move != Vector3.ZERO:
		_player.global_position += move.normalized() * PLAYER_SPEED * delta


## Polls the mouse the way PlayerInput polls the real `mine` action, and hands the result to
## the stand-in emitter in exactly the shape PlayerNoiseEmitter.authority_step() takes.
##
## THRUST IS DERIVED FROM MOVEMENT, which is what makes noise discipline a real choice here:
## there is no silent way to travel, so crossing the cave to reach the refuge costs you
## something whether or not you touch the drill.
func _poll_noise() -> void:
	if _emitter == null:
		return
	var moving: bool = (
		Input.is_physical_key_pressed(KEY_W)
		or Input.is_physical_key_pressed(KEY_A)
		or Input.is_physical_key_pressed(KEY_S)
		or Input.is_physical_key_pressed(KEY_D)
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	)
	_emitter.step(
		1.0 if moving else 0.0,
		Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT),
		_player.global_position
	)


## The keyboard fallback, straight into the creature -- the same shortcut both behavior
## sandboxes take, kept so the scene is usable without a mouse.
func _emit_once(loudness: float, category: StringName) -> void:
	_creature.receive_noise(
		NoiseEvent.make(_player.global_position, loudness, category, _player, _player)
	)
	print("[director] %s at %v" % [category, _player.global_position])


func _fill_lull() -> void:
	director.lull = 1.0
	print("[director] lull filled; bias and roam go positive and the alien drifts in")


## Fills the meter rather than forcing the exit, because there is no way to force one and
## there should not be: the Director owns that decision and this scene is watching it make it.
func _fill_menace() -> void:
	var track: EncounterTrack = director.track_for(behavior)
	if track == null:
		return
	track.menace = director.config.peak_threshold
	print("[director] menace filled; the Director will take it from here")


func _cycle_time_scale() -> void:
	_time_scale = (_time_scale + 1) % TIME_SCALES.size()
	print("[director] clock x%.0f (the config is untouched)" % TIME_SCALES[_time_scale])


## The consequence a near-miss and a kill have to have for the flag to mean anything.
##
## NO HEALTH SYSTEM IS ADDED TO gameplay/ FOR THIS. Nothing in the project has health,
## `attack_landed` is emitted into nothing, and the Director owns only the flag -- so the
## consequence lives here, in the scene that wants to show it, exactly where `bt_attack.gd`'s
## docstring says damage will attach when somebody builds it.
func _on_attack(target: Node, lethality: EncounterDirective.Lethality) -> void:
	var menace: float = 0.0
	var track: EncounterTrack = director.track_for(behavior)
	if track != null:
		menace = track.menace
	if lethality == EncounterDirective.Lethality.GRACE:
		var away: Vector3 = _player.global_position - _creature.global_position
		away.y = 0.0
		if away.is_zero_approx():
			away = Vector3.RIGHT
		_player.global_position += away.normalized() * GRACE_KNOCKBACK_M
		_hurt_until = 0.35
		print("[director] near-miss (grace), menace %.2f -- lethal from here" % menace)
		return
	_player.global_position = EncounterSandboxGeometry.PLAYER_START
	_hurt_until = 1.0
	# Arms respawn_grace_s. This one line is the whole of the seam the README documents, and
	# in the real game it hangs off PlayerRespawn.respawned instead.
	director.note_respawn(target if target != null else _player)
	print("[director] KILLED (lethal), menace %.2f -- respawn grace armed" % menace)


func _fade_hurt() -> void:
	if _player_skin == null:
		return
	var material := _player_skin.material_override as StandardMaterial3D
	if material == null:
		return
	_hurt_until = maxf(_hurt_until - get_process_delta_time(), 0.0)
	material.albedo_color = COLOR_HURT if _hurt_until > 0.0 else COLOR_PLAYER


func _reset() -> void:
	_creature.global_position = EncounterSandboxGeometry.CREATURE_START
	_player.global_position = EncounterSandboxGeometry.PLAYER_START
	_forward = Vector3.RIGHT
	_command = null
	_navigation.clear_goal()
	_navigation.set_body_state(_creature.global_position, Vector3.ZERO, _forward, Vector3.UP)
	_suspicion.reset()
	director.reset()
	behavior.hfsm.reset_to(CreatureState.State.UNALERTED, behavior.context)
	print("[director] reset -- session history cleared, so the first encounter teaches again")


func _toggle_debug() -> void:
	_debug_visible = not _debug_visible
	for node: CanvasItem in [
		_director_panel, _perception_panel, _suspicion_panel, _behavior_panel, _navigation_panel
	]:
		node.visible = _debug_visible
	for node: Node3D in [
		_graph_overlay, _locomotion_overlay, _perception_overlay, _suspicion_overlay
	]:
		node.visible = _debug_visible
	for nest: CreatureNest in _nests:
		nest.visible = _debug_visible


# ----- construction -----


func _build_creature() -> void:
	_creature = CreaturePerception.new()
	_creature.name = "CreaturePerception"
	_creature.position = EncounterSandboxGeometry.CREATURE_START
	_creature.rotation = Vector3(0.0, -PI * 0.5, 0.0)
	# Shipped defaults, for the reason navigation's own sandbox gives: a sandbox with a tuned
	# config proves only that SOME config works.
	_creature.config = PerceptionConfig.new()
	add_child(_creature)
	_creature.add_child(_blob(SphereMesh.new(), COLOR_CREATURE))


func _build_player() -> void:
	_player = Node3D.new()
	_player.name = "StandIn"
	_player.position = EncounterSandboxGeometry.PLAYER_START
	# The group CreaturePerception falls back to when `targets` is not wired.
	_player.add_to_group(&"perceivable")
	var capsule := CapsuleMesh.new()
	capsule.height = 1.8
	capsule.radius = 0.4
	add_child(_player)
	_player_skin = _blob(capsule, COLOR_PLAYER)
	_player.add_child(_player_skin)

	_emitter = _StandInEmitter.new()
	_emitter.name = "NoiseEmitter"
	_emitter.body = _player
	_player.add_child(_emitter)


func _build_belief() -> void:
	_suspicion = CreatureSuspicion.new()
	_suspicion.name = "CreatureSuspicion"
	_suspicion.config = SuspicionConfig.new()
	add_child(_suspicion)
	# The two-line coupling perception/README.md documents, and the only wiring between those
	# modules.
	_creature.evidence_observed.connect(_suspicion.submit_evidence)
	_creature.disconfirmation_observed.connect(_suspicion.submit_disconfirmation)

	# The wire that did not exist before this module: what the player DOES becomes what the
	# creature HEARS, through the same arithmetic the real prefab uses.
	_relay = PlayerNoiseRelay.new()
	_relay.name = "PlayerNoiseRelay"
	_relay.perception = _creature
	_relay.emitters = [_emitter]
	# Driven from this scene's _physics_process alongside the motor, so the whole tick order
	# is visible in one function rather than spread across four nodes' own callbacks.
	_relay.set_physics_process(false)
	add_child(_relay)
	_relay.bind_all()


func _build_navigation() -> void:
	_navigation = CreatureNavigation.new()
	_navigation.name = "CreatureNavigation"
	_navigation.config = NavigationConfig.new()
	add_child(_navigation)
	if _navigation.bake_now(EncounterSandboxGeometry.bake_region()) == null:
		push_error("DirectorSandbox could not bake a navigation graph over the cave")
		return
	_forward = -_creature.global_transform.basis.z
	_navigation.set_body_state(_creature.global_position, Vector3.ZERO, _forward, Vector3.UP)
	_navigation.motion_planned.connect(_on_motion_planned)


## Level-scoped, so it is a sibling of the creature rather than a child of it.
func _build_director() -> void:
	director = EncounterDirector.new()
	director.name = "EncounterDirector"
	# Shipped defaults. `4` scales the clock instead -- see the class docstring.
	director.config = DirectorConfig.new()
	director.players = [_player]
	director.set_physics_process(false)
	add_child(director)


func _build_behavior() -> void:
	behavior = CreatureBehavior.new()
	behavior.name = "CreatureBehavior"
	behavior.config = BehaviorConfig.new()
	behavior.behavior_seed = 20250816
	behavior.suspicion = _suspicion
	behavior.perception = _creature
	behavior.navigation = _navigation
	behavior.director = director
	# THE PERCEPTION NODE IS THE BODY. It is a Node3D and measures hearing and touch from its
	# own position, so moving it moves the creature.
	behavior.body = _creature
	add_child(behavior)
	behavior.state_changed.connect(_on_state_changed)
	behavior.attack_landed.connect(_on_attack)
	director.register(behavior, _suspicion)
	# Publish the resting alertness NOW rather than at the first tick: perception runs its own
	# _physics_process until Behavior mutes it, and one frame at full sharpness with the player
	# standing in the sightline opens the scene already hunting.
	_creature.set_alertness_context(behavior.config.alertness_for(behavior.state()))


func _plant_nests() -> void:
	for at: Vector3 in EncounterSandboxGeometry.NEST_POSITIONS:
		var nest := CreatureNest.new()
		nest.name = "Nest%d" % _nests.size()
		nest.position = at
		var pad := BoxMesh.new()
		pad.size = Vector3(2.0, 0.15, 2.0)
		add_child(nest)
		nest.add_child(_blob(pad, COLOR_NEST))
		_nests.append(nest)


## Five panels rather than four, and the Director gets the top of the screen.
##
## The four corners were already spoken for by the creature's own readouts, and this scene is
## about the fifth thing. The navigation panel is the least relevant here and starts hidden
## behind Tab; the Director panel carries the creature's state on its own bottom line, so the
## disagreement that matters -- HUNTING while the Director is in RELIEF -- is legible without
## looking at two corners at once.
func _build_debug() -> void:
	_graph_overlay = NavigationDebugDraw.new()
	_graph_overlay.navigation = _navigation
	add_child(_graph_overlay)

	_locomotion_overlay = NavigationLocomotionDraw.new()
	_locomotion_overlay.navigation = _navigation
	add_child(_locomotion_overlay)

	_perception_overlay = PerceptionDebugDraw.new()
	_perception_overlay.perception = _creature
	add_child(_perception_overlay)

	_suspicion_overlay = SuspicionDebugDraw.new()
	_suspicion_overlay.suspicion = _suspicion
	add_child(_suspicion_overlay)

	_goal_marker = _blob(_goal_bar(), COLOR_GOAL)
	_goal_marker.name = "GoalMarker"
	add_child(_goal_marker)

	var layer := CanvasLayer.new()
	add_child(layer)
	_build_panels(layer)


func _build_panels(layer: CanvasLayer) -> void:
	# Assigned BEFORE add_child, every one of them: these panels connect their signals in their
	# own _ready(), and one wired up afterwards renders every line except its event log.
	_director_panel = DirectorDebugPanel.new()
	_director_panel.director = director
	_director_panel.creature = behavior
	_director_panel.behavior = behavior
	_director_panel.anchor_left = 0.5
	_director_panel.anchor_right = 0.5
	_director_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_director_panel.position = Vector2(0.0, 12.0)
	layer.add_child(_director_panel)

	_perception_panel = PerceptionDebugPanel.new()
	_perception_panel.perception = _creature
	_perception_panel.debug_draw = _perception_overlay
	_perception_panel.position = Vector2(12, 12)
	layer.add_child(_perception_panel)

	_suspicion_panel = SuspicionDebugPanel.new()
	_suspicion_panel.suspicion = _suspicion
	_suspicion_panel.debug_draw = _suspicion_overlay
	_suspicion_panel.anchor_left = 1.0
	_suspicion_panel.anchor_right = 1.0
	_suspicion_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_suspicion_panel.position = Vector2(-12, 12)
	layer.add_child(_suspicion_panel)

	_behavior_panel = BehaviorDebugPanel.new()
	_behavior_panel.behavior = behavior
	_behavior_panel.anchor_top = 1.0
	_behavior_panel.anchor_bottom = 1.0
	_behavior_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_behavior_panel.position = Vector2(12, -12)
	layer.add_child(_behavior_panel)

	_navigation_panel = NavigationDebugPanel.new()
	_navigation_panel.navigation = _navigation
	_navigation_panel.anchor_left = 1.0
	_navigation_panel.anchor_right = 1.0
	_navigation_panel.anchor_top = 1.0
	_navigation_panel.anchor_bottom = 1.0
	_navigation_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_navigation_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_navigation_panel.position = Vector2(-12, -12)
	_navigation_panel.visible = false
	layer.add_child(_navigation_panel)


## Above the cave and off to one side, aimed with look_at rather than left on its default
## rotation -- a Camera3D faces its own -Z, so one dropped here unrotated stares at the sky.
func _build_camera() -> void:
	var interior: AABB = EncounterSandboxGeometry.INTERIOR
	var camera := Camera3D.new()
	camera.name = "SandboxCamera"
	camera.position = Vector3(interior.size.x * 0.5, CAMERA_HEIGHT, interior.size.z + 26.0)
	camera.far = 400.0
	camera.current = true
	add_child(camera)
	camera.look_at(interior.get_center(), Vector3.UP)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
	add_child(light)


## The cave as wireframe. Solid boxes hide the interior, and translucent ones sort PER OBJECT
## on the GL Compatibility renderer this project targets.
func _draw_cave() -> void:
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.disable_fog = true

	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for box: AABB in EncounterSandboxGeometry.solids():
		_wire_box(mesh, box)
	mesh.surface_end()

	var view := MeshInstance3D.new()
	view.name = "CaveWireframe"
	view.mesh = mesh
	view.material_override = material
	view.extra_cull_margin = 4096.0
	add_child(view)


func _wire_box(mesh: ImmediateMesh, box: AABB) -> void:
	# Godot's AABB endpoint order: bit 0 is +x, bit 1 is +y, bit 2 is +z. Two corners are
	# joined by an edge exactly when their indices differ in one bit.
	for corner: int in 8:
		for axis: int in 3:
			var neighbor: int = corner | (1 << axis)
			if neighbor == corner:
				continue
			mesh.surface_set_color(COLOR_CAVE)
			mesh.surface_add_vertex(box.get_endpoint(corner))
			mesh.surface_set_color(COLOR_CAVE)
			mesh.surface_add_vertex(box.get_endpoint(neighbor))


static func _goal_bar() -> BoxMesh:
	var bar := BoxMesh.new()
	bar.size = Vector3(0.3, 3.0, 0.3)
	return bar


static func _blob(mesh: Mesh, color: Color) -> MeshInstance3D:
	var view := MeshInstance3D.new()
	view.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	view.material_override = material
	return view


func _on_state_changed(
	from: CreatureState.State, to: CreatureState.State, reason: StringName
) -> void:
	print(
		(
			"[director] %s -> %s (%s)"
			% [CreatureState.state_name(from), CreatureState.state_name(to), reason]
		)
	)


## PlayerNoiseEmitter's arithmetic, without its CharacterBody3D, its oxygen, its tether or its
## network driver.
##
## IT USES THE REAL STATICS AND THE REAL SETTINGS, so what the creature hears in this scene is
## what it would hear in the game: `PlayerNoise.thrust_strength` and `PlayerNoise.loudest`
## against a stock `PlayerSettings`, announced on the same CHANGE_EPSILON the component uses.
## Reimplementing the numbers here would have made the sandbox agree with itself rather than
## with the game.
class _StandInEmitter:
	extends Node

	signal noise_emitted(strength: float, at: Vector3, source: int)

	const CHANGE_EPSILON: float = 0.05

	var body: Node3D = null
	var settings: PlayerSettings = PlayerSettings.new()

	var _announced: float = -1.0

	func step(thrust_fraction: float, mining: bool, at: Vector3) -> void:
		var thrust: float = PlayerNoise.thrust_strength(
			thrust_fraction, settings.thrust_noise_strength
		)
		var mined: float = settings.mining_noise_strength if mining else 0.0
		var strength: float = PlayerNoise.loudest(PackedFloat32Array([thrust, mined]))
		if absf(strength - _announced) < CHANGE_EPSILON:
			return
		_announced = strength
		var source: int = (
			PlayerNoise.Source.MINING if mined >= thrust else PlayerNoise.Source.THRUST
		)
		noise_emitted.emit(strength, at, source)
