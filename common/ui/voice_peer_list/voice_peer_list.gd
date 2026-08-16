class_name VoicePeerList
extends VBoxContainer

## Per-peer mute and volume, one row per survivor you can currently hear.
##
## Built at runtime because the peer set is dynamic, and deliberately not
## persisted: these are a local listening choice keyed by peer id, and peer 2 is
## a different person every session.

const VOLUME_WIDTH := 120.0


func refresh() -> void:
	for row in get_children():
		remove_child(row)
		row.queue_free()

	var peer_ids := VoiceService.remote_peer_ids()
	visible = not peer_ids.is_empty()
	for peer_id in peer_ids:
		add_child(_build_row(peer_id))


func _build_row(peer_id: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Peer%d" % peer_id

	var label := Label.new()
	label.text = "Survivor %02d" % peer_id
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var volume := HSlider.new()
	volume.min_value = 0.0
	volume.max_value = 1.0
	volume.step = 0.05
	volume.custom_minimum_size = Vector2(VOLUME_WIDTH, 0.0)
	volume.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	volume.set_value_no_signal(VoiceService.peer_volume(peer_id))
	volume.value_changed.connect(
		func(value: float) -> void: VoiceService.set_peer_volume(peer_id, value)
	)
	row.add_child(volume)

	var mute := CheckButton.new()
	mute.text = "Mute"
	mute.button_pressed = VoiceService.is_peer_muted(peer_id)
	mute.toggled.connect(func(pressed: bool) -> void: VoiceService.set_peer_muted(peer_id, pressed))
	row.add_child(mute)

	return row
