class_name AsteroidLayoutDebugger
extends Node3D

@export var visible_on_start: bool = true
@export var show_labels: bool = true

var markers_root: Node3D
var toggle_button: Button


func _ready() -> void:
	markers_root = Node3D.new()
	markers_root.name = "LayoutMarkers"
	add_child(markers_root)

	_build_layout()
	_build_toggle_button()
	_set_layout_visible(visible_on_start)


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(&"toggle_asteroid_layout"):
		_set_layout_visible(not markers_root.visible)


func _build_toggle_button() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 20
	add_child(canvas)

	toggle_button = Button.new()
	toggle_button.position = Vector2(16.0, 16.0)
	toggle_button.custom_minimum_size = Vector2(220.0, 42.0)
	toggle_button.pressed.connect(_on_toggle_button_pressed)
	canvas.add_child(toggle_button)


func _on_toggle_button_pressed() -> void:
	_set_layout_visible(not markers_root.visible)


func _set_layout_visible(layout_is_visible: bool) -> void:
	markers_root.visible = layout_is_visible
	toggle_button.text = (
		"Hide Asteroid Layout (L)" if layout_is_visible else "Show Asteroid Layout (L)"
	)


func _build_layout() -> void:
	for room in AsteroidLayout.get_debug_rooms():
		_add_room(room)

	for tunnel in AsteroidLayout.get_debug_tunnels():
		_add_tunnel(tunnel)

	for deposit in AsteroidLayout.get_debug_ore_deposits():
		_add_room(deposit)


func _add_room(room: Dictionary) -> void:
	var radius: float = room["radius"]
	var marker := MeshInstance3D.new()
	var sphere := SphereMesh.new()

	sphere.radius = radius
	sphere.height = radius * 2.0
	marker.mesh = sphere
	marker.position = room["center"]
	marker.material_override = _make_xray_material(room["color"])
	markers_root.add_child(marker)

	if show_labels:
		_add_label(room["name"], room["center"], room["color"])


func _add_tunnel(tunnel: Dictionary) -> void:
	var start: Vector3 = tunnel["start"]
	var end: Vector3 = tunnel["end"]
	var direction := end - start
	var radius: float = tunnel["radius"]
	var marker := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()

	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = direction.length()
	marker.mesh = cylinder
	marker.position = (start + end) * 0.5
	marker.quaternion = Quaternion(Vector3.UP, direction.normalized())
	marker.material_override = _make_xray_material(tunnel["color"])
	markers_root.add_child(marker)

	if show_labels:
		_add_label(tunnel["name"], marker.position, tunnel["color"])


func _add_label(label_text: String, label_position: Vector3, color: Color) -> void:
	var label := Label3D.new()

	label.text = label_text
	label.position = label_position
	label.modulate = Color(color.r, color.g, color.b, 1.0)
	label.outline_size = 8
	label.no_depth_test = true
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 32
	markers_root.add_child(label)


func _make_xray_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()

	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
