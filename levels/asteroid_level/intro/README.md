# The elevator intro

The asteroid level's opening. Forty-two seconds: a descent, a match cut into the
player's own head, the doors opening onto the mine, and a door shut in their face.

```
"D:/Godot_v4.7.1-stable_win64.exe" --path <repo> \
  res://levels/asteroid_level/asteroid_level.tscn
```

`run/main_scene` is the main menu, so a run has to name the scene or it boots the
menu instead. **Enter** skips. `AsteroidLevel.play_intro` turns it off entirely,
which is how you work on anything else in this level.

To tune it rather than play it, open the prototype instead — same sub-scene, plus
a greybox shaft and a slider panel. See `prototypes/elevator_cutscene/README.md`.

## The beats

| t (s) | What you see | What changes |
|---|---|---|
| 0.0–3.0 | the quota terminal, full screen | `car_descending` |
| 3.0–5.5 | pull back off the glass, revealing the car | |
| 5.5–11.5 | locked-off wide on three miners descending | |
| 11.5–16.5 | push in on MinerB; their helmet comes online | |
| **17.5** | **match cut to the player's own eye; the HUD strikes like a tube** | `hud_online` |
| 18.7 | | `hud_settled` |
| 20.5 | the car lands, strobe, BEGIN WORKDAY | `car_stopped` |
| 21.1–23.7 | the doors open | `doors_unlocked` |
| 24.5–25.5 | a beat, looking out at the mine | |
| **25.5–30.0** | **drifting out through the doorway** | |
| **30.0–32.0** | **turning, and sidling across to the call panel** | |
| **32.2–34.8** | **the doors shut** | `doors_locked` |
| **35.0–37.0** | **a hand comes up and presses the panel** | |
| **36.0** | **strobe, the tube sags, "Access denied."** | `access_denied` |
| 40.0–42.0 | panning back onto the mine, then control | `workday_begun` |

## The three rules this is built on

**The clock is authoritative and the animation is not.** Everything you can see is
a track in `animations/elevator_intro.anim.tres`; everything that changes the world
is a timestamped entry in `cutscenes/elevator_intro.cutscene.tres`, dispatched off
a clock that is *not* the animation's playhead. The pair that makes the case is
`doors_unlocked` / `doors_locked`: the leaves sliding is animation, the colliders
coming off and going back on is state, and dropping either on a skip leaves the
player sealed inside a box whose doors are visibly open, or swimming through one
whose doors just shut in their face.

**Shot timings are baked. There is no slider for them.** Times and camera poses
live in `elevator_intro_knobs.gd` and are compiled into the `.anim.tres`:

```
"D:/Godot_v4.7.1-stable_win64.exe" --headless --path <repo> \
  --script res://levels/asteroid_level/intro/tools/build_elevator_intro_animation.gd
```

Re-running it overwrites Animation Dock edits. Once a director starts tweaking
keys in the dock, stop running it — or move the number that keeps changing into
the knobs file so both stay true.

**Poses are in this sub-scene's space, not the level's.** `elevator_intro.tscn` is
instanced twice — into `asteroid_level` at the mine mouth, and into the prototype's
greybox shaft — and a shot composed in world coordinates would only be right in
one of them. `AnimationPlayer.root_node` points at the intro's root for the same
reason.

## Where it sits in the level

`asteroid_level.tscn` places the intro against the back wall of `mine_mouth`, the
dead-end chamber the player spawns in, with the doorway east onto the level's only
drift. **The placement exists to make one number true:** `PlayerExit` lands exactly
on `%PlayerSpawn`, so the teleport at the end of the cutscene is invisible and
respawn goes on using the marker it always used. `[spawn]` in the verifier checks
it, because nothing else would: get the placement wrong and the cutscene still
plays perfectly, then drops the player somewhere else in the chamber.

Two ways to get that placement wrong, both of which cost an afternoon and both of
which look like a bug in the cutscene rather than in the level:

> A `Transform3D` in a `.tscn` serialises its basis as **rows**, so the basis
> vectors are the columns. `Transform3D(0, 0, -1, 0, 1, 0, 1, 0, 0, …)` is the
> one that sends local −Z to world +X; the transpose is also a valid right-handed
> basis and points the other way.

> **Every node between an animated node and the animation root must be a `Node3D`.**
> A plain `Node` detaches the 3D hierarchy below it: the next `Node3D` down becomes
> its own transform root, its global transform equals its local one, and the whole
> cutscene plays at the world origin however the level placed this scene. Nothing
> errors. It is invisible in any harness that sits at the origin — which the
> prototype does — so `[hierarchy]` walks the chain instead.

## Three things that will surprise you

**The player's body rides the camera anchor.** From the match cut on,
`ElevatorIntroEffects.advance()` writes `rig.global_transform = anchor.global_transform`
every frame. The press is rendered from the player's *own rig*, so by 35 s the body
has to actually be outside the car — and keyframing a `CharacterBody3D` the solver
is also touching is how a rig jitters or gets ejected. Derived every frame, never
stored, so it scrubs and it skips.

**The arm is one number, not a clip.** An AnimationTree layer runs on its own
real-time clock and does not scrub, so the gesture layer holds a single pose solved
by two-bone IK at build time and the master clip keys only its blend weight. The
player's weight is reached through `Cutscenes/ElevatorIntro/Gesture`, a proxy node
*inside* the cutscene — the player is spawned into `Players/Player` at run time and
a track path that walked out to it would resolve to nothing, silently.

**The VO is an effect, not an audio track.** A `TYPE_AUDIO` track would be wiped by
the next build-script run, and a line that has to survive a skip decision belongs
with the state. It plays on the `Dialogue` bus and is faded out over 100 ms rather
than hard-stopped, because a hard cut on a vowel is audibly a bug.

## Checking it

```
# the assertions
"D:/Godot_v4.7.1-stable_win64.exe" --headless --path <repo> \
  res://levels/asteroid_level/intro/verify_elevator_intro.tscn

# the shots, as PNGs under user://shots - look at them
"D:/Godot_v4.7.1-stable_win64.exe" --path <repo> --resolution 1280x720 \
  res://prototypes/elevator_cutscene/tools/capture_shots.tscn
```

**Run both.** Every check in the suite passed against a draft in which the wide
shot was a miner's head filling the frame and the helmet emission blew the climax
out to a white blob. Geometry assertions cannot see composition.

The checks worth knowing about, beyond the ones the prototype already had:

| Check | The silent failure it catches |
|---|---|
| `[spawn]` | the intro's exit pose drifting off `%PlayerSpawn` — see above |
| `[hierarchy]` | a plain `Node` in the chain detaching the shot from the level placement |
| `[doors_closed]` | doors visually shut with their colliders still off: `doors_unlocked` in reverse |
| `[hud_boot]` | the HUD left inside the boot overlay's SubViewport, so the game has no HUD at all |
| `[press]` | the gesture filtered onto the wrong arm, or the cutter left hidden |
| `[vo]` | the line running past the end of the clip, so it is cut off mid-word on every playthrough |
| `[input_lock]` | a pause or a respawn handing control back mid-shot |
| `[equivalence]` | skipping inside any of the ten sampled moments landing on a different world state than watching |

## Known rough edge

**The press insert needs a first-person view-model arm.** The hand is the player's
real skeleton, and its shoulder sits about 0.33 m to the side of the lens and 0.48 m
below it — so a raised arm sweeps the upper arm across frame before the hand gets
anywhere. Every first-person game solves this with a separate arm mesh posed for the
camera rather than for the body; without one, no amount of camera aiming fixes it.
`PRESS_HAND_OFFSET`, `PRESS_ELBOW_POLE` and `PRESS_AIM` are the dials, and
`t36.0_contact_denied.png` is the frame to judge them by.
