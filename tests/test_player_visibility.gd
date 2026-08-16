extends McpTestSuite

## PlayerVisibility: which of the three suit meshes the local camera draws.
##
## layers_for() is matched by mesh NAME, so the one way this breaks is a name
## drifting apart from the glTF — silently, because a mesh that matches nothing
## simply stays on the world layer and is drawn. The head in particular encloses
## the camera, so getting it wrong fills the screen.

const BODY := &"player_character_body"
const HEAD := &"player_character_head"
const HELMET := &"player_character_helmet"
## The mining laser's one mesh, from sm_mining_laser.gltf.
const LASER := &"cutter_body"


func suite_name() -> String:
	return "player_visibility"


func _make(is_local: bool) -> PlayerVisibility:
	var visibility := track(PlayerVisibility.new()) as PlayerVisibility
	visibility.is_local_player = is_local
	return visibility


func _culled(visibility: PlayerVisibility, mesh_name: StringName) -> bool:
	return not PlayerRenderLayers.is_visible_to(
		visibility.layers_for(mesh_name), PlayerRenderLayers.local_camera_cull_mask()
	)


func test_the_default_list_hides_both_things_the_camera_sits_inside() -> void:
	var visibility := _make(true)
	assert_true(visibility.parts_hidden_from_self.has(HEAD), "the head is hidden by default")
	assert_true(visibility.parts_hidden_from_self.has(HELMET), "and so is the helmet")


func test_you_do_not_see_your_own_head_or_visor() -> void:
	var visibility := _make(true)
	assert_true(_culled(visibility, HEAD), "your own head is culled")
	assert_true(_culled(visibility, HELMET), "and your own visor with it")


func test_you_still_see_the_rest_of_your_suit() -> void:
	var visibility := _make(true)
	assert_false(_culled(visibility, BODY), "the body stays drawn, so you see your torso")


func test_a_remote_peer_is_drawn_whole() -> void:
	var visibility := _make(false)
	for mesh_name: StringName in [BODY, HEAD, HELMET, LASER]:
		assert_false(_culled(visibility, mesh_name), "%s of another player is drawn" % mesh_name)
	assert_eq(
		visibility.layers_for(BODY),
		PlayerRenderLayers.world_mask(),
		"their torso is world geometry"
	)


## Drawn, but not by their own lamp's shadow casters: it is mounted inside their
## visor and beside their laser, and would otherwise swallow their whole beam.
func test_a_remote_peers_visor_and_tool_are_on_the_peer_suit_layer() -> void:
	var visibility := _make(false)
	for mesh_name: StringName in [HEAD, HELMET, LASER]:
		assert_eq(
			visibility.layers_for(mesh_name),
			PlayerRenderLayers.peer_suit_mask(),
			"%s encloses or crowds their lamp" % mesh_name
		)


func test_third_person_shows_you_your_own_head_again() -> void:
	var visibility := _make(true)
	visibility.set_first_person(false)
	assert_false(_culled(visibility, HEAD), "a third-person camera draws the whole suit")


func test_hide_whole_model_takes_the_body_too() -> void:
	var visibility := _make(true)
	visibility.self_view = PlayerVisibility.SelfView.HIDE_WHOLE_MODEL
	assert_true(_culled(visibility, BODY), "nothing of your own suit is drawn")


func test_an_unlisted_mesh_is_drawn() -> void:
	var visibility := _make(true)
	assert_false(
		_culled(visibility, &"a_mesh_in_no_list"),
		"a mesh that matches nothing stays on the world layer"
	)


## The laser's own layer exists so PlayerLamp can keep your own lamp from casting
## off it. It is a rendering layer, not a hiding one — you still see the tool.
func test_your_own_laser_is_on_the_tool_layer_and_still_drawn() -> void:
	var visibility := _make(true)
	assert_eq(
		visibility.layers_for(LASER), PlayerRenderLayers.own_tool_mask(), "the laser is your tool"
	)
	assert_false(_culled(visibility, LASER), "and you still see it in your hands")


func test_hide_whole_model_takes_the_laser_too() -> void:
	var visibility := _make(true)
	visibility.self_view = PlayerVisibility.SelfView.HIDE_WHOLE_MODEL
	assert_true(_culled(visibility, LASER), "the tool hangs off the rig, so it goes with it")


## A third-person camera is looking at you from outside, where your own lamp
## casting off the laser is the shadow you would expect to see.
func test_third_person_puts_the_laser_back_on_the_world_layer() -> void:
	var visibility := _make(true)
	visibility.set_first_person(false)
	assert_eq(visibility.layers_for(LASER), PlayerRenderLayers.world_mask(), "drawn like any prop")
