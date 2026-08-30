"""Writes the glTF 2.0 document and its binary buffer, by hand.

No exporter, for the reason `tools/voxel-rubble/README.md` sets out and wins:
every face of a voxel model is axis-aligned and every vertex is a multiple of
the voxel size, and writing the file directly is the only way to guarantee both
without trusting an exporter's Y-up conversion and float round-trip.
`Object > Apply` cannot be forgotten if there is no object.

What this one adds over the rubble writer is a scene rather than a single mesh:
several nodes, several meshes, several primitives per mesh, and a texture. The
rules it has to satisfy are in `.claude/rules/3d-assets.md` and are enforced
below by assertion rather than by care, because every one of them is invisible
in the file and expensive to find after import.
"""

from __future__ import annotations

import hashlib
import json
import os
import struct

# Godot's ResourceImporterScene reinterprets a node name ending in one of these,
# separated by "-", "_" or "$" -- the mechanism that makes "-convcolonly" work,
# so it cannot be turned off. A mesh called `steering_wheel` imports as a
# VehicleWheel3D. Mirrored from tools/gltf-validator/gltf_godot_import.py; the
# validator would catch it too, but failing here names the node and the fix.
GODOT_NODE_SUFFIXES = frozenset(
    {
        "col",
        "colonly",
        "convcol",
        "convcolonly",
        "navmesh",
        "vehicle",
        "wheel",
        "rigid",
        "occ",
        "occonly",
        "noimp",
        "cycle",
        "loop",
    }
)

SUFFIX_SEPARATORS = "-_$"

NEAREST = 9728
CLAMP_TO_EDGE = 33071


def check_node_name(name, stem):
    token = name
    for separator in SUFFIX_SEPARATORS:
        token = token.rsplit(separator, 1)[-1]
    if token.lower() in GODOT_NODE_SUFFIXES:
        raise ValueError(f"node '{name}' ends in the Godot type suffix '{token}' -- rename it")
    if name == stem:
        # build_rubble.py found this one the hard way: Godot names the imported
        # scene root after the file, so a node sharing that name collides and
        # silently becomes "<stem>2".
        raise ValueError(f"node '{name}' collides with the file stem; the importer will rename it")


def _pad4(blob):
    return blob + b"\x00" * (-len(blob) % 4)


def material(name, texture_index, roughness, emissive):
    """One glTF material. Base colour comes entirely from the palette texture.

    metallicFactor is 0.0 on props that are visibly metal, on purpose. The web
    build uses the GL Compatibility renderer with no reflection probe, and a
    metallic surface with nothing to reflect renders near-black -- raising this
    to "look more like metal" makes it darker, not shinier. The metal is carried
    by the palette's value range instead.
    """
    document = {
        "name": name,
        "pbrMetallicRoughness": {
            "baseColorTexture": {"index": texture_index},
            "baseColorFactor": [1.0, 1.0, 1.0, 1.0],
            "metallicFactor": 0.0,
            "roughnessFactor": roughness,
        },
        "doubleSided": False,
    }
    if emissive:
        document["emissiveFactor"] = [1.0, 1.0, 1.0]
        document["emissiveTexture"] = {"index": texture_index}
    return document


def write(stem, out_dir, parts, anchors, materials, texture_uri, generator):
    """Write `<stem>.gltf` and `<stem>.bin`; return (bounds, triangle count).

    `parts` is a sequence of (node_name, translation_or_None, surfaces), where
    surfaces is {material_index: (positions, normals, uvs, indices)} from
    mesher.build. `anchors` is a sequence of (node_name, translation) for
    mesh-less Empties.

    Every node is written with no rotation and no scale key at all -- not an
    identity quaternion, no key. gltf_transforms.py inspects the whole chain
    from each scene root down to every mesh and hard-fails a rotation over 0.5
    degrees or a scale off 1.0 by more than 1e-3, and gltf_axes.py returns
    UNKNOWN (which reads as a failure naming nothing useful) if two roots
    disagree about which way is up. Translation is reported and never failed,
    which is what makes a translation-only pivot the one articulation this
    format can carry.
    """
    buffer = bytearray()
    views = []
    accessors = []
    meshes = []
    nodes = []
    triangles = 0
    lows = [float("inf")] * 3
    highs = [float("-inf")] * 3

    def add_view(blob, target):
        views.append({"buffer": 0, "byteOffset": len(buffer), "byteLength": len(blob), "target": target})
        buffer.extend(_pad4(blob))
        return len(views) - 1

    for name, translation, surfaces in parts:
        check_node_name(name, stem)
        primitives = []
        for material_index in sorted(surfaces):
            positions, normals, uvs, indices = surfaces[material_index]
            if len(positions) >= 65536:
                raise ValueError(f"{stem}/{name}: {len(positions)} vertices overflows UNSIGNED_SHORT indices")

            axes = tuple(zip(*positions))
            part_lows = [min(a) for a in axes]
            part_highs = [max(a) for a in axes]
            shift = translation or (0.0, 0.0, 0.0)
            lows = [min(lo, p + s) for lo, p, s in zip(lows, part_lows, shift)]
            highs = [max(hi, p + s) for hi, p, s in zip(highs, part_highs, shift)]

            position_view = add_view(b"".join(struct.pack("<3f", *p) for p in positions), 34962)
            normal_view = add_view(b"".join(struct.pack("<3f", *map(float, n)) for n in normals), 34962)
            uv_view = add_view(b"".join(struct.pack("<2f", *uv) for uv in uvs), 34962)
            index_view = add_view(b"".join(struct.pack("<H", i) for i in indices), 34963)

            base = len(accessors)
            accessors.append(
                {
                    "bufferView": position_view,
                    "componentType": 5126,
                    "count": len(positions),
                    "type": "VEC3",
                    "min": part_lows,
                    "max": part_highs,
                }
            )
            accessors.append(
                {"bufferView": normal_view, "componentType": 5126, "count": len(normals), "type": "VEC3"}
            )
            accessors.append({"bufferView": uv_view, "componentType": 5126, "count": len(uvs), "type": "VEC2"})
            accessors.append(
                {"bufferView": index_view, "componentType": 5123, "count": len(indices), "type": "SCALAR"}
            )
            primitives.append(
                {
                    "attributes": {"POSITION": base, "NORMAL": base + 1, "TEXCOORD_0": base + 2},
                    "indices": base + 3,
                    "material": material_index,
                    "mode": 4,
                }
            )
            triangles += len(indices) // 3

        node = {"name": name, "mesh": len(meshes)}
        if translation:
            node["translation"] = [float(c) for c in translation]
        meshes.append({"name": f"{stem}_{name}", "primitives": primitives})
        nodes.append(node)

    for name, translation in anchors:
        check_node_name(name, stem)
        # No mesh, so nothing in validate-model-files.py can see these: the
        # measurement skips nodes without a mesh, the transform check only keeps
        # paths that reach one, and the axis check ignores roots that never do.
        # That is what makes them free, and it is why verify_props_import.gd
        # asserts them instead.
        nodes.append({"name": name, "translation": [float(c) for c in translation]})

    document = {
        "asset": {
            "version": "2.0",
            "generator": generator,
            # A digest of the .bin, carried in the .gltf on purpose. Godot's
            # importer watches the .gltf and nothing else -- the .bin is not in
            # the sidecar's [deps] -- so a rebuild that changes geometry but not
            # the JSON is invisible and the engine silently keeps the old .scn.
            # Straight from build_rubble.py, where it cost a round of "the
            # change did not take" to find.
            "extras": {"bufferSha1": hashlib.sha1(bytes(buffer)).hexdigest()},
        },
        "scene": 0,
        "scenes": [{"nodes": list(range(len(nodes)))}],
        "nodes": nodes,
        "meshes": meshes,
        "materials": materials,
        "textures": [{"sampler": 0, "source": 0}],
        "images": [{"mimeType": "image/png", "name": os.path.splitext(texture_uri)[0], "uri": texture_uri}],
        "samplers": [
            {"magFilter": NEAREST, "minFilter": NEAREST, "wrapS": CLAMP_TO_EDGE, "wrapT": CLAMP_TO_EDGE}
        ],
        "buffers": [{"uri": f"{stem}.bin", "byteLength": len(buffer)}],
        "bufferViews": views,
        "accessors": accessors,
    }

    with open(os.path.join(out_dir, f"{stem}.bin"), "wb") as handle:
        handle.write(bytes(buffer))
    with open(os.path.join(out_dir, f"{stem}.gltf"), "w", encoding="utf-8", newline="\n") as handle:
        json.dump(document, handle, indent=2)
        handle.write("\n")

    return [h - l for l, h in zip(lows, highs)], triangles, lows
