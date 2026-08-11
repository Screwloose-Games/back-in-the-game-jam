@tool
extends ScrollContainer

## The Mine Level dock: everything the 3D editor does not already do for you.
##
## Placement, precise coordinates, naming, multi-select and undo are Godot's.
## What is here is the handful of operations that would otherwise mean typing a
## NodePath by hand, plus the numbers the level only has once it is read as a
## graph rather than as a pile of nodes.
##
## CONNECT SELECTED IS THE POINT OF THIS DOCK. A tunnel refers to its two ends by
## NodePath, and typing those is both slow and easy to get wrong. Selecting two
## rooms and pressing a button is the whole interaction the level gets built out
## of.

## How far in front of the 3D camera a newly created space lands.
const SPAWN_DISTANCE := 25.0

## Metres sampled along a tunnel when measuring what the straight-line hearing
## model would cover. Fine enough to compare against the graph answer.
const STRAIGHT_LINE_SAMPLE_STEP := 1.0

## The noise sources the core loop defines, as the radius each carries.
const NOISE_PRESETS := [
	{"label": "Drill / crank", "loudness": 60.0},
	{"label": "Sprint", "loudness": 20.0},
	{"label": "Thrust", "loudness": 12.0},
]

var _undo_redo: EditorUndoRedoManager = null

var _level_label: Label = null
var _color_mode_picker: OptionButton = null
var _label_toggle: CheckBox = null
var _width_slider: HSlider = null
var _width_value: Label = null
var _origin_label: Label = null
var _loudness_slider: HSlider = null
var _sound_report: RichTextLabel = null
var _problem_report: RichTextLabel = null
var _stats_report: RichTextLabel = null
var _content: VBoxContainer = null
var _refresh_timer: Timer = null
var _suppress_control_signals := false


func _ready() -> void:
	_build_scroll_frame()
	_build_ui()
	EditorInterface.get_selection().selection_changed.connect(_on_selection_changed)
	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = 0.5
	_refresh_timer.timeout.connect(refresh)
	add_child(_refresh_timer)
	_refresh_timer.start()
	refresh()


func bind_undo_redo(undo_redo: EditorUndoRedoManager) -> void:
	_undo_redo = undo_redo


## Re-reads the level and repaints every readout. Cheap enough to run on a timer,
## which is what keeps the stats honest while a room is being dragged.
func refresh() -> void:
	var level := _current_level()
	if level == null:
		_level_label.text = "No MineLevel in the open scene."
		_stats_report.text = ""
		_sound_report.text = ""
		return

	_level_label.text = "Editing: %s" % level.name
	_suppress_control_signals = true
	_color_mode_picker.selected = level.color_mode
	_label_toggle.button_pressed = level.show_labels
	_width_slider.value = level.creature_min_width
	_loudness_slider.value = level.sound_loudness
	_suppress_control_signals = false

	_width_value.text = "%.1f m" % level.creature_min_width
	var origin := level.get_node_or_null(level.sound_origin)
	_origin_label.text = "Noise from: %s" % ("nothing" if origin == null else origin.name)
	_stats_report.text = _format_stats(level)
	_sound_report.text = _format_sound_comparison(level)


func _build_ui() -> void:
	_content.add_theme_constant_override("separation", 6)
	_level_label = _add_heading("No MineLevel in the open scene.")

	_add_heading("Create")
	var create_row := HBoxContainer.new()
	_content.add_child(create_row)
	_add_button(create_row, "+ Room", _on_add_room_pressed)
	_add_button(create_row, "+ Junction", _on_add_junction_pressed)
	_add_button(create_row, "+ Dead end", _on_add_dead_end_pressed)

	var connect_row := HBoxContainer.new()
	_content.add_child(connect_row)
	var connect_button := _add_button(connect_row, "Connect selected", _on_connect_pressed)
	connect_button.tooltip_text = ("Select exactly two spaces, then press this. Creates the tunnel and fills in both ends.")
	var bend_button := _add_button(connect_row, "Add bend", _on_add_bend_pressed)
	bend_button.tooltip_text = ("With a tunnel selected, drops a corner at its midpoint. Drag it like any other node.")

	_add_separator()
	_add_heading("View")
	_color_mode_picker = OptionButton.new()
	for mode_name: String in MineLevel.ColorMode.keys():
		_color_mode_picker.add_item(mode_name.capitalize())
	_color_mode_picker.item_selected.connect(_on_color_mode_selected)
	_content.add_child(_color_mode_picker)

	_label_toggle = CheckBox.new()
	_label_toggle.text = "Show labels"
	_label_toggle.toggled.connect(_on_labels_toggled)
	_content.add_child(_label_toggle)

	_add_separator()
	_add_heading("Creature fit")
	var width_row := HBoxContainer.new()
	_content.add_child(width_row)
	_width_slider = HSlider.new()
	_width_slider.min_value = 0.0
	_width_slider.max_value = 16.0
	_width_slider.step = 0.1
	_width_slider.custom_minimum_size = Vector2(120, 0)
	_width_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_width_slider.value_changed.connect(_on_width_changed)
	width_row.add_child(_width_slider)
	_width_value = Label.new()
	_width_value.custom_minimum_size = Vector2(56, 0)
	width_row.add_child(_width_value)
	var width_note := Label.new()
	width_note.text = "Narrowest tunnel the creature fits down."
	width_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	width_note.add_theme_font_size_override("font_size", 10)
	_content.add_child(width_note)

	_add_separator()
	_add_heading("Noise")
	_origin_label = Label.new()
	_content.add_child(_origin_label)
	_add_button(_content, "Use selection as noise origin", _on_set_origin_pressed)

	_loudness_slider = HSlider.new()
	_loudness_slider.min_value = 0.0
	_loudness_slider.max_value = 200.0
	_loudness_slider.step = 1.0
	_loudness_slider.value_changed.connect(_on_loudness_changed)
	_content.add_child(_loudness_slider)

	var preset_row := HBoxContainer.new()
	_content.add_child(preset_row)
	for preset: Dictionary in NOISE_PRESETS:
		var loudness: float = preset["loudness"]
		var button := _add_button(
			preset_row, preset["label"], func() -> void: _apply_loudness(loudness)
		)
		button.tooltip_text = "%.0f m" % loudness

	_sound_report = _add_report()

	_add_separator()
	_add_button(_content, "Validate", _on_validate_pressed)
	_problem_report = _add_report()

	_add_separator()
	_add_heading("Totals")
	_stats_report = _add_report()


func _format_stats(level: MineLevel) -> String:
	var stats := level.describe_stats()
	var lines := PackedStringArray()
	(
		lines
		. append(
			(
				"%d spaces  (%d rooms, %d junctions, %d dead ends)"
				% [
					stats["space_count"],
					stats["room_count"],
					stats["junction_count"],
					stats["dead_end_count"],
				]
			)
		)
	)
	lines.append(
		"%d tunnels, %.0f m of centreline" % [stats["tunnel_count"], stats["total_length"]]
	)
	(
		lines
		. append(
			(
				"longest %s (%.0f m), shortest %s (%.0f m)"
				% [
					stats["longest_tunnel"],
					stats["longest_length"],
					stats["shortest_tunnel"],
					stats["shortest_length"],
				]
			)
		)
	)
	lines.append(
		(
			"creature fits down %d, blocked from %d"
			% [stats["passable_tunnels"], stats["refuge_tunnels"]]
		)
	)
	lines.append("depth %.0f m to %.0f m" % [stats["shallowest"], stats["deepest"]])
	return "\n".join(lines)


## The readout the whole sound feature exists for: what the graph says against
## what a plain distance check says.
##
## The noise system in the core loop prototype does the second one, so the gap
## between these two lines is the size of the bug - every space and every metre
## the creature would currently hear you through solid rock.
func _format_sound_comparison(level: MineLevel) -> String:
	var origin := level.get_node_or_null(level.sound_origin)
	if origin == null:
		return "Pick a space or tunnel and press the button above."

	var graph := level.build_graph()
	var field := level.current_sound_field()
	var loudness := level.sound_loudness
	var total_length := graph.total_length()

	var heard_spaces := field.remaining_at_space.size()
	var heard_metres := 0.0
	for tunnel: LevelGraph.Tunnel in graph.tunnels:
		heard_metres += field.covered_length(tunnel.id)

	var straight_spaces := graph.straight_line_audible_space_ids(field.origin_position, loudness)
	var straight_metres := _straight_line_tunnel_metres(graph, field.origin_position, loudness)

	var lines := PackedStringArray()
	lines.append("%.0f m of noise from %s" % [loudness, field.origin_description])
	lines.append(
		(
			"through tunnels:  %d/%d spaces, %.0f/%.0f m"
			% [heard_spaces, graph.spaces.size(), heard_metres, total_length]
		)
	)
	lines.append(
		(
			"straight line:    %d/%d spaces, %.0f/%.0f m"
			% [straight_spaces.size(), graph.spaces.size(), straight_metres, total_length]
		)
	)
	var extra_spaces := straight_spaces.size() - heard_spaces
	if extra_spaces > 0 or straight_metres > heard_metres + 1.0:
		lines.append(
			(
				"straight line hears through rock: +%d spaces, +%.0f m"
				% [extra_spaces, straight_metres - heard_metres]
			)
		)
	return "\n".join(lines)


func _straight_line_tunnel_metres(graph: LevelGraph, origin: Vector3, loudness: float) -> float:
	var total := 0.0
	for tunnel: LevelGraph.Tunnel in graph.tunnels:
		var span := tunnel.length()
		var steps := maxi(int(ceil(span / STRAIGHT_LINE_SAMPLE_STEP)), 1)
		var step_length := span / float(steps)
		for index: int in steps:
			var sample := tunnel.point_at((float(index) + 0.5) * step_length)
			if origin.distance_to(sample) <= loudness:
				total += step_length
	return total


func _on_add_room_pressed() -> void:
	_create_space(LevelGraph.SpaceKind.ROOM, "room", 5.0)


func _on_add_junction_pressed() -> void:
	_create_space(LevelGraph.SpaceKind.JUNCTION, "junction", 0.0)


func _on_add_dead_end_pressed() -> void:
	_create_space(LevelGraph.SpaceKind.DEAD_END, "pocket", 3.0)


func _create_space(kind: LevelGraph.SpaceKind, base_name: String, radius: float) -> void:
	var level := _current_level()
	if level == null:
		return
	var parent := _container_for(level, "Spaces")
	var space := MineSpace.new()
	space.name = _unique_name(parent, base_name)
	space.kind = kind
	space.radius = radius
	_commit_add(level, parent, space, "Add %s" % base_name, _spawn_position())


## Creates the tunnel between exactly two selected spaces.
func _on_connect_pressed() -> void:
	var level := _current_level()
	if level == null:
		return
	var chosen := _selected_spaces()
	if chosen.size() != 2:
		_problem_report.text = "Select exactly two spaces to connect (%d selected)." % chosen.size()
		return

	var parent := _container_for(level, "Tunnels")
	var tunnel := MineTunnel.new()
	tunnel.name = _unique_name(parent, "%s_to_%s" % [chosen[0].name, chosen[1].name])
	_commit_add(level, parent, tunnel, "Connect spaces", Vector3.ZERO)
	# Paths are relative to the tunnel, so they can only be worked out once it is
	# in the tree under its final parent.
	tunnel.from_space = tunnel.get_path_to(chosen[0])
	tunnel.to_space = tunnel.get_path_to(chosen[1])
	_problem_report.text = (
		"Connected %s to %s (%.0f m)." % [chosen[0].name, chosen[1].name, tunnel.length()]
	)


## Drops a corner at the midpoint of the selected tunnel, inserted into the right
## place in the run rather than appended, so an existing route is not zigzagged.
func _on_add_bend_pressed() -> void:
	var level := _current_level()
	if level == null:
		return
	var tunnel := _selected_tunnel()
	if tunnel == null:
		_problem_report.text = "Select a tunnel first."
		return

	var points := tunnel.build_polyline()
	if points.size() < 2:
		_problem_report.text = "Tunnel '%s' has no usable ends yet." % tunnel.name
		return

	var half := tunnel.length() * 0.5
	var bend := MineBend.new()
	bend.name = _unique_name(tunnel, "bend")
	_commit_add(level, tunnel, bend, "Add bend", _midpoint_of(points, half))
	tunnel.move_child(bend, _segment_index_at(points, half))
	level.mark_visuals_dirty()


func _on_set_origin_pressed() -> void:
	var level := _current_level()
	if level == null:
		return
	for node: Node in EditorInterface.get_selection().get_selected_nodes():
		if node is MineSpace or node is MineTunnel:
			level.sound_origin = level.get_path_to(node)
			EditorInterface.mark_scene_as_unsaved()
			refresh()
			return
	_problem_report.text = "Select a space or a tunnel to make the noise in."


func _on_validate_pressed() -> void:
	var level := _current_level()
	if level == null:
		return
	var problems := level.validate()
	if problems.is_empty():
		_problem_report.text = "No problems found."
		return
	_problem_report.text = "\n".join(problems)


func _on_color_mode_selected(index: int) -> void:
	var level := _current_level()
	if level == null or _suppress_control_signals:
		return
	level.color_mode = index as MineLevel.ColorMode
	EditorInterface.mark_scene_as_unsaved()


func _on_labels_toggled(pressed: bool) -> void:
	var level := _current_level()
	if level == null or _suppress_control_signals:
		return
	level.show_labels = pressed
	EditorInterface.mark_scene_as_unsaved()


func _on_width_changed(value: float) -> void:
	var level := _current_level()
	if level == null or _suppress_control_signals:
		return
	level.creature_min_width = value
	_width_value.text = "%.1f m" % value
	EditorInterface.mark_scene_as_unsaved()


func _on_loudness_changed(value: float) -> void:
	var level := _current_level()
	if level == null or _suppress_control_signals:
		return
	level.sound_loudness = value
	EditorInterface.mark_scene_as_unsaved()


func _on_selection_changed() -> void:
	refresh()


func _apply_loudness(loudness: float) -> void:
	var level := _current_level()
	if level == null:
		return
	level.sound_loudness = loudness
	EditorInterface.mark_scene_as_unsaved()
	refresh()


## Adds `node` under `parent` as one undoable step, owned by the scene root so it
## is actually saved, and leaves it selected.
func _commit_add(
	level: MineLevel, parent: Node, node: Node3D, action: String, world_position: Vector3
) -> void:
	var root := EditorInterface.get_edited_scene_root()
	_undo_redo.create_action(action)
	_undo_redo.add_do_method(parent, &"add_child", node)
	_undo_redo.add_do_method(node, &"set_owner", root)
	_undo_redo.add_do_reference(node)
	_undo_redo.add_undo_method(parent, &"remove_child", node)
	_undo_redo.commit_action()

	node.global_position = world_position
	level.mark_visuals_dirty()
	var selection := EditorInterface.get_selection()
	selection.clear()
	selection.add_node(node)


## The Spaces or Tunnels group under the level, created on demand so a level
## started from scratch does not need them set up by hand first.
func _container_for(level: MineLevel, container_name: String) -> Node:
	var existing := level.get_node_or_null(NodePath(container_name))
	if existing != null:
		return existing
	var container := Node3D.new()
	container.name = container_name
	level.add_child(container)
	container.owner = EditorInterface.get_edited_scene_root()
	return container


func _current_level() -> MineLevel:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return null
	var level := root as MineLevel
	if level != null:
		return level
	for child: Node in root.get_children():
		var nested := child as MineLevel
		if nested != null:
			return nested
	return null


func _selected_spaces() -> Array[MineSpace]:
	var chosen: Array[MineSpace] = []
	for node: Node in EditorInterface.get_selection().get_selected_nodes():
		var space := node as MineSpace
		if space != null:
			chosen.append(space)
	return chosen


func _selected_tunnel() -> MineTunnel:
	for node: Node in EditorInterface.get_selection().get_selected_nodes():
		var tunnel := node as MineTunnel
		if tunnel != null:
			return tunnel
		var bend := node as MineBend
		if bend != null:
			return bend.get_parent() as MineTunnel
	return null


## In front of the 3D viewport camera, so a new space appears where you are
## looking rather than at the world origin.
func _spawn_position() -> Vector3:
	var viewport := EditorInterface.get_editor_viewport_3d(0)
	if viewport == null:
		return Vector3.ZERO
	var camera := viewport.get_camera_3d()
	if camera == null:
		return Vector3.ZERO
	return camera.global_position - camera.global_transform.basis.z * SPAWN_DISTANCE


func _midpoint_of(points: PackedVector3Array, distance: float) -> Vector3:
	var travelled := 0.0
	for index: int in points.size() - 1:
		var step := points[index].distance_to(points[index + 1])
		if travelled + step >= distance and step > 0.0:
			return points[index].lerp(points[index + 1], (distance - travelled) / step)
		travelled += step
	return points[points.size() - 1]


## Which child slot a corner at `distance` belongs in. Polyline point 0 is the
## `from` space and the last is the `to` space, so polyline segment i is the gap
## after child i - which is exactly the index to insert at.
func _segment_index_at(points: PackedVector3Array, distance: float) -> int:
	var travelled := 0.0
	for index: int in points.size() - 1:
		var step := points[index].distance_to(points[index + 1])
		if travelled + step >= distance:
			return index
		travelled += step
	return maxi(points.size() - 2, 0)


func _unique_name(parent: Node, base_name: String) -> String:
	if parent.get_node_or_null(NodePath(base_name)) == null:
		return base_name
	var suffix := 2
	while parent.get_node_or_null(NodePath("%s_%d" % [base_name, suffix])) != null:
		suffix += 1
	return "%s_%d" % [base_name, suffix]


func _add_heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	_content.add_child(label)
	return label


func _add_button(parent: Node, text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(handler)
	parent.add_child(button)
	return button


func _add_report() -> RichTextLabel:
	var report := RichTextLabel.new()
	report.fit_content = true
	report.custom_minimum_size = Vector2(0, 40)
	report.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	report.selection_enabled = true
	_content.add_child(report)
	return report


func _add_separator() -> void:
	_content.add_child(HSeparator.new())


## Puts every control inside a scrolling column.
##
## THE DOCK MUST NOT ASK THE EDITOR FOR HEIGHT. A RichTextLabel with fit_content
## on reports its full text height as its minimum size, so the moment the reports
## were filled in the dock demanded several hundred pixels, the editor's vertical
## split gave it to them, and the bottom panel - filesystem, output, debugger -
## got squeezed off the screen. A ScrollContainer's minimum is its own and it
## clips the rest, so the reports can be as long as they like.
func _build_scroll_frame() -> void:
	custom_minimum_size = Vector2(0, 180)
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_content)
