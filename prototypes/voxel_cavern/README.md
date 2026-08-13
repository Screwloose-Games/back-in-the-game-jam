# voxel_cavern

A blocky voxel cavern you mine through — and get hunted in. Three rooms joined by
tunnels, carved out of solid rock, with glowing mineral veins in the walls. You
fly, you carve, and the tentacle crawler hunts you down the wide tunnels. When it
closes in, you dive into the narrow tunnel it can't fit through.

```
godot --path <root> res://prototypes/voxel_cavern/voxel_cavern_prototype.tscn
```

WASD + space/ctrl to thrust, mouse to look, Q/E to roll, shift to sprint,
R to stabilise. **Hold left mouse to fire the mining laser** (it fires from your
right hip and converges on the crosshair). Esc frees the cursor for the tuning
panel.

The cavern generates and the navmesh bakes over the first few seconds — the HUD
reads `alien: navmesh baking...` until the hunt begins.

---

## The layout

- **Room A** — where you spawn.
- **Room C** — where the alien spawns, on the far side.
- **Room B** — the corner between them.
- **Two wide tunnels** (9 m bore) join the rooms the long way, A → B → C. The alien
  is big enough to fit and will chase you down them.
- **One narrow tunnel** (2 m bore) is a direct A → C shortcut. You fit; the alien
  (2.15 m body radius, needs ~6.4 m of width to move) does not, and it isn't even
  in the alien's navmesh. This is your escape.

The alien, its hunting AI, and its wall-crawling navmesh are reused wholesale from
`prototypes/tentacle_crawler_chaser` — the creature senses the world only by
raycasts on the hull layer, so it drops onto the voxel terrain unchanged. It
crawls the walls toward the nearest point to you and never stops. If it gets within
reach, the HUD flashes `CAUGHT`, and after a moment you and the alien reset to your
spawns.

## The mining laser

Hold left mouse and the beam raycasts from the camera. Wherever it lands on terrain
it removes a sphere of voxels twice per second, of diameter
`mining_beam_deformation_diameter`. Each voxel is only removed if its class is
enabled — the two live CheckButtons in the panel:

- **`deform minerals`** — the glowing cyan/gold veins.
- **`deform terrain`** — the plain grey rock.

So you can carve everything, mine only ore, or (to see it) cut only rock and leave
the veins hanging. You can also widen your escape: mine the narrow tunnel bigger and
the alien will eventually fit — a knob on the fantasy, not a bug.

---

## What you can change quickly

**While flying**, from the bottom-left panel: carve diameter, deforms per second,
beam range, and the two deform toggles. **SAVE** writes them to
`voxel_cavern_settings.tres`; **RESET** returns to the `voxel_cavern_knobs.gd`
defaults.

**Between runs**, everything else lives in `voxel_cavern_knobs.gd`: the room
positions and radii, the tunnel widths (wide vs the narrow shortcut), the alien's
speed and size, and — most importantly — `VOXEL_SIZE`.

## A note on scale and performance

This map is much bigger than a pure mining pocket because the alien is ~4.3 m across
and needs 6.4 m+ tunnels to move. That forces a coarser grid: `VOXEL_SIZE` is
`0.4 m`, a compromise between mining detail and a map large enough to host the
chase. Generation and meshing cost scale with roughly `1 / VOXEL_SIZE^3`, and the
**whole** cavern is streamed at once (a single fixed viewer at the map centre) so
the navmesh can bake over the collided terrain — so startup takes a few seconds.
**If the GL Compatibility / web build is slow, raise `VOXEL_SIZE`** (0.5–0.6);
everything else is derived from it. Lower it for finer mining at a heavier startup.

The narrow tunnel is kept out of the alien's navmesh by setting the bake's
`NAVMESH_OPENNESS_RADIUS` above the tunnel's radius, so the alien never even tries
to path the shortcut.

---

## What it deliberately does not have

No ore collection, no inventory, no oxygen or power, no health — being caught just
resets the chase. The mining and the hunt are the two things under test: does
carving feel good, and is being chased through a cavern you can reshape tense?

---

*Technical notes — the layout-driven voxel carve, the selective sphere mining via
`VoxelTool`, the reused chase stack, and the runtime navmesh bake over the voxel
collider — live in the comments of the scripts themselves.*
