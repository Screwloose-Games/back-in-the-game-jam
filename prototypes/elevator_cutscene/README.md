# Elevator Cutscene

**The cutscene is not here any more.** It shipped: it is
`levels/asteroid_level/intro/`, it plays when the asteroid level loads, and that
directory's README is the one that describes it.

What is left here is the tuning harness. This scene instances the very same
`elevator_intro.tscn` the level does, in a greybox shaft instead of against the
mine mouth's back wall, and adds the two things a director needs and a level must
not have: a replay key and a slider panel.

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
`elevator_cutscene_input.gd`, and stay prototype-only — the shipped level uses a
real `cutscene_skip` action in `project.godot`.

## The same sub-scene, deliberately

A prototype that kept its own copy of the shot would answer questions about a film
nobody watches. Instancing the shipped one means a pose tuned here is the pose that
ships, and there is no second copy to drift. The prototype owns its shaft
environment, its greybox tunnel and its panel; the intro owns everything the shot
is composed against.

Two consequences worth knowing:

- **The knobs file lives with the intro**, not in this directory —
  `levels/asteroid_level/intro/elevator_intro_knobs.gd`. That is a deliberate
  deviation from `prototypes/AGENTS.md`, whose actual point is that a default is
  written down in exactly one place. It still is; the place moved.
  `elevator_cutscene_settings.gd` reads its slider bounds from there.
- **The greybox tunnel is sized off `EXIT_POSITION`.** The player leaves the car
  now, and a bore sized to the doorway put the rig's hull inside this rock — which
  the cutscene's own exit check catches and warns about on every run. The real
  level opens onto a 10.5 m chamber; this has to be at least as forgiving.

## What the three claims turned into

**A cutscene can take the camera off a live player and give it back.** Promoted to
`common/cutscene/` — `CutscenePlayer` (the clock, the enter/skip/cleanup contract),
`CutsceneCameraDriver` (`request_control` / `release_control`), `CutsceneData`,
`CutsceneTimedEffect`, `CutscenePlayerRig` (the firewall over `prefab_player`), and
two small base classes, `CutsceneHud` and `CutsceneEffects`, which are the whole of
what the clock is allowed to say to a cutscene it knows nothing about.

**Keyframes and state changes can be kept apart, and skipping proves it.** Still
the load-bearing claim, and the shipped intro leans on it harder than this
prototype ever did: `doors_unlocked` now has a mirror, `doors_locked`, and dropping
either one on a skip breaks the level in opposite directions.

**A director can scrub the shot and see what will run.** Select
`Intro/Cutscenes/ElevatorIntro/CameraAnchor/PreviewCamera`, hit **Preview**, drag
the timeline.

## The art is referenced, not copied

Nothing is duplicated into this directory. The car and the miners are shipped
prefabs now — `prefabs/environment/elevator/prefab_elevator_car.tscn` and
`prefabs/character/miner/prefab_miner.tscn` — built out of the same glTFs they
always were:

| | |
|---|---|
| `assets/art/environment/elevator_car/sm_elevator_car.tscn` | shell + two door leaves |
| `assets/art/environment/wall_switch/sm_wall_switch.tscn` | the call panel |
| `assets/art/character/sk_player_character.tscn` | the miners, and the player |
| `assets/art/gameplay/mining_laser/sm_mining_laser.tscn` | one per miner |

**A property override on a node inside an instanced glTF needs editable children
and does not survive a re-import.** That single rule still shapes three things,
each done from code, by node name, instead:

- The car is **one glTF instanced three times**, each copy showing one mesh
  (`elevator_car.gd::_hide_parts`), because the shell and the two leaves have to
  move independently. `@tool`, so the editor viewport is not three stacked cars.
- The helmet's emission is a **surface override built at `_ready`**
  (`miner_rig.gd::_build_visor`).
- Gesture clips are **added to a model's own `AnimationPlayer` by method call** —
  the miner's in `miner_rig.gd`, the player's in `player_rig_animation.gd`.

## Checking it

```
# the assertions, which now live with the intro
"D:/Godot_v4.7.1-stable_win64.exe" --headless --path <repo> \
  res://levels/asteroid_level/intro/verify_elevator_intro.tscn

# the shots, as PNGs under user://shots - look at them
"D:/Godot_v4.7.1-stable_win64.exe" --path <repo> --resolution 1280x720 \
  res://prototypes/elevator_cutscene/tools/capture_shots.tscn
```

**Run both.** The suite's checks all passed against a first draft in which the wide
shot was a miner's head filling the frame, the player's eye was inside a helmet,
the shot-2 camera pointed at the back of the subject's head, and a third miner
stood between the lens and the arm the shot exists to show. Geometry assertions
cannot see composition.

Shot timings are baked into the clip by
`levels/asteroid_level/intro/tools/build_elevator_intro_animation.gd`; change a
number in the knobs, re-run it, look again. Re-running it overwrites Animation Dock
edits. `playback_speed` is the only timing control that can honestly be live, and
it is the only one the panel has.

## What this prototype still keeps

```
elevator_cutscene_prototype.tscn/.gd   the shaft, the player, and the wiring
elevator_cutscene_settings.gd/.tres    the ten sliders
elevator_cutscene_input.gd             runtime InputMap registration
mine_tunnel_stub.gd                    generated CSG beyond the doors
shaft_lights.gd                        the streaming bars - NOT IN THE SCENE
materials/                             two StandardMaterial3D
tools/capture_shots.gd/.tscn           renders the shots to PNG
```
