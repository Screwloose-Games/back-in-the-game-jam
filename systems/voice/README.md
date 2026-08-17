# systems/voice

The voice pipeline's maths and its one seam onto the audio driver. Everything in
`core/` is a `RefCounted` over plain arrays — no `Node`, no `SceneTree`, no
`AudioServer` — so the codec, the gate and the jitter buffer can be exercised
headlessly with no microphone attached.

The nodes that use these live beside the prefab, in
`prefabs/character/player/components/`, and the session-level plumbing lives in
`globals/voice_service.gd` and `common/network/voice_channel.gd`. This directory
knows nothing about any of them.

`levels/design/proximity-voice-chat-spec.md` is the design document these files
implement; section numbers in the comments refer to it.

## What is here

| File | `class_name` | What it answers |
|---|---|---|
| `data/voice_config.gd` | `VoiceConfig` | Every tunable in one resource, and the frame sizes derived from them. |
| `core/voice_resampler.gd` | `VoiceResampler` | How to get from the mixer's rate to the codec's without aliasing the speech. |
| `core/voice_rate_estimator.gd` | `VoiceRateEstimator` | What rate capture is *really* delivering at, when the driver's answer cannot be trusted. |
| `core/voice_frame_assembler.gd` | `VoiceFrameAssembler` | Folding stereo capture to clamped mono, and cutting a ragged stream into fixed frames. |
| `core/voice_activity_detector.gd` | `VoiceActivityDetector` | Whether this frame is speech, and how loud it is for the meter. |
| `core/voice_adpcm.gd` | `VoiceAdpcm` | IMA ADPCM at four bits a sample, re-seeded so each frame decodes alone. |
| `core/voice_packet.gd` | `VoicePacket` | The eight byte wire header, and sequence arithmetic across the uint16 wrap. |
| `core/voice_jitter_buffer.gd` | `VoiceJitterBuffer` | One speaker's reorder queue, and what to play when a frame never arrives. |
| `capture/voice_capture.gd` | `VoiceCapture` | The capture seam — and, unchanged, the silent implementation. |
| `capture/mic_bus_voice_capture.gd` | `MicBusVoiceCapture` | Reading the microphone off a muted bus through an `AudioEffectCapture`. |

`capture/` is the one place here that touches `AudioServer`, which is why it is
separated from `core/` rather than mixed into it.

## Every frame decodes on its own

ADPCM is predictive: if the decoder's state drifts from the encoder's, everything
after it is corrupt. The transport is deliberately unreliable, so state is never
allowed to cross a packet boundary. The frame's first sample travels in the header
as the predictor and is reproduced exactly; the step index is picked from the
frame's own opening deltas rather than reset to zero, so the step size does not
have to climb out of silence 25 times a second. `VoiceConfig.code_count()` is
therefore one less than `samples_per_frame()`.

## The reported capture rate is a guess, never the truth

`AudioServer.get_input_mix_rate()` is where a capture stream *starts*, not what it
is resampled from. Godot on web asks its `AudioContext` for a rate and then adopts
whatever the browser hands back — `_godot_audio_init` in the exported `index.js`
takes the mix rate as an in/out pointer and overwrites it with `ctx.sampleRate` —
and Safari both ignores the requested rate and can switch again when `getUserMedia`
opens. Resampling by a ratio that is wrong by 48000/44100 pitch-shifts every frame
up by 8.8%, which the far side hears as the speaker sounding sped up.

So `VoiceCapture` counts the samples that really arrive against the wall clock,
snaps the result to the nearest standard rate, and retunes the resampler when two
windows agree that the driver is wrong. `VoiceConfig.adaptive_capture_rate` turns
it off. The heartbeat in `globals/voice_service.gd` prints `rate=reported/measured/applied`,
which on web is the only place a player can read it from.

## The capture base class is the null implementation

There is no `@abstract` here, matching `systems/navigation/stubs/`. `VoiceCapture`
starts cleanly, reports itself inactive and returns no frames. A denied permission,
a missing input device, a headless test and the editor all end up on that path, and
nothing downstream has to special-case a missing microphone.

## Tests

`tests/test_voice_adpcm.gd`, `test_voice_packet.gd`, `test_voice_resampler.gd`,
`test_voice_rate_estimator.gd`, `test_voice_frame_assembler.gd`,
`test_voice_activity_detector.gd`, `test_voice_jitter_buffer.gd`,
`test_voice_buses.gd`.

```
D:\Godot_v4.7.1-stable_win64.exe --headless --path . res://tests/run_tests.tscn
```

Name the scene or the main menu boots instead.

`test_voice_buses.gd` is the odd one out: it asserts against the live
`AudioServer` rather than pure data, because a mis-shaped bus layout is the one
failure here that can silence the entire game (spec section 14.1) and it is
cheap to catch.

## What this is not

It is not the transport, the node graph, or the options UI. It does not know
about peers, players, or the network. It reads no settings resource — numbers
arrive as a `VoiceConfig` argument, which is what lets the same functions serve
the game and a test that hands them values the game would never produce.
