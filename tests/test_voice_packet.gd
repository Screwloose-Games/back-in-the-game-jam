extends McpTestSuite

## VoicePacket: the byte layout, and sequence arithmetic across the uint16 wrap.
##
## The layout is asserted byte by byte rather than only round-tripped, because a
## round trip passes just as happily when both ends share the same wrong offsets -
## and the peer on the other side of the link is a different build.
##
## The wrap tests are here because 65535 to 0 is a step forward of one, and the
## obvious subtraction calls it a jump backwards of 65535, which the jitter buffer
## would read as a reconnect and reset on every wrap.

const Fixtures := preload("res://tests/voice_test_fixtures.gd")


func suite_name() -> String:
	return "voice_packet"


func test_header_is_eight_bytes_ahead_of_the_payload() -> void:
	var bytes := VoicePacket.pack(2, 7, _encoded())
	assert_eq(bytes.size(), VoicePacket.HEADER_SIZE + 160, "8 byte header plus a 160 byte payload")


func test_version_and_codec_share_the_first_byte() -> void:
	var bytes := VoicePacket.pack(2, 7, _encoded(), 3)
	assert_eq(bytes.decode_u8(0) >> 4, VoicePacket.VERSION, "version is the high nibble")
	assert_eq(bytes.decode_u8(0) & 0x0F, 3, "codec id is the low nibble")


func test_sequence_is_little_endian_at_offset_two() -> void:
	var bytes := VoicePacket.pack(1, 0x0201, _encoded())
	assert_eq(bytes.decode_u8(2), 0x01, "low byte first")
	assert_eq(bytes.decode_u8(3), 0x02, "high byte second")


func test_every_header_field_survives_a_round_trip() -> void:
	var encoded := {"predictor": -12345, "step_index": 42, "data": _payload()}
	var unpacked := VoicePacket.unpack(VoicePacket.pack(2, 65535, encoded, 0, 5))
	assert_eq(unpacked["speaker_id"], 2, "speaker id")
	assert_eq(unpacked["sequence"], 65535, "sequence")
	assert_eq(unpacked["predictor"], -12345, "predictor must survive as a signed value")
	assert_eq(unpacked["step_index"], 42, "step index")
	assert_eq(unpacked["flags"], 5, "flags")
	assert_eq(unpacked["data"].size(), 160, "payload length")


func test_a_short_buffer_is_refused() -> void:
	var stub := PackedByteArray()
	stub.resize(4)
	assert_true(VoicePacket.unpack(stub).is_empty(), "anything under a header is not a packet")


func test_a_future_version_is_refused_rather_than_misread() -> void:
	var bytes := VoicePacket.pack(2, 7, _encoded())
	bytes.encode_u8(0, 0xF0)
	assert_true(VoicePacket.unpack(bytes).is_empty(), "an unknown version must not be decoded")


func test_sequence_wraps_forward_by_one() -> void:
	assert_eq(VoicePacket.next_sequence(65535), 0, "the counter wraps rather than growing")
	assert_eq(VoicePacket.sequence_delta(0, 65535), 1, "65535 to 0 is one step forward")
	assert_eq(VoicePacket.sequence_delta(65535, 0), -1, "and the reverse is one step back")


func test_sequence_delta_is_signed_around_the_half_point() -> void:
	assert_eq(VoicePacket.sequence_delta(10, 3), 7, "an ordinary gap forward")
	assert_eq(VoicePacket.sequence_delta(3, 10), -7, "an ordinary gap back")
	assert_eq(VoicePacket.sequence_delta(2, 65530), 8, "a gap that straddles the wrap")


func _payload() -> PackedByteArray:
	var payload := PackedByteArray()
	payload.resize(160)
	for i in 160:
		payload[i] = i % 256
	return payload


func _encoded() -> Dictionary:
	return {"predictor": 1234, "step_index": 9, "data": _payload()}
