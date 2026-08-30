# Voxel prop generator: the mining laser, the elevator car and its wall switch.
#
#   python tools/voxel-props/build_props.py            # write the set
#   python tools/voxel-props/build_props.py --list     # measurements only
#   python tools/voxel-props/build_props.py --patch-imports
#
# Three hard-surface props in the style of assets/art/character/
# sk_player_character.gltf: the same 0.06 m lattice, the same indexed-palette
# scheme, no vertex colours. See README.md for the build loop and the traps.
#
# Stdlib only, no Blender, no Godot, and deterministic -- the same recipes
# always produce the same bytes, so regenerating is a no-op in git unless a
# recipe changed.
#
# What comes out, per prop:
#   <directory>/<stem>.gltf
#   <directory>/<stem>.bin
#   <directory>/<stem>.gltf.spec.yaml
#   <directory>/t_<object>_basecolor.png
#
# The .import sidecars are Godot's to write -- open the project once, then run
# --patch-imports, which fixes the two importer defaults that would otherwise
# quietly destroy this art.

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import gltf_writer  # noqa: E402
import mesher  # noqa: E402
import palette  # noqa: E402
from voxel_ops import Box, Cut, MirrorX, Paint, Part, Prop, Stripe  # noqa: E402

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GENERATOR = "tools/voxel-props/build_props.py"

# One voxel side, in metres. The character's lattice, measured off its buffer:
# every vertex coordinate in sk_player_character.bin is a multiple of this, and
# the figure is 26 voxels tall. Applied to the lattice as the mesh is written,
# so the geometry is already in metres and no node carries a scale --
# gltf_transforms.py hard-fails a node scale off 1.0 by more than 1e-3.
VOXEL = 0.06

# Base material roughness. Flat quads with no AO and no normal map, lit by
# helmet lamps: too smooth and every face becomes a mirror of the one lamp in
# the room, too rough and the silhouette is all there is.
ROUGHNESS = 0.78


# --- The elevator car -------------------------------------------------------
#
# Metrics from the greybox in prototypes/elevator_cutscene/
# elevator_cutscene_prototype.tscn, snapped to the lattice. Nothing there is a
# multiple of 0.06 -- 3.7 m is 61.67 voxels -- so every dimension moves by up to
# 2 cm. The spec's +/-10% swallows that with two orders of magnitude to spare,
# and the reason those numbers are what they are survives the snap:
#
#   "THREE METRES BACK FROM THE SUBJECT IS WHY THE CAR IS 3.4 m DEEP. The first
#    version of this was a 2.4 m car, and at that depth the widest shot
#    available from inside it was a miner's head filling the frame."
#
# Interior 3.36 x 3.36 m and a 2.04 m doorway is four suited miners with room to
# turn round; the character is 1.56 m tall and 0.66 m deep.

CAR_W, CAR_H, CAR_D = 62, 48, 62  # body: 3.72 x 2.88 x 3.72 m
MAST = 5  # hoist bracket on the roof, 0.30 m -- the one thing
# that says "hangs from a cable" rather than "shed"
WALL = 3  # 0.18 m -- three voxels reads as plate, two reads as foil
DECK, CEIL = 2, 2  # interior 2.64 m floor to ceiling
DOOR_W, DOOR_H = 34, 32  # 2.04 x 1.92 m opening, centred: (62 - 34) / 2 = 14
DOOR_X = (CAR_W - DOOR_W) // 2
LEAF_W, LEAF_T = 18, 2  # two 1.08 m leaves over a 2.04 m hole: one voxel of
LEAF_Z = WALL  # overlap onto each jamb when closed, and they
# ride the interior face of the front wall

# Yellow corner posts, a yellow skirt and a yellow mast. The brief asked for
# metal AND yellow, and the first render came back a grey box with one striped
# doorway: the hazard read has to be on the silhouette's corners, not only on
# the thing you walk through.
SKIRT = 4  # 0.24 m of hazard banding around the base


def _corner_posts():
    """Exterior corner posts, painted rather than proud.

    Proud posts would grow the bounding box and make the declared width and
    depth describe the posts instead of the car -- the same trap
    gltf_godot_import.py's oversized-collision check exists for, reached from
    the other direction.
    """
    return tuple(
        Paint(x, 0, z, x + WALL - 1, CAR_H - 1, z + WALL - 1, "hazard")
        for x in (0, CAR_W - WALL)
        for z in (0, CAR_D - WALL)
    )


def _hull_panels():
    """Straight panel lines down all four exterior walls.

    Applied before the corner posts and the doorway frame, so both overwrite
    it. Straight and not diagonal: a diagonal breaks every greedy run it
    crosses, and a hull is the largest surface in the set.
    """
    return (
        Stripe(0, SKIRT, 0, 0, CAR_H - 1, CAR_D - 1, "steel", "steel_dark", 8, "z"),
        Stripe(CAR_W - 1, SKIRT, 0, CAR_W - 1, CAR_H - 1, CAR_D - 1, "steel", "steel_dark", 8, "z"),
        Stripe(0, SKIRT, CAR_D - 1, CAR_W - 1, CAR_H - 1, CAR_D - 1, "steel", "steel_dark", 8, "x"),
        Stripe(0, SKIRT, 0, CAR_W - 1, CAR_H - 1, 0, "steel", "steel_dark", 8, "x"),
    )


def _door_leaf(mirrored):
    """One door leaf, authored in its own 18 x 32 x 2 lattice."""
    edge = 0 if mirrored else LEAF_W - 1
    return (
        Box(0, 0, 0, LEAF_W - 1, DOOR_H - 1, LEAF_T - 1, "steel"),
        # The face the doorway sees. Lighter than the hull so a closed door
        # reads as a door and not as more wall.
        Paint(0, 0, 0, LEAF_W - 1, DOOR_H - 1, 0, "steel_light"),
        # Hazard banding low on the leaf, where a boot scuffs it. A band and
        # not a field: a diagonal breaks every greedy run it crosses, so
        # striping a whole leaf costs several times what striping a tenth of
        # one does, for a read that is worse.
        Stripe(0, 2, 0, LEAF_W - 1, 9, 0, "hazard", "hazard_dark", 3, "xy"),
        # The rubber seal on the edge that meets the other leaf.
        Paint(edge, 0, 0, edge, DOOR_H - 1, LEAF_T - 1, "rubber"),
    )


ELEVATOR_CAR = Prop(
    root="car_shell",
    object_name="elevator_car",
    directory="assets/art/environment/elevator_car",
    facing="-Z",
    rests_on_ground=True,
    # The greybox's plan dimensions, not the lattice's. Height is the exception:
    # the greybox has no hoist bracket, so 2.9 + the mast is what to declare.
    declared=(3.7, 3.2, 3.7),
    budget=2500,
    palette=(
        "steel",
        "steel_dark",
        "steel_light",
        "iron",
        "deck",
        "hazard",
        "hazard_dark",
        "rubber",
        "lamp",
    ),
    parts=(
        Part(
            name="car_shell",
            extent=(CAR_W, CAR_H + MAST, CAR_D),
            ops=(
                Box(0, 0, 0, CAR_W - 1, CAR_H - 1, CAR_D - 1, "steel"),
                Cut(WALL, DECK, WALL, CAR_W - WALL - 1, CAR_H - CEIL - 1, CAR_D - WALL - 1),
                Cut(DOOR_X, DECK, 0, DOOR_X + DOOR_W - 1, DECK + DOOR_H - 1, WALL - 1),
                # Hoist bracket. The car hangs from a cable, and nothing else in
                # the silhouette says so -- without it this is a shipping
                # container with a striped door.
                Box(26, CAR_H, 26, 35, CAR_H + MAST - 2, 35, "steel_dark"),
                Box(28, CAR_H + MAST - 2, 28, 33, CAR_H + MAST - 1, 33, "hazard"),
                # Interior surfaces: the innermost layer of the shell, which is
                # all anyone standing inside can see. Painted, never modelled --
                # an inset panel costs geometry AND the run breaks a paint costs.
                Paint(WALL - 1, DECK, WALL, WALL - 1, CAR_H - CEIL - 1, CAR_D - WALL - 1, "steel_light"),
                Paint(
                    CAR_W - WALL, DECK, WALL, CAR_W - WALL, CAR_H - CEIL - 1, CAR_D - WALL - 1, "steel_light"
                ),
                Paint(WALL, DECK, WALL - 1, CAR_W - WALL - 1, CAR_H - CEIL - 1, WALL - 1, "steel_light"),
                Paint(
                    WALL, DECK, CAR_D - WALL, CAR_W - WALL - 1, CAR_H - CEIL - 1, CAR_D - WALL, "steel_light"
                ),
                # Grab rail at waist height, all the way round the interior.
                # Painted, so four people can hold on for free.
                Paint(WALL - 1, 18, WALL, WALL - 1, 20, CAR_D - WALL - 1, "hazard"),
                Paint(CAR_W - WALL, 18, WALL, CAR_W - WALL, 20, CAR_D - WALL - 1, "hazard"),
                Paint(WALL, 18, CAR_D - WALL, CAR_W - WALL - 1, 20, CAR_D - WALL, "hazard"),
                Paint(WALL, DECK - 1, WALL, CAR_W - WALL - 1, DECK - 1, CAR_D - WALL - 1, "deck"),
                Paint(WALL, CAR_H - CEIL, WALL, CAR_W - WALL - 1, CAR_H - CEIL, CAR_D - WALL - 1, "iron"),
                # Ceiling panel. The one emissive surface in the car, and the
                # reason the interior is legible at all in a mine lit by helmet
                # lamps.
                Paint(22, CAR_H - CEIL, 22, 39, CAR_H - CEIL, 39, "lamp"),
                # Worn tread inside the threshold, where every boot lands.
                Stripe(DOOR_X, DECK - 1, WALL, DOOR_X + DOOR_W - 1, DECK - 1, WALL + 2, "hazard", "hazard_dark", 3, "xz"),
            )
            + _hull_panels()
            + _corner_posts()
            + (
                # Hazard skirt round the base, and the chevron frame around the
                # doorway. Both go last so they overwrite the panel lines and the
                # corner posts. The doorway rect covers the opening as well, but
                # Paint adds nothing -- the opening was cut, so what survives is
                # exactly the surround.
                # Four bands, not one rect over the whole footprint: the floor
                # slab lives inside that rect at the same height, and striping
                # it turns the deck into hazard tape underfoot.
                Stripe(0, 0, 0, WALL - 1, SKIRT - 1, CAR_D - 1, "hazard", "hazard_dark", 3, "xz"),
                Stripe(CAR_W - WALL, 0, 0, CAR_W - 1, SKIRT - 1, CAR_D - 1, "hazard", "hazard_dark", 3, "xz"),
                Stripe(0, 0, 0, CAR_W - 1, SKIRT - 1, WALL - 1, "hazard", "hazard_dark", 3, "xz"),
                Stripe(0, 0, CAR_D - WALL, CAR_W - 1, SKIRT - 1, CAR_D - 1, "hazard", "hazard_dark", 3, "xz"),
                Stripe(
                    DOOR_X - 3, 0, 0, DOOR_X + DOOR_W + 2, DECK + DOOR_H + 2, 0, "hazard", "hazard_dark", 3, "xy"
                ),
                Paint(0, CAR_H - 1, 0, CAR_W - 1, CAR_H - 1, CAR_D - 1, "steel_dark"),
            ),
        ),
        Part(
            name="door_left",
            extent=(LEAF_W, DOOR_H, LEAF_T),
            ops=_door_leaf(mirrored=False),
            offset=(DOOR_X - 1, DECK, LEAF_Z),
        ),
        Part(
            name="door_right",
            extent=(LEAF_W, DOOR_H, LEAF_T),
            ops=_door_leaf(mirrored=True),
            offset=(DOOR_X + DOOR_W - LEAF_W + 1, DECK, LEAF_Z),
        ),
    ),
    origin=("centre", "min", "centre"),
    note=(
        "Three meshes in one file: car_shell plus door_left and door_right as\n"
        "sibling nodes, every one of them at identity. The leaves are authored\n"
        "closed and in place, so a container scene slides them by moving\n"
        "position.x away from zero -- no pivot, no rotation, nothing for\n"
        "gltf_transforms.py to object to. Fully open is x = -1.08 / +1.08.\n"
        "#\n"
        "# Interior 3.36 x 3.36 m with a 2.64 m ceiling and a 2.04 x 1.92 m\n"
        "# doorway. Pivot at the bottom centre of the outer shell; the deck is\n"
        "# 0.12 m above it."
    ),
)


# --- The elevator shaft ------------------------------------------------------
#
# A PARTS SHEET, NOT A SHAFT. The car is one object and this is four, because the
# thing a level places is a hoist frame of arbitrary height with beam rings at an
# arbitrary pitch, and neither number can be baked into a mesh. So the file holds
# one post tile, one beam member, one hood and one pad, each authored about its
# own local origin, and prefabs/environment/elevator/elevator_shaft.gd assembles
# them. The lattice layout below is a reference assembly -- it is what the
# validator measures and what a preview render shows, and nothing reads the node
# positions at runtime.
#
# THE POST TILE IS UNIFORM ALONG Y ON PURPOSE. The prefab scales one tile to the
# full shaft height rather than stacking tiles: an I-beam has no detail along its
# length, so a scaled instance is seamless and costs forty triangles where a
# 30 m stack would cost four thousand. Every colour on it therefore varies across
# X and Z only. The rhythm a tall shaft needs comes from the beam rings, which
# are not scaled -- which is also why every hazard accent lives on them.

# The car is 3.72 m square, so 66 voxels of clear bore leaves 0.12 m a side.
BORE = 66
POST = 8  # 0.48 m square I-beam; square so a 90 degree yaw maps it onto itself
POST_TILE = 10  # 0.60 m of column, scaled by the prefab
POST_WEB = 2  # the waist between the flanges, 0.12 m
BEAM_T, BEAM_H = 4, 6  # 0.24 x 0.36 m cross member
SLAB, SLAB_T = 92, 4  # 5.52 m poured pad, 0.24 m thick

# The collar, widening in three steps from the frame it hugs out to the flange
# that buries itself in rock. Stepped and not a plain plate because only the
# bottom step hangs below the ceiling: a 0.12 m lip read as a painted rectangle
# on the rock rather than as a fitting the shaft passes through.
HOOD_STEPS = ((6, 92), (6, 98), (8, 104))  # (voxels tall, outer width)
HOOD_T = sum(tall for tall, _wide in HOOD_STEPS)  # 20 voxels, 1.20 m
HOOD_LIP = max(wide for _tall, wide in HOOD_STEPS)  # 104 voxels, 6.24 m

# Half the outer frame, and the lattice centre everything is laid out about.
FRAME = BORE + POST * 2  # 82 voxels, 4.92 m
AXIS = HOOD_LIP // 2  # 52

# Where each part sits in the shared lattice: post at the -X/-Z corner, beam on
# the -Z face, pad under everything, hood on top.
POST_AT = AXIS - FRAME // 2  # 11
BEAM_LEN = FRAME - POST  # 74 voxels, post centre to post centre
BEAM_AT = AXIS - BEAM_LEN // 2  # 15


def _post_beam():
    """One I-beam column tile: two flanges and the web between them.

    Three boxes rather than a box and a cut, because the flanges and the web are
    different colours anyway and the I has to read at fifteen metres. Flanges
    lighter than the web: a recess that is not darker than what surrounds it is
    not a recess.
    """
    web_at = (POST - POST_WEB) // 2
    return (
        Box(0, 0, 0, POST - 1, POST_TILE - 1, 1, "steel"),
        Box(0, 0, POST - 2, POST - 1, POST_TILE - 1, POST - 1, "steel"),
        Box(web_at, 0, 2, web_at + POST_WEB - 1, POST_TILE - 1, POST - 3, "steel_dark"),
    )


def _cross_member():
    """One horizontal beam: steel, capped yellow above and shadowed below.

    Straight bands and not chevrons. A chevron breaks every greedy run it
    crosses, and a beam ring is the one part of this that repeats -- at a
    two-metre pitch a 30 m shaft has fifty of them.
    """
    return (
        Box(0, 0, 0, BEAM_LEN - 1, BEAM_H - 1, BEAM_T - 1, "steel"),
        Paint(0, BEAM_H - 1, 0, BEAM_LEN - 1, BEAM_H - 1, BEAM_T - 1, "hazard"),
        Paint(0, 0, 0, BEAM_LEN - 1, 0, BEAM_T - 1, "hazard_dark"),
    )


def _hood_collar():
    """The ceiling collar: a stepped flare, open in the middle.

    Open because the frame carries on up through it, and the darkness inside that
    opening is the only thing in the level that says the shaft goes anywhere. The
    widest step is wider than the bore the level carves, so the flange buries
    itself in rock and there is no seam left to see.

    ONLY THE BOTTOM STEP HANGS BELOW THE CEILING, which is why it is the one that
    is yellow and the one with any depth to it. The first version of this was a
    single 0.12 m plate and rendered as a rectangle painted on the rock.
    """
    inner = AXIS - FRAME // 2
    outer = inner + FRAME - 1
    ops = []
    base = 0
    for tall, wide in HOOD_STEPS:
        at = (HOOD_LIP - wide) // 2
        ops.append(Box(at, base, at, HOOD_LIP - at - 1, base + tall - 1, HOOD_LIP - at - 1, "steel_dark"))
        base += tall
    lip = HOOD_STEPS[0][0] - 1
    return tuple(ops) + (
        Cut(inner, 0, inner, outer, HOOD_T - 1, outer),
        Paint(0, 0, 0, HOOD_LIP - 1, lip, HOOD_LIP - 1, "hazard"),
        # A dark seat where the flare meets the rock, so the yellow reads as a
        # collar hanging off a ceiling rather than as part of the ceiling.
        Paint(0, lip, 0, HOOD_LIP - 1, lip, HOOD_LIP - 1, "hazard_dark"),
    )


def _pad():
    """The poured pad the frame stands on, with form lines down its sides.

    Straight banding on one axis per face: this is the largest flat surface in
    the file and a diagonal across it would cost more than the rest of the model
    put together.
    """
    edge = SLAB - 1
    top = SLAB_T - 1
    return (
        Box(0, 0, 0, edge, top, edge, "concrete"),
        Stripe(0, 0, 0, edge, top, 0, "concrete", "concrete_dark", 8, "x"),
        Stripe(0, 0, edge, edge, top, edge, "concrete", "concrete_dark", 8, "x"),
        Stripe(0, 0, 0, 0, top, edge, "concrete", "concrete_dark", 8, "z"),
        Stripe(edge, 0, 0, edge, top, edge, "concrete", "concrete_dark", 8, "z"),
        # A worn margin round the top, so the pad has an edge rather than ending.
        Paint(0, top, 0, edge, top, 1, "concrete_dark"),
        Paint(0, top, edge - 1, edge, top, edge, "concrete_dark"),
        Paint(0, top, 0, 1, top, edge, "concrete_dark"),
        Paint(edge - 1, top, 0, edge, top, edge, "concrete_dark"),
    )


ELEVATOR_SHAFT = Prop(
    root="shaft_post",
    object_name="elevator_shaft",
    directory="assets/art/environment/elevator_shaft",
    facing="-Z",
    rests_on_ground=True,
    # The reference assembly's plan size and its stack height, not a shaft's.
    declared=(6.2, 2.6, 6.2),
    budget=800,
    palette=("steel", "steel_dark", "hazard", "hazard_dark", "concrete", "concrete_dark"),
    parts=(
        Part(
            name="shaft_base",
            extent=(SLAB, SLAB_T, SLAB),
            ops=_pad(),
            offset=(AXIS - SLAB // 2, 0, AXIS - SLAB // 2),
            pivot=(float(AXIS), 0.0, float(AXIS)),
        ),
        Part(
            name="shaft_post",
            extent=(POST, POST_TILE, POST),
            ops=_post_beam(),
            offset=(POST_AT, SLAB_T, POST_AT),
            pivot=(POST_AT + POST / 2.0, float(SLAB_T), POST_AT + POST / 2.0),
        ),
        Part(
            name="shaft_beam",
            extent=(BEAM_LEN, BEAM_H, BEAM_T),
            ops=_cross_member(),
            offset=(BEAM_AT, SLAB_T + POST_TILE + 2, POST_AT),
            pivot=(float(AXIS), float(SLAB_T + POST_TILE + 2), POST_AT + BEAM_T / 2.0),
        ),
        Part(
            name="shaft_hood",
            extent=(HOOD_LIP, HOOD_T, HOOD_LIP),
            ops=_hood_collar(),
            offset=(0, SLAB_T + POST_TILE + 2 + BEAM_H + 2, 0),
            pivot=(float(AXIS), float(SLAB_T + POST_TILE + 2 + BEAM_H + 2), float(AXIS)),
        ),
    ),
    origin=("centre", "min", "centre"),
    note=(
        "Four meshes in one file, and the file is a PARTS SHEET rather than a\n"
        "shaft: shaft_post is 0.60 m of column, shaft_beam is one cross member,\n"
        "shaft_hood is the ceiling collar and shaft_base is the pad. Height and\n"
        "beam pitch are prefab knobs, so no assembled shaft can be baked here.\n"
        "prefabs/environment/elevator/elevator_shaft.gd reads the four meshes by\n"
        "name and places them; the node offsets below only lay out the reference\n"
        "assembly the validator measures.\n"
        "#\n"
        "# Clear bore 3.96 m square between the post inner faces, which is the\n"
        "# 3.72 m car with 0.12 m a side. Posts on a 4.44 m centre-to-centre\n"
        "# square, 4.92 m across the frame, pad 5.52 m square, collar 6.24 m.\n"
        "# The post tile is uniform along Y because the prefab scales it, and\n"
        "# the prefab sets the beam ring radius itself - it recesses the members\n"
        "# a voxel inside the columns rather than laying them flush, because two\n"
        "# coplanar faces z-fought at every junction."
    ),
)


# --- The wall switch --------------------------------------------------------

SW_W, SW_H = 10, 16  # 0.60 x 0.96 m
SW_BACK = 7  # the wall plane; the fixture hangs off it toward -Z
HINGE = (5.0, 14.0, 3.0)  # top of the blade, at its back face

WALL_SWITCH = Prop(
    root="switch_housing",
    object_name="wall_switch",
    directory="assets/art/environment/wall_switch",
    facing="-Z",
    rests_on_ground=False,
    declared=(0.60, 0.96, 0.48),
    budget=500,
    palette=("iron", "steel_light", "steel_dark", "hazard", "hazard_dark", "red"),
    parts=(
        Part(
            name="switch_housing",
            extent=(SW_W, SW_H, SW_BACK + 1),
            ops=(
                # Mounting plate flat against the wall, then the casting. The
                # casting is yellow, not grey: a grey box with a red panel in it
                # read as a wall vent in the first render. Yellow says "this is
                # the control", and it is the same yellow as the car it drives.
                Box(0, 0, SW_BACK - 1, SW_W - 1, SW_H - 1, SW_BACK, "iron"),
                Box(1, 1, 3, SW_W - 2, SW_H - 2, SW_BACK - 1, "hazard"),
                # The slot the paddle swings in.
                Cut(2, 2, 1, SW_W - 3, SW_H - 2, 4),
                # Dark bezel around the slot, so the paddle has an edge to read
                # against rather than sitting yellow-on-yellow.
                Paint(1, 1, 3, SW_W - 2, SW_H - 2, 3, "hazard_dark"),
                Stripe(1, SW_H - 4, 3, SW_W - 2, SW_H - 2, 3, "hazard", "hazard_dark", 2, "x"),
                Paint(0, SW_H - 1, SW_BACK - 1, SW_W - 1, SW_H - 1, SW_BACK, "steel_dark"),
                # Bolt heads at the plate corners.
                Paint(0, 0, SW_BACK, 0, 0, SW_BACK, "steel_light"),
                Paint(SW_W - 1, 0, SW_BACK, SW_W - 1, 0, SW_BACK, "steel_light"),
                Paint(0, SW_H - 1, SW_BACK, 0, SW_H - 1, SW_BACK, "steel_light"),
                Paint(SW_W - 1, SW_H - 1, SW_BACK, SW_W - 1, SW_H - 1, SW_BACK, "steel_light"),
            ),
        ),
        Part(
            name="switch_paddle",
            extent=(4, 11, 4),
            ops=(
                # Blade in the slot, and a handle knob proud of the housing.
                # The knob is what makes this a lever: a blade flush in a recess
                # is a panel, and the render said so.
                Box(0, 2, 1, 3, 10, 2, "red"),
                Box(0, 0, 0, 3, 2, 3, "steel_light"),
                Paint(0, 10, 1, 3, 10, 2, "steel_dark"),
            ),
            offset=(3, 3, 0),
            # Authored about the hinge, so the container rotates this node about
            # X and the paddle swings instead of orbiting the housing's origin.
            pivot=HINGE,
        ),
    ),
    origin=("centre", "min", "max"),
    note=(
        "Two meshes: switch_housing at identity, and switch_paddle on a\n"
        "translation-only node whose origin IS the hinge, so a container scene\n"
        "swings it by rotating that node about X with no rotation stored in the\n"
        "file. .claude/rules/3d-assets.md allows exactly this -- an axis-aligned\n"
        "pivot is expressible as a translation; a raked one would have to be a\n"
        "Marker3D in the .tscn.\n"
        "#\n"
        "# Origin at the horizontal centre and vertical bottom of the mounting\n"
        "# plate, ON the wall plane (Z = 0), with the fixture extending toward\n"
        "# -Z. rests_on_ground is false because this is a wall fixture, which is\n"
        "# the case the schema names -- so nothing machine-checks the origin and\n"
        "# the preview render is the only confirmation."
    ),
)


# --- The mining laser -------------------------------------------------------

# 1.14 m from emitter to shoulder plate. The first pass was 0.90 m and it
# rendered as a camera: at 15 voxels the receiver ate the barrel and there was
# no length left to read as a barrel at all. A mining cutter is a two-handed
# industrial tool, so it gets the length, a fore grip and heat fins -- length is
# what separates "gun" from "box" in a silhouette this coarse.
LZ = 19

MINING_LASER = Prop(
    root="cutter_body",
    object_name="mining_laser",
    directory="assets/art/gameplay/mining_laser",
    facing="-Z",
    rests_on_ground=True,
    declared=(0.30, 0.66, 1.14),
    budget=600,
    palette=("steel", "steel_dark", "steel_light", "rubber", "cyan", "hazard", "emitter"),
    parts=(
        Part(
            name="cutter_body",
            extent=(5, 11, LZ),
            ops=(
                # Barrel: long, narrow, and the front half of the whole tool.
                # Light, not dark. The first pass had a dark barrel between a
                # white collar and a mid-grey receiver, and at three voxels
                # across it simply vanished -- the tool read as two unrelated
                # boxes floating either side of a gap. Value has to alternate
                # ALONG the length or a silhouette this coarse has no length.
                Box(1, 5, 3, 3, 7, 9, "steel_light"),
                # Heat fins. Two collars that step the barrel wider and back
                # again, which is what stops 7 voxels of tube reading as a peg.
                Box(0, 4, 5, 4, 8, 5, "steel_dark"),
                Box(0, 4, 8, 4, 8, 8, "steel_dark"),
                # Muzzle collar. Yellow: it is the widest thing at the front, it
                # makes the tool nose-heavy in profile, and it is what ties a
                # hand prop to a set whose other two pieces are hazard-banded.
                Box(0, 4, 1, 4, 8, 2, "hazard"),
                # Emitter, emissive and recessed a voxel behind the collar, so
                # the aperture is a lit hole rather than a painted dot. The beam
                # is a runtime effect -- this is what makes the tool read as
                # powered with the beam off.
                Box(1, 5, 0, 3, 7, 0, "emitter"),
                # Receiver, the mass of the thing, behind the barrel.
                Box(0, 4, 10, 4, 8, 15, "steel"),
                # Sight rail along the top of the receiver.
                Box(2, 9, 10, 2, 9, 13, "steel_dark"),
                # Coolant tank over the rear, banded so it reads as a vessel.
                Box(0, 9, 14, 4, 10, 17, "cyan"),
                Paint(0, 9, 16, 4, 10, 16, "steel_dark"),
                # Two grips, because a 1.14 m tool is held with both hands --
                # and two verticals under one horizontal is the most legible
                # "this is a tool" shape there is.
                Box(1, 0, 14, 3, 4, 16, "rubber"),
                Box(1, 1, 9, 3, 4, 10, "rubber"),
                Box(2, 4, 13, 2, 4, 13, "steel_dark"),
                # Shoulder plate.
                Box(0, 4, 18, 4, 9, 18, "steel_dark"),
                # Hazard line along the top edge of the receiver flank. A clean
                # line, not chevrons: a 4x4 patch of diagonal at pitch 3 has
                # room for one and a half bands, and it rendered as a yellow
                # smear with a black staircase through it -- damage, not
                # signage. Chevrons need a run to read as chevrons.
                Paint(0, 8, 10, 0, 8, 15, "hazard"),
                MirrorX(),
            ),
        ),
    ),
    origin=("centre", "min", "centre"),
    anchors=(
        # Mesh-less Empties. Nothing in validate-model-files.py can see a node
        # with no mesh -- the measurement skips it, the transform check only
        # keeps paths that reach a mesh, the axis check ignores roots that never
        # do -- which is what makes them free, and why verify_props_import.gd
        # asserts them instead.
        #
        # They exist so the beam and the hands track the ART. A Marker3D placed
        # by hand in the prefab silently desyncs the first time the recipe moves
        # the emitter; these are regenerated from the same constants as the
        # voxels they name.
        #
        # Both grips are named, because the tool is held in two hands and the two
        # are not interchangeable: the rear one is the trigger hand and the one
        # the character's BoneAttachment3D hangs off, the fore one is the support
        # hand. A single `grip_point` meant the animation had to guess which, and
        # the guess is invisible until the hands are 33 cm apart on the wrong
        # ends. Same height on both, so the tool is carried level.
        ("muzzle_point", (2.5, 6.5, 0.0)),
        ("fore_grip_point", (2.5, 2.5, 10.0)),
        ("rear_grip_point", (2.5, 2.5, 15.5)),
    ),
    note=(
        "Handheld miner's laser cutter on the character's own 0.06 m lattice.\n"
        "A finer grid would make the tool read smoother than the hand holding\n"
        "it, which is the one inconsistency this style cannot absorb: the\n"
        "character is 26 voxels tall, so its hand is about the size of this\n"
        "tool's trigger.\n"
        "#\n"
        "# THE BEAM IS NOT IN THIS FILE. The aperture carries an emissive\n"
        "# material; the beam is spawned at muzzle_point by the prefab.\n"
        "#\n"
        "# Pivot at the bottom centre of the bounding box, emitter down -Z, so\n"
        "# the tool sits correctly when dropped on a floor or a bench. The grips\n"
        "# are anchors, not the origin -- that gives three attach points where an\n"
        "# origin would have given one."
    ),
)

PROPS = (MINING_LASER, ELEVATOR_CAR, ELEVATOR_SHAFT, WALL_SWITCH)


# --- Build ------------------------------------------------------------------


def _resolve_origin(rule, low, high):
    """One axis of the prop origin, in lattice coordinates.

    `high` is already the far face (max voxel + 1), so "max" lands on the
    outside surface -- which is what a wall fixture mounting flush needs.
    """
    if rule == "min":
        return float(low)
    if rule == "max":
        return float(high)
    if rule == "centre":
        return (low + high) / 2.0
    return float(rule)


def build(prop):
    """Resolve every part, mesh it, and return what the writer and spec need."""
    resolved = [(part, part.resolve()) for part in prop.parts]

    used = {colour for _part, voxels in resolved for colour in voxels.values()}
    declared = set(prop.palette)
    if used - declared:
        raise ValueError(f"{prop.stem}: colours used but not in the palette: {sorted(used - declared)}")
    if declared - used:
        raise ValueError(f"{prop.stem}: colours in the palette but unused: {sorted(declared - used)}")

    indices = palette.assign(prop.palette)
    emissive_used = any(colour in palette.EMISSIVE for colour in used)

    def uv_for(colour):
        return palette.slot_uv(indices[colour])

    def material_for(colour):
        return 1 if colour in palette.EMISSIVE else 0

    cells = [cell for _part, voxels in resolved for cell in voxels]
    axes = tuple(zip(*cells))
    low = [min(a) for a in axes]
    high = [max(a) + 1 for a in axes]
    origin = tuple(_resolve_origin(rule, low[k], high[k]) for k, rule in enumerate(prop.origin))

    built = []
    for part, voxels in resolved:
        part_origin = part.pivot or origin
        surfaces = mesher.build(voxels, uv_for, material_for, part_origin, VOXEL)
        shift = tuple((part_origin[k] - origin[k]) * VOXEL for k in range(3))
        built.append((part.name, shift if any(shift) else None, surfaces))

    materials = [gltf_writer.material(f"mat_{prop.object_name}", 0, ROUGHNESS, emissive=False)]
    if emissive_used:
        materials.append(gltf_writer.material(f"mat_{prop.object_name}_lamp", 0, 1.0, emissive=True))

    anchors = [(name, tuple((c - origin[k]) * VOXEL for k, c in enumerate(point))) for name, point in prop.anchors]
    return built, anchors, materials, len(cells)


SPEC_TEMPLATE = """\
# Generated by {generator} -- regenerate rather than edit.
#
{note}
#
# {voxel_count} voxels on a {voxel} m lattice; built bounds {built}.
# The declared width/height/depth are the design intent, not the lattice snap --
# copying the measurement back into the spec would make the check tautological.
width: {width:.4f}
height: {height:.4f}
depth: {depth:.4f}
poly_count_budget: {budget}
up_direction: "+Y"
facing_direction: "{facing}"
root_node_name: "{root}"
collision_expected: false
navigation_expected: false
min_material_count: {materials}
rests_on_ground: {rests}
textures_expected:
  - name: "{texture}"
"""


def _comment(note):
    """A prop note as a block of comment lines.

    A note line that already opens with "#" is a deliberate blank comment line
    and is left alone; prefixing it again is where the "# #" in every shipped
    spec came from.
    """
    lines = []
    for line in note.split("\n"):
        lines.append(line if line.startswith("#") else (f"# {line}" if line else "#"))
    return "\n".join(lines)


def write_spec(prop, out_dir, voxel_count, size, materials, generator=GENERATOR):
    """Write the acceptance spec beside the model.

    A second recipe file passes its own path as `generator`, so the spec's
    "regenerate rather than edit" line names the tool that actually owns it.
    """
    text = SPEC_TEMPLATE.format(
        generator=generator,
        note=_comment(prop.note),
        voxel_count=voxel_count,
        voxel=VOXEL,
        built=" x ".join(f"{s:.2f}" for s in size) + " m",
        width=prop.declared[0],
        height=prop.declared[1],
        depth=prop.declared[2],
        budget=prop.budget,
        facing=prop.facing,
        root=prop.root,
        materials=materials,
        rests="true" if prop.rests_on_ground else "false",
        texture=prop.texture_name,
    )
    path = os.path.join(out_dir, f"{prop.stem}.gltf.spec.yaml")
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)


def main():
    parser = argparse.ArgumentParser(description="Build the voxel props.")
    parser.add_argument("--list", action="store_true", help="report measurements without writing files")
    parser.add_argument(
        "--patch-imports",
        action="store_true",
        help="fix the importer defaults in sidecars Godot has already written, then exit",
    )
    parser.add_argument("--only", default=None, help="build one prop by stem")
    arguments = parser.parse_args()

    props = [p for p in PROPS if arguments.only in (None, p.stem)]
    if not props:
        parser.error(f"no prop named {arguments.only}")

    if arguments.patch_imports:
        import sidecars

        sidecars.patch(REPO_ROOT, props)
        return

    print(f"{'model':<18} {'voxels':>7} {'metres':>24} {'tris':>6} {'budget':>7} {'mats':>5}")
    for prop in props:
        built, anchors, materials, voxel_count = build(prop)
        out_dir = os.path.join(REPO_ROOT, prop.directory)

        if arguments.list:
            size, triangles, _low = _measure(built)
        else:
            os.makedirs(out_dir, exist_ok=True)
            palette.write_png(os.path.join(out_dir, prop.texture_name), palette.render(prop.palette))
            size, triangles, low = gltf_writer.write(
                prop.stem, out_dir, built, anchors, materials, prop.texture_name, GENERATOR
            )
            _assert_placement(prop, low)
            write_spec(prop, out_dir, voxel_count, size, len(materials))

        if triangles > prop.budget:
            raise SystemExit(f"{prop.stem}: {triangles} triangles exceeds the authored budget of {prop.budget}")
        for measured, claimed, axis in zip(size, prop.declared, "XYZ"):
            if abs(measured - claimed) > 0.10 * claimed:
                raise SystemExit(f"{prop.stem}: built {axis} is {measured:.3f} m against a declared {claimed} m")

        print(
            f"{prop.stem:<18} {voxel_count:>7} "
            f"{size[0]:>6.2f} x{size[1]:>6.2f} x{size[2]:>6.2f} m {triangles:>6} {prop.budget:>7} "
            f"{len(materials):>5}"
        )


def _measure(built):
    """Bounds and triangle count without writing anything."""
    lows = [float("inf")] * 3
    highs = [float("-inf")] * 3
    triangles = 0
    for _name, shift, surfaces in built:
        offset = shift or (0.0, 0.0, 0.0)
        for positions, _normals, _uvs, indices in surfaces.values():
            axes = tuple(zip(*positions))
            lows = [min(lo, min(a) + o) for lo, a, o in zip(lows, axes, offset)]
            highs = [max(hi, max(a) + o) for hi, a, o in zip(highs, axes, offset)]
            triangles += len(indices) // 3
    return [h - l for l, h in zip(lows, highs)], triangles, lows


def _assert_placement(prop, low):
    """The origin conventions the validator cannot check for us.

    rests_on_ground is the one the spec can assert, and only when it is true.
    For a wall fixture it is false by the schema's own instruction, which means
    nothing downstream would notice an origin that drifted -- so assert it here.
    """
    if prop.rests_on_ground and abs(low[1]) > 1e-6:
        raise SystemExit(f"{prop.stem}: rests_on_ground but the lowest point is at Y={low[1]:.4f}")


if __name__ == "__main__":
    main()
