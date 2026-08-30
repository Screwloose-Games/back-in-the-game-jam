# Creature Suspicion

The alien's memory. It turns Perception's momentary observations into a persistent,
decaying, **spatial** belief about where player activity is happening — and answers
exactly one question:

> Given everything I have perceived recently, what do I currently believe is worth
> investigating, and where?

It does not decide what to do about it. Behavior reads the answer and picks an action.

Spec: [`documentation/design/alien/suspicion.md`](../../../documentation/design/alien/suspicion.md).

```
        CreaturePerception
              │
   evidence_observed / disconfirmation_observed
              │
        CreatureSuspicion
              │
   ┌──────────┼──────────────┐
   ▼          ▼              ▼
evidence   hotspots     player beliefs
 memory
   └──────────┼──────────────┘
              ▼
        Behavior   Director
```

## Running the suites

```sh
GODOT=/path/to/Godot   # 4.7.x

# A new class_name does not resolve until the project is re-imported, and the same
# run generates the .uid sidecars the static suite checks for.
$GODOT --headless --path . --import

$GODOT --headless --path . -s addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json -gexit
$GODOT --headless --path . --script res://gameplay/creature/suspicion/tools/verify_suspicion_static.gd
$GODOT --headless --path .         res://gameplay/creature/suspicion/tools/verify_suspicion_runtime.tscn
```

**Do not trust `-s`'s exit code on its own.** `godot -s <path>` with an unresolvable
script prints one ERROR line and exits **0**. `.github/workflows/test-gdscript.yml`
greps the output for that reason.

**The runtime suite must be run as its `.tscn`.** A node added during
`SceneTree._initialize()` never receives `_ready()`, so `--script` on
`verify_suspicion_runtime.gd` runs nothing, prints nothing and exits 0.

## Looking at it

```sh
$GODOT --path . res://gameplay/creature/suspicion/sandbox/suspicion_sandbox.tscn
```

The sandbox instantiates the **perception** sandbox whole and bolts the belief layer
on top of it — the room, the player and the creature all come from there. Keys `1`–`4`,
`WASD`, `V`, `G`, `[`, `]` and `Tab` are the perception sandbox's; this scene adds:

| Key | |
|---|---|
| `5` | **Search where Suspicion says.** Behavior's half of the investigate loop, played by hand. |
| `L` | toggle the alertness feedback loop |
| `R` | forget everything |
| `Y` | toggle the belief overlay |

Press `2` next to a wall to drill, then `5` repeatedly. Two things are worth watching,
and neither is checkable any other way:

- **The hotspot from a muffled noise must be visibly wider than the one from a clear
  one** — 6.6 m against 2.3 m at the shipped defaults. If they look the same, the
  uncertainty kernel is not being applied and the alien has been handed exact
  coordinates.
- **The white spike must move** as you search. It marks the best unresolved location.
  If it stays put while the sample crosses around it go cold, disconfirmation is
  reaching the suppression field but not the sampling.

## The model, in three lines

```
support(p)      = Σ evidence    strength · confidence · sense_weight · e^(−decay·age) · kernel(p)
suppression(p)  = Σ searches    strength · e^(−recovery·age) · coverage(p)      (clamped to 1)
unresolved(p)   = support(p) · (1 − suppression(p))
```

Everything else is derived from those. `kernel` falls off over the observation's
`uncertainty_radius`, which is the load-bearing part: a noise reported with a 12 m
radius spreads its belief over a wide shallow area, and a sighting reported with 0.25 m
concentrates it. Read `position` and ignore `uncertainty_radius` and the alien becomes
omniscient for free.

Hotspots are rebuilt from the live evidence several times a second, and carry exactly
one thing across the rebuild: their `id`, matched by shared contributing evidence.
Nothing stores which parts of a hotspot have been searched — that is answered from the
disconfirmation records at query time, so a hotspot that moves cannot drag stale
"already searched" marks along with it.

## Four deliberate deviations from the spec

**`SuspicionEvidence` is Perception's name, not ours.** The spec declares a type by that
name here; Perception already declares it at
`perception/observations/suspicion_evidence.gd` as the wire DTO it emits, and Godot's
`class_name` table is flat and project-wide, so the second declaration is a hard parse
error at project scan that takes the whole project down. Suspicion consumes Perception's
type and wraps it in **`SuspicionEvidenceRecord`**. Perception's README reserves the
name explicitly.

**Decay runs from arrival, not from `observed_at`.** The spec implies one shared
timeline. `CreatureSuspicion.clock` and `CreaturePerception.clock` both start at 0.0
when their node is constructed, so they agree only if the two nodes were built on the
same frame — which nothing guarantees. Each record is stamped with `received_at` on
Suspicion's own clock and decays from that; `observed_at` is kept as data. The failure
this avoids is silent: evidence would arrive pre-decayed or with negative age, and the
creature would be inexplicably forgetful with nothing in the log.

**The thin-cave-wall rule is a `Callable`.** `require_same_spatial_region_for_merge`
needs someone to say which region a point is in, and Spatial Memory does not exist yet.
`CreatureSuspicion.region_resolver` takes a `func(Vector3) -> int`; unset means every
point is in the same region and the flag does nothing. That keeps the rule expressible
without Suspicion ever owning geometry or touching the physics server — which is what
`verify_suspicion_static.gd` enforces.

**Sub-hotspot resolution is derived, not stored.** The spec's diagram shows a fixed
cloud of samples with per-sample "resolved" marks. Storing those means migrating them
every time a hotspot moves or grows, and hotspots move by design. The persistent state
is evidence records plus disconfirmation records; samples are generated on demand from
a deterministic Fibonacci lattice and scored on the spot.

## Rules the code enforces on itself

`tools/verify_suspicion_static.gd` fails the build on each of these, because every one
would otherwise pass all 74 unit tests while destroying the property the tests exist to
protect:

| Rule | Why |
|---|---|
| **No file in the model reads world state** — no groups, no `get_node`, no `global_position`, no `Area3D` | The analogue of perception's physics seam, and the highest-value check here. An alien that peeks at a player's transform to sharpen a hotspot **works visibly better** while destroying the entire design, and no behavioural test would flag it. The overlay and sandbox are exempt and named. |
| No physics query anywhere | There is no probe in this module and there is not meant to be one. |
| Nothing reads a wall clock | `CreatureSuspicion.clock` is fed from the delta it is handed. `Time.get_ticks_msec()` ignores `get_tree().paused` and `Engine.time_scale`, so belief would decay in a paused game, and no test could drive it. |
| No `reduce_suspicion` / `clear_hotspot` / `mark_investigation_complete`, anywhere | Belief changes through evidence or not at all. Behavior makes the creature investigate; Perception observes the result. |

`mark_unreachable(hotspot_id)` is the one method that looks like a breach and is not. It is a
claim about the **creature**, not about the world: *I could not get there.* It subtracts
nothing, suppresses no evidence, and leaves `get_overall_suspicion`, `get_suspicion_near`,
`get_hotspot` and `get_hotspots` reading exactly what they read before — `tests/test_unreachable.gd`
asserts every one of those. All it does is stop the two LEAD queries, `get_strongest_hotspot`
and `get_hotspots_above`, offering that place as somewhere to walk, for
`unreachable_suppression_s`.

It exists because without it an alien re-selects a lead it physically cannot reach on the tick
after it gives up, forever — lead selection takes the strongest entry and has no memory. And
the suppression is keyed by **position, not by hotspot id**, because identity is carried by
shared contributing evidence: a lead that decays out and re-forms from the next noise is a new
id at the same spot, and an id-keyed suppression would lift itself the moment the player made
another sound.
| No behavioural or perceptual commands | Suspicion describes belief. It does not request scans, transition an HFSM or select a target. |
| Every `.gd` has its `.uid` sidecar | A missing one is regenerated with a fresh id, and scenes referencing the script by uid then point at nothing. |
| The overlay sets `vertex_color_use_as_albedo` | Godot does not infer it. Without it the overlay renders flat white and a hotspot the creature is certain about looks exactly like one it has already searched. |
| Scenes load, instantiate **and keep their script** | A `.tscn` whose script fails to parse still instantiates, scriptless, and reports as fine. This check caught exactly that while the sandbox was being written. |

`tests/test_suspicion_invariants.gd` covers the rest — including a sweep of
`get_script_method_list()` asserting the facade has grown no `set_*` / `add_*` /
`apply_*` method, because belief having a fourth door is the failure that makes every
other rule here decorative.

## Wiring one up

```gdscript
var suspicion := CreatureSuspicion.new()
suspicion.config = preload("res://.../my_creature_suspicion.tres")
add_child(suspicion)

perception.evidence_observed.connect(suspicion.submit_evidence)
perception.disconfirmation_observed.connect(suspicion.submit_disconfirmation)

# Optional. Suspicion feeds alertness back as READ-ONLY context: it changes how hard
# perception looks, never what it finds.
perception.set_alertness_context(suspicion.get_overall_suspicion())

# Optional. Once Spatial Memory lands, this is where the thin-cave-wall rule plugs in.
suspicion.region_resolver = spatial_memory.region_id_at
```

Behavior reads and then acts on its own thresholds — Suspicion transitions nothing:

```gdscript
if suspicion.get_overall_suspicion() > my_investigate_threshold:
    var hotspot := suspicion.get_strongest_hotspot()
    var where := suspicion.get_best_unresolved_location(hotspot.id)
    navigation.set_goal(where)
    perception.request_activity_scan(AABB(where - Vector3.ONE * 4, Vector3.ONE * 8), 1.0)
    # ...and the disconfirmation that search produces is what lowers the suspicion.
    # Nothing here tells Suspicion the area is clear.
```

The Director reads who, and applies its own stickiness and pacing:

```gdscript
var candidate := suspicion.get_best_player_candidate()   # a candidate, not a target
```

## Tuning

`SuspicionConfig` is the whole memory dial, the way `PerceptionConfig` is the whole
difficulty dial. Decay rates are per-second exponential; think in half-lives
(`half_life = 0.693 / rate`). The shipped defaults give hearing ~12 s, vision ~20 s and
touch ~6 s — contact is the strongest evidence there is and the fastest to go stale.

Two numbers are calibrated against the spec's own worked example rather than picked by
feel: `hotspot_saturation_rate = 3.0` puts a clear nearby drill at ~0.81, against the
spec's "strength .90 → hotspot .84". And `evidence_min_retention_strength = 0.005` sits
far below anything that could form a hotspot alone, so a drill heard faintly through a
wall (~0.02) is *remembered but not acted on* — one is ignored, five in a row become a
lead. Raise it to hotspot strength and a player can drill through a wall forever
without ever being noticed.

## Not included

Behavior, the HFSM and the Director; Spatial Memory and therefore a real
`region_resolver`; and any `.tres` config presets — every field has a working default,
so `SuspicionConfig.new()` runs without one.
