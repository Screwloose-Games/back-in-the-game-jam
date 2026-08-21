class_name MiningTuning
extends Resource

## Shared knobs for mining pace and mineral toughness. Assign a different
## resource to any prefab instance to override just that one.

@export var damage_per_second: float = 2.0
@export var chunk_health: float = 5.0
