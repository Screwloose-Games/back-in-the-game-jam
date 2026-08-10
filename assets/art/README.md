# Art Assets

## 3D

Models live in `{category}/{group}/`

### The file set for one model

Every model here is named `sm_<name>` (static mesh) and ships as a group of
files that only make sense together:

| File | What it is |
|---|---|
| `sm_<name>.gltf` | The mesh, in glTF's text form. The asset itself. |
| `sm_<name>.bin` | Its binary buffer, referenced by name from the `.gltf`. Neither file is usable without the other. |
| `sm_<name>.gltf.import` | Godot's sidecar. Carries the `uid://` that scenes reference, so omitting it breaks those references on every other machine. |
| `sm_<name>.gltf.spec.yaml` | Machine-checkable acceptance criteria for the model. |
| `sm_<name>.tscn` | Container scene: an inherited scene wrapping the `.gltf`, sharing its stem so the pair reads as one unit. Any modifications to correct the imported file should occur here |

Commit all of them in the same change. A `.gltf` without its `.bin`, or without
its `.import`, is broken for everyone but the person who exported it.

Optional siblings seen here, when a model needs them:

- `t_<name>_basecolor.png` + `.png.import` — textures, `t_` prefix.

On the voxel props and the character, that PNG is an **indexed palette**, not a
texture map: a 16×16 grid of 4×4-texel swatches, every face pointing at one
swatch centre. It has two `.import` settings it cannot survive without —
`detect_3d/compress_to=0` and `mipmaps/generate=false` — because Godot's defaults
block-compress it on first 3D use and ETC2's 4×4 blocks land exactly on the
swatch grid. See `tools/voxel-props/README.md`.

### Naming

Lowercase, underscores between words, prefix first: `sm_` static mesh, `t_`
texture, `mat_` material. Deliver glTF — `.gltf`, never `.fbx`. Numbered variants
in a set are zero-padded and consistent: `sm_rubble01` … `sm_rubble10`.

### The spec file

`sm_<name>.gltf.spec.yaml` states what the model is supposed to be, in fields
that can be measured against the exported file. Unrecognised keys are an error
rather than a silent no-op, so a typo fails loudly instead of quietly disabling a
check. Keys in use here:

```yaml
width: 0.4800            # X/Y/Z extent in metres, +/-10%
height: 0.4800
depth: 0.4800
poly_count_budget: 450   # max triangles across the whole scene
up_direction: "+Y"
facing_direction: "-Z"   # optional; omit for objects with no front
root_node_name: "rubble" # a node with this name must exist
collision_expected: false
navigation_expected: false
min_material_count: 1
rests_on_ground: false   # opt-in; false for anything that floats
textures_expected:       # matched as substrings against image URIs
  - name: t_smiley_basecolor
```

Lead the file with a comment explaining the numbers and any deliberate omission —
`sm_rubble01.gltf.spec.yaml` records that it is generated, that the pivot sits at
the centre of the bounds because the debris tumbles in zero-g, and why
`facing_direction` is absent. That comment is the only place those decisions are
written down.

Units are meters.

### The container scene

`sm_<name>.tscn` is a one-node scene instancing the `.gltf`, with the node named
after the file:

```gdscript
[node name="sm_rubble01" instance=ExtResource("1_8avgo")]
metadata/placeholder = true
```

It exists so other scenes reference a stable file rather than the imported mesh
directly.

Nothing places a container in a level. That is the prefab's job — the container's
counterpart under `prefabs/{category}/`, named `prefab_<object>.tscn`, which
instances this file and adds whatever makes the object work. `sm_rubble01.tscn`
here pairs with `prefabs/environment/props/prefab_rubble01.tscn`.

### Placeholder art

Art that is standing in for something real carries one line, on the container and
on its prefab both:

```gdscript
metadata/placeholder = true
```

The two files have different owners — integration owns the container, programming
owns the prefab — so each marks its own without editing the other's, and
`tools/placeholder-art/audit_placeholders.py` lists what still needs real art and
reports any pair that has drifted apart.

`examples/` is exempt. Those models exist to make the validator fail in known ways,
and `test_pass_crate` is the "everything reads OK" baseline and the 1 m scale
reference. None of them will ever be replaced by real art.
