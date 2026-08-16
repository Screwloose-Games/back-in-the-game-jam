class_name VoicePacket
extends RefCounted

## The eight byte wire header from spec section 5.4, little endian throughout.
##
## The speaker id is redundant on a two peer link but is carried anyway so a
## future host relay can forward a packet without rewriting it, and the codec id
## lets mixed-version peers negotiate down instead of needing a flag day.

const VERSION := 1
const CODEC_ADPCM := 0
const HEADER_SIZE := 8
const SEQUENCE_MODULO := 65536
const SEQUENCE_HALF := 32768


static func pack(
	speaker_id: int, sequence: int, encoded: Dictionary, codec_id := CODEC_ADPCM, flags := 0
) -> PackedByteArray:
	var payload: PackedByteArray = encoded.get("data", PackedByteArray())
	var bytes := PackedByteArray()
	bytes.resize(HEADER_SIZE + payload.size())
	bytes.encode_u8(0, ((VERSION & 0x0F) << 4) | (codec_id & 0x0F))
	bytes.encode_u8(1, speaker_id & 0xFF)
	bytes.encode_u16(2, sequence & 0xFFFF)
	bytes.encode_s16(4, clampi(int(encoded.get("predictor", 0)), -32768, 32767))
	bytes.encode_u8(6, int(encoded.get("step_index", 0)) & 0xFF)
	bytes.encode_u8(7, flags & 0xFF)
	for i in payload.size():
		bytes.encode_u8(HEADER_SIZE + i, payload[i])
	return bytes


## Returns an empty dictionary for anything that is not a packet we can read.
static func unpack(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < HEADER_SIZE:
		return {}
	var first := bytes.decode_u8(0)
	if (first >> 4) != VERSION:
		return {}
	return {
		"codec_id": first & 0x0F,
		"speaker_id": bytes.decode_u8(1),
		"sequence": bytes.decode_u16(2),
		"predictor": bytes.decode_s16(4),
		"step_index": bytes.decode_u8(6),
		"flags": bytes.decode_u8(7),
		"data": bytes.slice(HEADER_SIZE),
	}


static func next_sequence(sequence: int) -> int:
	return (sequence + 1) % SEQUENCE_MODULO


## Signed distance from b to a, correct across the uint16 wrap.
static func sequence_delta(a: int, b: int) -> int:
	var delta := (a - b) % SEQUENCE_MODULO
	if delta < 0:
		delta += SEQUENCE_MODULO
	if delta >= SEQUENCE_HALF:
		delta -= SEQUENCE_MODULO
	return delta
