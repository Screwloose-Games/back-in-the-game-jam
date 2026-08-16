class_name VoiceAdpcm
extends RefCounted

## IMA ADPCM at four bits per sample, re-seeded at every frame boundary.
##
## The transport is lossy by design, so no coder state may survive a packet: the
## first sample rides in the header as the predictor and the step index is picked
## from the frame's own opening amplitude, which costs a little quality per
## boundary and buys frames that decode independently of each other.

const STEP_TABLE := [
	7,
	8,
	9,
	10,
	11,
	12,
	13,
	14,
	16,
	17,
	19,
	21,
	23,
	25,
	28,
	31,
	34,
	37,
	41,
	45,
	50,
	55,
	60,
	66,
	73,
	80,
	88,
	97,
	107,
	118,
	130,
	143,
	157,
	173,
	190,
	209,
	230,
	253,
	279,
	307,
	337,
	371,
	408,
	449,
	494,
	544,
	598,
	658,
	724,
	796,
	876,
	963,
	1060,
	1166,
	1282,
	1411,
	1552,
	1707,
	1878,
	2066,
	2272,
	2499,
	2749,
	3024,
	3327,
	3660,
	4026,
	4428,
	4871,
	5358,
	5894,
	6484,
	7132,
	7845,
	8630,
	9493,
	10442,
	11487,
	12635,
	13899,
	15289,
	16818,
	18500,
	20350,
	22385,
	24623,
	27086,
	29794,
	32767,
]
const INDEX_TABLE := [-1, -1, -1, -1, 2, 4, 6, 8, -1, -1, -1, -1, 2, 4, 6, 8]
const MAX_STEP_INDEX := 88
const PCM_SCALE := 32767.0
## A four-bit code reconstructs at most about 1.875 step sizes.
const CODE_SPAN := 1.875


static func to_pcm16(samples: PackedFloat32Array) -> PackedInt32Array:
	var pcm := PackedInt32Array()
	pcm.resize(samples.size())
	for i in samples.size():
		pcm[i] = clampi(roundi(samples[i] * PCM_SCALE), -32768, 32767)
	return pcm


static func from_pcm16(value: int) -> float:
	return clampf(float(value) / PCM_SCALE, -1.0, 1.0)


## Chosen from the frame's opening deltas so the step size does not have to climb
## out of silence at the start of every frame.
static func initial_step_index(pcm: PackedInt32Array) -> int:
	if pcm.size() < 2:
		return 0
	var probe := mini(pcm.size() - 1, 8)
	var total := 0
	for i in probe:
		total += absi(pcm[i + 1] - pcm[i])
	var wanted := int(float(total) / float(probe) / CODE_SPAN)
	for i in STEP_TABLE.size():
		if int(STEP_TABLE[i]) >= wanted:
			return i
	return MAX_STEP_INDEX


## Returns predictor, step_index and data; the caller puts the first two in the header.
static func encode(samples: PackedFloat32Array) -> Dictionary:
	var pcm := to_pcm16(samples)
	if pcm.is_empty():
		return {"predictor": 0, "step_index": 0, "data": PackedByteArray()}

	var predictor := pcm[0]
	var step_index := initial_step_index(pcm)
	var code_count := pcm.size() - 1
	var data := PackedByteArray()
	data.resize((code_count + 1) / 2)
	data.fill(0)

	var running := predictor
	var index := step_index
	for k in code_count:
		var step := int(STEP_TABLE[index])
		var diff := pcm[k + 1] - running
		var code := 0
		if diff < 0:
			code = 8
			diff = -diff
		var reconstructed := step >> 3
		if diff >= step:
			code |= 4
			diff -= step
			reconstructed += step
		if diff >= step >> 1:
			code |= 2
			diff -= step >> 1
			reconstructed += step >> 1
		if diff >= step >> 2:
			code |= 1
			reconstructed += step >> 2
		if (code & 8) != 0:
			reconstructed = -reconstructed
		running = clampi(running + reconstructed, -32768, 32767)
		index = clampi(index + int(INDEX_TABLE[code]), 0, MAX_STEP_INDEX)
		if k % 2 == 0:
			data[k >> 1] = code
		else:
			data[k >> 1] |= code << 4

	return {"predictor": predictor, "step_index": step_index, "data": data}


static func decode(
	data: PackedByteArray, predictor: int, step_index: int, sample_count: int
) -> PackedFloat32Array:
	if sample_count <= 0:
		return PackedFloat32Array()
	var code_count := sample_count - 1
	if data.size() < (code_count + 1) / 2:
		return PackedFloat32Array()

	var out := PackedFloat32Array()
	out.resize(sample_count)
	var running := clampi(predictor, -32768, 32767)
	var index := clampi(step_index, 0, MAX_STEP_INDEX)
	out[0] = from_pcm16(running)

	for k in code_count:
		var byte := data[k >> 1]
		var code := (byte & 0x0F) if k % 2 == 0 else ((byte >> 4) & 0x0F)
		var step := int(STEP_TABLE[index])
		var reconstructed := step >> 3
		if (code & 4) != 0:
			reconstructed += step
		if (code & 2) != 0:
			reconstructed += step >> 1
		if (code & 1) != 0:
			reconstructed += step >> 2
		if (code & 8) != 0:
			reconstructed = -reconstructed
		running = clampi(running + reconstructed, -32768, 32767)
		index = clampi(index + int(INDEX_TABLE[code]), 0, MAX_STEP_INDEX)
		out[k + 1] = from_pcm16(running)

	return out
