# Elevator Cutscene

Does this project want cutscenes, and does the architecture in
`../cutscene_tool/cutscene-tool-requirements.md` actually hold up? This is the
walking skeleton that answers both — steps 1–4 of that document's build order,
single-player. Its own code is scoped to this directory; its art and its player
are the shipped ones, instanced from `assets/` and `prefabs/`.

It plays the opening beat from *Pitch for Opening Gameplay Movie: Scene 1*: it
opens full-screen on the car's quota terminal and pulls back to reveal three
miners in a descending elevator, one activating their helmet, a match cut to
first person, and the doors opening onto the mine with control handed back.

The opening shot is the readout itself, not a picture of it. `MonitorShot`
samples the very `SubViewport` texture the 3D plate composites, through a
canvas_item port of the same CRT shader, so there is one readout in the scene and
the words on the 2D shot cannot drift from the words on the wall. At
`PROLOGUE_LENGTH` the overlay cuts out onto a camera already parked nose-on the
glass, and the cut is a cut with nothing in it.

It was built out of greybox — a CSG car, box-limb miners, a cylinder for a
cutter, and an invisible sphere for the player. **It now runs on the shipped
art**, so it is a rough cut of the opening rather than a diagram of it. See
*The art is referenced, not copied* below.

## Running it

```
"D:/Godot_v4.7.1-stable_win64.exe" --path <repo> \
  res://prototypes/elevator_cutscene/elevator_cutscene_prototype.tscn
```

Or F6 in the editor. `run/main_scene` is the main menu, so a headless run has to
name the scene or it boots the menu instead.

| Key | Does |
|---|---|
| **Enter** | Skip |
| **P** | Replay from the top, from anywhere |
| WASD / Space / Ctrl / mouse | Fly, once control is yours |
| Esc | Free the mouse for the tuning panel |

Both cutscene keys are registered into the running process's `InputMap` by
`elevator_cutscene_input.gd`. **`project.godot` is not touched.**

## The three claims it tests

**A cutscene can take the camera off a live player and give it back.**
`cutscene_camera_driver.gd` is the spec's §7 seam in about ninety lines:
`request_control(anchor, authority, blend_time)` / `release_control(blend_time)`,
a smoothstepped lerp/slerp, and an explicit `current` handover. It is a
*dedicated* camera, not the player's head camera — see the docstring for why that
is not a detail.

**Keyframes and state changes can be kept apart, and skipping proves it.**
Everything you can see is a track in `animations/elevator_intro.anim.tres`.
Everything that changes the world is a timestamped entry in
`cutscenes/elevator_intro.cutscene.tres`, dispatched off an authoritative clock
that is *not* the animation's playhead. The effect that makes the case is
`doors_unlocked`: the doors sliding is animation, the colliders coming off is
state, and dropping it on a skip seals the player inside a box whose doors are
visibly open.

**A director can scrub the shot and see what will run.** Select
`Cutscenes/ElevatorIntro/CameraAnchor/PreviewCamera`, hit **Preview**, drag the
timeline. That is the whole payoff for not adopting a runtime tweening addon.

## Three things that will surprise you

**Shot timings are baked. There is no slider for them.** Times and camera poses
live in `elevator_cutscene_knobs.gd` and are compiled into the `.anim.tres` by
`tools/build_elevator_intro_animation.gd`. Change one, re-run the script:

```
"D:/Godot_v4.7.1-stable_win64.exe" --headless --path <repo> \
  --script res://prototypes/elevator_cutscene/tools/build_elevator_intro_animation.gd
```

`playback_speed` is the only timing control that can honestly be live, and it is
the only one the panel has. A slider on `SHOT2_CUT_TIME` would move a number
nothing reads until you re-run the script, which is worse than no control.

**Re-running the build script overwrites Animation Dock edits.** Once the
director starts tweaking keys in the dock, stop running it — or move the number
that keeps changing into the knobs file so both stay true.

**Geometry is authored in the `.tscn`, not pushed from the knobs file.** That is
the opposite of every other prototype here, and it is deliberate: if a script
resized the car at `_ready`, the editor viewport would show one car and the game
would show another, and the shot the director composed would not be the shot that
ships. Knobs owns behaviour; the scene owns shape. The two numbers that must
exist in both places get a `push_error` guard in `elevator_car.gd`.

## Checking it

```
# the shots, as PNGs under user://shots - look at them
"D:/Godot_v4.7.1-stable_win64.exe" --path <repo> --resolution 1280x720 \
  res://prototypes/elevator_cutscene/tools/capture_shots.tscn

# the assertions
"D:/Godot_v4.7.1-stable_win64.exe" --headless --path <repo> \
  res://prototypes/elevator_cutscene/verify_elevator_cutscene.tscn
```

**Run both.** The suite's checks all passed against a first draft in which the
wide shot was a miner's head filling the frame, the player's eye was inside a
helmet, the shot-2 camera pointed at the back of the subject's head, and a third
miner stood between the lens and the arm the shot exists to show. Geometry
assertions cannot see composition.

The art swap proved the point again, twice over. Every check was green while
shot 2 framed a voxel helmet across the middle third of frame, and again while
the helmet's emission — tuned for a 0.185 m greybox visor box, applied to a
material that covers the whole real helmet — blew the climax of the cutscene out
to a white blob.

What the suite does cover, and why each one is there rather than assumed:

| Check | The silent failure it catches |
|---|---|
| `[camera]` | Godot gives `current` to whichever `Camera3D` readies last. Three exist here. The failure is the wrong shot, decided by scene-dock order. |
| `[framing]` | The opening close-up is framed so the glass covers the frame *exactly*, and the usable window is about 2.4% wide: any wider and the plate's bezel — which the 2D copy does not have — comes into shot, any narrower and the crop eats EXTRACTION CREW 067. Recomputed off the live scene, because the pose is also the one place the `.tscn` lies (`QuotaScreen` reads y = 2.4 there and is at world 0.9844). |
| `[prologue]` | The `shot_alpha` keyframe, asserted on the **clip**. `_cleanup()` also forces the overlay off, so the runtime check alone would pass with the keyframe deleted — and the prologue would then simply never appear. |
| `[root_node]` | `AnimationPlayer.root_node` left at its default resolves to the cutscene node, not the level. Every track path dies. Nothing errors. |
| `[length]` | `Animation.length` defaults to 1.0 and truncates every track past it. The clip just ends and the doors never open. |
| `[tracks]` / `[paths]` | A track whose path no longer resolves does not warn; the property simply never moves. |
| `[materials]` | Emission has to reach one miner. The check is behavioural, not by identity: each miner instantiates its own model, so comparing three material objects would pass even if nothing were wired at all. |
| `[gesture]` | The hero miner's cutter must not ride the arm the gesture raises. |
| `[environment]` | `PlayerView` writes the **shared** `WorldEnvironment` in its `_ready`. Left on, it silently replaces the shaft's fog and repaints every composed shot — and only a rendered frame would ever show it. |
| `[hud]` / `[pause]` | `prefab_player` brings its own HUD (whose minimap carries a `Camera3D`) and a pause menu whose unpause re-enables input unconditionally, mid-shot, behind the cutscene's back. |
| `[budget]` | Nothing empties the suit today only because `player_settings.tres` tunes the drain rates thirty times below their class defaults. A balance pass on a shared resource could put a death inside a cutscene. |
| `[window]` | A frame hitch can put several effects in one tick. An equality check drops them all — silently, only under load, only on someone else's machine. |
| `[equivalence]` | Skip at 0 s, 1.5 s, 4 s, 13.5 s and 23.5 s must land on the same world state as watching. Otherwise the cutscene has two endings and one is untested. The first two are inside the prologue — mid-2D-shot and mid-pull-back — because a skip that leaves a full-screen opaque overlay covering the game is the worst failure here. |
| `[no-orphan]` | No terminal path may leave the player without input, without collision, or without a camera. |

## What is deliberately not here

No networking, no role binding, no `CutsceneTrigger`, no `@tool` Initialize
button, no editor dock, no `CutsceneEffect` subclasses, no `BIND_AND_POSE`, no
`ANCHORED` camera mode (the enum branch exists in the driver; nothing exercises
it). Those are steps 5–11 of the spec's build order.

**And no audio.** A descending elevator with no hum is doing this on hard mode.
It is still the single cheapest improvement available, and it is no longer
blocked by anything — the repo has SFX now. It is the first thing to add.

## The art is referenced, not copied

The three models are instanced straight from `assets/`. Nothing is duplicated
into this directory, so a re-export reaches the cutscene:

| | |
|---|---|
| `assets/art/environment/elevator_car/sm_elevator_car.tscn` | shell + two door leaves |
| `assets/art/character/sk_player_character.tscn` | the miners, and the player |
| `assets/art/gameplay/mining_laser/sm_mining_laser.tscn` | one per miner |

**A property override on a node inside an instanced glTF needs editable children
and does not survive a re-import.** That single rule shapes three things here,
and each is done from code, by node name, instead:

- The car is **one glTF instanced three times**, each copy showing one mesh
  (`elevator_car.gd::_hide_parts`), because the shell and the two leaves have to
  move independently. `@tool`, so the editor viewport is not three stacked cars.
- The helmet's emission is a **surface override built at `_ready`**
  (`miner_rig.gd::_build_visor`). The imported material has no emission at all —
  this authors one, and takes only its colour from `materials/`.
- The gesture clip is **added to the model's own `AnimationPlayer` by method
  call**, since a library cannot be authored onto it in a `.tscn`.

The character is authored facing `+Z`, against this project's `-Z`. The 180°
yaw that corrects it is on `MinerRig/Rig`, exactly as `prefab_player` does it, so
the three placements in the level never mention it.

## The player is the real prefab now

`prefabs/character/player/prefab_player.tscn`, not a forked copy — one player
implementation instead of two, and `PlayerSettings` as the single source for fov,
clip planes and lamp. The five seams the old fork had to add by hand all already
existed on it: `PlayerInput.enabled`, `PlayerLocomotion.halt()`,
`PlayerRespawn.set_spawn_transform()`, `PlayerLamp.set_lit()`, and the head
camera by path. Only `PlayerInput.release_mouse()` was added, for symmetry with
`capture_mouse()`.

**`cutscene_player_rig.gd` is the firewall.** Twenty-seven components arrive with
the prefab and the cutscene needs about six things; everything it says to the
player goes through that one file, so `cutscene_player.gd` changed only the
*type* of its `rig` and not one call. What that firewall does **not** cover is
behaviour, which is why `[environment]`, `[hud]`, `[pause]` and `[budget]` exist
— four ways a shared component can quietly wreck a shot, each now a named
failure.

## Layout

```
elevator_cutscene_prototype.tscn/.gd   the level and its wiring
elevator_cutscene_knobs.gd             every tunable number
elevator_cutscene_settings.gd/.tres    the ten with sliders
elevator_cutscene_hud.gd               helmet overlay, crosshair, readout
elevator_cutscene_input.gd             runtime InputMap registration

cutscene_camera_driver.gd              the spec's section 7 seam
cutscene_player.gd                     clock, enter/exit contract, skip
cutscene_data.gd                       one cutscene's effects list + flags
cutscene_timed_effect.gd               {time, effect_name, detail}
elevator_effects.gd                    name -> change to the world
cutscenes/elevator_intro.cutscene.tres the effects, hand-authored

cutscene_player_rig.gd                 the whole view of prefab_player
elevator_monitor_shot.gd               the opening full-screen shot of the tube

elevator_car.gd                        text, lights, doors, which meshes show
shaft_lights.gd                        the streaming bars - NO LONGER IN THE SCENE
mine_tunnel_stub.gd                    generated CSG beyond the doors
miner_rig.tscn/.gd                     the real miner, instanced 3x
materials/                             five StandardMaterial3D

animations/                            GENERATED by tools/, editable after
tools/build_elevator_intro_animation.gd
tools/capture_shots.gd/.tscn           renders the shots to PNG - the pair
                                       either side of PROLOGUE_LENGTH is
                                       what judges the match cut
verify_elevator_cutscene.gd/.tscn      the headless suite
```

## Two things the swap changed on purpose

**The shaft-light column is gone from the scene.** The real shell has no wall
slot, so a column of bars streaming past outside it cannot be seen from inside a
closed car. `set_shaft_running()` keeps its name and its caller and now wavers
the ceiling lamp instead — with no window, the car's own lighting reacting to the
machinery is all that is left to say it is moving. `shaft_lights.gd`, its knobs
and its invariant all survive for the day a slot is authored into the art.

**MinerB holds their cutter left-handed, and the player looks down a different
lane.** The gesture raises the right arm to the helmet, and a 1.14 m tool welded
to that hand sweeps across their face in the medium close-up the whole cutscene
is built around. Moving the camera is not available — shot 2 sits front-right
*precisely* so the gesturing arm is nearest the lens — so the tool moves instead,
via `MinerRig.tool_bone`. That puts it in the old MinerA-to-MinerB sightline, so
the match cut now threads between MinerB and MinerC, which is clear because
MinerC holds theirs right-handed, out towards the wall. Three shots, one knob
each; all of it visible only in a PNG.
