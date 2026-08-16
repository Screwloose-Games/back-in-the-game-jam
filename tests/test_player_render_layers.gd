extends McpTestSuite

## PlayerRenderLayers: the networked visibility rule. Each machine draws one
## camera, so the only thing a mesh has to answer is whether it is the local
## player's own body — remote players need no per-peer bookkeeping at all.


func suite_name() -> String:
	return "player_render_layers"


func _local_sees(mesh_layers: int) -> bool:
	return PlayerRenderLayers.is_visible_to(
		mesh_layers, PlayerRenderLayers.local_camera_cull_mask()
	)


func test_you_do_not_see_your_own_body() -> void:
	assert_false(_local_sees(PlayerRenderLayers.own_body_mask()), "your own suit is culled")


func test_you_do_see_a_remote_player() -> void:
	assert_true(
		_local_sees(PlayerRenderLayers.world_mask()), "remote peers stay on the world layer"
	)


func test_you_see_your_own_viewmodel() -> void:
	assert_true(_local_sees(PlayerRenderLayers.own_viewmodel_mask()), "first-person arms are yours")


func test_you_see_your_own_tool() -> void:
	assert_true(_local_sees(PlayerRenderLayers.own_tool_mask()), "the laser in your hands is drawn")


func test_you_do_see_a_remote_players_visor_and_tool() -> void:
	assert_true(_local_sees(PlayerRenderLayers.peer_suit_mask()), "an ally is drawn whole")


func test_the_five_layers_are_distinct() -> void:
	var masks := {
		"world": PlayerRenderLayers.world_mask(),
		"own body": PlayerRenderLayers.own_body_mask(),
		"viewmodel": PlayerRenderLayers.own_viewmodel_mask(),
		"own tool": PlayerRenderLayers.own_tool_mask(),
		"peer suit": PlayerRenderLayers.peer_suit_mask(),
	}
	for a: String in masks:
		for b: String in masks:
			if a != b:
				assert_eq(masks[a] & masks[b], 0, "%s and %s do not overlap" % [a, b])


func test_layers_stay_inside_godots_twenty() -> void:
	var outside := ~PlayerRenderLayers.ALL_LAYERS
	assert_eq(PlayerRenderLayers.own_body_mask() & outside, 0, "own body")
	assert_eq(PlayerRenderLayers.own_viewmodel_mask() & outside, 0, "viewmodel")
	assert_eq(PlayerRenderLayers.own_tool_mask() & outside, 0, "own tool")
	assert_eq(PlayerRenderLayers.peer_suit_mask() & outside, 0, "peer suit")
	assert_eq(PlayerRenderLayers.local_camera_cull_mask() & outside, 0, "cull mask")
	assert_eq(PlayerRenderLayers.own_lamp_shadow_caster_mask() & outside, 0, "own caster mask")
	assert_eq(PlayerRenderLayers.peer_lamp_shadow_caster_mask() & outside, 0, "peer caster mask")


func test_the_cull_mask_drops_exactly_one_layer() -> void:
	var dropped := PlayerRenderLayers.ALL_LAYERS & ~PlayerRenderLayers.local_camera_cull_mask()
	assert_eq(dropped, PlayerRenderLayers.own_body_mask(), "only your own body is culled")


## A lamp mounted inside a visor and beside a laser casts shadows off both and
## blacks out its own beam. Dropping the suit it is mounted on is what these
## layers exist for, and each lamp drops its own suit and only its own.
func test_a_lamp_casts_no_shadow_from_the_suit_it_is_mounted_on() -> void:
	var own := PlayerRenderLayers.own_lamp_shadow_caster_mask()
	assert_eq(own & PlayerRenderLayers.own_tool_mask(), 0, "your own tool casts nothing")
	assert_eq(own & PlayerRenderLayers.own_body_mask(), 0, "and neither does your own visor")
	var peer := PlayerRenderLayers.peer_lamp_shadow_caster_mask()
	assert_eq(peer & PlayerRenderLayers.peer_suit_mask(), 0, "an ally's own suit casts nothing")
	for casters: int in [own, peer]:
		assert_true(casters & PlayerRenderLayers.world_mask() != 0, "the asteroid still casts")


## The whole point of two masks rather than one: an ally lit by your lamp still
## throws a shadow, and you still throw one in theirs.
func test_each_lamp_still_casts_the_other_players_shadow() -> void:
	assert_true(
		PlayerRenderLayers.own_lamp_shadow_caster_mask() & PlayerRenderLayers.peer_suit_mask() != 0,
		"your lamp casts an ally's shadow"
	)
	assert_true(
		PlayerRenderLayers.peer_lamp_shadow_caster_mask() & PlayerRenderLayers.own_body_mask() != 0,
		"and their lamp casts yours"
	)
