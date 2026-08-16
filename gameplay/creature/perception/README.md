# Creature Perception

The alien's controlled interface to the authoritative game world. It converts real
world state into imperfect, localized **observations**, and nothing else in the AI
is allowed to read reality directly.

Spec: [`documentation/design/alien/perception.md`](../../../documentation/design/alien/perception.md).
Section numbers below refer to it.

```
        world (noises / players / terrain)
                      │
                 CreaturePerception
                      │
        ┌─────────────┴─────────────┐
        ▼                           ▼
  evidence_observed           geometry_observed
  disconfirmation_observed
        │                           │
     Suspicion                Spatial Memory
```

## Running the suites

```sh
GODOT=/path/to/Godot   # 4.7.x

# A new class_name does not resolve until the project is re-imported, and the same
# run generates the .uid sidecars the static suite checks for.
$GODOT --headless --path . --import

$GODOT --headless --path . -s addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json -gexit
$GODOT --headless --path . --script res://gameplay/creature/perception/tools/verify_perception_static.gd
$GODOT --headless --path .         res://gameplay/creature/perception/tools/verify_perception_runtime.tscn
```

**Do not trust `-s`'s exit code on its own.** `godot -s <path>` with an unresolvable
script prints one ERROR line and exits **0**. `.github/workflows/test-gdscript.yml`
greps the output for that reason.

**The runtime suite must be run as its `.tscn`.** A node added during
`SceneTree._initialize()` never receives `_ready()`, so `--script` on
`verify_perception_runtime.gd` runs nothing, prints nothing and exits 0.

## Looking at the overlay

Every geometric assertion in `tests/` and `tools/` passes against a debug draw that
renders as nothing at all, so the only check on the section 30 overlay is looking at
it. Either drive it by hand:

```sh
$GODOT --path . res://gameplay/creature/perception/sandbox/perception_sandbox.tscn
```

or render the six canonical shots to `user://` (**not** `--headless` — there is no
framebuffer to read back in that mode):

```sh
$GODOT --path . res://gameplay/creature/perception/tools/capture_sandbox.tscn
```

The pair worth checking every time is `03_noise_near_drill` and
`04_noise_far_footstep`. Nearby drilling must draw a visibly **tighter** uncertainty
sphere than distant footsteps — 2.7 m against 9.6 m at the shipped defaults. If those
two shots look the same, hearing is handing Suspicion magically precise coordinates
and the whole searching layer above it has nothing to do.

Three defects were found by looking at these and by nothing else: a passive scan
costing 1728 shape queries every half second, geometry cells evicting every piece of
evidence from the overlay's ring buffer, and a thorough search emitting one
maximum-strength record *per sample* for a single stationary player.

## Three deliberate deviations from the spec

**Output is signals, not direct calls.** Sections 20–21 describe
`suspicion.submit_evidence(...)` and `spatial_memory.observe_geometry(...)`. This
module emits `evidence_observed`, `disconfirmation_observed` and `geometry_observed`
instead, and consumers connect. When those two systems land, the spec's call API is
a four-line adapter. The architectural rule the spec cares about — that the two
channels never cross — is asserted in `tests/test_dispatch.gd` either way.

**The senses are prefixed.** `CreatureHearing`, `CreatureVision`, `CreatureTouch`,
`CreatureGeometryPerception` rather than section 4's `Hearing` / `Vision` / `Touch`.
Godot's `class_name` table is flat and project-wide, `Vision` and `Touch` are
plausible names for unrelated things in a web-first project, and a collision is a
parse failure across the whole project rather than a warning. Section 4 calls its
own list "recommended internal structure".

**Hearing displaces the position it reports.** Section 11 asks for spatial
uncertainty; reporting a *true* position alongside a 12 m radius means any consumer
that reads `position` and ignores `uncertainty_radius` gets a perfectly omniscient
alien for free. `PerceptionConfig.hearing_position_jitter` controls it and
`CreatureHearing.rng` is seedable, so tests stay deterministic. Set the jitter to
`0.0` for exact reporting.

## Two names this module reserves project-wide

`suspicion.md` §8 and `spatial_memory.md` §8 each re-declare a type this module
already declares. Godot's global class table is flat, so **the second declaration is
a hard parse error at project scan**, not a warning:

- `SuspicionEvidence` — owned here, as the wire DTO. Suspicion's internal decaying
  record needs a different name (`SuspicionEvidenceRecord`).
- `GeometryObservation` — owned here. Spatial Memory should consume this type rather
  than declaring its own.

`DisconfirmationObservation` and `NoiseEvent` are likewise owned here.

## Rules the code enforces on itself

`tools/verify_perception_static.gd` fails the build on each of these, because every
one of them would otherwise pass all 123 unit tests while destroying the property
the tests exist to protect:

| Rule | Why |
|---|---|
| Only `perception_probe.gd` may name a physics query | The seam is what lets every other file be tested with no physics server. Erode it and the fast suite quietly stops covering anything. |
| Nothing reads a wall clock | `CreaturePerception.clock` is fed from the delta it is handed. `Time.get_ticks_msec()` ignores `get_tree().paused` and `Engine.time_scale`, and cannot be driven from a test. |
| No behavioural or navigation commands | Section 31. `increase_suspicion`, `start_hunting`, `NavigationAgent3D` and friends would couple sensing to interpretation. |
| The overlay sets `vertex_color_use_as_albedo` | Godot does not infer it. Without it the whole overlay renders flat white and every colour encoding silently disappears. |
| Every `.gd` has its `.uid` sidecar | A missing one is regenerated with a fresh id, and scenes referencing the script by uid then point at nothing. |

`tests/test_perception_invariants.gd` covers the rest of sections 28 and 31 —
including a property-list sweep asserting perception declares no remembered state,
because a field named `last_known_position` would make the alien omniscient in a way
no behavioural test catches. The creature would simply start working better.

## Wiring one up

```gdscript
var perception := CreaturePerception.new()
perception.config = preload("res://.../my_creature_perception.tres")
perception.candidate_group = &"perceivable"      # or set `targets` explicitly
add_child(perception)

perception.evidence_observed.connect(suspicion.submit_evidence)
perception.geometry_observed.connect(spatial_memory.observe_geometry_batch)

# Suspicion feeds alertness back as READ-ONLY context (section 14): it changes how
# hard the creature looks, never what it finds.
perception.set_alertness_context(suspicion.get_overall_suspicion())
# ...unless Behavior is wired up, in which case IT owns this line and publishes a per-state
# value instead (fsm.md's tick contract, step 6). Do not do both: the last writer of the
# frame wins, and which one that is depends on node order.
```

Noises are pushed in — nothing polls for them:

```gdscript
perception.receive_noise(NoiseEvent.make(drill.global_position, 1.0, &"drill", drill, player))
```

Behavior and Navigation ask perception to **observe**, never to conclude:

```gdscript
perception.request_activity_scan(region, thoroughness)   # section 23
perception.request_geometry_scan(region, CreatureGeometryPerception.GeometryScanReason.PATH_BLOCKED)
```

Both always complete, even when the sense involved is disabled or the probe is
unbound — otherwise a request-then-poll loop hangs forever on a config flag with
nothing in the log. An aborted scan reports a **zero-strength** disconfirmation, so
it clears nothing.

## Not included

Suspicion and Spatial Memory themselves; any noise-emitting producer (the sandbox
emits `NoiseEvent`s by keypress); and rewiring `prototypes/tentacle_crawler_chaser`,
whose `ChaseTarget` still reads `quarry.global_position` directly — exactly the
omniscience section 3 forbids, and the natural first customer for this module.
