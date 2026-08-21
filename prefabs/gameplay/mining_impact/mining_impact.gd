class_name MiningImpact
extends Node3D

## Reusable billboard "chip" burst for a point that's actively being cut.
## Knows nothing about ore -- the owner supplies the color and on/off state.

@onready var _particles: CPUParticles3D = $Particles


func set_color(color: Color) -> void:
	_particles.color = color


func start() -> void:
	_particles.emitting = true


func stop() -> void:
	_particles.emitting = false
