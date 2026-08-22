"""The authoring format: a voxel prop described as an ordered list of ops.

`tools/voxel-rubble/build_rubble.py` grows its shapes out of noise, and its own
README admits the consequence -- "a recipe is not a shape", so it walks seeds
until one comes out acceptable. These props are the opposite case. An elevator
car and a wall switch are *designed*, not grown, so the recipe here IS the shape:
additive boxes, subtractive cuts, and repaints, applied in order.

    Box(0, 0, 0, 9, 3, 5, "steel")   # fill an inclusive voxel range
    Cut(2, 1, 1, 7, 3, 4)            # carve it hollow
    Paint(0, 3, 0, 9, 3, 5, "amber") # recolour what is already there
    Stripe(...)                      # hazard banding across a face
    MirrorX()                        # mirror everything so far

Every coordinate is an integer voxel index into the part's lattice, and every
range is inclusive at both ends -- Box(0, 0, 0, 0, 0, 0) is one voxel. Inclusive
because these are hand-typed: a doorway "from voxel 15 to voxel 46" is a
measurement someone reads off a drawing, and a half-open range turns every one
of those into an off-by-one waiting to happen.

Resolving produces `{(x, y, z): colour_name}`. Nothing here knows about metres,
palettes or glTF; mesher.py and gltf_writer.py take it from there.
"""

from __future__ import annotations

import itertools
from dataclasses import dataclass


def _cells(x0, y0, z0, x1, y1, z1):
    """Every voxel in an inclusive range, tolerant of reversed bounds."""
    return itertools.product(
        range(min(x0, x1), max(x0, x1) + 1),
        range(min(y0, y1), max(y0, y1) + 1),
        range(min(z0, z1), max(z0, z1) + 1),
    )


# --- Ops --------------------------------------------------------------------
#
# Each op is a plain record with an apply() that mutates the voxel dict in
# place. Ops are frozen so a recipe cannot be edited after it is declared, and
# so a PROPS table is safe to read twice.


@dataclass(frozen=True)
class Box:
    """Fill an inclusive voxel range with one colour, overwriting what is there."""

    x0: int
    y0: int
    z0: int
    x1: int
    y1: int
    z1: int
    paint: str

    def apply(self, voxels, extent):
        for cell in _cells(self.x0, self.y0, self.z0, self.x1, self.y1, self.z1):
            voxels[cell] = self.paint


@dataclass(frozen=True)
class Cut:
    """Remove every voxel in an inclusive range."""

    x0: int
    y0: int
    z0: int
    x1: int
    y1: int
    z1: int

    def apply(self, voxels, extent):
        for cell in _cells(self.x0, self.y0, self.z0, self.x1, self.y1, self.z1):
            voxels.pop(cell, None)


@dataclass(frozen=True)
class Paint:
    """Recolour voxels in an inclusive range. Adds nothing -- empty stays empty.

    This is what puts a yellow band on a hull that is already the right shape,
    which is the whole reason surfacing is a separate step from geometry: the
    silhouette can be settled and re-cut without touching a single colour.
    """

    x0: int
    y0: int
    z0: int
    x1: int
    y1: int
    z1: int
    paint: str

    def apply(self, voxels, extent):
        for cell in _cells(self.x0, self.y0, self.z0, self.x1, self.y1, self.z1):
            if cell in voxels:
                voxels[cell] = self.paint


@dataclass(frozen=True)
class Stripe:
    """Diagonal hazard banding across existing voxels in a range.

    `axes` names the two lattice axes the diagonal runs across -- "xy" for a
    wall you look at down Z, "xz" for a floor. Bands are `pitch` voxels wide;
    at 0.06 m a pitch of 3 is an 18 cm stripe, which is about what real hazard
    tape looks like at this scale and, more usefully, is wide enough that the
    greedy mesher still merges runs within a band.

    Name ONE axis instead and the bands run straight rather than diagonally --
    panel lines down a hull side. Worth preferring where it reads: a diagonal
    breaks every greedy run it crosses, so chevrons across a whole wall cost
    several times what straight banding does. Chevrons are for the places that
    have to shout.
    """

    x0: int
    y0: int
    z0: int
    x1: int
    y1: int
    z1: int
    paint: str
    alternate: str
    pitch: int = 3
    axes: str = "xy"

    def apply(self, voxels, extent):
        picked = [
            "xyz".index(axis) for axis in self.axes
        ]
        for cell in _cells(self.x0, self.y0, self.z0, self.x1, self.y1, self.z1):
            if cell not in voxels:
                continue
            band = sum(cell[axis] for axis in picked) // self.pitch
            voxels[cell] = self.paint if band % 2 == 0 else self.alternate


@dataclass(frozen=True)
class MirrorX:
    """Mirror everything placed so far about the lattice's X centre.

    Declared once and applied where it sits in the list, so a part can be built
    symmetric, mirrored, and then have asymmetric detail added after. The mirror
    is about the lattice, not about the occupied bounds -- mirroring about a
    bounding box that later ops will grow would move the axis of symmetry
    depending on the order things were typed in.
    """

    def apply(self, voxels, extent):
        last = extent[0] - 1
        for (x, y, z), paint in list(voxels.items()):
            voxels.setdefault((last - x, y, z), paint)


# --- Parts and props --------------------------------------------------------


@dataclass(frozen=True)
class Part:
    """One glTF mesh node: a name, a lattice to build in, and the ops to build it.

    `name` becomes the node name in the glTF, so it must be clear of every entry
    in GODOT_NODE_SUFFIXES (tools/gltf-validator/gltf_godot_import.py) and must
    not equal the file stem -- Godot names the imported scene root after the
    file, and a child with the same name silently becomes "<stem>2".
    """

    name: str
    extent: tuple
    ops: tuple
    offset: tuple = (0, 0, 0)
    pivot: tuple = None
    """Where this part's own (0, 0, 0) goes, in shared lattice coordinates.

    Left unset, the part shares the prop's origin and its node carries no
    transform at all -- right for anything that only ever slides, because a
    slide is just `position.x` moving away from zero.

    Set it for a part that ROTATES. A lever swinging about its hinge has to be
    authored about that hinge, and the node then carries the translation from
    the prop origin out to it. `.claude/rules/3d-assets.md` allows exactly this:
    a translation is reported and never failed, so an axis-aligned pivot is the
    one articulation a glTF can carry here. A raked pivot cannot be, and would
    have to become a Marker3D in the container scene.
    """

    def resolve(self):
        """Ops -> {(x, y, z): colour_name}, in the prop's shared lattice space."""
        voxels = {}
        for op in self.ops:
            op.apply(voxels, self.extent)
        for cell in voxels:
            for axis in range(3):
                if not 0 <= cell[axis] < self.extent[axis]:
                    raise ValueError(f"{self.name}: voxel {cell} is outside extent {self.extent}")
        if not voxels:
            raise ValueError(f"{self.name}: no voxels survived; every op removed what the last one added")
        return {
            (cell[0] + self.offset[0], cell[1] + self.offset[1], cell[2] + self.offset[2]): paint
            for cell, paint in voxels.items()
        }


@dataclass(frozen=True)
class Prop:
    """One glTF file: every part a scene root, plus any mesh-less anchors.

    No wrapper node. Godot's importer already names the scene root after the
    file and hangs the glTF's roots off it, so adding an Empty here would only
    buy a redundant level in every scene that instances the thing.

    `origin` is where the file's (0, 0, 0) lands, per axis, resolved once
    against the union of every part -- so an elevator car's doors keep their
    position relative to its shell. Each entry is "centre", "min", "max", or a
    float lattice coordinate.

    `declared` is the design intent in metres, which is deliberately not the
    same as what gets built: the lattice snaps every dimension by up to half a
    voxel, and a spec back-filled from the measurement checks nothing.

    `palette` is an explicit ordered tuple rather than whatever the recipe
    happened to use, because that order fixes which swatch each colour lands in,
    which fixes every UV in the file. It is checked both ways against what the
    ops actually paint -- a colour missing from it is an error, and so is one
    listed but never used.
    """

    root: str
    object_name: str
    directory: str
    parts: tuple
    origin: tuple
    palette: tuple
    declared: tuple
    budget: int
    facing: str = "-Z"
    rests_on_ground: bool = False
    anchors: tuple = ()
    note: str = ""

    @property
    def stem(self):
        return f"sm_{self.object_name}"

    @property
    def texture_name(self):
        return f"t_{self.object_name}_basecolor.png"
