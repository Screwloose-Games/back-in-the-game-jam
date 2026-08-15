---
paths:
    - "assets/art/**"
    - "tools/blender-vehicle/**"
    - "tools/gltf-validator/**"
    - "**/*.gltf"
    - "**/*.glb"
    - "**/*.gltf.spec.yaml"
---

# Building 3D assets

## Use the toolkit before hand-modelling

`tools/blender-vehicle/` builds vehicles procedurally in Blender: geometry, UVs,
a baked texture atlas, collision proxies and a validated glTF, in two calls.
Read its README before starting a vehicle — it is the retrospective from the
asset that produced it, and it lists the traps below with the reasoning.

```python
import sys; sys.path.insert(0, "tools/blender-vehicle")
import build
build.blockout("my_truck", repo_root=".")   # ~4 s — get the silhouette approved first
build.produce("my_truck", repo_root=".")    # ~110 s — ships the asset
```

Only `models/<name>.py` is bespoke. Everything else is generic.

**Get the blockout signed off before running `produce`.** `produce` spends ~90
seconds baking, and a rejected silhouette throws all of it away. It is the single
largest cost in the whole process; nothing else takes more than about five seconds.

Hand-modelling is not forbidden — a model that passes every check is fine however
it was made. But the constraints below are not optional, and the toolkit already
encodes them.

## The constraints that are easy to get wrong

**Every pivot must be identity rotation and unit scale.** A static asset — no
skins, no animations — is inspected by `gltf_transforms.py` *all the way down the
mesh chain*, not just at the scene roots. Any rotation over 0.5° or scale off 1.0
by more than 1e-3 is a hard fail. Author rotation into the mesh data (bmesh) and
let pivot Empties carry translation only.

A pivot that genuinely is not axis-aligned — a raked steering column — cannot be
expressed in the glTF at all. Put it in the container `.tscn` as a `Marker3D` and
rotate about `marker.global_basis.z`. Do **not** reach for
`allow_unapplied_transforms`: it disables the check for the entire model.

**No mesh may be parented under another mesh.** It breaks Godot's collision-shape
generation. Parent through Empties.

**Godot reinterprets node names.** Its importer matches `_wheel` and `$wheel` as
well as `-wheel`, and ignores trailing digits, so an ordinary descriptive name can
silently change a node's class — `steering_wheel` and `steering_wheel2` both import
as a `VehicleWheel3D`. This is the same mechanism that makes `-convcolonly` work,
so it cannot be disabled. The validator now checks this (`godot_node_suffixes`);
the full list lives in `tools/gltf-validator/gltf_godot_import.py`.

**A looping animation is named `<clip>-loop`.** That suffix is how Godot is told a
clip repeats: it imports the animation with `loop_mode = LOOP_LINEAR` and *strips
the flag off the name*. Author `idle_float-loop` and the engine gives you
`idle_float`, looping — so play it, and write it in the spec's
`animations_expected`, without the suffix. Never set `loop_mode` by hand in a
post-import script; the suffix is the supported switch and it survives re-export.

A clip that does not loop simply carries no flag. `validate-model-files.py` fails
(`animation_loop_suffix`) any other spelling Godot honours — `_loop`, `$loop`,
`-cycle`, `-Loop` — because a clip that loops on purpose and one that loops by
accident are otherwise indistinguishable. Matching is end-anchored and ignores
trailing digits, so `idle_loop_fast` does not loop but `walk_loop2` does, arriving
as `walk2`. Beware a name that merely ends in those letters: `walkloop` loops and
keeps its name, which is exactly the accident the check exists to catch.

Declare the intent in the spec so a missing suffix is caught rather than inferred:

```yaml
animations_expected:
  - name: "idle_float"    # the imported name, no suffix
    loops: true           # requires the glTF to call it idle_float-loop
```

This is an animation mechanism only. `loop` and `cycle` are **not** node suffixes —
a mesh named `crate_loop` imports untouched, so it does not belong in
`godot_node_suffixes_allowed`.

**Collision proxies must stay inside the visual mesh.** The size checks measure
the whole file, so a proxy sticking out past the art *becomes* the model's declared
width, height or depth — and the failure then points at a number no render shows.

**Triangles are counted per instance.** Four wheels cost four times; collision
proxies count too.

**Blender's glTF export converts +Y forward → −Z and +Z up → +Y.** Model facing
+Y in Blender. `facing_direction` in the spec is INFO-only and can never fail —
confirm it from a render.

## Before committing a model

Run the gate. It is the same command CI and the pre-commit hook use:

```
python .github/scripts/validate-model-files.py path/to/sm_thing.gltf
```

Every line must read `OK` except `facing_direction`, which is always `INFO`.

Spec keys are validated against `schemas/model-spec.schema.json` with
`additionalProperties: false` — a misspelled key is a hard error, not a silent
no-op, because a key the validator does not recognise is a check that never runs.

Commit the `.gltf`, its `.bin`, every texture, and every `.import` sidecar
together. A `.gltf` without its `.bin` is the failure that actually reaches main.
