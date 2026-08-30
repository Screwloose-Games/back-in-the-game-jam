@tool
class_name MineralZoneRule
extends Resource

## One biome's share of a MineralScatter pass: which part of the level graph it
## covers, how much ore lands there, and what that ore is made of. Authored per
## level, because the node names and the tags it filters on are level geometry.

## Name of the node under the scatterer's level whose MineSpaces and MineTunnels
## this rule dresses -- "MineBlockout", "RavineBlockout", "HiveBlockout".
@export var zone_node_name: StringName = &""

@export var mineral_types: Array[MineralType] = []

## Parallel to mineral_types. ANY OTHER SIZE MEANS EVERY WEIGHT IS 1.0, so the
## common case of one type per zone needs nothing here at all.
@export var mineral_weights: PackedFloat32Array = PackedFloat32Array()

@export_range(0, 200, 1, "or_greater") var deposit_count: int = 16

## Share of this zone's deposits that go in chambers rather than on tunnel walls.
@export_range(0.0, 1.0, 0.05) var chamber_share: float = 0.7

@export_range(1, 12, 1, "or_greater") var chunk_count: int = 4

## Tag -> multiplier on a chamber's or a bore's sampling weight. Unlisted tags
## count as 1.0, and a site's multipliers are multiplied together. This is how
## the design notes' "the centre has the densest pockets" gets expressed without
## naming individual rooms.
@export var tag_weights: Dictionary[StringName, float] = {}

## Sites carrying any of these are skipped. `winze` keeps the scatter out of the
## elevator shaft, which is tagged that way in every biome that has one.
@export var excluded_tags: Array[StringName] = [&"winze"]


## The mineral type for one deposit, drawn against `mineral_weights`.
func pick_type(rng: RandomNumberGenerator) -> MineralType:
	if mineral_types.is_empty():
		return null
	var weighted := mineral_weights.size() == mineral_types.size()
	var total := 0.0
	for index: int in mineral_types.size():
		total += mineral_weights[index] if weighted else 1.0
	if total <= 0.0:
		return mineral_types[0]

	var roll := rng.randf() * total
	for index: int in mineral_types.size():
		roll -= mineral_weights[index] if weighted else 1.0
		if roll <= 0.0:
			return mineral_types[index]
	return mineral_types[mineral_types.size() - 1]


## How much this rule wants a site carrying `tags`, or 0.0 when it is excluded.
func weight_for_tags(tags: Array[StringName]) -> float:
	var weight := 1.0
	for tag: StringName in tags:
		if excluded_tags.has(tag):
			return 0.0
		weight *= float(tag_weights.get(tag, 1.0))
	return weight


## Empty when this rule is usable, otherwise why it is not.
func describe_problem() -> String:
	if zone_node_name.is_empty():
		return "no zone_node_name set"
	if mineral_types.is_empty():
		return "no mineral_types set on zone '%s'" % zone_node_name
	for type: MineralType in mineral_types:
		if type == null:
			return "an empty slot in mineral_types on zone '%s'" % zone_node_name
	var count := mineral_weights.size()
	if count != 0 and count != mineral_types.size():
		return (
			"zone '%s' has %d mineral_weights for %d mineral_types; it needs the same number or none"
			% [zone_node_name, count, mineral_types.size()]
		)
	return ""
