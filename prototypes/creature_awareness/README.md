# creature_awareness

Make a noise somewhere in the cave. Watch the alien work out that something happened,
decide it is worth a look, and come.

```
godot --path <repo root> res://prototypes/creature_awareness/creature_awareness_prototype.tscn
```

This is the first scene in the project where **navigation, perception and suspicion are all
in the same room**. Each module was complete and each had its own sandbox, but nothing
anywhere connected a suspicion hotspot to `CreatureNavigation.set_goal` — that layer is
deliberately not shipped, on both sides. `creature_awareness_behaviour.gd` is that layer,
and it is the only genuinely new code here. **Nothing under `gameplay/creature/` is
touched.**

## Controls

| | |
|---|---|
| **LMB, held** | perform the selected activity where you point — drag to move it |
| **Q / E** | EVA thrust · mining |
| **Tab**, or **1 2 3** | camera: free fly · ant farm · follow |
| WASD / Space / Ctrl | thrust · **Q/E** roll · **Shift** sprint · **Esc** release the mouse |
| F1 / F2 / F3 | world graph · locomotion · belief |
| R | rebake |

The activity streams for as long as the button is down. That matters — see
[the cliff](#one-is-ignored-five-in-a-row-become-a-lead).

## What to try, in order

1. **Ant farm camera.** The near rock is culled away and the whole level is open to you at
   once: three caverns, both tunnels, the player shaft. It is the only view that shows the
   alien and your stimulus at the same time, which is the comparison the whole scene is
   about.
2. **Hold mining in a cavern the alien is not in.** The readout walks down the chain as it
   happens — heard → evidence → hotspot → above threshold — and the alien leaves its nest.
3. **Notice it does not go where you clicked.** The orange marker is the true position; the
   hotspot it commits to is somewhere else. Hearing displaces what it reports by up to the
   uncertainty radius, so a consumer that reads `position` and ignores `uncertainty_radius`
   cannot get an omniscient alien for free. Drag `hearing_jitter` to 0 if you want them to
   coincide while you debug something else.
4. **Let it arrive.** It searches, finds nothing, and the belief decays until the hotspot is
   dropped. Then it goes back to wandering. Behaviour never lowers a number — the alien
   resolves a hotspot by *looking*, which makes perception emit a disconfirmation.
5. **Hold near the alien, then far.** The near hotspot is visibly tighter. If they look the
   same, hearing is handing suspicion exact coordinates and everything above it is
   pointless.
6. **Ping in the loft**, above the Dock. The route comes back PARTIAL, the alien stops at
   the mouth of the 1 m shaft, and it searches from there without ever resolving what is
   above it. Fly up yourself to prove the opening is real.

## The map

Three 40 m caverns and a loft, joined by the four passage classes.

```
                    Loft  (player only)
                     ║ 1 m shaft
                     ║
 Warren ══════════ Dock ═════ 4 m swim ═════ Gallery
       2 m squeeze
```

| | bore | who fits |
|---|---|---|
| swim tunnel | **4 m** | the alien, swimming |
| squeeze | **2 m** | the alien, compressed |
| player shaft | **1 m** | you, and nothing else |

Sized against the shipped `ClearanceProfile`: the normal body needs 2.5 m, the squeezed body
1.5 m, your hull 0.8 m. A player-only tunnel is not a flag — it is simply narrower than the
alien, so no edge is ever validated through it.

**4 m is a better swim tunnel than the shipped demo's 6 m**, which is the opposite of what
that demo suggests. `tunnel_enclosure_reach` is 3 m and the fan is ten rays, so 4 m reads
0.70 enclosure against a 0.60 gate. At 6 m the lateral rays land exactly at the reach limit,
enclosure collapses to 0.40, and the demo only swims through a fallback — `nav_local_planner`
documents a body found stalled because of it. The docstring on `tunnel_enclosure_reach` still
describes a six-ray fan and is stale.

## Three things that are not obvious

**Every bore's centre line is on even world coordinates.** The candidate lattice snaps to
world multiples of `candidate_spacing` (2 m) and the flood steps between adjacent cells, so a
passage that misses the lattice contains no candidate and does not exist to the graph. Moving
a tunnel one metre is how you delete it.

**The caverns contain pillars and a bridge, and they are load-bearing.** Decimation sorts by
clearance descending and the clearance ceiling is 6 m, so everything past 6 m from a wall ties
and nodes scatter through the empty middle of a 40 m sphere. The centre is 20 m from any wall
against a crawl reach of 3.5. Without structure, crossing a cavern is one long leap; with it,
short hops. **Expect to see leaping — that is correct for a room this size.**

<a name="one-is-ignored-five-in-a-row-become-a-lead"></a>
**One is ignored, five in a row become a lead.** A single pulse only becomes a hotspot if its
received strength clears about 0.204. Below that, hearing still emits evidence and suspicion
still stores it — it just decays before it can matter. Holding accumulates. That is why the
input is press-and-hold and not a click.

Related, and measured the hard way: `hearing_max_range` is **120 m** here, not the module's
40. Range does not only decide what is audible, it decides *confidence*, and confidence is
what keeps a record above `evidence_min_retention_strength` long enough to accumulate at all.
At 90 m a stimulus 60 m away arrived at confidence 0.06 and was pruned about three seconds
later; held for twenty seconds it produced **no hotspot whatsoever**. At 120 m the intended
distinction survives: one pulse at 60 m forms a visible hotspot but stays under the
investigate threshold, and holding carries it over.

## What it deliberately does not have

No hunting, no chase, no player detection — the alien has no eyes on you and hearing never
attributes a source, so every hotspot is anonymous. No mining: the "mining" stimulus is a
noise, not a carve, so the graph never changes and `notify_terrain_changed` is not exercised.
No director, no menace pacing. The behaviour FSM covers `behavior.md` §24 and §25 and stops
there.

## Checking it still works

```
godot --headless --path . res://prototypes/creature_awareness/tools/verify_creature_awareness_runtime.tscn
```

Twelve checks: the four passage classes, then the chain end to end — one pulse is not enough,
a held one is, the alien commits, its goal is not the world origin, and a route exists. Run
it as the `.tscn`; a node added during `SceneTree._initialize()` never gets `_ready()`, so
`--script` on the `.gd` prints nothing and exits 0, which looks exactly like a pass.

Numbers live in `creature_awareness_knobs.gd`, and the ones worth arguing about while playing
have sliders.
