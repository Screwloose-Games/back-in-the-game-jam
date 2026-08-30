"""Voxels -> triangles: face culling, then greedy merging of same-colour runs.

Adapted from `build_mesh` and `_greedy_rects` in
`tools/voxel-rubble/build_rubble.py`. The two differ in what a face carries, and
it is not a small difference: the rubble mesher's merge key is (shade, four
corner occlusion levels), so a wall of one colour still fragments wherever the
lighting changes. Here the key is the colour alone. A 3.4 m elevator wall is one
quad no matter how many voxels span it, which is the only reason a 62-voxel
lattice is affordable at all.

All four corners of a merged quad get the same UV -- the palette lookup for that
colour. Nothing is ever interpolated across a face, which is what makes the
sampler's filter mode a cosmetic question rather than a correctness one.
"""

from __future__ import annotations

# Outward normal, and the two in-plane axes (a, b) chosen so that
# e_a x e_b = normal. Winding (0,0) -> (1,0) -> (1,1) -> (0,1) is then
# counter-clockwise seen from outside, which is glTF's front face.
FACES = (
    ((1, 0, 0), 1, 2),  # +X : Y x Z
    ((-1, 0, 0), 2, 1),  # -X : Z x Y
    ((0, 1, 0), 2, 0),  # +Y : Z x X
    ((0, -1, 0), 0, 2),  # -Y : X x Z
    ((0, 0, 1), 0, 1),  # +Z : X x Y
    ((0, 0, -1), 1, 0),  # -Z : Y x X
)


def _greedy_rects(mask, width, height):
    """Standard greedy meshing over a 2D slice of equal keys."""
    rects = []
    for j in range(height):
        i = 0
        while i < width:
            key = mask[j][i]
            if key is None:
                i += 1
                continue
            run = 1
            while i + run < width and mask[j][i + run] == key:
                run += 1
            depth = 1
            while j + depth < height and all(mask[j + depth][i + k] == key for k in range(run)):
                depth += 1
            for dj in range(depth):
                for di in range(run):
                    mask[j + dj][i + di] = None
            rects.append((i, j, run, depth, key))
            i += run
    return rects


def build(voxels, uv_for_colour, material_for_colour, origin, voxel_size):
    """{(x,y,z): colour} -> {material: (positions, normals, uvs, indices)}.

    One entry per material the part actually uses, which becomes one glTF
    primitive each. Faces are culled and merged first and partitioned second,
    so a lamp voxel buried inside a hull still contributes no geometry, and a
    run of hull never merges across into a lamp -- the merge key is the colour,
    and a colour belongs to exactly one material.

    Positions come out in metres, already offset so that `origin` -- a float
    triple in lattice coordinates -- sits at (0, 0, 0). Doing the metres
    conversion here rather than as a node scale is not a style choice:
    gltf_transforms.py hard-fails a node scale off 1.0 by more than 1e-3, so a
    0.06 on the node would not survive the gate.

    Culling looks only at `voxels`, so a part sees no neighbour. That is what a
    moving part needs -- an elevator door welded to the jamb it slides away from
    would open onto a hole.
    """
    surfaces = {}

    for normal, axis_a, axis_b in FACES:
        axis_n = 0 if normal[0] else (1 if normal[1] else 2)
        forward = normal[axis_n] > 0

        # Group the exposed faces by the slice they live in.
        slices = {}
        for cell in voxels:
            if (cell[0] + normal[0], cell[1] + normal[1], cell[2] + normal[2]) in voxels:
                continue
            slices.setdefault(cell[axis_n], []).append(cell)

        for slice_index in sorted(slices):
            cells = slices[slice_index]
            a_values = [c[axis_a] for c in cells]
            b_values = [c[axis_b] for c in cells]
            a_min, b_min = min(a_values), min(b_values)
            width = max(a_values) - a_min + 1
            height = max(b_values) - b_min + 1

            mask = [[None] * width for _ in range(height)]
            for cell in cells:
                mask[cell[axis_b] - b_min][cell[axis_a] - a_min] = voxels[cell]

            for i, j, run, depth, colour in _greedy_rects(mask, width, height):
                corner = [0, 0, 0]
                corner[axis_n] = slice_index + (1 if forward else 0)
                corner[axis_a] = a_min + i
                corner[axis_b] = b_min + j

                positions, normals, uvs, indices = surfaces.setdefault(material_for_colour(colour), ([], [], [], []))
                base = len(positions)
                uv = uv_for_colour(colour)
                for step_a, step_b in ((0, 0), (run, 0), (run, depth), (0, depth)):
                    point = list(corner)
                    point[axis_a] += step_a
                    point[axis_b] += step_b
                    positions.append(tuple((point[k] - origin[k]) * voxel_size for k in range(3)))
                    normals.append(normal)
                    uvs.append(uv)
                indices.extend((base, base + 1, base + 2, base, base + 2, base + 3))

    return surfaces


def bounds(positions):
    """(lows, highs) over a list of float triples."""
    axes = tuple(zip(*positions))
    return [min(a) for a in axes], [max(a) for a in axes]
