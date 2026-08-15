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
prediction, and replay after an authoritative correction. Commands carry
bounded thrust, per-tick look motion, roll, and stabilizing/sprinting flags:

```gdscript
func _simulate_network_command(
	thrust: Vector3,
	look_delta: Vector2,
	roll: float,
	flags: int,
	delta: float,
	context: int,
) -> void:
	pass
```

Each client input has an epoch and sequence number. Peer 1 validates its sender
and bounds, uses the newest accepted held intent instead of accumulating stale
input, consumes each accepted look delta once, and publishes the acknowledged
sequence with the authoritative transform, velocity, and optional adapter-owned
auxiliary state. The controlling client
rewinds to that snapshot and replays newer commands when the two simulations
differ. Matching snapshots are only pruned, so ordinary updates do not repeat
physics work. A `Presentation` child visually decays small corrections while
the collision body is corrected immediately. Other players are shown from a
short interpolation buffer instead of stepping at the snapshot rate.

Movement state that affects the following tick but does not live on
`CharacterBody3D` belongs in the auxiliary state hooks. Examples include an
angular velocity, an eased sprint cap, or a contact latch. Pass capture and
restore together; the comparison callback is optional and defaults to exact
Dictionary equality:

```gdscript
prediction.configure(
	controlled_peer_id,
	presentation,
	Callable(self, "_simulate_network_command"),
	true,
	Callable(self, "_capture_prediction_state"),
	Callable(self, "_restore_prediction_state"),
	Callable(self, "_prediction_states_match"),
)
```

The sibling `MultiplayerSynchronizer` must replicate these seven properties
from `Prediction`: `authoritative_transform`, `authoritative_velocity`,
`authoritative_auxiliary_state`, `authoritative_epoch`,
`acknowledged_input_sequence`, `simulation_active`, and `snapshot_sequence`.

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

Movement callbacks must not create one-shot effects while predicting or
replaying. Damage, audio, inventory changes, shared rigid-body forces, and
similar outcomes remain host-only. Client prediction is expected to be
corrected when collision or other shared state differs from the host.
