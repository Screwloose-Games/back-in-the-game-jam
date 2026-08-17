extends McpTestSuite

## PlayerPowerClient's powered/unpowered edges — the ones the helmet failure cue
## and every "no power, no lamp" rule hang off.
##
## The suite drives the node without putting it in a tree on purpose: spend() and
## store() touch nothing but charge, while _ready() and is_supplied() want a
## %Tether sibling that only the prefab has. Everything pinned here is arithmetic.

## Enough charge to be unambiguously above RESTORE_FRACTION.
const HEALTHY_FRACTION := 0.5


func suite_name() -> String:
	return "player_power_client"


func _make_client() -> PlayerPowerClient:
	var client := track(PlayerPowerClient.new()) as PlayerPowerClient
	client.settings = PlayerSettings.new()
	client.charge = client.settings.suit_capacity
	return client


func _count(client: PlayerPowerClient, signal_name: StringName) -> Array:
	var heard := []
	client.connect(signal_name, func() -> void: heard.append(true))
	return heard


func test_draining_the_suit_to_empty_says_so_once() -> void:
	var client := _make_client()
	var lost := _count(client, &"power_lost")
	client.spend(client.settings.suit_capacity)
	assert_eq(lost.size(), 1, "the suit going dark is announced")


func test_a_suit_with_charge_left_is_not_lost() -> void:
	var client := _make_client()
	var lost := _count(client, &"power_lost")
	client.spend(client.settings.suit_capacity * 0.9)
	assert_eq(lost.size(), 0, "ten percent is low, not lost")


func test_an_empty_suit_only_says_it_once() -> void:
	var client := _make_client()
	client.spend(client.settings.suit_capacity)
	var lost := _count(client, &"power_lost")
	client.spend(1.0)
	client.spend(1.0)
	assert_eq(lost.size(), 0, "already dark, and it stays quiet")


func test_charge_coming_back_says_so() -> void:
	var client := _make_client()
	client.spend(client.settings.suit_capacity)
	var restored := _count(client, &"power_restored")
	client.store(client.settings.suit_capacity * HEALTHY_FRACTION)
	assert_eq(restored.size(), 1, "power is back")


func test_a_trickle_below_the_dead_band_does_not_count_as_restored() -> void:
	var client := _make_client()
	client.spend(client.settings.suit_capacity)
	var restored := _count(client, &"power_restored")
	var trickle := PlayerPowerClient.RESTORE_FRACTION * 0.5
	client.store(client.settings.suit_capacity * trickle)
	assert_eq(restored.size(), 0, "a box handing back crumbs must not flap the warning")


func test_the_edge_re_arms_after_a_recovery() -> void:
	var client := _make_client()
	client.spend(client.settings.suit_capacity)
	client.store(client.settings.suit_capacity * HEALTHY_FRACTION)
	var lost := _count(client, &"power_lost")
	client.spend(client.settings.suit_capacity)
	assert_eq(lost.size(), 1, "dying twice is announced twice")


func test_running_dry_is_announced_even_below_the_charge_epsilon() -> void:
	var client := _make_client()
	# The last sliver of charge moves the fraction by less than CHANGE_EPSILON,
	# which is the gate charge_changed returns early on.
	client.charge = client.settings.suit_capacity * PlayerPowerClient.CHANGE_EPSILON * 0.5
	var lost := _count(client, &"power_lost")
	client.spend(client.charge)
	assert_eq(lost.size(), 1, "the quietest possible drain still kills the suit")
