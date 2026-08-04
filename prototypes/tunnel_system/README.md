# tunnel_system

A 200 m cube of branching underground tunnels you can fly around in, built to
answer one thing: **what does moving through this place actually feel like?**

Nothing here is a mechanic. There is no ore, no oxygen, no creature, no tether.
It is a space, a suit, and a lamp — so that questions about the space get
answered without anything else muddying them.

```
godot --path <root> res://prototypes/tunnel_system/tunnel_system_prototype.tscn
```

WASD + space/ctrl to thrust, mouse to look, Q/E to roll, shift to stabilise,
R to respawn, escape to release the mouse.

Press **escape** and use the panel in the bottom left: it drops you straight into
any size of tunnel in the level, and lets you drag the lamp cone and the view
distance while you fly.

---

## The questions it exists to answer

### How long does anything take?

There is about a kilometre of tunnel in here and the suit tops out at 4 m/s.
Flying every metre of it once is roughly four minutes — so a round trip to the
bottom and back is most of a run, and that is the point. The asteroid brief
budgets five minutes for the whole loop.

- Does the trip to the deepest chamber feel like a **journey** or like a commute?
- At what depth do you start thinking about the trip *back*?
- Is 4 m/s too slow to be pleasant, or is the slowness the tension?

The HUD prints depth, speed, and straight-line distance home. Watch that last
number climb and notice when it starts to bother you.

### What is it like to travel here?

There is no up. There is no horizon. Every wall is the same rock, and you can
see about 22 metres.

- Can you tell which way you came from?
- Does rolling to line up with a tunnel feel natural or fiddly?
- When you come out of a bend, do you know where you are — and do you care?
- Is bouncing off a wall a mistake you regret, or just how you get around?

### What is it like when it gets tight?

The tunnels are deliberately not one size:

| | Diameter | Feels like |
|---|---|---|
| Trunk routes | 8 m | Room to turn, room to be caught |
| Connectors | 6 m | Comfortable |
| Branches | 3 m | You are threading it |
| Tight spurs and the squeeze | 2–2.5 m | Barely wider than your reach |

You are a 0.8 m ball. In a 2 m tunnel that leaves about half a metre either side.

The bottom-left panel jumps between all of these, so the comparison takes a
second rather than a four-minute flight and a good memory. Bounce between the
core chamber and the tight spur a few times.

- At what width does flying stop being flying and start being **crawling**?
- Is a tight tunnel exciting, or just slow and annoying?
- Can you turn around in a dead-end spur, or do you have to reverse out?
- Does going from an 8 m trunk into a 2.5 m branch read as *going somewhere
  worse*?

### Does the tight/wide split do anything?

The creature from the other prototypes is nearly 4 m across and needs about 6.5 m
of clearance. Only three routes here are wide enough for it: the entrance shaft,
the east trunk, and the deep shaft.

Everything else is somewhere it cannot go.

- Does a tunnel too small for the thing chasing you read as **safety**?
- Or does it just read as a corridor, because nothing is chasing you yet?
- `the_squeeze` is 170 m of 2.5 m tunnel connecting the west side to the bottom.
  From the west it is the direct way down — about 170 m against 210 m going back
  and around. Is that trade legible while you are flying it, or only on a map?

### Can you find your way?

Junctions are marked with small coloured lights, and the HUD has a map: a plan
view on top, a side-on view underneath, with you as a green dot.

- How long before you are properly lost?
- Do the coloured lights work as landmarks, or do they all blur together?
- **Try it with the map covered.** That is the real test.

---

## A run worth doing

1. Start at the mouth and go straight down. Note when you lose the daylight.
2. At the first chamber, take the east trunk. Wide, fast, easy.
3. Keep going down the deep shaft to the bottom hub.
4. Now find your way back **without using the map**.
5. Do it again, but come back through `the_squeeze` and out the west side.

Then say which of those five you would want to do a second time.

---

## What you can change quickly

**While flying**, from the bottom-left panel: lamp cone width and view distance.
Neither is saved — when you find values you like, read them off the panel and put
them in `tunnel_knobs.gd`.

**Between runs**, everything else lives in `tunnel_knobs.gd` too, each number
with a note on why it is what it is. The ones most worth arguing about:

- **Tunnel widths** — the four bore sizes above.
- **The teleport stops** — add one anywhere you keep wanting to get back to.
- **The layout itself** — junctions and routes are a plain list of coordinates.

The layout is also a set of ordinary `Path3D` curves in
`paths/tunnel_paths.tscn`. Open it, drag a curve point, re-run the two build
commands in `tools/`, and the cave changes shape. You do not have to touch code
to move a tunnel.

---

## What it deliberately does not have

No ore, no mining, no oxygen or power, no tether, no creature, no objective, and
no second player. Every one of those would change how the space feels, and the
space has to be judged on its own first.

It also has no *content* — no set pieces, no reason to prefer one branch over
another. If a route feels pointless, that is expected; the question is whether it
feels **good to fly**, not whether it is worth flying to.

---

## Known rough edges

- **Wide chambers read as black voids.** Their far walls are past the lamp's
  throw. Deliberate, but it means the junction chambers currently register as
  "somewhere the tunnel got bigger" rather than as places.
- **Faint ring-shaped banding in the two biggest chambers.** A shadow artefact,
  very dim, cosmetic. Known and left alone.
- The walls are untextured grey. Speed is hard to judge without surface detail —
  worth remembering before concluding the movement is too slow.

---

*Technical notes — how the cave is generated, and the traps involved — live in
the comments of the scripts themselves, and are not needed to play it.*
