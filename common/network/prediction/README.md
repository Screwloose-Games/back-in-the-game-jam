# Predicted host-authoritative movement

`ClientPredictor3D` is the reusable movement boundary for network players. It
keeps peer 1 authoritative without making the controlling client wait for a
round trip before its camera moves.

The scene contract is deliberately small:

```text
CharacterBody3D                 authority: peer 1
├── Presentation               camera, mesh, nameplate
├── Prediction                 ClientPredictor3D, authority: peer 1
├── StateSync                  authoritative snapshot, authority: peer 1
└── Inputs                     device sampling, authority: controlling peer
```

The player script supplies one deterministic movement callback. The predictor
uses that same callback in three contexts: host simulation, immediate local
prediction, and replay after an authoritative correction.

Each client input has an epoch and sequence number. Peer 1 validates its sender
and bounds, uses the newest accepted intent instead of accumulating stale input,
and publishes the acknowledged sequence with the authoritative transform and
velocity. The controlling client rewinds to that snapshot and replays newer
commands when the two simulations differ. Matching snapshots are only pruned,
so ordinary updates do not repeat physics work. A `Presentation` child visually
decays small corrections while the collision body is corrected immediately.
Other players are shown from a short interpolation buffer instead of stepping
at the snapshot rate.

This is prediction with authoritative correction, not deterministic lockstep.
The host advances at its own physics rate and may coalesce several newer input
packets into the latest held intent. Shared collisions and rigid bodies can also
make the two simulations differ. A correction therefore replays only a bounded
history; a long stall or missing history rebases cleanly and keeps sequence
numbers monotonic instead of attempting unbounded catch-up work.

`MultiplayerSpawner` and `MultiplayerSynchronizer` remain the normal Godot
integration points. Prediction replaces only latency-sensitive movement input;
shared and discrete game state should keep using synchronizers. A reset,
teleport, respawn, or activation change must call `authoritative_reset()` so a
new epoch discards commands from the previous state.

Movement callbacks must not create one-shot effects while replaying. Damage,
audio, inventory changes, shared rigid-body forces, and similar outcomes remain
host-only. Client prediction is expected to be corrected when collision or
other shared state differs from the host.
