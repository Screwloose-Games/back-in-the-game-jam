class_name TentacleImpactAudio
extends Node3D

## The thud a tentacle makes when it hits a wall.
##
## Listens to `TentacleArray.tentacle_planted` and plays one clip at the point of
## contact. It reads that signal and nothing else -- no phases, no anchors, no
## poll of the strand state -- so it cannot disagree with the gait about when a
## tentacle landed, and deleting this node changes nothing about how the creature
## moves.
##
## A POOL, NOT ONE PLAYER. Eight strands land about two and a half times a second
## and a pair lands together by design, so a single AudioStreamPlayer3D would cut
## its own previous thud off every time - the gait's signature double-tap would be
## the one thing you could never hear. Each voice is also MOVED to the anchor
## before it plays, so the sound comes from the piece of wall that was hit rather
## than from the middle of the animal.
##
## PITCH AND VOLUME COME FROM THE IMPACT, then get a little noise on top. A strand
## that threw itself the full length of its chain should land harder than one that
## found a wall a metre away, and a bank of identical thuds is the fastest way to
## make eight limbs sound like one machine gun.

## Placeholder tones, and deliberately an array rather than one stream: the real
## recordings drop in here without this file changing. As generated they are all
## the same 880 Hz sine at different lengths, so today the audible variety is
## almost entirely the pitch and volume below.
const CLIPS: Array[AudioStream] = [
	preload("../../assets/audio/sfx_tentacle_thud_01.wav"),
	preload("../../assets/audio/sfx_tentacle_thud_02.wav"),
	preload("../../assets/audio/sfx_tentacle_thud_03.wav"),
]

@export_group("Wiring")
## The strands to listen to. Without one this node does nothing at all, quietly:
## a creature with no audio is a perfectly good creature.
@export var tentacles: TentacleArray

@export_group("Voices")
## How many thuds can overlap. Six covers a pair landing together three times over
## before the oldest is reused, which is more overlap than the gait can produce.
@export var voice_count: int = 6
## Metres at which a thud has faded to nothing.
@export var max_distance: float = 40.0
## Bus to play on. Falls back to Master with a warning if the host project has no
## bus by this name, so the creature still makes noise in a project that has never
## heard of it.
@export var bus: StringName = &"SFX"

@export_group("Impact")
## Volume in dB at the softest and hardest landing. The quiet end is audible
## rather than silent - a tentacle taking a short grip still touches the wall.
@export var quiet_db: float = -22.0
@export var loud_db: float = -6.0
## Pitch at the softest and hardest landing. Harder is LOWER: a heavy impact is a
## deeper thud, and running this the intuitive way round makes the creature sound
## like it is squeaking when it lunges.
@export var high_pitch: float = 1.35
@export var low_pitch: float = 0.72
## Random spread added on top, so two identical impacts never sound identical.
@export var pitch_jitter: float = 0.12
@export var volume_jitter_db: float = 2.5

var _voices: Array[AudioStreamPlayer3D] = []
var _cursor: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	# Seeded, not global randf(), for the same reason TentacleArray is: two runs of
	# the same scene should sound the same, or an intermittent audio bug cannot be
	# reproduced long enough to find.
	_rng.seed = tentacles.crawler_seed if tentacles != null else 0

	var voice_bus := bus
	if AudioServer.get_bus_index(bus) < 0:
		push_warning('TentacleImpactAudio: no audio bus named "%s"; falling back to Master.' % bus)
		voice_bus = &"Master"

	for i: int in voice_count:
		var voice := AudioStreamPlayer3D.new()
		voice.name = "Voice%d" % i
		voice.bus = voice_bus
		voice.max_distance = max_distance
		# Top level so moving a voice to an anchor is not undone by the creature
		# writhing underneath it. The anchor is a world point.
		voice.top_level = true
		add_child(voice)
		_voices.append(voice)

	if tentacles != null:
		tentacles.tentacle_planted.connect(_on_tentacle_planted)


## Play one thud. `strand` is unused - which tentacle it was does not change what
## hitting a wall sounds like - but it is in the signature because the signal
## carries it and a future version may well want per-limb voices.
func _on_tentacle_planted(_strand: int, position: Vector3, impact: float) -> void:
	if _voices.is_empty() or CLIPS.is_empty():
		return

	var voice := _voices[_cursor]
	_cursor = (_cursor + 1) % _voices.size()

	voice.stream = CLIPS[_rng.randi() % CLIPS.size()]
	voice.global_position = position
	voice.volume_db = (
		lerpf(quiet_db, loud_db, impact) + _rng.randf_range(-volume_jitter_db, volume_jitter_db)
	)
	voice.pitch_scale = maxf(
		lerpf(high_pitch, low_pitch, impact) + _rng.randf_range(-pitch_jitter, pitch_jitter), 0.05
	)
	voice.play()
