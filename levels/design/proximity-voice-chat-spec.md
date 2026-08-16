# Proximity Voice Chat — Technical Specification

**Status:** Draft — platform assumptions verified
**Target:** Godot 4.7.1, Web (HTML5) export, WebRTC data channels
**Last updated:** 2026-08-16

> **Revision note.** The first draft treated A5 and A6 as blocking unknowns and chose an
> architecture (a JavaScript capture bridge) to route around A6. A6 has since been resolved
> **yes** from engine source and from this project's own exported web build, so that
> architecture is no longer needed. §3, §4, §6 and §7 changed substantially. §14 is new and
> is the most important section to read before writing code.

---

## 1. Overview

### 1.1 Purpose

Add positional ("proximity") voice chat to a 3D co-op first-person game so that
players hear each other's speech attenuated and spatialised according to their
relative positions in the game world.

### 1.2 Scope

In scope:

- Microphone capture in the browser
- Voice activity detection and gating
- Compression and framing of speech audio
- Transport over the existing WebRTC connection
- Per-speaker jitter buffering and playout
- 3D spatialisation, distance attenuation, and occlusion filtering
- Per-player mute and volume controls
- A stable internal interface that allows the capture and codec layers to be
  replaced without touching downstream systems

Out of scope for v1:

- Radio / walkie-talkie channels layered over local voice
- Text chat
- Voice-driven lipsync or facial animation
- Server-side recording, moderation tooling, or abuse reporting
- Non-web export targets (desktop builds may reuse the transport and playback
  layers but are not validated by this spec)

### 1.3 Non-goals

- **Broadcast-quality audio.** The target is intelligible speech at minimum
  bandwidth. Artefacts from aggressive compression are acceptable and, in a
  horror or survival context, often desirable.
- **Large lobbies.** The design targets small co-op sessions (see §2.1). It does
  not attempt to scale to dozens of concurrent speakers.

---

## 2. Assumptions and Open Questions

| # | Item | Status |
|---|------|--------|
| A1 | Concurrent players per session | **Resolved: exactly 2 today.** Design for 2, keep the seams for N. See §5.1 |
| A2 | Whether the session has an authoritative host peer or is a pure mesh | **Resolved: host-authoritative star.** Peer 1 hosts, peer 2 joins |
| A3 | Acceptable end-to-end mouth-to-ear latency budget | **Resolved: ≤350 ms.** The original ≤200 ms is not reachable in a browser; see §2.1 |
| A4 | Whether voice amplitude feeds any gameplay system | **TBD** — see §12 |
| A5 | Whether the deployment host can serve COOP/COEP headers | **Unverified, and untestable today** — nothing has ever been deployed. See §2.2 |
| A6 | Whether microphone capture works in a Godot web export | **Resolved: YES.** See §3.2 |

A6 is closed. A5 is the only remaining blocking item, and it is a *deployment* question
rather than a design one — it gates the whole game, not just voice.

### 2.1 A1 and A3, resolved

`common/network/network_session.gd` describes itself as a "reusable two-player host/join
session coordinator". `WebRTCSession` holds a single `WebRTCPeerConnection`, peer IDs are
validated against `[1, 2]`, and the spawner's `spawn_limit` is 2. There is no mesh and no
third peer is possible without networking work that is out of scope here.

Voice is therefore a single bidirectional link. The packet format (§5.4) and the per-speaker
component structure (§6) are retained so that an N-peer version drops in later, but none of
the mesh fan-out or relevance-culling machinery is built for v1.

The latency budget, measured against the platform rather than assumed:

| Stage | Cost |
|---|---|
| Browser capture + AudioWorklet render quantum | ~10–20 ms |
| Framing at 40 ms | 40 ms |
| Network, direct WebRTC, same region | 20–60 ms |
| Jitter buffer, 3 frames | 120 ms |
| Web output ring (2048 frames) + `audio/driver/output_latency.web` (50 ms) | ~50–95 ms |

Roughly **300 ms** is realistic and ~250 ms is the floor. The only cheap lever is dropping
the jitter target to 2 frames.

### 2.2 A5, and why it is still open

The web preset already sets `variant/thread_support=true`, which requires
`Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: require-corp`.
Without them a threads build **refuses to boot** with a visible SharedArrayBuffer failure
notice — it does not silently fall back to single-threaded.

`progressive_web_app/ensure_cross_origin_isolation_headers=true` is inert here, because
`progressive_web_app/enabled=false` and the engine only emits the service worker for PWA
builds. CI injects `gzuidhof/coi-serviceworker` instead, but a service worker inside the
frame cannot make itch.io's cross-origin `html-classic.itch.zone` iframe isolated — that
requires the *top-level* document's COOP.

The real mechanism is itch.io's **SharedArrayBuffer support** checkbox under
*Embed Options → Frame Options*. Chrome works; Firefox's status is contested between itch's
own blog post and later community reports; Safari needs the game popped out into its own
window. Enabling it also moves content to `html.itch.zone`, invalidating existing
`localStorage` saves, and breaks embedded third-party iframes.

None of this has been exercised, because **nothing has ever been published**: there are no
git tags, and `ITCH_USER` / `ITCH_GAME` are unset. A5 fires the first time someone pushes a
`v*` tag. Resolve it with spike S0 (§10.1) before building anything on top of it.

Note that microphone capture itself does **not** depend on cross-origin isolation (§3.2), so
A5 is a latency-and-does-the-game-boot question, not a voice-capture question.

---

## 3. Platform Constraints

These constraints are properties of the target platform, not design choices.
They are the reason the architecture below looks the way it does.

### 3.1 Godot's WebRTC exposes data channels only

Godot's `WebRTCPeerConnection` / `WebRTCMultiplayerPeer` surface `WebRTCDataChannel`
and nothing else. There is no `MediaStream` or `MediaStreamTrack` binding —
`modules/webrtc/library_godot_webrtc.js` contains no `MediaStream`, `addTrack`,
`addTransceiver` or `ontrack` anywhere.

Consequences:

- The browser's built-in Opus encode/decode path is **not reachable** through
  Godot's WebRTC API. (It *is* reachable another way — see §6.4.)
- SDP-level codec configuration (`maxaveragebitrate`, `usedtx`, `ptime`) is not
  available.
- RTP-level features Godot cannot use: in-band FEC, packet loss concealment,
  adaptive jitter buffering, DTX, and bandwidth estimation. Each must be
  implemented in application code or deliberately forgone.
- SFU-based routing is not available, because an SFU forwards media tracks, not
  application data channel payloads.

### 3.2 Microphone capture on web **works**

The previous draft assumed otherwise, because Godot's "Recording with microphone" tutorial
lists only Windows, macOS, Linux, Android and iOS. **That documentation is stale.** The
capture path is implemented end to end:

- `platform/web/js/libs/library_godot_audio.js` — `godot_audio_input_start` calls
  `GodotAudio.create_input`, which calls
  `navigator.mediaDevices.getUserMedia({ 'audio': true })` and connects the resulting
  `MediaStreamAudioSourceNode` into the driver node.
- `platform/web/audio_driver_web.cpp` — `AudioDriverWeb::input_start()` allocates the input
  ring unconditionally and calls into that JS; `_audio_driver_capture()` feeds
  `input_buffer_write()`.
- `platform/web/js/libs/audio.worklet.js` — the processor copies `inputs[0]` into a
  SharedArrayBuffer ring (threads path) or posts `{cmd: 'input'}` to the main thread
  (no-threads path). `start_no_threads(...)` takes input-buffer arguments, so **both**
  driver variants carry input.

This is verifiable without building anything: the committed export at `releases/web/index.js`
already contains `_godot_audio_input_start`, `create_input` and `getUserMedia`, and
`releases/web/index.audio.worklet.js` contains the input branch.

Two conditions apply, neither of which is a browser limitation:

1. **`audio/driver/enable_input` must be `true`.** It defaults to `false`, and
   `AudioServer::set_input_device_active()` returns `FAILED` with a warning when it is unset.
   `project.godot` currently has no `[audio]` section at all, so capture would fail today.
2. **Secure context and a user gesture.** `getUserMedia` needs HTTPS and the `AudioContext`
   needs a gesture to resume. The existing "click to start" gate satisfies the second.

It is *not* gated on threads or SharedArrayBuffer.

Because this is undocumented, it is also untested by the engine team. S1 (§10.1) still runs —
its question has changed from "is this possible?" to "which browsers honour it?".

### 3.3 Web audio playback defaults to samples, which have no effect chain

On web, Godot defaults to sample-based playback, which routes audio through WebAudio and
bypasses Godot's mixer. The JS-side "bus" under sample playback is literally three
`GainNode`s — gain, solo, mute — with no effect chain, so `AudioEffectLowPassFilter` has
nowhere to live. `AudioServer::_mix_step` skips any playback whose `get_is_sample()` is true.

**Requirement:** every voice playback node sets `playback_type = Stream` **individually**.
Do *not* flip `audio/general/default_playback_type.web` — that would move every SFX and music
stream in the game onto the higher-latency path for no benefit.

Under stream playback, `AudioStreamPlayer3D` attenuation and panning are computed in Godot's
C++ mixer and delivered as a per-channel volume vector, so 3D positioning and bus effects
behave exactly as they do on desktop.

### 3.4 GDExtension on web is available, but is not the v1 path

The previous draft treated GDExtension as unavailable. It is not: the web preset already sets
`variant/extensions_support=true` and the build already ships a 43.3 MB `index.side.wasm`.
A web GDExtension is a real option — see §6.4 for what that buys.

For v1 we still avoid it, on effort and dependency grounds rather than availability.

---

## 4. Architecture

### 4.1 Options considered

**Option A — Fully in-engine (selected).** Capture through `AudioServer`, encode in GDScript,
send over a Godot data channel, play through `AudioStreamPlayer3D`.

- Pro: single codebase; spatialisation and effects come free from the engine; identical in
  the editor and in the export, so voice is testable on desktop without a browser.
- Con: no browser-grade codec; resampling and gating are ours to write.

**Option B — Fully in JavaScript.** A second `RTCPeerConnection` created in JS carries an
audio track alongside Godot's data-channel connection, spatialised with a WebAudio
`PannerNode`.

- Rejected. Spatialisation would live outside the engine, so bus effects, reverb zones and
  occlusion logic could not be shared; it needs a second signalling path; and
  `JavaScriptBridge` exists only in web builds, so voice could never be exercised in the
  editor. No instance of anyone doing this in Godot could be found.

**Option C — Hybrid capture.** JavaScript performs microphone acquisition and downsampling;
Godot performs everything else.

- Rejected. This existed only to route around A6. With A6 resolved it is pure cost: a JS glue
  layer to maintain, and capture that cannot be tested in-editor without a stub.

### 4.2 Decision

**Option A is selected.** Capture uses `AudioServer.get_input_frames()`.

That API (added in 4.6, and **marked experimental**) returns a `PackedVector2Array` of frames
straight from the driver's input buffer. Compared with the previously specified
`AudioStreamMicrophone` + `AudioEffectCapture` chain it avoids: an `AudioStreamPlayer` node,
a capture bus, the `playback_type` question for the capture side, any risk of routing the
microphone to the speakers, and `AudioStreamPlaybackMicrophone`'s deliberate ~50 ms
`playback_delay` warm-up.

`AudioStreamMicrophone` + `AudioEffectCapture` on a silent bus remains the documented fallback
if `get_input_frames()` misbehaves — TwoVoip's issue #76 reports unresolved latency
regressions with it on desktop 4.6 beta3, so verify before committing.

The `IVoiceCapture` interface (§6.1) is retained anyway: `NullVoiceCapture` is what lets the
editor and the automated tests run with no microphone.

### 4.3 Data flow

```
 LOCAL                                          REMOTE
 ─────                                          ──────
 AudioServer.get_input_frames()
   │  device rate (≈48 kHz), PackedVector2Array
   ▼
 Mono fold + clamp to ±1.0        ← §14.4
   │
   ▼
 Decimating low-pass  48 kHz → 8 kHz
   │  accumulate into 320-sample frames
   ▼
 VAD gate ───── gated closed ──► drop frame, send nothing
   │
   │ open
   ▼
 Encoder  ──►  Packetiser  ──►  backpressure check   ← §14.3
                                     │
                                     ▼
                      WebRTCDataChannel (unreliable, unordered)
                                     │
                                     ▼
                              ══════════════
                                     │
                                     ▼
                               Depacketiser
                                     │
                                     ▼
                               JitterBuffer (per speaker)
                                     │
                                     ▼
                                 Decoder
                                     │
                                     ▼
                         AudioStreamGeneratorPlayback
                                     │
                                     ▼
                           AudioStreamPlayer3D
                           playback_type = Stream        ← §3.3
                           (parented to speaker avatar)
                                     │
                                     ▼
                    Statically declared per-speaker bus  ← §14.1
                    (low-pass = occlusion, gain = mute/volume)
```

---

## 5. Network Design

### 5.1 Topology

**Host-authoritative star, two peers.** Peer 1 hosts, peer 2 joins, signalled by the
Cloudflare Worker at `wss://signaling.screwloose.workers.dev` which carries only
`offer` / `answer` / `ice_candidate`. Gameplay rides `WebRTCMultiplayerPeer`.

Voice is one bidirectional stream. At ~48 kbps per active direction (§6.4) there is no
bandwidth question to answer.

**When A1 grows.** A mesh at 6 players means a speaking client sends 5 copies of a ~48 kbps
stream, ~240 kbps upstream — within reach of typical residential connections, and the DTX
gate (§6.3) means only actively speaking clients pay it. Above 8, mesh upstream grows
linearly per speaker and quadratically per session; switch to host relay at that point. The
packet format already carries an explicit speaker ID so relay needs no reframing.

### 5.2 Relevance filtering — deferred to the N-player case

With two peers there is exactly one possible listener, so there is nothing to cull. Distance
attenuation is handled entirely by `AudioStreamPlayer3D`, whose `max_distance` fades to
exactly zero with no discontinuity.

The N-player design is recorded here so it is not rediscovered:

1. **Sender-side culling.** The sender consults its own view of peer positions and does not
   transmit to peers outside its audible radius. Cheap and simple, but **not a security
   boundary** — a modified client can transmit to, and accept from, everyone. For a co-op
   game played with friends that is an accepted risk.
2. **Host relay.** All voice routes through the host, which applies culling. The only option
   robust against a modified client, but it roughly doubles mouth-to-ear latency.

Either needs hysteresis (enter at radius, exit at `radius * 1.2`, recompute at 8 Hz) or a
player standing near the boundary makes the audible set thrash, producing audible chopping at
the exact moment players are most likely to be coordinating.

### 5.3 Channel configuration

Voice uses a **dedicated data channel**, separate from the channels carrying game state.
This is **mandatory, not merely preferable** — see §14.2: Godot's own "unreliable" multiplayer
channels are in fact fully reliable on web, so the only way to get unreliable delivery is to
configure a channel ourselves.

| Property | Value | Rationale |
|---|---|---|
| Ordered | `false` | Reordering is handled by the jitter buffer |
| Max retransmits | `0` | Retransmitted voice always arrives too late to use. This option **is** honoured on web |
| Max packet lifetime | *do not use* | Godot misspells the key; it is silently dropped (§14.2) |
| Channel | Dedicated, not shared with gameplay | Prevents a voice burst from head-of-line blocking state updates |

The repo passes no `channels_config` today, so exactly Godot's three reserved channels exist.
Adding a fourth is a two-line change: pass a channels array to `create_server()` and
`create_client()` on both sides. No code in the repo calls `create_data_channel` directly.

### 5.4 Packet format

All multi-byte fields are little-endian.

```
Offset  Size  Field
──────  ────  ─────────────────────────────────────────────
0       1     version (high nibble) | codec ID (low nibble)
1       1     speaker peer ID
2       2     sequence number (uint16, wraps)
4       2     ADPCM initial predictor (int16)
6       1     ADPCM initial step index (uint8)
7       1     reserved / flags
8       N     encoded payload
```

Header is 8 bytes.

**Every frame is independently decodable.** IMA ADPCM is a predictive codec: if the decoder's
state diverges from the encoder's, all subsequent audio is corrupted. Since the transport is
lossy by design, state cannot be allowed to carry across packets.

Concretely, at each frame boundary the encoder **re-seeds** rather than zeroing:

- `initial predictor` is the frame's **first PCM sample**, and the encoder begins predicting
  from it. It is not zero. (The earlier wording, "resets its state at every frame boundary",
  read as reset-to-zero, which would make this field redundant and the first samples of every
  frame wrong.)
- `initial step index` is chosen from the frame's opening amplitude rather than reset to 0, so
  the step size does not have to climb from silence at the start of each frame.

This costs a small amount of quality at each boundary and buys independent decodability.

The `speaker peer ID` is redundant with two peers but is included so that a future
host-relay mode can forward packets without rewriting them.

---

## 6. Component Specification

### 6.1 `IVoiceCapture`

Produces fixed-size frames of mono PCM at the configured rate.

```gdscript
signal frame_ready(samples: PackedFloat32Array)

func start() -> Error
func stop() -> void
func is_active() -> bool
func get_input_level() -> float   # 0.0–1.0, for UI meter
```

Implementations:

- `GodotVoiceCapture` — the selected path. `AudioServer.get_input_frames()`, plus the
  conditioning in §6.2.
- `NullVoiceCapture` — returns silence. Used in the editor and in automated tests so nothing
  downstream needs to special-case a missing microphone.

Failure handling: if permission is denied or no input device exists, report the failure once
to `VoiceService`, which surfaces a UI indicator and falls back to `NullVoiceCapture`. Voice
failing must never block or degrade gameplay.

### 6.2 Input conditioning

This work moved in-engine when Option C was dropped. It is not optional.

1. **Enable input.** `audio/driver/enable_input = true` in project settings, then
   `AudioServer.set_input_device_active(true)` behind an explicit player action (§9).
2. **Poll.** `AudioServer.get_input_frames_available()` then
   `AudioServer.get_input_frames(n)`. Frames arrive at `AudioServer.get_input_mix_rate()` —
   the browser's `AudioContext` rate, typically 48 kHz. Do not hardcode it.
3. **Fold to mono.** `get_input_frames()` returns `PackedVector2Array`; take `.x` or the
   channel average.
4. **Clamp to ±1.0.** Web input samples are *not* guaranteed to be in range (§14.4).
5. **Decimate to 8 kHz.** 48 kHz → 8 kHz is an exact 6:1 ratio. A naive "take every sixth
   sample" aliases badly on speech; low-pass first. A ~24-tap windowed-sinc FIR costs roughly
   200 k multiply-accumulates per second, which is not a budget concern even in GDScript.
   Handle non-48 kHz device rates by falling back to a generic resampler or refusing to run.
6. **Accumulate** into fixed 320-sample frames.

Browser-side echo cancellation, noise suppression and AGC come along free: Chrome, Firefox
and Safari all enable them by default for `getUserMedia({audio: true})`, which is what the
engine requests. If explicit control is ever needed, `JavaScriptBridge.eval` can call
`applyConstraints` on `GodotAudio.input.mediaStream`'s track without owning the capture path.

### 6.3 `VoiceActivityDetector`

Gates transmission. Frame-level, energy-based.

| Parameter | Value | Notes |
|---|---|---|
| Open threshold | −45 dBFS RMS | Tune during S3 |
| Close threshold | −52 dBFS RMS | Hysteresis prevents chatter |
| Hangover | 200 ms | Prevents clipping trailing consonants |
| Attack | 1 frame | Speech onset must not be clipped |

Also exposes a smoothed `current_loudness` value, which is the input to any
gameplay coupling (§12) and to the on-screen speaking indicator.

### 6.4 `Encoder` / `Decoder`

**Codec: IMA ADPCM, 4 bits per sample.** Selected because it is trivially
implementable in GDScript, has no native dependency, is fast enough to run per
frame without threading, and its artefacts are a good aesthetic fit for
degraded-radio-style voice.

| Parameter | Value |
|---|---|
| Sample rate | 8 kHz (v1) |
| Frame duration | 40 ms |
| Samples per frame | 320 |
| Payload bytes per frame | 160 |
| Packets per second (while speaking) | 25 |

Bandwidth per active stream:

| Component | Rate |
|---|---|
| Payload | 32 kbps |
| Packet header (8 B × 25/s) | 1.6 kbps |
| SCTP/DTLS/UDP/IP overhead (~70 B × 25/s) | ~14 kbps |
| **Total per active stream** | **~48 kbps** |
| While gated closed | ~0 |

This is roughly three times what Opus would cost at comparable intelligibility. That is the
price of §3.1 and is accepted for v1. In absolute terms it is small next to state replication
for a game of this size.

Both encoder and decoder are stateless across frames by design (§5.4). The codec ID field
exists so a better codec can be introduced without a flag day: mixed-version peers negotiate
down to the lowest common codec ID.

**Upgrade paths, if 8 kHz ADPCM proves unintelligible.** In order of increasing cost:

- **Codec ID 1 — 12 kHz ADPCM.** One constant. 50% more bandwidth. Try this first.
- **Codec ID 2 — WebCodecs Opus.** `AudioEncoder` / `AudioDecoder` with codec `"opus"`,
  driven from JS through `JavaScriptBridge`. Needs only a secure context — no
  SharedArrayBuffer, no cross-origin isolation, no `MediaStreamTrack`, so it composes with
  Godot's data channels. Ships in Chrome 94+, Firefox 130+ and Safari 26+. **Firefox for
  Android has no `AudioEncoder` at all**, and Safari's Opus support is reported unreliable, so
  it must degrade to codec 0/1 rather than being assumed.
- **Codec ID 3 — a web GDExtension.** goatchurchprime's **TwoVoip** compiles libopus and
  RNNoise to wasm32 and declares both threads and nothreads web libraries. `extensions_support`
  is already enabled here, so this is available. Their no-threads web build is currently broken
  (their issue #77), and it adds a third-party native dependency.

### 6.5 `JitterBuffer`

One instance per remote speaker.

Behaviour:

- Buffers frames keyed by sequence number, accounting for `uint16` wraparound.
- Holds a target of 3 frames (120 ms) before beginning playout. Tune in S3.
- Discards frames that arrive after their playout deadline.
- Discards duplicates.
- On underrun, emits a copy of the last decoded frame with a linear fade to
  silence over its duration, rather than hard silence. This is a cheap
  substitute for real packet loss concealment and materially reduces how harsh
  dropouts sound.
- After 3 consecutive underruns, emits silence and marks the speaker inactive.
- Resets when a speaker's sequence number jumps by more than 32, which indicates
  a reconnect rather than loss.

**Floor on buffered depth.** Godot's resampler pulls 128 source frames at a time, so the
generator must have at least 128 samples (16 ms at 8 kHz) queued at every pull or it
zero-fills. Never let the buffer drain below that. Generator ring capacity at
`buffer_length = 0.2 s` and 8 kHz is 2047 frames (0.256 s) — the ring is rounded to a power of
two, minus one.

Underruns are safe rather than fatal: `AudioStreamGeneratorPlayback` zero-fills, increments
`skips`, and is never auto-deleted.

### 6.6 `VoicePlayback`

One instance per remote speaker, pooled.

Node structure per speaker:

```
VoicePlayback (Node3D)
└── AudioStreamPlayer3D
      stream: AudioStreamGenerator
      playback_type: Stream          # REQUIRED — see §3.3
      bus: "Voice_<slot>"            # statically declared — see §14.1
```

Configuration:

| Property | Value |
|---|---|
| `AudioStreamGenerator.mix_rate` | Codec sample rate (8000) |
| `AudioStreamGenerator.mix_rate_mode` | `MIX_RATE_CUSTOM` (the default) — any other value ignores `mix_rate` entirely |
| `AudioStreamGenerator.buffer_length` | 0.2 s |
| `attenuation_model` | Inverse-distance |
| `unit_size` | **TBD** — tune to level scale |
| `max_distance` | `AUDIBLE_RADIUS` |
| `doppler_tracking` | Disabled |

**Buses are declared statically, never added at runtime** (§14.1). Add `Voice_0 … Voice_N` to
`default_bus_layout.tres`, which currently declares Master, SFX, Music, Ambient and Dialogue.

**Node pooling is mandatory.** Creating and freeing `AudioStreamPlayer3D` nodes as players
cross the audible boundary produces clicks. Build the node once per peer on session join and
gate audibility with bus gain.

**Parenting.** Remote avatars live at `AsteroidLevel/Players/<peer_id>/PlayerBody`, are
interpolated behind a 100 ms snapshot buffer, and the local player already carries an
`AudioListener3D` at `PlayerBody/Head`. Parenting the voice player under the remote
`PlayerBody` inherits the correct interpolated transform for free.

Do not bother driving the transform on the render tick: `AudioStreamPlayer3D` recomputes
panning on `NOTIFICATION_INTERNAL_PHYSICS_PROCESS`, so render-rate updates buy no extra
resolution.

### 6.7 `OcclusionFilter`

An `AudioEffectLowPassFilter` on each speaker's bus, driven by a raycast from
listener to speaker performed at 8 Hz.

| State | Cutoff |
|---|---|
| Clear line of sight | 20000 Hz |
| Fully occluded | 700 Hz |

Transitions are ramped over ~50 ms, **driven step-by-step from GDScript**. The engine picks
up a cutoff change once per 512-frame mix block and does no coefficient interpolation, so
stepping the cutoff directly produces zipper noise. `cutoff_hz` is clamped to 1–20500, so
20000 is legal. Per-bus cost is one biquad stage across 2 channels per block — trivial.

Note that at an 8 kHz codec rate the audible band is already capped at 4 kHz, so the
perceptual range of this filter is compressed. Evaluate during S3 whether occlusion is better
expressed as gain reduction plus a modest cutoff change.

### 6.8 `VoiceService`

The facade. The only voice type the rest of the game references.

```gdscript
func initialise(config: VoiceConfig) -> Error
func shutdown() -> void

func set_local_muted(muted: bool) -> void
func set_peer_muted(peer_id: int, muted: bool) -> void
func set_peer_volume(peer_id: int, volume_db: float) -> void

func get_speaker_loudness(peer_id: int) -> float
func is_peer_speaking(peer_id: int) -> bool

signal voice_unavailable(reason: String)
signal peer_started_speaking(peer_id: int)
signal peer_stopped_speaking(peer_id: int)
```

Owns the peer state machines, the capture instance, and the playback pool.

### 6.9 Per-peer state machine

```
DISCONNECTED ──► CONNECTING ──► ACTIVE ──► DISCONNECTED
                                  │ ▲
                                  ▼ │
                            OUT_OF_RANGE
                                  │ ▲
                                  ▼ │
                                MUTED
```

Voice connections fail independently of the game connection. A peer whose voice
channel has dropped must remain fully playable — the state machine exists so
that this is structurally guaranteed rather than incidentally true.

---

## 7. Configuration Reference

### 7.1 Godot project settings

| Setting | Required value | Reason |
|---|---|---|
| `audio/driver/enable_input` | `true` | **Hard blocker.** Defaults to `false`; `set_input_device_active()` fails without it. `project.godot` currently has no `[audio]` section at all |
| `audio/general/default_playback_type.web` | **leave alone** | Set `playback_type = Stream` per voice node instead (§3.3) |

### 7.2 Export settings

Threads are already enabled (`variant/thread_support=true`) and require COOP/COEP, which on
itch.io means the SharedArrayBuffer checkbox (§2.2). `ensure_cross_origin_isolation_headers`
is inert while PWA is disabled; CI's injected `coi-serviceworker` cannot isolate itch's
cross-origin iframe. Enabling *Progressive Web App* is the in-engine fallback if the itch
route proves unworkable.

Test on the real host early — a build that works locally and fails on the host is the expected
failure mode here.

### 7.3 Tunables summary

| Constant | Value | Tuned in |
|---|---|---|
| `VOICE_SAMPLE_RATE` | 8000 | S3 |
| `VOICE_FRAME_MS` | 40 | S3 |
| `VAD_OPEN_DBFS` | −45 | S3 |
| `VAD_CLOSE_DBFS` | −52 | S3 |
| `VAD_HANGOVER_MS` | 200 | S3 |
| `JITTER_TARGET_FRAMES` | 3 | S3 |
| `JITTER_MIN_SAMPLES` | 128 | Fixed by the engine resampler |
| `AUDIBLE_RADIUS` | TBD | Level design |
| `RELEVANCE_HZ` | 8 | N-player only |

---

## 8. Failure Modes and Degradation

| Failure | Behaviour |
|---|---|
| Microphone permission denied | Receive-only mode. Persistent UI indicator. Gameplay unaffected. |
| No input device | As above. |
| `audio/driver/enable_input` unset | `set_input_device_active()` returns `FAILED`; surface it as "voice unavailable" rather than failing silently. |
| `AudioContext` not resumed | Retry on next user gesture. Log once, do not spam. |
| Input samples outside ±1.0 | Clamped at capture (§14.4). Never reaches the encoder. |
| Data channel send queue backing up | Drop the oldest frames. Do not rely on an error return — there isn't one (§14.3). |
| Voice data channel fails to open for one peer | That peer is silent both ways. Retry with backoff. Game connection unaffected. |
| Sustained packet loss > 30% | Voice is degraded but not disabled. Surface a connection-quality indicator. |
| Jitter buffer persistent underrun | Increase target depth by one frame, up to a maximum of 6. |
| `get_input_frames()` unavailable or misbehaving | Fall back to `AudioStreamMicrophone` + `AudioEffectCapture` (§4.2), then to `NullVoiceCapture`. |

The governing principle: **voice is never load-bearing.** Every failure above
degrades to a playable game with no voice, never to a broken session.

---

## 9. Privacy and Consent

- The microphone is not opened until the player explicitly enables voice. There
  is no implicit start on session join.
- A persistent, always-visible indicator shows when the microphone is live.
- Push-to-talk is available as an alternative to the VAD gate and should be the
  default for first-time users.
- No audio is recorded, buffered to disk, or transmitted anywhere other than
  directly to peers in the session.
- A per-player mute control is reachable within one interaction from gameplay.

---

## 10. Testing

### 10.1 Spikes (blocking, complete before implementation)

| ID | Question | Exit criterion |
|---|---|---|
| S0 | Does the current threaded web build boot on itch.io at all? | Tick the SharedArrayBuffer checkbox, publish a throwaway build, load it in Chrome, Firefox and Safari. This validates the **existing game** and is independent of voice — run it first |
| S1 | Which browsers honour `get_input_frames()` in a web export? | With `enable_input = true`, non-zero frames in Chrome, Firefox and Safari on the real host, permission prompt fires, and no sample exceeds ±1.0 unclamped |
| S2 | Do threads and audio work together on the real host? | `OS.has_feature("threads")` true, audio plays without underruns |
| S3 | Loopback quality and latency | See §10.2 |

None of S0–S2 can be answered by `godot --headless`; they require the real export on the real
host.

### 10.2 Loopback milestone

Before any networking is written: capture → clamp → decimate → encode → decode → play back
locally, through the full node graph including the 3D player and a statically declared
`Voice_0` bus.

This isolates the audio pipeline from the network entirely. Measure:

- Mouth-to-ear latency against the §2.1 budget
- Subjective intelligibility at 8 kHz ADPCM
- CPU cost of decimation, encode and decode per frame in the web export specifically, not
  in the editor

If intelligibility fails here, raise the sample rate to 12 kHz and re-measure before
considering any other change (§6.4).

### 10.3 Network test matrix

| Condition | Expected |
|---|---|
| 0% loss, <20 ms jitter | Clean |
| 5% loss | Occasional artefacts, fully intelligible |
| 15% loss | Degraded, intelligible |
| 30% loss | Heavily degraded, no crashes or state corruption |
| 200 ms jitter spike | Buffer adapts within 2 s |
| Peer hard-disconnect mid-speech | Playback stops cleanly, node returns to pool, no stuck audio |
| Sustained send faster than the channel drains | Frames dropped, no uncaught JS exception |

Use browser devtools network throttling plus an artificial loss injector in the
send path — do not rely on a clean LAN for validation.

Confirm early that the dedicated channel really is unreliable: with `maxRetransmits: 0` set,
induced loss should produce dropouts, not delayed delivery. If it produces delayed delivery,
the channel is not configured as intended (§14.2).

### 10.4 Spatial verification

- A speaker circling the listener pans correctly through a full rotation.
- Voice fades to inaudible at `AUDIBLE_RADIUS` with no discontinuity.
- Crossing the audible boundary repeatedly produces no clicks (validates pooling).
- Occlusion engages and disengages smoothly when a speaker moves behind geometry.
- **Every other sound in the game still plays.** A silenced Master bus is the signature of
  the runtime-`add_bus` bug (§14.1).

---

## 11. Implementation Phases

Each phase is independently testable. Do not combine them — if the artefacts
appear only after three layers land at once, isolating the cause is expensive.

**Phase 0 — Spikes.** S0, S1, S2. Blocking.

**Phase 1 — Loopback.** Capture, conditioning, encoder, decoder,
`AudioStreamPlayer3D` playback on a static bus. No network. Exit: §10.2 passes.

**Phase 2 — Transport.** Dedicated channel setup, packet format, send and receive
paths, per-peer state machine. Fixed 2-frame (~80 ms) jitter buffer, no adaptation. Exit:
both peers hear each other with correct positioning.

**Phase 3 — Robustness.** Real jitter buffer, underrun concealment, backpressure handling,
reconnect handling, failure degradation. Exit: §10.3 passes.

**Phase 4 — Occlusion and controls.** Occlusion raycasts and filtering, per-peer mute and
volume UI. Exit: §10.4 passes.

**Phase 5 — Tuning.** Walk the §7.3 table with real players in the real level.

Relevance culling (§5.2) is not a phase. It arrives with the N-player work, if that happens.

---

## 12. Deferred: Gameplay Coupling

`VoiceService.get_speaker_loudness()` is exposed from v1 specifically so that
gameplay systems can consume voice amplitude later without any change to the
voice stack.

Candidate uses, none in scope for v1 (see A4):

- Voice amplitude as an input to AI perception, so that speaking has a cost
- Speaking indicator on the player avatar or HUD
- Voice-reactive visual effects

Deferred because the coupling is a design decision with balance implications,
and it should be made against a working voice system rather than in the
abstract.

---

## 13. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Cross-origin isolation unavailable or browser-limited on itch.io (A5) | **High — the whole game fails to boot, not just voice** | Resolve in S0 before anything else. Fallbacks: enable PWA export, or drop `thread_support` |
| The four engine bugs in §14 | High — one of them silences the entire game | Each has a stated workaround. Verify each in Phase 1 |
| `get_input_frames()` is marked experimental | Medium | `AudioStreamMicrophone` + `AudioEffectCapture` fallback is specified in §4.2 |
| Nobody has shipped proximity voice in a Godot web export | Medium — no prior art to copy | Phase gates are deliberately small; S1 and S3 are cheap to abandon |
| 8 kHz ADPCM proves unintelligible | Medium | 12 kHz is one constant; then WebCodecs; then TwoVoip (§6.4) |
| Browser inconsistency, Safari especially | Medium | Test all three engines from Phase 1, not at the end |
| Audio-thread contention causing frame drops | Low | Encode/decode measured in the web export in Phase 1 |
| Scope creep into radio channels and voice effects | Medium | Explicitly out of scope in §1.2 |

---

## 14. Engine Bugs to Design Around

All four are verified against Godot 4.7.1 source. None has a fix in the version this project
ships. Read this section before writing code.

### 14.1 `AudioServer.add_bus()` at runtime corrupts the web bus mirror

GDScript's default `at_position = -1` reaches the JS side as `Bus.addAt(-1)`, which calls
`move()` → `splice(-2, 0, bus)`, inserting at `length - 2` instead of appending. JS bus
indices then desync from C++: `set_bus_send` lands on the wrong bus, and Master can be
disconnected from `ctx.destination` — **silencing every sample-mode sound in the game** (all
normal SFX and music) while the stream-mode voice keeps playing. Tracked as
godotengine/godot#119026.

**Workaround:** declare all voice buses statically in `default_bus_layout.tres`.
`set_bus_layout` goes through `set_sample_bus_count`, which appends via `Bus.create()` and
never calls `move()`.

### 14.2 Godot's "unreliable" multiplayer channels are reliable on web

`WebRTCMultiplayerPeer` writes `cfg["maxPacketLifetime"]` — lowercase `t` — where the W3C name
is `maxPacketLifeTime`. WebIDL silently drops the unrecognised key, so the channel keeps its
default reliable, ordered behaviour. Present in 4.6, 4.7.1 and master.

**Workaround:** use a dedicated channel and rely on `maxRetransmits: 0`, which *is* honoured
(Godot JSON-serialises the whole options dictionary and hands it verbatim to
`createDataChannel`, with no allowlist). Never rely on packet lifetime. Verify empirically in
§10.3.

### 14.3 There is no backpressure signal and no send error

Godot's web `put_packet` calls `RTCDataChannel.send()` with no `try`/`catch` and returns `OK`
unconditionally. An `OperationError` at libwebrtc's 16 MiB send-queue ceiling surfaces as an
uncaught JS exception inside the WASM frame rather than as a Godot error.

**Workaround:** poll `WebRTCDataChannel.get_buffered_amount()` before every send and drop
frames when it exceeds a threshold. There is no `bufferedamountlow` event or signal to
subscribe to.

### 14.4 Web microphone samples are not clamped to ±1.0

godotengine/godot#118599, open since April 2026 against 4.6.1 and master, with fix PR #118601
outstanding: "Web audio input samples are not guaranteed to be within -1.0 and 1.0, such as
when all browser preprocessing is disabled."

**Workaround:** clamp at capture, before quantising. An out-of-range sample fed to the ADPCM
encoder produces garbage, not merely clipping.

---

## Appendix A — Glossary

**ADPCM** — Adaptive Differential Pulse Code Modulation. A predictive codec that
encodes the difference between successive samples. Cheap; stateful, which is why
state is re-seeded per frame here.

**COOP / COEP** — Cross-Origin-Opener-Policy and Cross-Origin-Embedder-Policy. The two
response headers a page must carry before the browser grants it `SharedArrayBuffer`.

**Cross-origin isolation** — the state a document is in when COOP and COEP are both set.
Required for WebAssembly threads. Only the *top-level* document can establish it.

**DTX** — Discontinuous Transmission. Sending nothing during silence.

**Jitter buffer** — A short queue that absorbs variance in packet arrival times,
trading latency for smooth playout.

**Mesh** — A topology where every peer connects directly to every other peer. Not what this
project uses; see §5.1.

**PLC** — Packet Loss Concealment. Synthesising plausible audio to cover a lost
frame.

**Sample playback** — Godot's web-default audio path, which routes streams through WebAudio
nodes and bypasses the engine mixer, and therefore all bus effects. Contrast *stream playback*.

**SFU** — Selective Forwarding Unit. A server that forwards media streams
without decoding them. Not available here (§3.1).

**VAD** — Voice Activity Detection. Deciding whether a frame contains speech.

**WebCodecs** — A browser API exposing raw audio/video encoders and decoders, including Opus,
independently of `MediaStreamTrack` and WebRTC.
