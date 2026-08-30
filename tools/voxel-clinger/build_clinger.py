# Procedural voxel generator for the clinger -- SURFACE FAUNA, MINOR.
#
#   python tools/voxel-clinger/build_clinger.py            # write the model
#   python tools/voxel-clinger/build_clinger.py --list     # measurements only
#   python tools/voxel-clinger/build_clinger.py --patch-imports
#
# Everything that does the work lives in tools/voxel-props/ -- the ops, the
# mesher, the palette and the glTF writer. This file is the recipe and nothing
# else, which is the same relationship tools/voxel-minerals/ has to
# tools/voxel-rubble/. Read tools/voxel-props/README.md for the build loop and
# for the two importer defaults that would otherwise destroy this art.
#
# THE EIGHT LEGS ARE EIGHT SEPARATE ROOT NODES, each carrying a translation out
# to its own shoulder and nothing else. That is what lets clinger_legs.gd splay
# them across a visor at runtime: .claude/rules/3d-assets.md hard-fails a node
# rotation over half a degree, so the rest pose has to be the neutral one and
# the splay has to be engine-side. A pivot is a translation, and a translation
# is the one articulation this format can carry.
#
# What comes out:
#   assets/art/character/clinger/sm_clinger.gltf
#   assets/art/character/clinger/sm_clinger.bin
#   assets/art/character/clinger/sm_clinger.gltf.spec.yaml
#   assets/art/character/clinger/t_clinger_basecolor.png

import argparse
import os
import sys

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(TOOLS, "voxel-props"))

import build_props  # noqa: E402
import gltf_writer  # noqa: E402
import palette  # noqa: E402
from voxel_ops import Box, Cut, Paint, Part, Prop  # noqa: E402

REPO_ROOT = os.path.dirname(TOOLS)
GENERATOR = "tools/voxel-clinger/build_clinger.py"

# The shell, on the shared 0.06 m lattice: 5 x 2 x 5 voxels, 0.30 m across and
# 0.12 m thick. TWO VOXELS THICK IS THE POINT. Section 3 of
# documentation/design/environmental-storytelling.md says debris reads as a
# silhouette in a lamp cone at four metres or it does not read at all, and flat
# is what makes "clung to a surface" legible from the side.
SHELL = 5
SHELL_H = 2

# Voxels of reach per leg. Three on the axes and a four-cell staircase on the
# diagonals, which lands both at the same 0.66 m span.
REACH = 3

# The whole lattice: shell plus a leg on each side.
SPAN = SHELL + 2 * REACH
LOW = REACH
HIGH = REACH + SHELL - 1
MID = REACH + SHELL // 2

# Eight compass directions, counter-clockwise from +X. clinger_legs.gd never
# reads these -- it recovers each leg's outward direction from the translation
# the writer puts on the node -- so the order here only fixes the node names.
DIRECTIONS = (
    (1, 0),
    (1, 1),
    (0, 1),
    (-1, 1),
    (-1, 0),
    (-1, -1),
    (0, -1),
    (1, -1),
)


def _axis_leg(step_x, step_z):
    """A straight run of REACH voxels out from the shell, and its shoulder."""
    start_x = HIGH + 1 if step_x > 0 else (LOW - 1 if step_x < 0 else MID)
    start_z = HIGH + 1 if step_z > 0 else (LOW - 1 if step_z < 0 else MID)
    cells = [(start_x + step_x * n, start_z + step_z * n) for n in range(REACH)]
    shoulder = (
        float(HIGH + 1) if step_x > 0 else (float(LOW) if step_x < 0 else MID + 0.5),
        float(HIGH + 1) if step_z > 0 else (float(LOW) if step_z < 0 else MID + 0.5),
    )
    return cells, shoulder


def _diagonal_leg(step_x, step_z):
    """A face-connected staircase. A true 45 degree run of single voxels touches
    only at the corners, which reads as four separated cubes rather than a leg."""
    x = HIGH + 1 if step_x > 0 else LOW - 1
    z = HIGH if step_z > 0 else LOW
    cells = [(x, z)]
    for _ in range(REACH // 2 + 1):
        z += step_z
        cells.append((x, z))
        x += step_x
        cells.append((x, z))
    shoulder = (
        float(HIGH + 1) if step_x > 0 else float(LOW),
        float(HIGH + 1) if step_z > 0 else float(LOW),
    )
    return cells[:-1], shoulder


def _legs():
    """One Part per leg, authored about its own shoulder in shared coordinates.

    Every leg lives on the lower layer only, so it reads as reaching out from
    under the shell rather than growing off its back.
    """
    parts = []
    for index, (step_x, step_z) in enumerate(DIRECTIONS):
        diagonal = step_x != 0 and step_z != 0
        cells, shoulder = (_diagonal_leg if diagonal else _axis_leg)(step_x, step_z)
        parts.append(
            Part(
                name=f"leg_{index}",
                extent=(SPAN, SHELL_H, SPAN),
                ops=tuple(Box(x, 0, z, x, 0, z, "chitin_dark") for x, z in cells),
                pivot=(shoulder[0], SHELL_H / 2.0, shoulder[1]),
            )
        )
    return tuple(parts)


CLINGER = Prop(
    root="carapace",
    object_name="clinger",
    directory="assets/art/character/clinger",
    facing="-Z",
    rests_on_ground=False,
    declared=(0.66, 0.12, 0.66),
    budget=420,
    palette=("chitin", "chitin_dark", "chitin_light", "belly"),
    parts=(
        Part(
            name="carapace",
            extent=(SPAN, SHELL_H, SPAN),
            ops=(
                Box(LOW, 0, LOW, HIGH, SHELL_H - 1, HIGH, "chitin"),
                # Corners off the top layer only, so the back domes and the
                # underside stays a full disc against the glass.
                Cut(LOW, SHELL_H - 1, LOW, LOW, SHELL_H - 1, LOW),
                Cut(HIGH, SHELL_H - 1, LOW, HIGH, SHELL_H - 1, LOW),
                Cut(LOW, SHELL_H - 1, HIGH, LOW, SHELL_H - 1, HIGH),
                Cut(HIGH, SHELL_H - 1, HIGH, HIGH, SHELL_H - 1, HIGH),
                # The whole underside is pale. It is the face the player spends
                # the encounter looking at, and a dark one on a dark visor is a
                # creature you cannot tell you are wearing.
                Paint(LOW, 0, LOW, HIGH, 0, HIGH, "belly"),
                Paint(LOW + 1, SHELL_H - 1, LOW + 1, HIGH - 1, SHELL_H - 1, HIGH - 1, "chitin_light"),
                # A dark band across the front of the back, which is the only
                # thing that gives a radially symmetric animal a facing at all.
                Paint(LOW + 1, SHELL_H - 1, LOW, HIGH - 1, SHELL_H - 1, LOW, "chitin_dark"),
            ),
        ),
    )
    + _legs(),
    origin=("centre", "centre", "centre"),
    note=(
        "SURFACE FAUNA, MINOR. A 5 x 2 x 5 voxel shell with eight legs reaching\n"
        "three voxels out, so the declared 0.66 m is the LEG SPAN and not the\n"
        "shell -- the span is what covers a visor, and the shell alone would\n"
        "understate it by half.\n"
        "#\n"
        "# NINE ROOT NODES, EVERY ONE TRANSLATION-ONLY. The shell sits at the\n"
        "# origin and each leg carries the offset out to its own shoulder, so\n"
        "# clinger_legs.gd splays them by rotating those nodes at runtime.\n"
        "# .claude/rules/3d-assets.md allows exactly that and nothing more: the\n"
        "# rest pose in the file is neutral, and a splayed rest pose would fail\n"
        "# gltf_transforms.py on every leg at once.\n"
        "#\n"
        "# facing_direction is -Z, the project convention, and it is carried by\n"
        "# the dark band across the front of the shell rather than by geometry --\n"
        "# eight radial legs have no front. It is INFO-only and cannot be read\n"
        "# off the mesh, so confirm it from the render.\n"
        "#\n"
        "# rests_on_ground is false. There is no ground; the origin is the centre\n"
        "# of the shell so the body tumbles about itself mid-leap."
    ),
)


def main():
    parser = argparse.ArgumentParser(description="Build the clinger.")
    parser.add_argument("--list", action="store_true", help="report measurements without writing files")
    parser.add_argument(
        "--patch-imports",
        action="store_true",
        help="fix the importer defaults in sidecars Godot has already written, then exit",
    )
    arguments = parser.parse_args()

    if arguments.patch_imports:
        import sidecars

        sidecars.patch(REPO_ROOT, [CLINGER])
        return

    built, anchors, materials, voxel_count = build_props.build(CLINGER)
    out_dir = os.path.join(REPO_ROOT, CLINGER.directory)

    if arguments.list:
        size, triangles, _low = build_props._measure(built)
    else:
        os.makedirs(out_dir, exist_ok=True)
        palette.write_png(os.path.join(out_dir, CLINGER.texture_name), palette.render(CLINGER.palette))
        size, triangles, _low = gltf_writer.write(
            CLINGER.stem, out_dir, built, anchors, materials, CLINGER.texture_name, GENERATOR
        )
        build_props.write_spec(CLINGER, out_dir, voxel_count, size, len(materials), GENERATOR)

    if triangles > CLINGER.budget:
        raise SystemExit(f"{CLINGER.stem}: {triangles} triangles exceeds the authored budget of {CLINGER.budget}")
    for measured, claimed, axis in zip(size, CLINGER.declared, "XYZ"):
        if abs(measured - claimed) > 0.10 * claimed:
            raise SystemExit(f"{CLINGER.stem}: built {axis} is {measured:.3f} m against a declared {claimed} m")

    print(f"{'model':<14} {'voxels':>7} {'metres':>24} {'tris':>6} {'budget':>7} {'nodes':>6}")
    print(
        f"{CLINGER.stem:<14} {voxel_count:>7} "
        f"{size[0]:>6.2f} x{size[1]:>6.2f} x{size[2]:>6.2f} m {triangles:>6} {CLINGER.budget:>7} "
        f"{len(built):>6}"
    )


if __name__ == "__main__":
    main()
