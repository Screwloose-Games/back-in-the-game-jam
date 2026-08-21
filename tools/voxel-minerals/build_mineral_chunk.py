# Procedural voxel mineral-chunk generator.
#
# Run this with: python tools/voxel-minerals/build_mineral_chunk.py
# (--list prints the measurement without writing anything.)
#
# Writes one fist-sized crystal shard as glTF 2.0 straight out of Python -- no
# Blender, no export step. Same technique as tools/voxel-rubble/build_rubble.py
# (read that file's header first if this one is confusing): every face is
# axis-aligned and every vertex a multiple of the voxel size, which is only
# guaranteed by authoring the file directly rather than trusting an exporter's
# Y-up conversion and float round-trip.
#
# Stdlib only, and deterministic: the same recipe always produces the same
# bytes, so a regenerated asset is a no-op in git unless the recipe changed.
#
# The one thing that differs from rubble: the field function. Rubble scores a
# point by distance to the nearest of several overlapping ellipsoids, which
# reads as a rounded blob. A mineral shard needs to read as a spike on a
# chunky base, so the field here is a single anisotropic lump whose radius in
# X/Z shrinks with height -- wide at the base, narrow at the tip -- perturbed
# by the same coherent noise and shaved by the same planar cuts. Everything
# past the field function (noise, cuts, despur, largest-component, greedy
# meshing, AO, glTF writing) is lifted unchanged from build_rubble.py.
#
# What comes out:
#   assets/art/environment/minerals/sm_mineral_chunk.gltf
#   assets/art/environment/minerals/sm_mineral_chunk.bin
#   assets/art/environment/minerals/sm_mineral_chunk.gltf.spec.yaml
#
# Colour is neutral AO only -- no hue is baked into COLOR_0. Three external
# StandardMaterial3D resources (mat_mineral_common/uncommon/rare.tres) supply
# the actual colour via albedo_color/emission, swapped in at runtime by code
# that picks the material per mineral type. So there is no --patch-imports
# step here: unlike rubble, this mesh's colour is not fixed at import time.

import hashlib
import json
import math
import os
import struct

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ASSET_DIR = os.path.join("assets", "art", "environment", "minerals")

# --- The two numbers the brief fixes ----------------------------------------

# One voxel side, in metres. Applied to the lattice coordinates as the mesh is
# written, so the exported geometry is already in metres and the glTF node
# carries no scale at all -- gltf_transforms.py hard-fails any node scale off
# 1.0 by more than 1e-3. A fist-sized shard (0.15-0.35 m) needs a much smaller
# voxel than rubble's torso-sized debris (0.06 m), or a shard this small would
# be carved from a handful of voxels and lose every facet.
VOXEL_SIZE = 0.025

# No piece may span more than this many voxels on any axis -- 0.4 m at the
# size above, comfortably above the 0.35 m ceiling the brief sets.
MAX_VOXELS = 16

# --- The one recipe ----------------------------------------------------------
#
# extent is the lattice the piece is carved out of, in voxels, as (x, y, z).
# Taller than it is wide on purpose -- the reference art's spike-on-a-base
# silhouette needs headroom to taper into. roughness and frequency are tuned
# the way rubble's smallest "chip" recipe is: high frequency so a handful of
# voxels per axis still gets a couple of facets instead of one smooth taper.
NAME = "sm_mineral_chunk"
EXTENT = (8, 16, 8)
ROUGHNESS = 0.28
FREQUENCY = 0.42
CUT_COUNT = 3

# --- Surfacing --------------------------------------------------------------
#
# Neutral grey-white, and all three "shades" identical -- unlike rubble, which
# uses three shades to read as banded mineral, this mesh must carry no hue at
# all. Colour comes entirely from the external material swapped in per
# mineral type at runtime; baking any tint here would fight that override.
# COLOR_0 here is ambient occlusion only, via AO_LEVELS below.
SHADES = (
    (0xC8, 0xC8, 0xC8),
    (0xC8, 0xC8, 0xC8),
    (0xC8, 0xC8, 0xC8),
)

# Multiplier per vertex-occlusion level 0..3, 3 being fully open. Same table
# as rubble's -- the floor is 0.58, not a starker AO ramp, because a crevice
# rendering as a black slot reads as a hole in the mesh rather than shading.
AO_LEVELS = (0.58, 0.72, 0.86, 1.00)

MATERIAL_NAME = "mat_mineral_chunk_placeholder"

# The mesh node inside the glTF. Deliberately not the file stem: Godot's
# importer names the scene root after the file, so a node also called
# sm_mineral_chunk would collide with it and the root would silently become
# "sm_mineral_chunk2". "crystal_chunk" also does not end in any of the
# Godot-reinterpreted suffixes (col, colonly, convcol, convcolonly, navmesh,
# vehicle, wheel, rigid, occ, occonly, noimp), so the importer will not
# reinterpret its type.
NODE_NAME = "crystal_chunk"


# --- Value noise (identical to build_rubble.py) ------------------------------


def _hash3(ix, iy, iz, seed):
    h = (ix * 374761393 + iy * 668265263 + iz * 1442695040 + seed * 1274126177) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    h ^= h >> 16
    return (h & 0xFFFFFF) / float(0x1000000)


def _fade(t):
    return t * t * (3.0 - 2.0 * t)


def _lerp(a, b, t):
    return a + (b - a) * t


def value_noise(x, y, z, seed):
    """Trilinear value noise in [0, 1]."""
    ix, iy, iz = math.floor(x), math.floor(y), math.floor(z)
    ux, uy, uz = _fade(x - ix), _fade(y - iy), _fade(z - iz)

    def h(dx, dy, dz):
        return _hash3(ix + dx, iy + dy, iz + dz, seed)

    c00 = _lerp(h(0, 0, 0), h(1, 0, 0), ux)
    c10 = _lerp(h(0, 1, 0), h(1, 1, 0), ux)
    c01 = _lerp(h(0, 0, 1), h(1, 0, 1), ux)
    c11 = _lerp(h(0, 1, 1), h(1, 1, 1), ux)
    return _lerp(_lerp(c00, c10, uy), _lerp(c01, c11, uy), uz)


def fractal_noise(x, y, z, seed):
    """Two octaves, in [0, 1]. Enough for a hull this small."""
    return (value_noise(x, y, z, seed) + 0.5 * value_noise(x * 2.17, y * 2.17, z * 2.17, seed + 7)) / 1.5


# --- Voxel generation -------------------------------------------------------


def _rand_stream(seed):
    """A deterministic float generator, so results do not depend on the
    `random` module's implementation staying put across Python versions."""
    state = [seed & 0xFFFFFFFF]

    def next_float():
        state[0] = (state[0] * 1664525 + 1013904223) & 0xFFFFFFFF
        return ((state[0] >> 8) & 0xFFFFFF) / float(0x1000000)

    return next_float


def _spike_field(extent, rnd):
    """A single anisotropic lump that tapers with height.

    Positive inside the mass. Unlike rubble's overlapping ellipsoids, this
    scores only the X/Z distance from a per-height centre, against a per-height
    radius that shrinks from a wide base to a narrow tip -- so the silhouette
    reads as a spike on a chunky base rather than a rounded blob. The centre
    drifts sideways with height too, so the spike leans rather than standing
    dead vertical, which keeps a single piece from reading as a manufactured
    cone.
    """
    ex, ey, ez = extent
    cx0 = _lerp(0.42, 0.58, rnd()) * ex
    cz0 = _lerp(0.42, 0.58, rnd()) * ez
    lean_x = _lerp(-0.22, 0.22, rnd()) * ex
    lean_z = _lerp(-0.22, 0.22, rnd()) * ez
    base_rx = _lerp(0.40, 0.48, rnd()) * ex
    base_rz = _lerp(0.40, 0.48, rnd()) * ez
    tip_rx = _lerp(0.09, 0.14, rnd()) * ex
    tip_rz = _lerp(0.09, 0.14, rnd()) * ez
    # >1 keeps the base's width for longer before the taper narrows quickly
    # near the tip, which is what reads as "chunky base, sharp spike" rather
    # than a uniform cone.
    taper_power = _lerp(1.3, 1.9, rnd())

    def field(x, y, z):
        t = min(max(y / float(ey), 0.0), 1.0)
        shrink = (1.0 - t) ** taper_power
        rx = tip_rx + (base_rx - tip_rx) * shrink
        rz = tip_rz + (base_rz - tip_rz) * shrink
        cx = cx0 + lean_x * t
        cz = cz0 + lean_z * t
        dx, dz = (x - cx) / rx, (z - cz) / rz
        return 1.0 - math.sqrt(dx * dx + dz * dz)

    return field


def _apply_cuts(voxels, cut_count, rnd):
    """Shave caps off the hull with random planes.

    The plane is arbitrary but the lattice is not, so the cut face comes out as
    a staircase -- which is the point. It still reads as one flat break rather
    than as more erosion, because every step lies on the same plane.
    """
    for _ in range(cut_count):
        if len(voxels) < 24:
            break
        # A random direction on the sphere, from two uniform numbers.
        z = _lerp(-1.0, 1.0, rnd())
        phi = rnd() * math.tau
        r = math.sqrt(max(0.0, 1.0 - z * z))
        normal = (r * math.cos(phi), r * math.sin(phi), z)

        projections = [normal[0] * (v[0] + 0.5) + normal[1] * (v[1] + 0.5) + normal[2] * (v[2] + 0.5) for v in voxels]
        low, high = min(projections), max(projections)
        # Take between 6% and 22% of the span. More than that and a small piece
        # loses a whole face; less and the cut is invisible at this voxel count.
        limit = high - (high - low) * _lerp(0.06, 0.22, rnd())
        survivors = {v for v, p in zip(voxels, projections) if p <= limit}
        if len(survivors) >= 24:
            voxels = survivors
    return voxels


_NEIGHBOURS = ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1))


def _despur(voxels):
    """Drop voxels hanging off the hull by one or two faces.

    These are the erosion's leftovers: a single cube touching the mass at one
    face. They cost twelve triangles each, catch the light like a defect, and
    disappear at any distance -- so they are pure loss.
    """
    while True:
        doomed = set()
        for v in voxels:
            attached = sum(1 for d in _NEIGHBOURS if (v[0] + d[0], v[1] + d[1], v[2] + d[2]) in voxels)
            if attached <= 2:
                doomed.add(v)
        if not doomed or len(doomed) >= len(voxels):
            return voxels
        voxels = voxels - doomed


def _largest_component(voxels):
    """Keep only the biggest 6-connected island.

    Cuts and erosion both strand fragments. A stranded fragment is not free
    detail -- it is a second, disconnected body inside one rigid body, so it
    floats alongside the chunk it broke off and never moves relative to it.
    """
    unseen = set(voxels)
    best = set()
    while unseen:
        seed = next(iter(unseen))
        stack, island = [seed], set()
        unseen.discard(seed)
        while stack:
            v = stack.pop()
            island.add(v)
            for d in _NEIGHBOURS:
                n = (v[0] + d[0], v[1] + d[1], v[2] + d[2])
                if n in unseen:
                    unseen.discard(n)
                    stack.append(n)
        if len(island) > len(best):
            best = island
    return best


def _attempt(extent, roughness, frequency, cut_count, seed):
    ex, ey, ez = extent
    rnd = _rand_stream(seed)
    field = _spike_field(extent, rnd)

    voxels = set()
    for x in range(ex):
        for y in range(ey):
            for z in range(ez):
                n = fractal_noise((x + 0.5) * frequency, (y + 0.5) * frequency, (z + 0.5) * frequency, seed)
                if field(x + 0.5, y + 0.5, z + 0.5) + roughness * (n * 2.0 - 1.0) > 0.0:
                    voxels.add((x, y, z))

    if len(voxels) < 24:
        return None
    voxels = _apply_cuts(voxels, cut_count, rnd)
    voxels = _largest_component(voxels)
    voxels = _despur(voxels)
    voxels = _largest_component(voxels)
    return voxels or None


def generate_voxels(name, extent, roughness, frequency, cut_count):
    """Carve the piece, retrying seeds until the result is worth shipping.

    Erosion plus three random planes is not a reliable process -- a bad draw
    hollows the piece out or slices it in half. Rather than hand-tune the
    recipe until no draw is bad, walk the seeds in order and take the first
    that passes. Deterministic, because the order is fixed.
    """
    ex, ey, ez = extent
    assert max(extent) <= MAX_VOXELS, f"{name}: recipe extent {extent} exceeds {MAX_VOXELS} voxels"

    # A piece must still fill most of the lattice it was carved from, or the
    # recipe's stated silhouette is not what shipped. Y gets a lower floor than
    # X/Z: the tip of a spike is meant to taper down to almost nothing, so
    # demanding 75% of the height span (like rubble does on every axis) would
    # reject the very silhouette this recipe is trying to produce.
    floor_x = max(2, int(round(ex * 0.75)))
    floor_y = max(2, int(round(ey * 0.60)))
    floor_z = max(2, int(round(ez * 0.75)))
    floors = (floor_x, floor_y, floor_z)
    min_voxels = max(24, int(0.14 * ex * ey * ez))

    base = sum((ord(c) << (i % 4 * 8)) for i, c in enumerate(name)) & 0xFFFFFFFF
    for attempt in range(256):
        voxels = _attempt(extent, roughness, frequency, cut_count, base + attempt * 7919)
        if voxels is None or len(voxels) < min_voxels:
            continue
        spans = _spans(voxels)
        if all(s >= f for s, f in zip(spans, floors)):
            assert max(spans) <= MAX_VOXELS, f"{name}: spans {spans} exceed {MAX_VOXELS} voxels"
            return _normalise(voxels)
    raise RuntimeError(f"{name}: no seed in 256 produced a piece filling {floors} of {extent}")


def _spans(voxels):
    axes = tuple(zip(*voxels))
    return tuple(max(a) - min(a) + 1 for a in axes)


def _normalise(voxels):
    """Shift the piece so its lattice starts at the origin."""
    axes = tuple(zip(*voxels))
    lo = tuple(min(a) for a in axes)
    return {(v[0] - lo[0], v[1] - lo[1], v[2] - lo[2]) for v in voxels}


# --- Meshing (identical to build_rubble.py) ---------------------------------
#
# Face culling, per-vertex ambient occlusion, then greedy merging of runs that
# agree on both shade and occlusion. Merging across differing AO would smear one
# corner's darkening across a whole wall, so the AO tuple is part of the merge
# key -- which costs some triangles back and is the reason the counts below are
# not as low as a plain greedy mesher's.

# Outward normal, and the two in-plane axes (a, b) chosen so that
# e_a x e_b = normal. Winding (0,0) -> (1,0) -> (1,1) -> (0,1) is then
# counter-clockwise seen from outside, which is glTF's front face.
_FACES = (
    ((1, 0, 0), 1, 2),  # +X : Y x Z
    ((-1, 0, 0), 2, 1),  # -X : Z x Y
    ((0, 1, 0), 2, 0),  # +Y : Z x X
    ((0, -1, 0), 0, 2),  # -Y : X x Z
    ((0, 0, 1), 0, 1),  # +Z : X x Y
    ((0, 0, -1), 1, 0),  # -Z : Y x X
)


def _vertex_ao(side1, side2, corner):
    # Two blocking sides fully close the corner; the diagonal is then hidden and
    # must not be counted, or the value goes negative.
    if side1 and side2:
        return 0
    return 3 - (side1 + side2 + corner)


def _shade_index(voxel, seed):
    n = fractal_noise((voxel[0] + 0.5) * 0.23, (voxel[1] + 0.5) * 0.23, (voxel[2] + 0.5) * 0.23, seed + 1013)
    # Quantised, not continuous -- kept only so contiguous runs of one shade
    # still let the greedy merge do its job. All three shades are the same
    # neutral grey (see SHADES above), so this no longer carries colour, only
    # merge-key stability.
    return 0 if n < 0.38 else (1 if n < 0.72 else 2)


def _face_key(voxels, voxel, normal, axis_a, axis_b, shade):
    """(shade, ao x4) for one face -- both the merge key and the shading."""
    above = (voxel[0] + normal[0], voxel[1] + normal[1], voxel[2] + normal[2])
    step_a = [0, 0, 0]
    step_a[axis_a] = 1
    step_b = [0, 0, 0]
    step_b[axis_b] = 1

    def occupied(sa, sb):
        return (
            above[0] + step_a[0] * sa + step_b[0] * sb,
            above[1] + step_a[1] * sa + step_b[1] * sb,
            above[2] + step_a[2] * sa + step_b[2] * sb,
        ) in voxels

    ao = []
    for i, j in ((0, 0), (1, 0), (1, 1), (0, 1)):
        sa, sb = (2 * i - 1), (2 * j - 1)
        ao.append(_vertex_ao(occupied(sa, 0), occupied(0, sb), occupied(sa, sb)))
    return (shade, ao[0], ao[1], ao[2], ao[3])


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


def _srgb_to_linear(channel):
    c = channel / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _colour_byte(shade, ao_level):
    return bytes(
        min(255, int(round(_srgb_to_linear(component) * AO_LEVELS[ao_level] * 255.0 + 0.5))) for component in shade
    ) + b"\xff"


def build_mesh(voxels, seed):
    """Voxels -> (positions, normals, colours, indices), in metres, centred.

    Positions are float triples in metres; colours are RGBA bytes; indices are
    unsigned shorts.
    """
    shades = {v: _shade_index(v, seed) for v in voxels}
    positions, normals, colours, indices = [], [], [], []

    for normal, axis_a, axis_b in _FACES:
        axis_n = 0 if normal[0] else (1 if normal[1] else 2)
        forward = normal[axis_n] > 0

        # Group the exposed faces by the slice they live in.
        slices = {}
        for v in voxels:
            if (v[0] + normal[0], v[1] + normal[1], v[2] + normal[2]) in voxels:
                continue
            slices.setdefault(v[axis_n], []).append(v)

        for slice_index, cells in slices.items():
            a_values = [c[axis_a] for c in cells]
            b_values = [c[axis_b] for c in cells]
            a_min, b_min = min(a_values), min(b_values)
            width = max(a_values) - a_min + 1
            height = max(b_values) - b_min + 1

            mask = [[None] * width for _ in range(height)]
            for c in cells:
                key = _face_key(voxels, c, normal, axis_a, axis_b, shades[c])
                mask[c[axis_b] - b_min][c[axis_a] - a_min] = key

            for i, j, run, depth, key in _greedy_rects(mask, width, height):
                shade_index, ao00, ao10, ao11, ao01 = key
                shade = SHADES[shade_index]

                origin = [0, 0, 0]
                origin[axis_n] = slice_index + (1 if forward else 0)
                origin[axis_a] = a_min + i
                origin[axis_b] = b_min + j

                base = len(positions)
                for corner_a, corner_b in ((0, 0), (run, 0), (run, depth), (0, depth)):
                    p = list(origin)
                    p[axis_a] += corner_a
                    p[axis_b] += corner_b
                    positions.append(tuple(p))
                    normals.append(normal)
                for ao in (ao00, ao10, ao11, ao01):
                    colours.append(_colour_byte(shade, ao))

                # Split the quad along whichever diagonal keeps the darkest and
                # lightest corners apart. The other diagonal interpolates them
                # across the whole face and produces the classic AO seam.
                if ao00 + ao11 > ao10 + ao01:
                    indices.extend((base + 1, base + 2, base + 3, base + 1, base + 3, base + 0))
                else:
                    indices.extend((base + 0, base + 1, base + 2, base + 0, base + 2, base + 3))

    # Centre on the bounding box, then leave the lattice for metres. This chunk
    # flies through the air when collected, so a pivot anywhere but the middle
    # makes it orbit a corner of itself; and centring on the box rather than
    # the centroid keeps the declared width/height/depth symmetric about the
    # origin.
    axes = tuple(zip(*positions))
    centre = tuple((min(a) + max(a)) / 2.0 for a in axes)
    metres = [tuple((p[k] - centre[k]) * VOXEL_SIZE for k in range(3)) for p in positions]
    return metres, normals, colours, indices


# --- glTF (identical structure to build_rubble.py) --------------------------


def _pad4(blob):
    return blob + b"\x00" * (-len(blob) % 4)


def write_gltf(stem, mesh, out_dir):
    positions, normals, colours, indices = mesh
    assert len(positions) < 65536, f"{stem}: {len(positions)} vertices overflows UNSIGNED_SHORT indices"

    position_blob = b"".join(struct.pack("<3f", *p) for p in positions)
    normal_blob = b"".join(struct.pack("<3f", *map(float, n)) for n in normals)
    colour_blob = b"".join(colours)
    index_blob = b"".join(struct.pack("<H", i) for i in indices)

    buffer = bytearray()
    views = []
    for blob, target in (
        (position_blob, 34962),
        (normal_blob, 34962),
        (colour_blob, 34962),
        (index_blob, 34963),
    ):
        offset = len(buffer)
        views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(blob), "target": target})
        buffer.extend(_pad4(blob))

    axes = tuple(zip(*positions))
    lows = [min(a) for a in axes]
    highs = [max(a) for a in axes]

    document = {
        "asset": {
            "version": "2.0",
            "generator": "tools/voxel-minerals/build_mineral_chunk.py",
            # A digest of the .bin, carried in the .gltf on purpose -- Godot's
            # importer watches the .gltf and nothing else, so a regeneration
            # that changes geometry but not JSON structure would otherwise be
            # invisible to it. See build_rubble.py's write_gltf for the fuller
            # version of this note.
            "extras": {"bufferSha1": hashlib.sha1(bytes(buffer)).hexdigest()},
        },
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        # No translation, rotation or scale: the geometry is already centred
        # and already in metres, and an identity node is the only thing
        # gltf_transforms.py accepts without an opt-out.
        "nodes": [{"name": NODE_NAME, "mesh": 0}],
        "meshes": [
            {
                "name": stem,
                "primitives": [
                    {
                        "attributes": {"POSITION": 0, "NORMAL": 1, "COLOR_0": 2},
                        "indices": 3,
                        "material": 0,
                        "mode": 4,
                    }
                ],
            }
        ],
        "materials": [
            {
                "name": MATERIAL_NAME,
                "pbrMetallicRoughness": {
                    # White base colour so COLOR_0 carries the whole albedo --
                    # glTF multiplies the two. This material is a placeholder
                    # only: the runtime colour comes from one of three external
                    # StandardMaterial3D resources set as material_override by
                    # code, never from this glTF material or its import
                    # sidecar.
                    "baseColorFactor": [1.0, 1.0, 1.0, 1.0],
                    "metallicFactor": 0.0,
                    "roughnessFactor": 0.92,
                },
                "doubleSided": False,
            }
        ],
        "buffers": [{"uri": f"{stem}.bin", "byteLength": len(buffer)}],
        "bufferViews": views,
        "accessors": [
            {
                "bufferView": 0,
                "componentType": 5126,
                "count": len(positions),
                "type": "VEC3",
                "min": lows,
                "max": highs,
            },
            {"bufferView": 1, "componentType": 5126, "count": len(normals), "type": "VEC3"},
            {
                "bufferView": 2,
                "componentType": 5121,
                "count": len(colours),
                "type": "VEC4",
                "normalized": True,
            },
            {"bufferView": 3, "componentType": 5123, "count": len(indices), "type": "SCALAR"},
        ],
    }

    with open(os.path.join(out_dir, f"{stem}.bin"), "wb") as handle:
        handle.write(bytes(buffer))
    with open(os.path.join(out_dir, f"{stem}.gltf"), "w", encoding="utf-8", newline="\n") as handle:
        json.dump(document, handle, indent=2)
        handle.write("\n")

    return [h - l for l, h in zip(lows, highs)], len(indices) // 3


SPEC_TEMPLATE = """\
# Generated by tools/voxel-minerals/build_mineral_chunk.py -- regenerate rather
# than edit.
#
# A tapering crystal spike on a chunky base, carved from a {ex}x{ey}x{ez} voxel
# lattice at {voxel} m per voxel ({voxel_count} voxels kept). Fist-sized
# collectible: pivot at the centre of the bounding box, and rests_on_ground is
# false because it starts embedded in a wall and later flies through the air
# when collected -- it never sits on a floor.
#
# facing_direction is deliberately absent, the same reasoning
# sm_rubble01.gltf.spec.yaml gives: a crystal shard has no canonical front, so
# declaring one would put an unconfirmable INFO line in every PR comment. Colour
# is not part of this asset at all -- COLOR_0 is neutral AO only, and the three
# mineral hues live in external materials swapped in at runtime.
width: {width:.4f}
height: {height:.4f}
depth: {depth:.4f}
poly_count_budget: {budget}
up_direction: "+Y"
root_node_name: "{node}"
collision_expected: false
navigation_expected: false
min_material_count: 1
rests_on_ground: false
"""


def write_spec(stem, extent, voxel_count, dimensions, triangles, out_dir):
    width, height, depth = dimensions
    # Round the budget up to the next 50 so a recipe tweak that moves the
    # count by a triangle or two does not have to move the spec with it.
    budget = int(math.ceil(triangles / 50.0) * 50)
    text = SPEC_TEMPLATE.format(
        ex=extent[0],
        ey=extent[1],
        ez=extent[2],
        voxel=VOXEL_SIZE,
        voxel_count=voxel_count,
        width=width,
        height=height,
        depth=depth,
        budget=budget,
        node=NODE_NAME,
    )
    with open(os.path.join(out_dir, f"{stem}.gltf.spec.yaml"), "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)


# --- Driver -----------------------------------------------------------------


def main():
    import argparse

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default=None, help=f"output directory (default: <repo>/{ASSET_DIR})")
    parser.add_argument("--list", action="store_true", help="report measurements without writing files")
    args = parser.parse_args()

    out_dir = args.out or os.path.join(REPO_ROOT, ASSET_DIR)
    if not args.list:
        os.makedirs(out_dir, exist_ok=True)

    voxels = generate_voxels(NAME, EXTENT, ROUGHNESS, FREQUENCY, CUT_COUNT)
    spans = _spans(voxels)
    seed = sum((ord(c) << (i % 4 * 8)) for i, c in enumerate(NAME)) & 0xFFFFFFFF
    mesh = build_mesh(voxels, seed)

    if args.list:
        dimensions = tuple(s * VOXEL_SIZE for s in spans)
        triangles = len(mesh[3]) // 3
    else:
        dimensions, triangles = write_gltf(NAME, mesh, out_dir)
        write_spec(NAME, EXTENT, len(voxels), dimensions, triangles, out_dir)

    print(f"{'model':<18} {'voxels':>7} {'spans':>12} {'metres':>22} {'tris':>6}")
    print(
        f"{NAME:<18} {len(voxels):>7} {spans[0]:>3}x{spans[1]:<3}x{spans[2]:<4} "
        f"{dimensions[0]:>6.3f} x{dimensions[1]:>6.3f} x{dimensions[2]:>6.3f} m {triangles:>6}"
    )


if __name__ == "__main__":
    main()
