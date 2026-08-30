# tools/voxel-clinger

Writes the clinger's placeholder model — `assets/art/character/clinger/sm_clinger.gltf`,
its buffer, its palette PNG and its acceptance spec — straight out of Python. No Blender,
no Godot, stdlib only, and deterministic: the same recipe always produces the same bytes,
so regenerating is a no-op in git unless the recipe changed.

Everything that does the work lives in [`../voxel-props/`](../voxel-props/README.md) — the
ops, the mesher, the palette and the glTF writer. `build_clinger.py` is the recipe and
nothing else, the same relationship `tools/voxel-minerals/` has to `tools/voxel-rubble/`.
**Read that README first**; it owns the build loop and the two importer defaults that would
otherwise quietly destroy this art.

## The shape

A 5 × 2 × 5 voxel shell on the shared 0.06 m lattice with eight legs reaching three voxels
out — 0.66 × 0.12 × 0.66 m, 74 voxels, 196 triangles against a 420 budget.

```
.....2.....
.3...2...1.
.33..2..11.
..3SSSSS1..
...SSSSS...
444SSSSS000     S = shell, 0-7 = legs
...SSSSS...
..5SSSSS7..
.55..6..77.
.5...6...7.
.....6.....
```

**Two voxels thick is the point.** §3 of
`documentation/design/environmental-storytelling.md` says debris reads as a silhouette in a
lamp cone at four metres or it does not read at all, and flat is what makes "clung to a
surface" legible from the side.

The diagonal legs are face-connected staircases rather than true 45° runs: a run of single
voxels touching only at their corners reads as four separated cubes, not a leg.

## Nine root nodes, every one translation-only

The shell sits at the origin and each leg carries the offset out to its own shoulder, so
`clinger_legs.gd` splays them by rotating those nodes at runtime — and recovers each leg's
outward direction from its own translation, so nothing in the script has to know which leg
is which.

`.claude/rules/3d-assets.md` allows exactly that and nothing more: `gltf_transforms.py`
hard-fails a node rotation over half a degree or a scale off 1.0 by more than 1e-3,
anywhere down the mesh chain. The rest pose in the file is therefore neutral, and a splayed
one would fail on all eight legs at once. Do not reach for `allow_unapplied_transforms` —
it disables the check for the whole model.

## The build loop

Godot is `D:\Godot_v4.7.1-stable_win64.exe`; `godot.cmd` swallows its arguments.

```bash
python tools/voxel-clinger/build_clinger.py --list      # measure, write nothing
python tools/voxel-clinger/build_clinger.py
python .github/scripts/validate-model-files.py assets/art/character/clinger/sm_clinger.gltf
#   every line OK; facing_direction is always INFO

<godot> --headless --path . --import                    # Godot writes the .import sidecars
python tools/voxel-clinger/build_clinger.py --patch-imports
<godot> --headless --path . --import                    # and picks the patched settings up
```

`--patch-imports` only ever **edits** a sidecar Godot has already written. An `.import`
carries a `uid://` and a content-hashed destination path that only the engine can produce,
so a fabricated one is worse than a missing one.

The container scene beside the model was scaffolded with
`tools/voxel-rubble/make_container_scenes.gd`; the prefab is hand-written, because its root
is a `CharacterBody3D` and `tools/placeholder-art/make_prefab_scenes.gd` emits a `Node3D`.
Both carry `metadata/placeholder = true`, and
`python tools/placeholder-art/audit_placeholders.py` reports a pair that disagrees.

## Committing

The `.gltf`, the `.bin`, the PNG and **every `.import` sidecar** go together. A `.gltf`
without its `.bin` is the failure that actually reaches main.
