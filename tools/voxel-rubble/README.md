# Voxel rubble generator

Ten pieces of floating debris for the zero-g mine, built procedurally and written
straight out as glTF. Everything under
`assets/art/environment/props/sm_rubble*.gltf` comes from here.

```
python tools/voxel-rubble/build_rubble.py          # write the set
python tools/voxel-rubble/build_rubble.py --list   # measurements only, writes nothing
```

| | |
|---|---|
| Voxel size | 0.06 m |
| Cap | 16 voxels on any axis (0.96 m) |
| Actual range | 0.18 m – 0.84 m, 100 – 752 tris |
| Textures | none — three quantised rock shades and baked corner occlusion in `COLOR_0` |
| Pivot | centre of the bounding box, so a tumbling `RigidBody3D` spins about itself |

Deterministic: the same recipe list always produces the same bytes, so
regenerating is a no-op in git unless a recipe changed.

## No Blender

Every face of a voxel model is axis-aligned and every vertex is a multiple of the
voxel size. Writing the glTF directly is the only way to guarantee both without
trusting an exporter's Y-up conversion and float round-trip — `Object > Apply`
cannot be forgotten if there is no object. The brief's "renormalise so each voxel
side is 0.06 m" is satisfied in the mesh data itself, which is also what
`gltf_transforms.py` demands: it hard-fails a node scale off 1.0 by more than
1e-3, so a 0.06 scale left on the node would not survive the validator.

The trade is that nothing here is hand-editable in a DCC. Change a recipe and
rebuild; do not open the glTF and push vertices, because the next run overwrites
it.

## Container scenes

Each model has an inherited scene beside it — `sm_rubble01.tscn` next to
`sm_rubble01.gltf`, per the `model_container_scene` rule in `pipeline.yaml`:
`{mesh_stem}.tscn`, same directory. Not `prefab_rubble01.tscn`; that name is
listed as invalid for this slot.

**Scripts and gameplay components go in the prefab**, not here and not in the
glTF — `pipeline.yaml` is master and its `programming.create_prefab_scene` step
owns that layer. The container is the seam that survives a re-export: regenerating
a model overwrites the glTF and leaves the container's material overrides alone.

**Collision, physics bodies and navmeshes have a second home.** Godot's importer
reinterprets node names, so a mesh named `*-col`, `*-colonly`, `*-convcol`,
`*-convcolonly` or `*-navmesh` in the glTF becomes collision or navigation on
import — a legitimate choice when the shape belongs to the art rather than to the
gameplay. If you take it, flip `collision_expected` or `navigation_expected` in
the spec to match: the validator fails when presence disagrees with the flag,
in both directions. Otherwise the shape goes in the prefab with everything else.

Right now the containers are bare — the inherited root and the placeholder marker,
nothing more — and so are the prefabs, so a debris piece still needs a
`RigidBody3D` and a collision shape before it can be shoved around.

Each container carries `metadata/placeholder = true`, and so does its prefab. See
`tools/placeholder-art/README.md` for what the marker means and how to list what
still needs real art.

```
<godot> --headless --path . --script res://tools/voxel-rubble/make_container_scenes.gd
```

Creates only what is missing and never overwrites, because a container that has
picked up collision must not be silently reset. Takes an optional `res://`
directory after `--`; defaults to the props folder.

## Adding or changing a piece

1. Edit `RECIPES` in `build_rubble.py` — extent, lump count, roughness, noise
   frequency and how many planar cuts to shave off the hull.
2. `python tools/voxel-rubble/build_rubble.py`
3. `<godot> --headless --path . --import`
4. `python tools/voxel-rubble/build_rubble.py --patch-imports` (new pieces only)
5. `<godot> --headless --path . --import` again, if step 4 patched anything.
6. `<godot> --headless --path . --script res://tools/voxel-rubble/make_container_scenes.gd`
7. `<godot> --headless --path . --script res://tools/placeholder-art/make_prefab_scenes.gd`

Steps 6 and 7 create only what is missing, so running the whole loop after a
recipe change is safe.

A recipe is not a shape. Erosion plus random cutting planes is an unreliable
process — a bad draw hollows a piece out or slices it in half — so the generator
walks seeds in order and takes the first result that fills at least 20% of its
lattice and 75% of each span. Deterministic, because the order is fixed. If a
recipe cannot satisfy that in 256 tries it raises rather than shipping a husk.

## Two things that are not obvious

**Godot does not enable vertex colours by itself.** Its glTF importer leaves
`vertex_color_use_as_albedo` off (verified against 4.7.1), so `COLOR_0` imports as
dead weight and every piece renders flat white. The fix is the external material
override that `--patch-imports` writes into each `.import` sidecar, pointing at
`assets/art/environment/props/mat_rubble.tres`. That resource is now where the
whole set's tint and roughness live — retuning the rock is one inspector, not ten
regenerated meshes.

`--patch-imports` only ever *edits* a sidecar Godot already wrote, never creates
one. An `.import` carries a uid and a content-hashed destination path that only
the engine can produce, so a fabricated sidecar is worse than a missing one.

**`PackedScene.pack()` does not make an inherited scene.** Instantiating with
`GEN_EDIT_STATE_MAIN_INHERITED` and packing the result is the obvious API for
"New Inherited Scene" and it is wrong: outside the editor the inheritance is
dropped, and `pack()` bakes the entire `ArrayMesh` into the `.tscn` as a
sub-resource. The file looks fine, loads fine, renders fine — and is frozen, so
the model can never be reimported through it again. `make_container_scenes.gd`
emits the four lines of scene text instead, and reads each file back to confirm
no `[sub_resource]` appeared. `verify_rubble_import.gd` asserts the same thing,
because a flattened container has no symptom until months later when a
regenerated mesh fails to show up.

**Godot watches the `.gltf`, not the `.bin`.** Every vertex position and colour
lives in the `.bin`, which is not in the sidecar's `[deps]`. A regeneration that
changed the geometry but not the JSON used to be invisible — the engine compared
the `.gltf`'s hash, found it unchanged, and silently kept the old `.scn`. The
generator now writes a digest of the buffer into `asset.extras.bufferSha1`, so any
change to the geometry is a change to the file Godot is actually watching.

## Checking the result

```
python .github/scripts/validate-model-files.py assets/art/environment/props/*.gltf

<godot> --headless --path . --script res://tools/voxel-rubble/verify_rubble_import.gd

set RUBBLE_SHOT=<somewhere>\rubble.png
<godot> --path . --resolution 1600x760 --rendering-driver opengl3 \
  res://tools/voxel-rubble/preview_rubble.tscn

python tools/placeholder-art/audit_placeholders.py
```

Four checks, because each sees something the others cannot. The validator reads
the glTF JSON and is the pass/fail authority CI runs. `verify_rubble_import.gd`
reads what Godot then *made* of it — the material flag above is decided there and
is invisible to everything else. The preview is not headless, because headless has
no rendering device: it is the only one of the four that would have caught a set
that passed every check and rendered flat white. The audit reads none of that — it
checks that every container reached a prefab and that both still agree the art is
a stand-in.
