@tool
class_name MineralScatter
extends Node3D

## Dresses cave walls with MineralDeposits, one pass per biome, so a level's ore
## can be re-rolled without losing the deposits that were adjusted by hand.
##
## DEPOSITS THIS TOOL MADE JOIN A GROUP, AND NOTHING ELSE IS EVER TOUCHED. Every
## button here ignores any deposit that is not in it, so ore a person placed
## cannot be moved or deleted by pressing the wrong thing.

const DEPOSIT_SCENE := preload("res://prefabs/environment/minerals/prefab_mineral_deposit.tscn")

## Marks a deposit as this tool's to manage. Persistent, so it survives the scene
## file.
const GENERATED_GROUP := &"mineral_scatter"

## The pose a deposit was generated at. One whose transform still matches has not
## been touched, and is the only kind Clear Unedited removes.
const META_TRANSFORM := &"_scatter_transform"

const META_ZONE := &"_scatter_zone"

## Layer 1, `hull`. The rock is on it, but so are the elevator car and its shaft,
## which is why every hit is checked against the rock body rather than trusted
## for having come back on the mask at all.
const HULL_MASK := 1

## Fraction of a chamber or bore a ray is started inside. The carve is a
## 16-segment approximation of its own analytic shape, so the outer ~2% of the
## radius can be solid rock; the ray, not the sample point, finds the wall.
const SAMPLE_INSET := 0.9

## How far past the analytic wall a ray may reach before its hit is rejected as
## something in another room, seen down a tunnel mouth.
const RAY_OVERSHOOT := 1.25

## Metres a deposit's origin is held off the rock. Never negative: the trimesh is
## backface-blind, so an origin inside rock is one no ray can see out of.
const SURFACE_LIFT := 0.05

const TRIES_PER_PLACEMENT := 12

## Draws allowed when sampling a wall by area. A handful is plenty: the worst
## ratio here is the hive's flattest stratum, which accepts about one in three.
const REJECTION_TRIES := 8
const SITE_CHAMBER := 0
const SITE_SPAN := 1

## Tunnels carrying any of these were carved with a round bore rather than a
## square one, so their cross section is an ellipse. Mirrors the default on
## LevelGeometryBuilder.round_profile_tags, which is what actually cut the rock.
const ROUND_PROFILE_TAGS: Array[StringName] = [
	&"natural", &"hive", &"winding", &"warren", &"biome_link"
]

## The MineLevel whose chambers and bores are dressed. Its nested biome scenes
## are what the zone rules name.
@export_node_path("Node3D") var level_path := NodePath("../../LevelFullBlockout"):
	set(value):
		level_path = value
		update_configuration_warnings()

## The baked rock. Only hits on the body under here are accepted, which is what
## keeps deposits off the elevator and off each other.
@export_node_path("Node3D") var rock_path := NodePath("../../LevelRock"):
	set(value):
		rock_path = value
		update_configuration_warnings()

@export var zones: Array[MineralZoneRule] = []:
	set(value):
		zones = value
		update_configuration_warnings()

## Change this and press Generate to re-roll. The same seed always produces the
## same layout, cluster shapes included.
@export var scatter_seed: int = 1

@export_group("Fit")

## Metres between deposits, measured against hand-placed ore as well.
@export_range(0.0, 30.0, 0.5, "or_greater", "suffix:m") var min_separation := 6.0

## Tunnels narrower than this across or floor-to-roof are skipped. A five-chunk
## deposit is roughly 4 m across and 5 m tall and would plug a squeeze.
@export_range(0.0, 30.0, 0.5, "or_greater", "suffix:m") var min_bore := 5.0

@export_range(0.0, 30.0, 0.5, "or_greater", "suffix:m") var min_chamber_radius := 3.0

## Metres of open air a deposit needs in front of the wall it sits on, so a
## cluster is never dropped into a gap it would fill.
@export_range(0.0, 12.0, 0.5, "suffix:m") var min_clearance := 3.0

## Degrees a deposit may lean off the wall normal. Chunk bases are buried along
## the deposit's own Y, so a steep lean buries them at an angle and they surface.
@export_range(0.0, 45.0, 1.0, "suffix:deg") var max_tilt := 10.0

## Lowest surface normal Y a deposit may sit on. -1 takes ceilings as happily as
## floors, which is right here -- chunks are frozen and never fall.
@export_range(-1.0, 1.0, 0.05) var min_surface_up := -1.0

## Nothing is placed within keep_out_radius of these. Player spawn, creature
## spawn and the elevator are the ones that matter.
@export var keep_out: Array[NodePath] = []

@export_range(0.0, 60.0, 1.0, "suffix:m") var keep_out_radius := 12.0

@export_group("Actions")
@export_tool_button("Generate") var generate_action := _generate
@export_tool_button("Re-snap All") var resnap_action := _resnap_all
@export_tool_button("Clear Unedited") var clear_unedited_action := _clear_unedited
@export_tool_button("Clear All") var clear_all_action := _clear_all


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not is_inside_tree():
		return warnings

	var level := get_node_or_null(level_path) as MineLevel
	if level == null:
		warnings.append("level_path does not point at a MineLevel, so there is nothing to dress.")
	if rock_body() == null:
		warnings.append("rock_path has no StaticBody3D under it, so no hit can ever be accepted.")
	if zones.is_empty():
		warnings.append("No zone rules, so Generate would place nothing.")

	for rule: MineralZoneRule in zones:
		if rule == null:
			warnings.append("An empty slot in zones.")
			continue
		var problem := rule.describe_problem()
		if not problem.is_empty():
			warnings.append(problem)
		elif level != null and zone_node(level, rule.zone_node_name) == null:
			warnings.append("No node named '%s' under the level." % rule.zone_node_name)
	return warnings


## Tops the level up to every rule's deposit_count, after dropping the deposits
## nobody has touched since the last pass.
func _generate() -> void:
	if not _can_run():
		return
	var level := get_node_or_null(level_path) as MineLevel
	var rock := rock_body()
	if level == null or rock == null:
		push_warning("MineralScatter: no level or no rock body; nothing generated.")
		return

	_free_unedited()
	var rng := RandomNumberGenerator.new()
	rng.seed = scatter_seed
	var taken := _existing_positions()
	var blocked := _keep_out_positions()
	var placed := 0

	for rule: MineralZoneRule in zones:
		if rule == null or not rule.describe_problem().is_empty():
			continue
		var zone := zone_node(level, rule.zone_node_name)
		if zone == null:
			continue
		var wanted := maxi(rule.deposit_count - _deposits_in_zone(rule.zone_node_name), 0)
		var in_chambers := int(round(wanted * rule.chamber_share))
		var chambers := chamber_sites(zone, rule)
		var spans := span_sites(zone, rule)
		placed += _fill(rule, chambers, in_chambers, rng, rock, taken, blocked)
		placed += _fill(rule, spans, wanted - in_chambers, rng, rock, taken, blocked)

	print("[mineral_scatter] placed %d deposits from seed %d." % [placed, scatter_seed])
	_mark_unsaved()


## Re-buries every managed deposit's chunks against the rock as it stands now,
## without moving or re-picking anything. For a level that has been re-carved.
func _resnap_all() -> void:
	if not _can_run():
		return
	var deposits := _managed_deposits()
	for deposit: MineralDeposit in deposits:
		deposit.dress_in_place()
	print("[mineral_scatter] re-dressed %d deposits." % deposits.size())
	_mark_unsaved()


func _clear_unedited() -> void:
	if not _can_run():
		return
	print("[mineral_scatter] cleared %d unedited deposits." % _free_unedited())
	_mark_unsaved()


## Removes every managed deposit, adjusted ones included, as one undoable step.
func _clear_all() -> void:
	if not _can_run():
		return
	var deposits := _managed_deposits()
	if deposits.is_empty():
		return

	var undo := _undo_redo()
	if undo == null:
		for deposit: MineralDeposit in deposits:
			deposit.get_parent().remove_child(deposit)
			deposit.queue_free()
	else:
		undo.create_action("Clear scattered minerals", UndoRedo.MERGE_DISABLE, self)
		for deposit: MineralDeposit in deposits:
			undo.add_do_method(self, &"_detach", deposit)
			undo.add_undo_method(self, &"_reattach", deposit, deposit.get_parent())
			undo.add_undo_reference(deposit)
		undo.commit_action()
	print("[mineral_scatter] cleared %d deposits." % deposits.size())
	_mark_unsaved()


## Places up to `wanted` deposits on `sites`, and reports how many landed.
func _fill(
	rule: MineralZoneRule,
	sites: Array[Dictionary],
	wanted: int,
	rng: RandomNumberGenerator,
	rock: Node,
	taken: PackedVector3Array,
	blocked: PackedVector3Array
) -> int:
	if sites.is_empty() or wanted <= 0:
		return 0
	var total := 0.0
	for site: Dictionary in sites:
		total += site["weight"]
	if total <= 0.0:
		return 0

	var container := _container_for(rule.zone_node_name)
	var placed := 0
	for _index: int in wanted:
		for _attempt: int in TRIES_PER_PLACEMENT:
			var hit := probe(sample_ray(sites, total, rng), rock)
			if hit.is_empty():
				continue
			var normal: Vector3 = hit["normal"]
			var at: Vector3 = hit["position"] + normal * SURFACE_LIFT
			if _too_close(at, taken, min_separation) or _too_close(at, blocked, keep_out_radius):
				continue
			if not _has_clearance(at, normal):
				continue
			_spawn(rule, container, at, normal, rng)
			taken.append(at)
			placed += 1
			break
	return placed


## One ray from inside a site's analytic volume out to its wall, or an empty
## dictionary when nothing usable was found.
func probe(ray: Dictionary, rock: Node) -> Dictionary:
	var from: Vector3 = ray["origin"]
	var heading: Vector3 = ray["heading"]
	var reach: float = ray["reach"] * RAY_OVERSHOOT
	if reach <= 0.0:
		return {}

	var query := PhysicsRayQueryParameters3D.create(from, from + heading * reach, HULL_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.get("collider") != rock:
		return {}
	var normal: Vector3 = hit["normal"]
	if normal.length_squared() < 0.5 or normal.dot(heading) > -0.1:
		return {}
	if normal.dot(Vector3.UP) < min_surface_up:
		return {}
	return {"position": hit["position"], "normal": normal.normalized()}


## Instantiates a deposit, seats it, dresses it and records the pose it was born
## at. Every line here is ordered; read the comments before moving one.
func _spawn(
	rule: MineralZoneRule,
	container: Node3D,
	at: Vector3,
	normal: Vector3,
	rng: RandomNumberGenerator
) -> void:
	var deposit := DEPOSIT_SCENE.instantiate() as MineralDeposit
	# Both BEFORE add_child: _scatter_chunks() runs from _ready() and copies them.
	deposit.mineral_type = rule.pick_type(rng)
	deposit.chunk_count = rule.chunk_count
	deposit.name = "%s_%02d" % [_short_name(rule.zone_node_name), container.get_child_count() + 1]
	# _scatter_chunks() draws on the global RNG, so seeding it here is what makes
	# one seed reproduce a whole layout rather than only the placements.
	seed(rng.randi())
	container.add_child(deposit)
	# After add_child or PackedScene.pack() drops it, and before dress_in_place()
	# because _bake_chunks() reads the edited scene root to own the chunks.
	deposit.owner = get_tree().edited_scene_root
	deposit.add_to_group(GENERATED_GROUP, true)
	deposit.global_transform = Transform3D(_facing(normal, rng), at)
	deposit.dress_in_place()
	# Local, not global, so moving the container does not orphan every deposit at
	# once. Recorded last, because dressing is part of the generated pose.
	deposit.set_meta(META_TRANSFORM, deposit.transform)
	deposit.set_meta(META_ZONE, rule.zone_node_name)


## A basis whose +Y is the wall normal, spun at random about it and leaned by up
## to max_tilt so a run of deposits does not read as stamped.
func _facing(normal: Vector3, rng: RandomNumberGenerator) -> Basis:
	var up := normal.normalized()
	var reference := Vector3.RIGHT if absf(up.dot(Vector3.UP)) > 0.99 else Vector3.UP
	var side := reference.cross(up).normalized()
	var basis := Basis(side, up, side.cross(up)).rotated(up, rng.randf() * TAU)
	var tilt := deg_to_rad(max_tilt)
	basis = basis.rotated(basis.x, rng.randf_range(-tilt, tilt))
	basis = basis.rotated(basis.z, rng.randf_range(-tilt, tilt))
	return basis.orthonormalized()


## Every chamber in a zone worth dressing, as a weighted sampling site.
##
## A radius below min_chamber_radius drops out here, which also removes every
## bare corner: those carve no chamber at all, and a cluster at one lands in rock.
func chamber_sites(zone: Node3D, rule: MineralZoneRule) -> Array[Dictionary]:
	var sites: Array[Dictionary] = []
	for space: MineSpace in _spaces_under(zone):
		if space.radius < min_chamber_radius:
			continue
		var tag_weight := rule.weight_for_tags(space.tags)
		if tag_weight <= 0.0:
			continue
		var extents := Vector3(space.radius, space.radius * space.vertical_scale, space.radius)
		(
			sites
			. append(
				{
					"kind": SITE_CHAMBER,
					"center": space.global_position,
					"extents": extents,
					"weight": extents.x * extents.y * extents.z * tag_weight,
				}
			)
		)
	return sites


## Every straight run of every tunnel in a zone, as weighted sampling sites.
##
## One site per span rather than per tunnel: a bend's two halves point different
## ways, and a bore's cross section is only defined across its own run.
func span_sites(zone: Node3D, rule: MineralZoneRule) -> Array[Dictionary]:
	var sites: Array[Dictionary] = []
	for tunnel: MineTunnel in _tunnels_under(zone):
		var tall := tunnel.bore_height()
		if minf(tunnel.width, tall) < min_bore:
			continue
		var tag_weight := rule.weight_for_tags(tunnel.tags)
		if tag_weight <= 0.0:
			continue
		var is_round := _wants_round_bore(tunnel)
		var area := PI * 0.25 * tunnel.width * tall if is_round else tunnel.width * tall
		# Empty for a half-wired tunnel, which is exactly what the carve skipped.
		var points := tunnel.build_polyline()
		for index: int in maxi(points.size() - 1, 0):
			var span := points[index + 1] - points[index]
			if span.is_zero_approx():
				continue
			var heading := span.normalized()
			(
				sites
				. append(
					{
						"kind": SITE_SPAN,
						"from": points[index],
						"to": points[index + 1],
						# Matches the carve: X across, Y floor to roof, -Z along the run.
						"basis": Basis.looking_at(heading, _reference_up(heading)),
						"half": Vector2(tunnel.width, tall) * 0.5,
						"round": is_round,
						"weight": area * span.length() * tag_weight,
					}
				)
			)
	return sites


## Picks a site by weight and turns it into a ray: where to start, which way to
## look, and how far the analytic wall is in that direction.
func sample_ray(sites: Array[Dictionary], total: float, rng: RandomNumberGenerator) -> Dictionary:
	var roll := rng.randf() * total
	var site: Dictionary = sites[sites.size() - 1]
	for candidate: Dictionary in sites:
		roll -= candidate["weight"]
		if roll <= 0.0:
			site = candidate
			break
	if site["kind"] == SITE_CHAMBER:
		return _chamber_ray(site, rng)
	return _span_ray(site, rng)


## Picks where a ray starts and the point on the analytic wall it aims for, so
## its reach is a distance rather than an intersection to solve.
func _chamber_ray(site: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var extents: Vector3 = site["extents"]
	var centre: Vector3 = site["center"]
	var inside := _unit_vector(rng) * pow(rng.randf(), 1.0 / 3.0) * SAMPLE_INSET * extents
	return _aim(centre + inside, _on_spheroid(rng, extents) - inside)


## A ray across a bore rather than along it, so it can never run out of a tunnel
## end and strike the far wall of the room beyond.
func _span_ray(site: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var basis: Basis = site["basis"]
	var half: Vector2 = site["half"]
	var is_round: bool = site["round"]
	var inside := _in_cross_section(rng, half, is_round) * SAMPLE_INSET
	var across := _on_cross_section(rng, half, is_round) - inside
	var from: Vector3 = site["from"]
	var origin := from.lerp(site["to"], rng.randf()) + basis.x * inside.x + basis.y * inside.y
	return _aim(origin, basis.x * across.x + basis.y * across.y)


func _aim(origin: Vector3, span: Vector3) -> Dictionary:
	var reach := span.length()
	if reach < 0.001:
		return {"origin": origin, "heading": Vector3.UP, "reach": 0.0}
	return {"origin": origin, "heading": span / reach, "reach": reach}


## A point on a chamber wall, drawn evenly over its AREA rather than evenly over
## direction.
##
## THE DIFFERENCE IS THE WHOLE HIVE. Its chambers are flattened to a third of
## their width, so most of the wall is floor and roof; sampling by direction
## aims most rays at the narrow rim instead, out along the plane of the stratum
## where the next chamber is already open air and there is nothing to hit.
func _on_spheroid(rng: RandomNumberGenerator, extents: Vector3) -> Vector3:
	var densest := maxf(extents.x * extents.y, maxf(extents.y * extents.z, extents.z * extents.x))
	var facing := _unit_vector(rng)
	for _attempt: int in REJECTION_TRIES:
		var element := Vector3(
			extents.y * extents.z * facing.x,
			extents.x * extents.z * facing.y,
			extents.x * extents.y * facing.z
		)
		if rng.randf() * densest <= element.length():
			break
		facing = _unit_vector(rng)
	return facing * extents


func _in_cross_section(rng: RandomNumberGenerator, half: Vector2, is_round: bool) -> Vector2:
	if not is_round:
		return Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * half
	var spin := rng.randf() * TAU
	return Vector2(cos(spin), sin(spin)) * sqrt(rng.randf()) * half


## A point on a bore wall, drawn evenly along its PERIMETER, for the same reason
## _on_spheroid draws evenly over area.
func _on_cross_section(rng: RandomNumberGenerator, half: Vector2, is_round: bool) -> Vector2:
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	if not is_round:
		if rng.randf() * (half.x + half.y) < half.x:
			return Vector2(rng.randf_range(-half.x, half.x), half.y * side)
		return Vector2(half.x * side, rng.randf_range(-half.y, half.y))

	var longest := maxf(half.x, half.y)
	var angle := rng.randf() * TAU
	for _attempt: int in REJECTION_TRIES:
		if rng.randf() * longest <= Vector2(half.x * sin(angle), half.y * cos(angle)).length():
			break
		angle = rng.randf() * TAU
	return Vector2(half.x * cos(angle), half.y * sin(angle))


## Whether there is room in front of this spot for the cluster that goes on it.
func _has_clearance(at: Vector3, normal: Vector3) -> bool:
	if min_clearance <= 0.0:
		return true
	var query := PhysicsRayQueryParameters3D.create(at, at + normal * min_clearance, HULL_MASK)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Frees managed deposits still sitting exactly where they were generated, and
## reports how many went.
##
## EXACT COMPARISON, NOT is_equal_approx. The scene writer round-trips a float
## losslessly, while the approximate test is relative: out at this asteroid's
## coordinates its tolerance is wider than the Inspector's own step, so a real
## nudge would read as untouched and the tool would delete the work.
func _free_unedited() -> int:
	var freed := 0
	for deposit: MineralDeposit in _managed_deposits():
		if not deposit.has_meta(META_TRANSFORM):
			continue
		if deposit.transform != (deposit.get_meta(META_TRANSFORM) as Transform3D):
			continue
		deposit.get_parent().remove_child(deposit)
		deposit.queue_free()
		freed += 1
	return freed


func _managed_deposits() -> Array[MineralDeposit]:
	var found: Array[MineralDeposit] = []
	for deposit: MineralDeposit in _all_deposits():
		if deposit.is_in_group(GENERATED_GROUP):
			found.append(deposit)
	return found


func _all_deposits() -> Array[MineralDeposit]:
	var found: Array[MineralDeposit] = []
	var root := get_tree().edited_scene_root
	if root == null:
		return found
	for node: Node in root.find_children("*", "MineralDeposit", true, false):
		found.append(node as MineralDeposit)
	return found


func _deposits_in_zone(zone_name: StringName) -> int:
	var count := 0
	for deposit: MineralDeposit in _managed_deposits():
		if deposit.get_meta(META_ZONE, &"") == zone_name:
			count += 1
	return count


## Where every deposit in the level is, this tool's and everyone else's, so hand
## placed ore is respected by the spacing test without being managed by it.
func _existing_positions() -> PackedVector3Array:
	var found := PackedVector3Array()
	for deposit: MineralDeposit in _all_deposits():
		found.append(deposit.global_position)
	return found


func _keep_out_positions() -> PackedVector3Array:
	var found := PackedVector3Array()
	for path: NodePath in keep_out:
		var node := get_node_or_null(path) as Node3D
		if node != null:
			found.append(node.global_position)
	return found


## The zone's own child of this node, made on first use and reused after.
func _container_for(zone_name: StringName) -> Node3D:
	var existing := get_node_or_null(NodePath(String(zone_name))) as Node3D
	if existing != null:
		return existing
	var container := Node3D.new()
	container.name = String(zone_name)
	add_child(container)
	container.owner = get_tree().edited_scene_root
	return container


func zone_node(level: MineLevel, zone_name: StringName) -> Node3D:
	if level.name == zone_name:
		return level
	for node: Node in level.find_children(String(zone_name), "Node3D", true, false):
		return node as Node3D
	return null


func _spaces_under(zone: Node3D) -> Array[MineSpace]:
	var level := zone as MineLevel
	if level != null:
		return level.spaces_in_level()
	var found: Array[MineSpace] = []
	for node: Node in zone.find_children("*", "MineSpace", true, false):
		found.append(node as MineSpace)
	return found


func _tunnels_under(zone: Node3D) -> Array[MineTunnel]:
	var level := zone as MineLevel
	if level != null:
		return level.tunnels_in_level()
	var found: Array[MineTunnel] = []
	for node: Node in zone.find_children("*", "MineTunnel", true, false):
		found.append(node as MineTunnel)
	return found


func rock_body() -> Node:
	var holder := get_node_or_null(rock_path)
	if holder == null:
		return null
	if holder is StaticBody3D:
		return holder
	for node: Node in holder.find_children("*", "StaticBody3D", true, false):
		return node
	return null


func _wants_round_bore(tunnel: MineTunnel) -> bool:
	for tag: StringName in ROUND_PROFILE_TAGS:
		if tunnel.tags.has(tag):
			return true
	return false


## Basis.looking_at refuses an up vector parallel to its direction, and the hive
## risers and the ravine's connecting shafts are exactly vertical.
func _reference_up(direction: Vector3) -> Vector3:
	return Vector3.BACK if absf(direction.dot(Vector3.UP)) > 0.99 else Vector3.UP


func _unit_vector(rng: RandomNumberGenerator) -> Vector3:
	var height := rng.randf_range(-1.0, 1.0)
	var ring := sqrt(maxf(1.0 - height * height, 0.0))
	var angle := rng.randf() * TAU
	return Vector3(cos(angle) * ring, height, sin(angle) * ring)


func _can_run() -> bool:
	return Engine.is_editor_hint() and is_inside_tree() and get_tree().edited_scene_root != null


func _detach(deposit: Node) -> void:
	deposit.get_parent().remove_child(deposit)


func _reattach(deposit: Node, parent: Node) -> void:
	parent.add_child(deposit)
	deposit.owner = get_tree().edited_scene_root


## Typed as Object rather than EditorUndoRedoManager on purpose: this script
## ships, and an editor-only class named in a signature is not there to resolve.
func _undo_redo() -> Object:
	if not Engine.has_singleton(&"EditorInterface"):
		return null
	return Engine.get_singleton(&"EditorInterface").get_editor_undo_redo()


func _mark_unsaved() -> void:
	if Engine.has_singleton(&"EditorInterface"):
		Engine.get_singleton(&"EditorInterface").mark_scene_as_unsaved()


static func _too_close(at: Vector3, others: PackedVector3Array, gap: float) -> bool:
	if gap <= 0.0:
		return false
	for other: Vector3 in others:
		if at.distance_to(other) < gap:
			return true
	return false


static func _short_name(zone_name: StringName) -> String:
	return String(zone_name).trim_suffix("Blockout")
