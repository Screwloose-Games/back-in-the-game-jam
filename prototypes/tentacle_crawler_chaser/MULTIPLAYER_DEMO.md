# Tentacle crawler multiplayer demo

This companion scene proves that `common/network/` is not tied to the power-room
prototype. It uses the same two-player WebRTC session and Godot high-level
multiplayer peer with a different game loop:

- `MultiplayerSpawner` creates the two survivors.
- Each survivor owns only its bounded `Inputs` subtree. Movement is sent as
  sequenced commands; the controlling client predicts immediately.
- Peer 1 simulates both survivor bodies and publishes acknowledged snapshots.
  Local corrections are reconciled and remote survivors are interpolated.
- Peer 1 alone simulates the crawler, target selection, catches, extraction, and
  round resets.
- The crawler root is synchronized at 20 Hz. Tentacle raycasts and bones remain
  local visual presentation and cannot affect client gameplay authority.

The room is six static primitive colliders. It intentionally does not use the
original chaser's runtime CSG, navigation bake, follower, or debug tooling.

## Build and run

From `game/`:

```bash
./tools/export_tentacle_crawler_multiplayer_demo_web.sh
cd releases/tentacle-crawler-multiplayer-demo-web
python3 -m http.server --bind 127.0.0.1 8002
```

Open `http://127.0.0.1:8002/` in two visible browser windows. Host in one, enter
its code in the other, then use each window's Enter button to capture its mouse.
The export is single-threaded and does not require cross-origin-isolation
headers. The signaling endpoint defaults to
`wss://signaling.screwloose.workers.dev`.

## What to verify

1. Both windows see both survivors move.
2. Both windows show the same crawler target and round result.
3. A client cannot directly move the host's survivor or the crawler.
4. A catch or successful extraction resets both views.
5. Closing the guest leaves the host's session and solo chase running.

STUN is enabled; TURN fallback remains deliberately outside the MVP.
