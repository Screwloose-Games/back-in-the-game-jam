class_name PlayerSettings
extends Resource

## Every tunable number the player has, in one resource. This is the single
## source of truth that replaced the five near-duplicate `*_knobs.gd` files in
## `prototypes/`; the components read it and `systems/player/core/` takes these
## values as plain arguments.

## Widest camera_fov that keeps the suit's open neck seam out of frame. The head
## is a separate mesh so the local camera can cull it, which leaves the body open
## at the collar; the nearest rim vertex sits 36.12 deg below the view axis at the
## worst frame of idle_float, so a half-angle past that sees through it.
const CAMERA_FOV_NECK_SEAM_LIMIT := 72.0

## The shortest an empty tank may take to kill from full health. Under this the
## suffocation clock is a cliff again, which is the thing the pool exists to replace.
const SUFFOCATION_MIN_SECONDS := 4.0

## The shortest a live arc may take to empty a full suit. Under this, crossing one is
## a sentence rather than a price.
const ARC_MIN_DRAIN_SECONDS := 3.0

## How many multiples of a reference-speed impact the worst crash can cost. The
## stalker owns instant death; a wall must not be able to take it.
const IMPACT_HARDNESS_CAP := 3.0

## Thruster strength in metres per second squared, per axis.
@export_group("Thrusters")
@export_range(1.0, 40.0, 0.5) var thrust_acceleration: float = 10.0

## Ceiling on drift speed.
@export_range(0.5, 20.0, 0.1, "suffix:m/s") var max_speed: float = 4.0

## Thrust multiplier while sprint is held.
@export_range(1.0, 6.0, 0.1) var sprint_acceleration_multiplier: float = 2.0

## Speed-cap multiplier while sprint is held.
@export_range(1.0, 6.0, 0.1) var sprint_speed_multiplier: float = 2.5

## How fast the raised speed cap eases back down after sprint is released.
@export_range(0.1, 10.0, 0.1) var sprint_falloff_rate: float = 2.0

## Fraction of drift speed shed per second while stabilisers are held.
@export_range(0.0, 20.0, 0.1) var linear_stabilizer_rate: float = 4.0

@export_group("Rotation")

## DIRECT maps look straight onto this frame; INERTIAL accumulates a tumble.
@export var rotation_mode: PlayerFlight.RotationMode = PlayerFlight.RotationMode.INERTIAL

## Radians of rotation per pixel of mouse movement.
@export_range(0.0002, 0.01, 0.0001) var mouse_sensitivity: float = 0.0022

## Roll speed in radians per second, or its acceleration in INERTIAL mode.
@export_range(0.1, 10.0, 0.1) var roll_rate: float = 2.0

## Gain applied to look input when it feeds angular velocity. INERTIAL only.
@export_range(0.1, 20.0, 0.1) var angular_acceleration: float = 6.0

## Ceiling on tumble rate.
@export_range(0.5, 20.0, 0.1, "suffix:rad/s") var max_angular_speed: float = 10.0

## Fraction of tumble shed per second with no input held. This is the dial
## between the two rotation modes: at 0.0 a flick spins you until you counter it.
@export_range(0.0, 8.0, 0.1) var angular_drag: float = 2.0

## Fraction of tumble shed per second while stabilisers are held.
@export_range(0.0, 20.0, 0.1) var angular_stabilizer_rate: float = 5.0

@export_group("Collision")

## The player's mass. Half of every mass ratio that decides who moves.
@export_range(20.0, 300.0, 1.0, "suffix:kg") var player_mass: float = 90.0

## Radius of the suit's collision sphere.
@export_range(0.1, 2.0, 0.05, "suffix:m") var hull_radius: float = 0.4

## How much into-the-wall speed is thrown back out. 1.0 is a perfect bounce.
@export_range(0.0, 1.0, 0.05) var collision_restitution: float = 0.35

## How much along-the-wall speed is scrubbed on impact.
@export_range(0.0, 1.0, 0.05) var collision_friction: float = 0.25

## How strongly a glancing blow twists you. 0.0 disables impact spin.
@export_range(0.0, 5.0, 0.1) var collision_spin_transfer: float = 1.5

## Fraction of speed shed per second while still scraping along a surface.
@export_range(0.0, 8.0, 0.1) var scrape_friction: float = 1.5

@export_group("Grip")

## How far the grab ray reaches. Arm's reach, not a tractor beam.
@export_range(0.5, 6.0, 0.1, "suffix:m") var grab_range: float = 2.0

## Distance between the hands, straddling the point you aimed at. This is the
## lever the pair of springs works through, so it sets how hard the load twists.
@export_range(0.1, 2.0, 0.05, "suffix:m") var grip_hand_separation: float = 0.7

## Where a held object's centre settles, in suit-local metres.
@export var grip_carry_offset := Vector3(0.0, -0.5, -1.5)

## Seconds spent easing from the pose you caught it in to the carry pose.
@export_range(0.0, 2.0, 0.05, "suffix:s") var grip_settle_time: float = 0.55

## How stiff the hands are. Higher snaps the load square; lower lets it wallow.
@export_range(0.2, 8.0, 0.1) var grip_spring_frequency: float = 2.2

## Grip damping as a fraction of critical.
@export_range(0.0, 2.0, 0.05) var grip_spring_damping_ratio: float = 0.9

## Ceiling on grip force across both hands, so one bad frame cannot launch you.
@export_range(100.0, 60000.0, 100.0, "suffix:N") var grip_max_force: float = 20000.0

## How far a hand can be pulled off its hold before the grip slips.
@export_range(0.2, 4.0, 0.05, "suffix:m") var grip_break_distance: float = 1.2

## Wrist stiffness, holding the one roll two hands cannot. 0.0 lets it spin.
@export_range(0.0, 8.0, 0.1) var grip_twist_frequency: float = 2.0

## Wrist damping as a fraction of critical.
@export_range(0.0, 2.0, 0.05) var grip_twist_damping_ratio: float = 0.9

## Ceiling on wrist torque.
@export_range(100.0, 30000.0, 100.0) var grip_twist_max_torque: float = 8000.0

## How much of the suit's own manoeuvring moves you and the load as one body.
@export_range(0.0, 1.0, 0.05) var grip_bracing: float = 1.0

## How strongly grip force applied off your centre of mass slews your aim.
@export_range(0.0, 2.0, 0.05) var grip_spin_transfer: float = 0.5

## The same for the wrist spring, kept well under grip_spin_transfer.
@export_range(0.0, 2.0, 0.05) var grip_twist_spin_transfer: float = 0.2

## What a carryable weighs while your hands are on it. Physically a cheat: one
## mass cannot be both an anchor to moor to and a load you can actually haul.
@export_range(20.0, 2000.0, 10.0, "suffix:kg") var carry_object_held_mass: float = 200.0

@export_group("Tether")

## Length of the line. Below this the tether is limp and exerts nothing.
@export_range(2.0, 30.0, 0.5, "suffix:m") var tether_length: float = 10.0

## Where the line is anchored on the suit, behind and below the eye.
@export var tether_anchor_offset := Vector3(0.0, -0.25, 0.45)

## Tether stiffness, deliberately below the grip's — a rope that snaps taut as
## hard as a hand grip would defeat the point.
@export_range(0.1, 8.0, 0.1) var tether_spring_frequency: float = 1.0

## Tether damping along the line only, as a fraction of critical.
@export_range(0.0, 2.0, 0.05) var tether_spring_damping_ratio: float = 0.1

## Ceiling on tether force.
@export_range(100.0, 30000.0, 100.0, "suffix:N") var tether_max_force: float = 8000.0

## How far past its length the line stretches before it parts.
@export_range(0.2, 6.0, 0.1, "suffix:m") var tether_break_stretch: float = 1.5

## How strongly a taut line twists you. Keep it under grip_spin_transfer.
@export_range(0.0, 2.0, 0.05) var tether_spin_transfer: float = 0.25

@export_group("Rope")

## How far apart the rope's simulated points sit. This is what it can wrap.
@export_range(0.05, 1.0, 0.05, "suffix:m") var tether_rope_segment: float = 0.2

## Constraint passes per step. Too few and the rope stretches under load.
@export_range(1, 32, 1) var tether_rope_iterations: int = 12

## Fraction of a rope point's speed shed per second, to stop the chain ringing.
@export_range(0.0, 10.0, 0.1) var tether_rope_damping: float = 2.0

## How far a segment may close up before it pushes back. 0.0 lets it collapse.
@export_range(0.0, 1.0, 0.05) var tether_rope_spread: float = 0.85

## How far off a surface a rope point rests. Trades a floating rope for a
## clipping one.
@export_range(0.01, 0.5, 0.01, "suffix:m") var tether_rope_radius: float = 0.16

## Radius the rope is drawn at. Purely cosmetic; deliberately under the radius
## it behaves as, or it would pinch through itself at every bend.
@export_range(0.01, 0.3, 0.01, "suffix:m") var tether_rope_draw_radius: float = 0.05

## Faces around the drawn rope's circumference.
@export_range(3, 16, 1) var tether_rope_draw_sides: int = 6

## Fraction of along-the-wall speed a rope point loses when it scrapes.
@export_range(0.0, 1.0, 0.05) var tether_rope_friction: float = 0.4

## Layers the rope collides with. Hull only, or it catches on itself.
@export_flags_3d_physics var tether_rope_layers: int = 1

@export_group("Oxygen")

## Size of the personal tank. Only ratios matter; readouts are percentages.
@export_range(10.0, 400.0, 5.0) var oxygen_capacity: float = 100.0

## How full the tank starts.
@export_range(0.0, 1.0, 0.05) var oxygen_start_fraction: float = 1.0

## Oxygen gained per second from a powered tether.
@export_range(0.0, 20.0, 0.1) var oxygen_regen_per_second: float = 5.0

## Oxygen lost per second with no power reaching you.
@export_range(0.0, 20.0, 0.1) var oxygen_idle_drain_per_second: float = 1.0

## Extra oxygen full thrust costs per second while untethered. This is the
## design's "move or breathe, pick one".
@export_range(0.0, 20.0, 0.5) var oxygen_thrust_cost_per_second: float = 4.0

@export_group("Power")

## Size of the suit's own battery.
@export_range(20.0, 400.0, 5.0) var suit_capacity: float = 100.0

## How full the suit battery starts.
@export_range(0.0, 1.0, 0.05) var suit_start_fraction: float = 0.6

## What the suit leaks per second on its own.
@export_range(0.0, 5.0, 0.1) var suit_drain_per_second: float = 3.0

## How fast a live tether refills the suit from the shared box.
@export_range(0.0, 12.0, 0.5) var suit_charge_per_second: float = 12.0

## What the helmet lamp costs per second while lit.
@export_range(0.0, 12.0, 0.1) var lamp_power_per_second: float = 1.5

## What the mining laser costs per second while firing.
@export_range(0.0, 40.0, 0.1) var mining_power_per_second: float = 8.0

@export_group("Lamp")

## Brightness of the helmet lamp at full power.
@export_range(0.5, 8.0, 0.1) var helmet_lamp_energy: float = 3.5

## Cone width of the helmet lamp.
@export_range(15.0, 75.0, 1.0, "suffix:°") var helmet_lamp_angle: float = 45.0

## How sharply the cone fades at its edge.
@export_range(0.0, 4.0, 0.05) var helmet_lamp_angle_attenuation: float = 0.75

## How sharply the lamp falls off across its range.
@export_range(0.2, 4.0, 0.05) var helmet_lamp_attenuation: float = 1.0

## Lamp colour. Warm, so it reads apart from the shared box's cool light.
@export var helmet_lamp_color := Color(1.0, 0.96, 0.89)

## Whether the lamp casts shadows. Most of what makes it worth having, and the
## expensive half of it.
@export var helmet_lamp_shadows: bool = true

## How far the lamp throws at full power.
@export_range(4.0, 80.0, 1.0, "suffix:m") var helmet_lamp_range: float = 30.0

## The shortest the beam gets as power runs down, as a fraction of its range.
@export_range(0.0, 1.0, 0.05) var helmet_lamp_min_range_fraction: float = 0.47

## Whether the lamp is lit on spawn.
@export var lamp_starts_on: bool = true

## How deeply a flicker dips the beam.
@export_range(0.0, 1.0, 0.01) var lamp_flicker_depth: float = 0.15

## Flickers per second at the bottom of the power curve.
@export_range(0.0, 10.0, 0.1) var lamp_flicker_rate_max: float = 3.0

## How long one flicker lasts.
@export_range(0.01, 1.0, 0.01, "suffix:s") var lamp_flicker_duration: float = 0.09

@export_group("View")

## Past CAMERA_FOV_NECK_SEAM_LIMIT the open collar comes into view — checked in
## invariant_failures().
@export_range(40.0, 110.0, 1.0, "suffix:°") var camera_fov: float = 67.0

@export_range(0.01, 1.0, 0.01, "suffix:m") var camera_near: float = 0.05

## Hard clip distance. Must stay past fog_depth_end or geometry pops out before
## the fog has hidden it — checked in invariant_failures().
@export_range(5.0, 120.0, 1.0, "suffix:m") var camera_far: float = 38.0

## Metres at which fog starts to thicken.
@export_range(0.0, 20.0, 0.5, "suffix:m") var fog_depth_begin: float = 0.0

## Metres at which geometry is fully swallowed. This sets how far you can see.
@export_range(5.0, 80.0, 1.0, "suffix:m") var fog_depth_end: float = 30.0

## How sharply fog ramps between begin and end.
@export_range(0.0, 4.0, 0.05) var fog_density: float = 1.0

@export_range(0.0, 0.25, 0.005) var ambient_energy: float = 0.02

@export_group("Mining")

## How far the mining laser reaches.
@export_range(1.0, 30.0, 0.5, "suffix:m") var mining_range: float = 6.0

## How fast the laser breaks an ore node down.
@export_range(0.1, 20.0, 0.1) var mining_damage_per_second: float = 1.0

## Colour of the beam and of the light it throws where it lands. One value for
## both, so the beam and the glow it casts can never disagree.
@export var mining_beam_color := Color(1.0, 0.15, 0.08)

## Brightness of that light.
@export_range(0.0, 16.0, 0.1) var mining_light_energy: float = 4.0

## How far it reaches. Local glow at the cut, not a second lamp.
@export_range(0.5, 20.0, 0.5, "suffix:m") var mining_light_range: float = 5.0

## Radius the beam is drawn at.
@export_range(0.005, 0.2, 0.005, "suffix:m") var mining_beam_radius: float = 0.03

## multiplies the minerals collected by this value
@export_range(1, 50, 1) var mining_multiplier: int = 1

@export_group("Radar")

## How far one pulse reaches before it dies. Tuned so the creature shows up only as it
## is about to enter your general proximity, not while it is still a room away.
@export_range(10.0, 200.0, 1.0, "suffix:m") var radar_range: float = 80.0

## How fast the wavefront travels outward. Range over this is the sweep, and the HUD's
## four rings are stretched to match, so the outermost ring touches the rim of the dish
## on the frame the pulse touches its range.
@export_range(5.0, 400.0, 1.0, "suffix:m/s") var radar_pulse_speed: float = 80.0

## Seconds from one pulse leaving to the next. Must not be shorter than a sweep --
## checked in invariant_failures().
@export_range(0.25, 20.0, 0.05, "suffix:s") var radar_interval: float = 2.0

## Charge spent the instant a pulse fires. Priced per pulse rather than per second
## because the radar is an event, not a beam.
@export_range(0.0, 20.0, 0.05) var radar_power_per_pulse: float = 0.25

## What a pulse can see. Layer 8, and deliberately nothing else -- an 80 m sphere that
## also masked the hull would test against every wall in the asteroid.
@export_flags_3d_physics var radar_detectable_layers: int = RadarDetectable.LAYER

@export_group("Interaction")

## How far the suit's reach extends. The same order as grab_range on purpose: what you
## can address should be what you could touch, or one press means different things at
## different distances.
@export_range(0.5, 8.0, 0.1, "suffix:m") var interact_range: float = 2.5

## How far off your forward axis something may sit and still be addressed, as a dot
## product. -0.2 is about 101 degrees, so nothing behind you is ever prompted.
@export_range(-1.0, 1.0, 0.05) var interact_min_facing: float = -0.2

## What being off-axis costs, as a multiple of true distance at 90 degrees. 0.0 makes
## selection purely nearest, which is what a plain trigger volume wants.
@export_range(0.0, 8.0, 0.1) var interact_facing_weight: float = 2.0

## The discount the thing already focused gets. Without it, two consoles that score alike
## swap the prompt every frame.
@export_range(0.0, 0.5, 0.01) var interact_focus_stickiness: float = 0.15

## How long the key is held before the press stops being a tap.
@export_range(0.05, 1.0, 0.01, "suffix:s")
var interact_hold_threshold: float = InteractionHold.DEFAULT_THRESHOLD

## What the reach can see. Layer 9, and deliberately nothing else -- a sphere that also
## masked the hull would test against every wall in the asteroid.
@export_flags_3d_physics var interactable_layers: int = Interactable.LAYER

@export_group("Health")

## The damage pool. Only ratios reach the HUD; the debug readout shows points.
@export_range(10.0, 500.0, 5.0) var max_health: float = 100.0

## How intact the suit starts.
@export_range(0.0, 1.0, 0.05) var health_start_fraction: float = 1.0

## Points recovered per second once nothing has hit you for health_regen_delay.
## Deliberately slow: attrition you cannot outheal is what makes depth cost something.
@export_range(0.0, 20.0, 0.1, "suffix:/s") var health_regen_per_second: float = 2.0

## Quiet seconds before the suit starts sealing itself. Suffocation restarts this every
## frame, so recovery does not begin the instant air comes back.
@export_range(0.0, 30.0, 0.5, "suffix:s") var health_regen_delay: float = 6.0

@export_group("Hazards")

## What an empty tank costs per second. This is the suffocation clock's new shape: a
## bad decision becomes survivable-but-expensive instead of fatal on the frame.
@export_range(0.0, 40.0, 0.5, "suffix:/s") var suffocation_damage_per_second: float = 6.0

## Below this a contact is a scrape and costs nothing. Well above PlayerSfx's own
## 0.8 m/s floor on purpose: you hear every knock and are billed only for the hard ones.
@export_range(0.0, 20.0, 0.5, "suffix:m/s") var impact_damage_min_speed: float = 4.0

## What an impact at impact_reference_speed costs. Damage climbs linearly from the
## deadband and is capped at IMPACT_HARDNESS_CAP multiples of this.
@export_range(0.0, 100.0, 1.0) var impact_damage_at_reference_speed: float = 18.0

## What a gas pod costs at the epicentre, falling off to nothing at its blast radius.
@export_range(0.0, 200.0, 1.0) var hazard_gas_pod_damage: float = 35.0

## How wide a gas pod's bubble is across its base. The prefab authors its dome at one
## metre, so this scales it and its two triggers directly.
@export_range(0.1, 4.0, 0.05, "suffix:m") var hazard_gas_pod_diameter: float = 0.9

## How close you may get to a gas pod before it starts counting down, measured from the
## pod's centre.
##
## The band you can occupy WITHOUT already touching it is this minus half the bubble and
## the suit's own hull. Go under that and the contact trigger fires first, the countdown
## never gets a turn, and the entire warning is lost without an error -- which is what
## invariant_failures() checks.
@export_range(0.2, 10.0, 0.1, "suffix:m") var hazard_gas_pod_trigger_range: float = 1.0

## What standing inside a live arc costs per second. Small: the charge is the real bill.
@export_range(0.0, 60.0, 0.5, "suffix:/s") var hazard_arc_damage_per_second: float = 4.0

## What a live arc pulls out of the suit per second. The meter you have been carefully
## managing drops for reasons that are not your fault.
@export_range(0.0, 100.0, 0.5, "suffix:/s") var hazard_arc_power_drain_per_second: float = 20.0

@export_group("Noise")

## How loud full thrust is. There is no silent way to travel.
@export_range(0.0, 20.0, 0.5) var thrust_noise_strength: float = 6.0

## How loud mining is. The loudest thing the player does on purpose. This is the
## strength at the point the beam LANDS -- the cut is what makes the noise.
@export_range(0.0, 20.0, 0.5) var mining_noise_strength: float = 10.0

## How loud the gun itself is, as a fraction of the rock face it is cutting.
##
## Mining reaches the creature as two noises from two places, and this is the split.
## PlayerBeamNoiseEmitter reports the full strength out at the beam endpoint;
## PlayerNoiseEmitter reports this fraction of it at the player's body. Aim across a
## chamber and the alien walks to the wall you were cutting, not to where you stood.
@export_range(0.0, 1.0, 0.05) var mining_muzzle_noise_fraction: float = 0.5

## How loud the hardest impact is.
@export_range(0.0, 20.0, 0.5) var impact_noise_strength: float = 4.0

## The closing speed an impact counts as full strength at.
@export_range(1.0, 30.0, 0.5, "suffix:m/s") var impact_reference_speed: float = 8.0

## How far one unit of noise carries.
@export_range(0.5, 20.0, 0.5, "suffix:m") var noise_metres_per_unit: float = 4.0


## Cross-field rules that a slider can break at runtime. Checked by PlayerView
## on load rather than assumed, because these read as art bugs when violated.
func invariant_failures() -> PackedStringArray:
	var failures := PackedStringArray()
	if camera_far <= fog_depth_end:
		failures.append(
			(
				"camera_far %.1f is not past fog_depth_end %.1f; geometry pops at the clip"
				% [camera_far, fog_depth_end]
			)
		)
	if camera_fov > CAMERA_FOV_NECK_SEAM_LIMIT:
		failures.append(
			(
				"camera_fov %.1f is past %.1f; the suit's open collar comes into view"
				% [camera_fov, CAMERA_FOV_NECK_SEAM_LIMIT]
			)
		)
	if helmet_lamp_range > camera_far:
		failures.append(
			(
				"helmet_lamp_range %.1f reaches past camera_far %.1f; the beam lights nothing there"
				% [helmet_lamp_range, camera_far]
			)
		)
	if radar_pulse_speed > 0.0 and radar_interval < radar_range / radar_pulse_speed:
		failures.append(
			(
				"radar_interval %.2fs is shorter than one sweep (%.2fs); pulses overlap"
				% [radar_interval, radar_range / radar_pulse_speed]
			)
		)
	if tether_rope_draw_radius > tether_rope_radius:
		failures.append(
			(
				"tether_rope_draw_radius %.2f exceeds tether_rope_radius %.2f; the rope will pinch"
				% [tether_rope_draw_radius, tether_rope_radius]
			)
		)
	if suffocation_damage_per_second <= health_regen_per_second:
		(
			failures
			. append(
				(
					"suffocation_damage_per_second %.2f does not beat health_regen_per_second %.2f; running out of air would never kill"
					% [suffocation_damage_per_second, health_regen_per_second]
				)
			)
		)
	if seconds_of_suffocation() < SUFFOCATION_MIN_SECONDS:
		(
			failures
			. append(
				(
					"an empty tank kills in %.1fs, under the %.1fs that keeps suffocation a slope rather than a cliff"
					% [seconds_of_suffocation(), SUFFOCATION_MIN_SECONDS]
				)
			)
		)
	if hazard_gas_pod_damage >= max_health:
		(
			failures
			. append(
				(
					"hazard_gas_pod_damage %.1f is not under max_health %.1f; a pod would kill outright, which only the stalker may do"
					% [hazard_gas_pod_damage, max_health]
				)
			)
		)
	if hazard_gas_pod_trigger_range <= gas_pod_contact_distance():
		(
			failures
			. append(
				(
					"hazard_gas_pod_trigger_range %.2f is not past the %.2f m at which a suit is already touching the bubble; the proximity countdown would never get a turn"
					% [hazard_gas_pod_trigger_range, gas_pod_contact_distance()]
				)
			)
		)
	if seconds_of_arc_drain() < ARC_MIN_DRAIN_SECONDS:
		(
			failures
			. append(
				(
					"an arc empties the suit in %.1fs, under the %.1fs that keeps crossing one a price rather than a sentence"
					% [seconds_of_arc_drain(), ARC_MIN_DRAIN_SECONDS]
				)
			)
		)
	if impact_damage_min_speed >= impact_reference_speed:
		(
			failures
			. append(
				(
					"impact_damage_min_speed %.1f is not below impact_reference_speed %.1f; a reference impact would cost nothing"
					% [impact_damage_min_speed, impact_reference_speed]
				)
			)
		)
	return failures


## Thrust acceleration with sprint folded in.
func thrust_acceleration_for(sprint_engaged: bool) -> float:
	if sprint_engaged:
		return thrust_acceleration * sprint_acceleration_multiplier
	return thrust_acceleration


## The gain look input feeds into angular velocity in INERTIAL mode.
func aim_gain() -> float:
	return mouse_sensitivity * angular_acceleration


## Health one impact costs, priced against the same reference speed the noise uses.
func impact_damage_for(closing_speed: float) -> float:
	return PlayerHealthModel.impact_damage(
		closing_speed,
		impact_damage_min_speed,
		impact_reference_speed,
		impact_damage_at_reference_speed,
		IMPACT_HARDNESS_CAP
	)


## How long an empty tank takes to kill from full health, or INF when it never does.
func seconds_of_suffocation() -> float:
	if suffocation_damage_per_second <= 0.0:
		return INF
	return max_health / suffocation_damage_per_second


## How far from a gas pod's centre a suit is already touching its bubble, which is the
## floor hazard_gas_pod_trigger_range has to clear to leave any countdown band at all.
func gas_pod_contact_distance() -> float:
	return hazard_gas_pod_diameter * 0.5 + hull_radius


## How long a live arc takes to empty a full suit, or INF when it never does.
func seconds_of_arc_drain() -> float:
	if hazard_arc_power_drain_per_second <= 0.0:
		return INF
	return suit_capacity / hazard_arc_power_drain_per_second
