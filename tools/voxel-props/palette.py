"""The indexed palette: named colours, their UV lookups, and the PNG writer.

`assets/art/character/sk_player_character.gltf` is the style reference and this
is the part of it worth copying exactly. That file's 64x64 texture is not a
texture map -- its whole mesh samples eleven distinct UV pairs. Nothing is
unwrapped, nothing is painted; a face just points at the colour it wants. For a
model whose every surface is a flat axis-aligned quad that is the correct answer:
a real texture would carry detail the silhouette has already stated, and a web
build's texture budget is the tightest budget it has.

Decoding that file's UVs shows the layout exactly: every texel coordinate it
samples -- 2, 6, 10, 14, 18, 22, 30, 34, 46, 54, 58 -- is congruent to 2 mod 4.
The image is a 16x16 grid of 4x4-texel swatches and each lookup points at a
swatch's centre, two texels clear of every edge. That margin, not the precision
of the coordinate, is what makes the scheme filter-proof. Reproduced here to the
same arithmetic.
"""

from __future__ import annotations

import struct
import zlib

# 64x64 to match the character's palette, in 4x4 blocks: 256 slots, of which the
# props below use ten. The spare room is not waste -- it is where per-face
# occlusion shading would go if these ever need it, four shaded variants per
# colour, still one UV lookup and still no second texture.
TEXTURE_SIZE = 64
BLOCK_SIZE = 4
BLOCKS_PER_ROW = TEXTURE_SIZE // BLOCK_SIZE

# Fills every slot no colour claims. Magenta on purpose: the slack above should
# make a mis-sampled lookup impossible, and if one ever happens anyway this is
# the difference between noticing immediately and shipping a subtly wrong tint.
UNUSED = (0xFF, 0x00, 0xFF)

# sRGB, written to the PNG unconverted -- glTF defines baseColorTexture as sRGB
# encoded, so the linearisation build_rubble.py has to do for COLOR_0 is not
# just unnecessary here, it would be a bug.
#
# Kept light and low-saturation for the same reason the rubble shades are: a
# level can always light an asset down, and nothing in the scene can recover
# detail from one authored dark. The mine is lit by helmet lamps.
COLOURS = {
    # Structure.
    "steel": (0x8A, 0x8F, 0x96),  # the default hull plate
    "steel_dark": (0x5E, 0x63, 0x6A),  # ribs, recesses, anything that reads as behind
    "steel_light": (0xB0, 0xB6, 0xBD),  # top faces and wear edges
    "iron": (0x46, 0x49, 0x4E),  # heavy castings: switch housing, elevator floor
    "deck": (0x74, 0x79, 0x80),  # walked-on plate, a shade off the walls
    # Warm enough to separate from every steel above it under a white lamp, which
    # is the only reason the shaft's pad reads as poured rather than fabricated.
    "concrete": (0x9A, 0x97, 0x90),  # the shaft's foundation pad
    "concrete_dark": (0x6F, 0x6D, 0x68),  # its form lines and the worn edge
    # Hazard. Warm enough to separate from the steel under a white lamp; the
    # black is not black, because a true 0x00 next to these reads as a hole.
    "hazard": (0xE0, 0xA8, 0x1E),
    "hazard_dark": (0x24, 0x22, 0x20),
    # Signal and trim.
    "red": (0xC4, 0x3D, 0x30),  # the switch paddle, emergency trim
    "cyan": (0x4F, 0xC7, 0xD4),  # coolant lines, the one cool colour
    "rubber": (0x33, 0x33, 0x36),  # grips, gaskets, the meeting edge of a door
    # Fauna. The clinger, and the only organic thing in the palette. Cold and
    # low-saturation like everything above it -- a warm creature in a mine lit by
    # helmet lamps reads as a prop someone tinted, not as something alive. The
    # belly is the pale one on purpose: it is what a player sees on the glass.
    "chitin": (0x67, 0x6B, 0x60),
    "chitin_dark": (0x3D, 0x40, 0x39),
    "chitin_light": (0x8C, 0x90, 0x83),
    "belly": (0xC0, 0xB6, 0xA4),
    # Emissive. These land on a second material so a container override can
    # drive the glow without touching the hull -- see EMISSIVE below.
    "lamp": (0xF6, 0xF2, 0xD8),  # the car's ceiling panel
    "emitter": (0x6E, 0xE8, 0xF2),  # the cutter's aperture, powered with the beam off
}

# Colours that go on the second, emissive material. The mesher partitions faces
# by this, so a prop that uses none of them writes one material and a prop that
# uses any writes two -- which is why min_material_count in the spec is derived
# from the recipe rather than typed.
#
# The aperture is the point: "the beam is a runtime effect" only works if the
# tool still reads as powered when the beam is off, and in a mine lit by helmet
# lamps an unlit emitter is indistinguishable from a hole.
EMISSIVE = frozenset({"lamp", "emitter"})


def slot_uv(index):
    """UV at the centre of swatch `index`.

    BLOCK_SIZE / 2, which is the same arithmetic the character's own UVs decode
    to (every texel coordinate it samples is 2 mod 4). Two texels of clearance
    to the nearest swatch edge on all four sides.
    """
    column = index % BLOCKS_PER_ROW
    row = index // BLOCKS_PER_ROW
    return (
        (column * BLOCK_SIZE + BLOCK_SIZE / 2) / TEXTURE_SIZE,
        (row * BLOCK_SIZE + BLOCK_SIZE / 2) / TEXTURE_SIZE,
    )


def assign(names):
    """Colour names -> {name: index}, in the order given.

    The order is the recipe's, not sorted and not the dict's: it is what decides
    which block a colour lands in, so it has to be something a human controls and
    can leave alone. Reordering a prop's palette rewrites its every UV.
    """
    unknown = [name for name in names if name not in COLOURS]
    if unknown:
        raise KeyError(f"no such colour(s): {', '.join(unknown)}")
    if len(names) > BLOCKS_PER_ROW * BLOCKS_PER_ROW:
        raise ValueError(f"{len(names)} colours exceeds the {BLOCKS_PER_ROW ** 2} slots in the palette")
    return {name: index for index, name in enumerate(names)}


def render(names):
    """Colour names -> TEXTURE_SIZE rows of RGB bytes."""
    indices = assign(names)
    rows = [bytearray(UNUSED * TEXTURE_SIZE) for _ in range(TEXTURE_SIZE)]
    for name, index in indices.items():
        colour = bytes(COLOURS[name])
        column = (index % BLOCKS_PER_ROW) * BLOCK_SIZE
        for row in range((index // BLOCKS_PER_ROW) * BLOCK_SIZE, (index // BLOCKS_PER_ROW) * BLOCK_SIZE + BLOCK_SIZE):
            rows[row][column * 3 : (column + BLOCK_SIZE) * 3] = colour * BLOCK_SIZE
    return rows


def write_png(path, rows):
    """Write 8-bit RGB rows as a PNG. Stdlib only, like everything else here.

    Deliberately minimal: no interlacing, no ancillary chunks, filter type 0 on
    every scanline. A palette is 256 flat blocks, so there is nothing for a
    filter to predict and nothing for a colour profile to say.
    """

    def chunk(kind, payload):
        return (
            struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)
        )

    height = len(rows)
    width = len(rows[0]) // 3
    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    raw = b"".join(b"\x00" + bytes(row) for row in rows)
    with open(path, "wb") as handle:
        handle.write(
            b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(raw, 9))
            + chunk(b"IEND", b"")
        )
