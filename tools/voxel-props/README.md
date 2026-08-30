# Voxel prop generator

Four hard-surface props for the mine — a handheld mining laser, an industrial
elevator car, the hoist frame it runs in, and the wall switch that drives it —
built procedurally and written straight out as glTF.

```
python tools/voxel-props/build_props.py                  # write the set
python tools/voxel-props/build_props.py --list           # measurements only
python tools/voxel-props/build_props.py --only sm_wall_switch
```

| | |
|---|---|
| Voxel size | 0.06 m |
| Surfacing | 64×64 indexed palette PNG, one per prop, sampled at swatch centres |
| Output | 0.30–6.24 m, 142–1696 tris |
| Pivot | bottom-centre, except the wall switch (centred on its mounting plate, on the wall plane) |

| Prop | Built | Tris | Meshes |
|---|---|---|---|
| `sm_mining_laser` | 0.30 × 0.66 × 1.14 m | 222 | `cutter_body`, plus `muzzle_point` / `fore_grip_point` / `rear_grip_point` anchors |
| `sm_elevator_car` | 3.72 × 3.18 × 3.72 m | 1696 | `car_shell`, `door_left`, `door_right` |
| `sm_elevator_shaft` | 6.24 × 2.64 × 6.24 m | 386 | `shaft_base`, `shaft_post`, `shaft_beam`, `shaft_hood` |
| `sm_wall_switch` | 0.60 × 0.96 × 0.48 m | 142 | `switch_housing`, `switch_paddle` |

`sm_elevator_shaft` is the one file here that is **not** an object. It is a parts
sheet: a shaft's height and its beam pitch are level-design knobs, so what is baked
is one 0.60 m column tile, one cross member, one collar and one pad, each about its
own origin, and `prefabs/environment/elevator/elevator_shaft.gd` assembles them.
Its declared size is the reference assembly the lattice lays out, not a shaft.

That is also why its column tile carries no colour that varies along Y: the prefab
**scales** one tile to the full height rather than stacking tiles, so a band across
Y would smear. An I-beam has no detail along its length, so the scaled instance is
seamless and costs forty triangles where a 30 m stack would cost four thousand. The
rhythm comes from the beam rings, which are not scaled — which is why every hazard
accent lives on them and on the pad.

Deterministic: the same recipes always produce the same bytes, so regenerating is
a no-op in git unless a recipe changed.

## Style: matching the character

`assets/art/character/sk_player_character.gltf` is the reference, and two facts
about it are load-bearing. Both were measured off its buffer, not assumed.

**It sits on an exact 0.06 m lattice.** Every vertex coordinate in
`sk_player_character.bin` is a multiple of 0.06, and every normal is one of six
axis-aligned directions. The figure is 26 voxels tall. Everything here is on the
same grid, including the elevator car, which is why the character standing in its
doorway reads as the same world and not as two art styles in one frame.

**Its texture is a palette, not a texture map.** The 64×64 PNG is sampled by
eleven distinct UV pairs, all of which decode to texel coordinates congruent to 2
mod 4 — a 16×16 grid of 4×4-texel swatches, each lookup landing on a swatch
centre with two texels of clearance. That margin, not the precision of the
coordinate, is what makes the scheme survive a filter. Reproduced here exactly.

Two things about that file are **not** worth copying:

- Its node chain carries a −90° X rotation, a Z-up export with the conversion
  left on the nodes. It has no `.spec.yaml`, so nothing checks it — give it one
  and `unapplied_transforms` fails immediately. Do not take its file structure as
  a model.
- `t_player_character.png` does not match the `texture_map` naming pattern in
  `pipeline.yaml` (no map descriptor). That rule is review-enforced, so nothing
  fails today. The textures here are `t_{object}_basecolor.png`.

## No Blender

Every face of a voxel model is axis-aligned and every vertex is a multiple of the
voxel size. Writing the glTF directly is the only way to guarantee both without
trusting an exporter's Y-up conversion and float round-trip — `Object > Apply`
cannot be forgotten if there is no object. It is also what
`gltf_transforms.py` demands: it hard-fails a node scale off 1.0 by more than
1e-3, so the metres conversion has to live in the mesh data, and it does.

The trade is that nothing here is hand-editable in a DCC. Change a recipe and
rebuild; do not open the glTF and push vertices, because the next run overwrites
it.

## Why this is not `tools/voxel-rubble/`

The rubble generator grows its shapes out of noise and erosion — its own README
says "a recipe is not a shape", which is why it walks seeds until one comes out
acceptable. These props are designed, not grown, so the recipe **is** the shape:
additive boxes, subtractive cuts and repaints, applied in order.

The two also surface differently, and that is the sharper split. Rubble bakes
occlusion into `COLOR_0`, which glTF defines as **linear**. A palette lands in a
`baseColorTexture`, which glTF defines as **sRGB**. Running the rubble's
`_srgb_to_linear` on palette bytes would wash every prop out, so the one function
that looks most reusable is the one that must not be.

What genuinely overlaps is `_greedy_rects` and the `_FACES` winding table, about
thirty lines, re-derived here in `mesher.py`. Extracting them into a shared module
would mean regenerating ten committed rubble meshes to prove the bytes did not
move — more work than re-deriving thirty lines, and more risk. If someone later
wants the shared package, the right shape is a `tools/voxelkit/` (no hyphen, so
it imports) with both generators moved behind a byte-identical-output test.

## The authoring format

A prop is a list of named **parts**; each part is an ordered list of ops over an
integer voxel lattice, resolved into `{(x, y, z): colour_name}`. Coordinates are
inclusive at both ends, because these are hand-typed off a drawing and a
half-open range turns every measurement into an off-by-one.

```python
Box(0, 0, 0, 9, 3, 5, "steel")      # fill, overwriting
Cut(2, 1, 1, 7, 3, 4)               # carve
Paint(0, 3, 0, 9, 3, 5, "hazard")   # recolour what is already there; adds nothing
Stripe(..., "hazard", "hazard_dark", pitch=3, axes="xy")   # diagonal chevrons
Stripe(..., "steel", "steel_dark",  pitch=8, axes="z")     # straight panel lines
MirrorX()                           # mirror everything so far
```

Colour is per **voxel**, not per face. A 3-voxel wall paints its inner layer and
its outer layer separately, which is how voxel art works anyway; a 1-voxel panel
cannot have two faces, which is a constraint worth knowing before designing one.

`Paint` adding nothing is what makes the elevator's doorway frame a single op: the
rect covers the opening as well, but the opening was already cut, so what survives
is exactly the surround.

**Chevrons are expensive; straight banding is not.** A diagonal breaks every
greedy run it crosses. Chevrons are for the doorway and the skirt — the places
that have to shout — and straight `Stripe` with one axis named is for hull panel
lines. A 4×4 patch of chevron does not read as chevron at all; it reads as damage.

## Articulation

Everything is a scene root at identity. There is no wrapper node: Godot's importer
already names the scene root after the file and hangs the glTF's roots off it.

- **Sliding parts carry no transform.** The elevator's leaves are authored closed
  and in place, so a container scene opens them by moving `position.x` away from
  zero. Fully open is ∓1.08 m.
- **Rotating parts carry a translation only.** The switch's paddle is authored
  about its hinge, and its node holds the offset out to it, so a container rotates
  `rotation.x` and the paddle swings. `.claude/rules/3d-assets.md` blesses exactly
  this — an axis-aligned pivot is expressible as a translation, a raked one is not
  and would have to be a `Marker3D` in the `.tscn`. A translation is reported by
  the validator and never failed; a rotation is failed at 0.5°.
- **Anchors are mesh-less Empties.** `muzzle_point`, `fore_grip_point` and
  `rear_grip_point` on the laser.
  Nothing in `validate-model-files.py` can see a node with no mesh — the
  measurement skips it, the transform check only keeps paths that reach a mesh,
  the axis check ignores roots that never do. That is what makes them free, and it
  is why `verify_props_import.gd` asserts them instead. They exist so the beam and
  the hands track the art: a `Marker3D` placed by hand in the prefab desyncs the
  first time a recipe moves the emitter. Both grips are named because the tool is
  two-handed and the ends are not interchangeable — the rear one is the trigger
  hand, and the character's `BoneAttachment3D` offset is derived from it.

**The beam is not in the laser file.** The aperture carries an emissive material
so the tool reads as powered with the beam off; the beam itself is a runtime
effect spawned at `muzzle_point`.

## Two importer defaults that destroy this art

`--patch-imports` fixes both. Like `build_rubble.py`, it only ever **edits a
sidecar Godot has already written, never creates one** — an `.import` carries a
uid and a content-hashed destination path only the engine can produce, so a
fabricated sidecar is worse than a missing one.

**`detect_3d/compress_to=1` on the palette PNG.** The first time a 3D material
binds the texture, Godot re-imports it with VRAM compression, and `project.godot`
has `import_etc2_astc=true`. ETC2 compresses in 4×4 texel blocks. The palette
*is* a 4×4 texel block grid. Every swatch would become an average of itself. This
fires only after the art has already looked correct once, which is what makes it
the worst line in the tool.

**`meshes/generate_lods=true` on the model.** Every triangle here has zero UV
area — all three corners share one lookup. LOD simplification welds vertices, and
a weld across a colour boundary drags a corner onto a different swatch, so a prop
changes colour at distance. There is nothing to gain either way at 1700 triangles.

(`meshes/ensure_tangents` goes off with it: tangents from degenerate UV triangles
are undefined, and the warnings hide real ones.)

## The build loop

Godot is `D:\Godot_v4.7.1-stable_win64.exe` — not `godot.cmd`, which eats
arguments. The preview is not `--headless`, and must name its scene or the main
menu boots.

1. Edit a recipe in `build_props.py`
2. `python tools/voxel-props/build_props.py`
3. `python .github/scripts/validate-model-files.py <the three .gltf files>`
4. `<godot> --headless --path . --import`
5. `python tools/voxel-props/build_props.py --patch-imports` (new files only)
6. `<godot> --headless --path . --import` again, if step 5 patched anything
7. `<godot> --headless --path . --script res://tools/voxel-rubble/make_container_scenes.gd -- <res:// asset dir>`
8. `<godot> --headless --path . --script res://tools/placeholder-art/make_prefab_scenes.gd -- <res:// asset dir> <res:// prefab dir>`

Steps 7 and 8 create only what is missing, so running the loop after a recipe
change is safe. Both scaffolders default to the rubble folders, so **always pass
the directory** — the defaults would touch the wrong set. Both take one directory
at a time, so they run three times each.

`make_prefab_scenes.gd` writes `metadata/placeholder = true` on every prefab it
scaffolds and refuses to write one without it. These are final art, so the line
is removed afterwards; the containers never had it, so the pair agrees and
`audit_placeholders.py` is quiet. If the team later decides these are stand-ins,
add the line to the **containers** as well — the audit reports a pair that
disagrees, in either direction.

## Checking the result

```
python .github/scripts/validate-model-files.py assets/art/gameplay/mining_laser/sm_mining_laser.gltf ...

<godot> --headless --path . --script res://tools/voxel-props/verify_props_import.gd

set PROPS_SHOT=<somewhere>\props.png
<godot> --path . --resolution 1600x900 --rendering-driver opengl3 \
  res://tools/voxel-props/preview_props.tscn

python tools/placeholder-art/audit_placeholders.py
```

Four checks, because each sees something the others cannot. The validator reads
the glTF JSON and is the pass/fail authority CI runs. `verify_props_import.gd`
reads what Godot then *made* of it — the texture filter, the compression and the
mipmaps are decided there and are invisible to everything else. The preview is not
headless, because headless has no rendering device: it is the only one of the four
that would catch a set that passed every check and rendered wrong, and the rubble
set has already been that set once.

The preview writes **two** frames. `props.png` is the scale check — the character
in the car's doorway, which is the whole reason the character is instanced there
rather than described in a comment. `props_detail.png` is where the two small
props are actually judged; at wide-shot distance a 1.14 m hand tool is sixty
pixels and every silhouette looks fine.

Anything magenta in either frame is a UV landing outside its swatch. Unused
palette slots are filled magenta on purpose, so that failure is loud.

## What the render decided

Recorded because none of it is recoverable from the files, and all of it cost a
round trip:

- **The laser was 0.90 m and read as a camera.** At 15 voxels the receiver ate
  the barrel and there was no length left to read as a barrel. It is 1.14 m now,
  with a fore grip and heat fins.
- **A dark barrel between a bright collar and a mid-grey receiver vanished.**
  Value has to alternate *along* the length or a silhouette this coarse has no
  length. The barrel is the lightest part of the tool.
- **The car was a grey box with one striped doorway.** The hazard read has to be
  on the silhouette's corners — yellow corner posts, a yellow skirt, a yellow
  mast — not only on the thing you walk through.
- **The car needed a hoist bracket.** Without one it is a shipping container.
- **The switch's paddle was flush in its recess and read as a wall vent.** It has
  a handle knob proud of the housing now, and a yellow casting rather than a grey
  one, so it reads as a control rather than a fitting.
- **The shaft's collar was a single 0.12 m plate and read as a rectangle painted
  on the rock.** Only the bottom step of a hood hangs below a ceiling, so that is
  the step that needs the depth and the yellow. It is a three-tier flare now,
  0.36 m of it proud, with a dark seat where it meets the rock.

`prefabs/environment/elevator/tools/preview_elevator_shaft.tscn` is the shaft's own
render check — the frame is too tall to share a frame with the other three, and it
needs a slab of stand-in rock to pierce before the collar has anything to do.
