# voxel_cavern

A blocky rock body you spawn *inside*, built to answer one thing: **what does it
feel like to carve mineral veins out of a voxel cavern with a mining laser?**

Every surface is a voxel face, so everything the beam touches — walls, veins, the
hole you just made — is perpendicular and stair-stepped. The rock is threaded with
glowing mineral veins, and the laser can be set to eat the rock, the ore, or both.

```
godot --path <root> res://prototypes/voxel_cavern/voxel_cavern_prototype.tscn
```

WASD + space/ctrl to thrust, mouse to look, Q/E to roll, shift to sprint,
R to stabilise, escape to release the mouse. **Hold left mouse to fire the laser.**

Press **escape** and use the panel in the bottom left to change the laser while you
fly.

---

## The questions it exists to answer

- Does carving into a wall and following a vein feel **satisfying**, or fiddly?
- Is a sphere-shaped bite out of a cubic wall a good "dig", or does it read wrong?
- Twice a second is the deform rate — does the beam feel like it's *working*, or
  like it's lagging behind you?
- With **deform terrain off**, the laser removes only ore and leaves the rock — a
  clean "mining laser only cuts the valuable stuff" fantasy. Does that read, or is
  ore-only mining more frustrating than freeform digging?

## How the laser works

Hold left mouse and the beam raycasts from the camera. Wherever it lands on
terrain it removes a sphere of voxels **twice per second**, of diameter
`mining_beam_deformation_diameter` (the sphere radius is half that). Each voxel in
the sphere is only removed if its class is enabled:

- **`deform minerals`** — the glowing cyan/gold veins.
- **`deform terrain`** — the plain grey rock.

Both are live CheckButtons in the panel, so you can flip between "cut everything",
"cut only ore", and "cut only rock (leave the veins floating)" without a restart.

---

## What you can change quickly

**While flying**, from the bottom-left panel: carve diameter, deforms per second,
beam range, and the two deform toggles. **SAVE** writes them to
`voxel_cavern_settings.tres` (committed); **RESET** returns to the
`voxel_cavern_knobs.gd` defaults; deleting the `.tres` runs on those defaults again.

**Between runs**, everything else lives in `voxel_cavern_knobs.gd`: the world size,
the spawn chamber, the vein noise, and — most importantly — `VOXEL_SIZE`.

## A note on voxel size and performance

`VOXEL_SIZE` is `0.06 m` — a deliberately fine grid, so the walls read as detailed
rather than as big Minecraft cubes. That is expensive: generation and meshing cost
scale with roughly `1 / VOXEL_SIZE^3`, and the world is kept small (a 5 m rock
body) and the view distance short (4 m, hidden by fog) to pay for it. **If the
GL Compatibility / web build can't hold framerate, raise `VOXEL_SIZE` first**
(0.12–0.25 m) — everything else is derived from it.

---

## What it deliberately does not have

No ore collection, no inventory, no oxygen or power, no structural collapse, no
enemies, no objective. The laser removes voxels and nothing else happens — the
question is only whether *removing* them feels good.

---

*Technical notes — the generator, the selective sphere carve via `VoxelTool`, and
the voxel-space coordinate conversion — live in the comments of the scripts
themselves.*
