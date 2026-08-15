# Multiplayer Requirements — Brief

**Owner:** Michael
**Source:** July 31, 2026 design kickoff; local multiplayer decision, August 1, 2026;
network-only decision, August 14, 2026
**Version:** 2.0

---

## 1. Scope of ownership

Michael owns multiplayer implementation. No one else on the team is assigned to it.

**Networked multiplayer only.** The August 1 decision to build local split-screen
first is reversed: there is one camera per machine, and nothing in the game is
built for two viewports. That assumption is already load-bearing in code —
`PlayerRenderLayers` gives the local player's own body a culled layer with no
per-peer coordination, which works precisely because only one camera exists.

---

## 2. Multiplayer requirements

| Requirement | Decision |
|---|---|
| Player count target | 2 |
| 3–4 players | Not a design target. Acceptable if it works, acceptable if it doesn't |
| Single-player | Must be a first-class experience, not a degraded mode |
| Local multiplayer | **Not a target.** Reversed August 14, 2026 |
| Network multiplayer | Required. Real-time and synchronous |
| Network authority model | Host-authoritative. Player 1 is the authority |
| Session length | ~5 minutes per run, more if time permits |
| Competitive play | None. PvE co-op only |

---

## 4. Game systems affecting multiplayer implementation

### Player
- First-person, zero gravity.
- Six degrees of freedom, thruster-based, Newtonian physics.
- Player may / may not collide with other players. This is a design decision to be made later.

### Shared power/oxygen tank
- One unit, shared by all players.
- Physically carried, pushed, or dragged by a player.
- Tether limits player distance from the unit.
- Shared drain across the crew self-balances by player count.
- Players may abandon the tether ("cut the cord").

---

## Multiplayer — Top Things to Think About

Two of the local-multiplayer items survive the reversal, because they are about
not hard-coding "the player" rather than about viewports:

1. **Input device routing.** InputMap actions are global by default. Per-player
   input sources; no direct `Input` reads in gameplay code. `PlayerInput` already
   holds this seam.
2. **No singletons assuming one player.** Any "the player" autoload breaks the
   moment a second prefab exists — which it already can, via the pause menu's
   debug second player.

The rest — device assignment, join and leave flow, 6DoF on a gamepad,
split-screen render cost, per-viewport listeners, mouse capture, shared speakers —
were split-screen problems and are gone with it.

---

### Network multiplayer

#### Connection
1. **Transport choice.** `ENetMultiplayerPeer` (UDP, desktop-only, fewest moving parts) vs. `WebRTCMultiplayerPeer` (required for web export, needs supporting infrastructure).
2. **How players find each other.** Direct IP entry, room/lobby codes, or a lobby service. Room codes are the cheap middle ground.
3. **Signaling server.** Required for WebRTC — exchanges SDP offers/answers and ICE candidates before peers connect. Needs hosting, usually WebSocket. Doubles as the room-code broker.
4. **STUN.** Discovers each peer's public address for NAT traversal. Free public servers exist.
5. **TURN.** Relays when direct connection fails, roughly 20–30% of the time. Costs bandwidth. Decide whether to run one or accept the failure rate.
6. **Port forwarding.** ENet direct connections need it unless a relay is in front. Determines whether testers can connect without setup.
7. **Topology.** Peer-to-peer with one peer authoritative. No dedicated server.

#### State
8. **Abstract the input source.** Local device or remote peer should be interchangeable.
9. **Authority as an explicit property.** Host-authoritative, player 1 is peer ID 1.
10. **Terrain syncs operations, not meshes.** Requires deterministic regeneration from identical inputs.
11. **The shared tank changes hands.** Levels, position, carrier, crank state — ownership transfers mid-run.
12. **Physics authority for ore chunks.** Host-owned with interpolation, or assigned on mining.
13. **Noise events must be authoritative.** Client-side firing desyncs creature detection.
14. **No cheating threat model.** Clients can own their own player state. Likely no prediction or reconciliation.
15. **Five-minute sessions.** No host migration, reconnection, or persistence. Decide on late-join.
