"""Fixes the importer defaults that would quietly destroy indexed-palette art.

Only ever EDITS a sidecar Godot has already written, never creates one. That
distinction is `tools/voxel-rubble/build_rubble.py`'s rule and it is a real one:
an `.import` carries a uid and a content-hashed destination path that only the
engine can produce, so a fabricated sidecar is worse than a missing one.

Three defaults, each of which is fine for ordinary art and wrong for this:

**`detect_3d/compress_to=1` on the texture.** The first time a 3D material binds
the palette, Godot re-imports it with VRAM compression, and `project.godot` has
`textures/vram_compression/import_etc2_astc=true`. ETC2 compresses in 4x4 texel
blocks. The palette is a 4x4 texel grid. The block boundaries land exactly on
the swatch boundaries and every swatch becomes an average of itself -- which
mostly still looks right, until two swatches that differ by a little bleed into
each other. This is the highest-risk line in the whole tool, and it fires only
after the art has already looked correct once.

**`meshes/generate_lods=true` on the model.** Every triangle here has zero UV
area: all three corners share one lookup. LOD simplification welds vertices, and
a weld across a colour boundary drags a corner onto a different swatch, so a
prop changes colour at distance. There is also nothing to gain -- these are
400-to-2000 triangle props.

**`meshes/ensure_tangents=true` on the model.** Tangents from degenerate UV
triangles are undefined. Harmless without a normal map, but it fills the import
log with noise that hides real warnings.
"""

from __future__ import annotations

import os

MODEL_SETTINGS = {
    "meshes/generate_lods": "false",
    "meshes/ensure_tangents": "false",
}

TEXTURE_SETTINGS = {
    "compress/mode": "0",
    "mipmaps/generate": "false",
    "detect_3d/compress_to": "0",
}


def _patch_file(path, settings):
    """Rewrite the named keys in one sidecar. Returns "" or a reason it did not."""
    if not os.path.exists(path):
        return "missing"
    with open(path, "r", encoding="utf-8") as handle:
        lines = handle.read().split("\n")

    remaining = dict(settings)
    changed = False
    for index, line in enumerate(lines):
        key = line.split("=", 1)[0].strip()
        if key in remaining:
            wanted = f"{key}={remaining.pop(key)}"
            if line.strip() != wanted:
                lines[index] = wanted
                changed = True
    if remaining:
        # A key we expected the importer to write is absent. Adding it blind
        # would put it in whatever section happens to be last, so say so instead
        # -- a silently misplaced key reads as applied and is not.
        return f"no line for {', '.join(sorted(remaining))}"
    if not changed:
        return "current"

    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines))
    return ""


def patch(repo_root, props):
    """Patch the model and texture sidecars for every prop given."""
    missing = []
    for prop in props:
        directory = os.path.join(repo_root, prop.directory)
        for name, settings in (
            (f"{prop.stem}.gltf.import", MODEL_SETTINGS),
            (f"{prop.texture_name}.import", TEXTURE_SETTINGS),
        ):
            problem = _patch_file(os.path.join(directory, name), settings)
            if problem == "missing":
                missing.append(name)
            elif problem == "current":
                print(f"current  {name}")
            elif problem:
                raise RuntimeError(f"{name}: {problem}")
            else:
                print(f"patched  {name}")

    if missing:
        print(
            f"\n{len(missing)} sidecar(s) not written yet: {', '.join(missing)}\n"
            "Import the project once, then run --patch-imports again:\n"
            "  <godot> --headless --path . --import"
        )
    else:
        print("\nRe-import so Godot picks the changes up:\n  <godot> --headless --path . --import")
