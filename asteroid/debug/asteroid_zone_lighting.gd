class_name AsteroidZoneLighting
extends Node3D


func _ready() -> void:
	for light_data in AsteroidLayout.get_zone_lights():
		_add_zone_light(light_data)


func _add_zone_light(light_data: Dictionary) -> void:
	var light := OmniLight3D.new()

	light.name = light_data["name"]
	light.position = light_data["position"]
	light.light_color = light_data["color"]
	light.light_energy = light_data["energy"]
	light.omni_range = light_data["range"]
	light.omni_attenuation = 1.35
	light.shadow_enabled = true
	add_child(light)
