"""Checks for models that are valid glTF but wrong once Godot imports them.

Everything in the rest of this validator asks "is this file correct". These checks
ask a different question: "will this file still be correct after Godot has
finished with it". A model can satisfy the glTF spec, the size checks, the poly
budget and the transform rules, and still arrive in the engine as the wrong kind
of node, resting below the floor, playing an animation that does not repeat, or
claiming a size no render agrees with.

Most of them came out of building assets/art/vehicles/jeep_turret, and each cost a
full round trip -- export, import, open the scene, read the tree -- to find by
hand. They are cheap to compute from the glTF JSON, so they belong in the gate
rather than in a checklist.

* **Node type suffixes.** Godot's importer reinterprets node names, and its
  `_teststr()` matches `-name`, `_name` AND `$name`. That is the mechanism behind
  `-convcolonly`, so it cannot be turned off -- and it means an ordinary
  descriptive name can silently change a node's class. A mesh called
  `steering_wheel` imported as a `VehicleWheel3D`: a physics node that only
  functions parented to a `VehicleBody3D`, from a file where nothing was wrong.
* **Animation loop flags.** The same importer reads a trailing `loop` or `cycle`
  on an *animation* name and imports that clip looping, with the flag stripped
  from the name. It is the supported way to ship a looping clip, so this pipeline
  uses it -- and checks that a clip which loops says so as `-loop`, because every
  other spelling Godot honours also loops clips nobody meant to loop.
* **Oversized collision.** The size checks measure the whole file, so a collision
  proxy larger than the art it stands in for *becomes* the model's declared width,
  height or depth. The failure then reads as a modelling error against a number
  invisible in every render.
* **Ground contact.** Nothing else checks that a model rests on the floor, and
  everything downstream assumes it. Opt-in, because plenty of assets legitimately
  do not -- a wall bracket, a ceiling lamp, a floating drone.

Node suffixes and animation flags are separate mechanisms and are easy to conflate.
`loop` and `cycle` are animation-only: a *node* named `crate_loop` imports
untouched. Everything above is verified against Godot 4.7.1.

Standard library and numpy only, like the rest of the non-Docker checks.
"""

from __future__ import annotations

import re

import numpy as np

from gltf_measure import node_bounds

# Godot's ResourceImporterScene node-type suffixes, and what each one produces.
# Sourced from its _pre_fix_node handling; the values are what an artist sees in
# the scene tree afterwards.
#
# `loop` and `cycle` are deliberately NOT here. They are animation flags, not node
# flags -- see the animation section below. Verified against 4.7.1: a node named
# `crate_loop` imports as an untouched MeshInstance3D still called `crate_loop`.
GODOT_NODE_SUFFIXES = {
    "col": "StaticBody3D with trimesh collision",
    "colonly": "StaticBody3D, visual mesh discarded",
    "convcol": "StaticBody3D with convex collision",
    "convcolonly": "StaticBody3D with convex collision, visual mesh discarded",
    "navmesh": "NavigationRegion3D",
    "vehicle": "VehicleBody3D",
    "wheel": "VehicleWheel3D",
    "rigid": "RigidBody3D",
    "occ": "OccluderInstance3D",
    "occonly": "OccluderInstance3D, visual mesh discarded",
    "noimp": "nothing -- the node is skipped entirely on import",
}

# The suffixes this pipeline uses on purpose. documentation/pipeline/pipeline.yaml
# documents collision and navmesh as the supported way to ship those; the rest of
# the list is only ever reached by accident here, which is why it is worth
# reporting.
INTENDED_SUFFIXES = frozenset({"col", "colonly", "convcol", "convcolonly", "navmesh"})

# Suffixes that make Godot build collision from the mesh.
COLLISION_SUFFIXES = frozenset({"col", "colonly", "convcol", "convcolonly"})

# Godot separates a suffix from the rest of the name with any of these.
SUFFIX_SEPARATORS = "-_$"

# Godot strips trailing digits before testing a suffix and puts them back after,
# so `steering_wheel2` is still a VehicleWheel3D -- it imports as `steering2`.
TRAILING_DIGITS = re.compile(r"\d*$")

# Millimetres past the art are the faceting of a curved proxy against the flat
# mesh approximating it; centimetres are a proxy that is genuinely the wrong size.
# The case this exists to catch overshot by 70mm.
COLLISION_SLACK = 0.01

# Ground contact is measured in glTF space, where up is +Y.
UP_AXIS = 1
GROUND_TOLERANCE = 0.01


def node_suffix(name):
    """The Godot type suffix a node name ends in, or None."""
    if not name:
        return None
    tail = re.split(f"[{re.escape(SUFFIX_SEPARATORS)}]", str(name).lower())[-1]
    tail = TRAILING_DIGITS.sub("", tail)
    return tail if tail in GODOT_NODE_SUFFIXES else None


def is_collision_node(name):
    return node_suffix(name) in COLLISION_SUFFIXES


def _node_names(document):
    return [(node.get("name") or "") for node in (document.get("nodes") or [])]


def _animation_names(document):
    return [(anim.get("name") or "") for anim in (document.get("animations") or [])]


def find_surprising_suffixes(document, allowed=()):
    """Nodes Godot will reinterpret that this pipeline did not ask it to.

    Returns [(node name, suffix, what Godot makes of it)]. `allowed` lets a model
    opt a suffix in through its spec, for the rare case where a VehicleBody3D or a
    RigidBody3D really is the intent.
    """
    permitted = INTENDED_SUFFIXES | {str(entry).lower().lstrip("-_$") for entry in allowed}
    found = []
    for name in _node_names(document):
        suffix = node_suffix(name)
        if suffix is not None and suffix not in permitted:
            found.append((name, suffix, GODOT_NODE_SUFFIXES[suffix]))
    return found


# --- animation loop flags -----------------------------------------------------
#
# A trailing `loop` or `cycle` on an ANIMATION name is how Godot is told the clip
# repeats: it imports with loop_mode LOOP_LINEAR and the flag is stripped off the
# name. Verified against 4.7.1 -- `idle_float-loop` imports as `idle_float`,
# looping. Matching is case-insensitive, end-anchored, and ignores trailing digits
# (`walk_loop2` imports as `walk2`), so a flag in the middle of a name is inert:
# `idle_loop_fast` does not loop.
#
# This pipeline writes `-loop` and nothing else. Every other spelling Godot
# accepts still loops the clip, which is exactly what makes them worth failing:
# the ones nobody chose on purpose are indistinguishable from the ones they did.
ANIMATION_LOOP_FLAGS = ("loop", "cycle")
CANONICAL_LOOP_SUFFIX = "-loop"

LOOP_FLAG_PATTERN = re.compile(
    r"(?P<flag>[{separators}]?(?:{flags}))(?P<digits>\d*)$".format(
        separators=re.escape(SUFFIX_SEPARATORS),
        flags="|".join(ANIMATION_LOOP_FLAGS),
    ),
    re.IGNORECASE,
)


def animation_loop_flag(name):
    """How Godot reads a loop flag off an animation name.

    Returns (flag as authored, name after import) for a clip that will import
    looping, or None for one that will not.
    """
    match = LOOP_FLAG_PATTERN.search(str(name or ""))
    if match is None:
        return None
    flag = match.group("flag")
    if flag[0] not in SUFFIX_SEPARATORS:
        # Without a separator Godot still loops the clip but has nothing to strip,
        # so the flag stays: `walkloop` imports as `walkloop`.
        return flag, name
    return flag, name[: match.start()] + match.group("digits")


def imported_animation_name(name):
    """What a clip is called once Godot has imported it."""
    found = animation_loop_flag(name)
    return found[1] if found else name


def find_animation_loop_issues(document):
    """Animations Godot will loop that are not spelled this pipeline's way.

    Returns [(name, flag, imported name)]. Covers both halves of the problem: a
    clip that loops by accident because its name happens to end in those letters,
    and one that loops on purpose but says so in a spelling the rest of the
    repository does not use.
    """
    issues = []
    for name in _animation_names(document):
        found = animation_loop_flag(name)
        if found is None:
            continue
        flag, imported = found
        # Compared exactly, not case-folded: `-Loop` loops the clip just as well,
        # and names are lowercase everywhere else in this repository.
        if flag == CANONICAL_LOOP_SUFFIX:
            continue
        issues.append((name, flag, imported))
    return issues


def looping_animations(document):
    """The imported names of every clip that will loop."""
    return [
        imported_animation_name(name)
        for name in _animation_names(document)
        if animation_loop_flag(name) is not None
    ]


def split_bounds(document):
    """((visual min, visual max), (collision min, collision max)); None when empty."""
    names = _node_names(document)
    visual_lo = visual_hi = collision_lo = collision_hi = None

    for index, (low, high) in node_bounds(document).items():
        name = names[index] if index < len(names) else ""
        if is_collision_node(name):
            collision_lo = low if collision_lo is None else np.minimum(collision_lo, low)
            collision_hi = high if collision_hi is None else np.maximum(collision_hi, high)
        else:
            visual_lo = low if visual_lo is None else np.minimum(visual_lo, low)
            visual_hi = high if visual_hi is None else np.maximum(visual_hi, high)

    visual = (visual_lo, visual_hi) if visual_lo is not None else None
    collision = (collision_lo, collision_hi) if collision_lo is not None else None
    return visual, collision


def oversized_collision(document, slack=COLLISION_SLACK):
    """How far collision proxies stick out past the art, per axis.

    Returns [(axis name, 'below'/'above', metres)]. Empty when the proxies sit
    inside the visual mesh, and empty when the model has no collision or no visual
    geometry to compare against.
    """
    visual, collision = split_bounds(document)
    if visual is None or collision is None:
        return []

    (visual_lo, visual_hi), (collision_lo, collision_hi) = visual, collision
    findings = []
    for axis, name in enumerate("XYZ"):
        under = float(visual_lo[axis] - collision_lo[axis])
        over = float(collision_hi[axis] - visual_hi[axis])
        if under > slack:
            findings.append((name, "below", under))
        if over > slack:
            findings.append((name, "above", over))
    return findings


def ground_offset(document):
    """Distance from Y=0 to the lowest point of the model, or None if unmeasurable.

    Collision is included deliberately: what a vehicle rests on is its collision,
    not its art, and the two are allowed to differ by a few millimetres where a
    faceted wheel approximates a round hull.
    """
    bounds = node_bounds(document)
    if not bounds:
        return None
    return float(min(low[UP_AXIS] for low, _high in bounds.values()))
