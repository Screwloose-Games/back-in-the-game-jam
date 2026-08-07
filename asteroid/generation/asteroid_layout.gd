class_name AsteroidLayout
extends RefCounted

const LANDING_CENTER := Vector3(0.0, 0.0, 16.0)
const LANDING_RADIUS := 6.0

const ENTRANCE_START := Vector3(0.0, 0.0, 15.0)
const ENTRANCE_END := Vector3(-2.0, -1.0, 7.0)
const ENTRANCE_RADIUS := 2.5

const BLUE_ROOM_CENTER := Vector3(-2.0, -1.0, 7.0)
const BLUE_ROOM_RADIUS := 4.0

const PURPLE_TUNNEL_START := BLUE_ROOM_CENTER
const PURPLE_TUNNEL_END := Vector3(4.0, -3.0, 1.0)
const PURPLE_TUNNEL_RADIUS := 2.0

const PURPLE_ROOM_CENTER := PURPLE_TUNNEL_END
const PURPLE_ROOM_RADIUS := 4.5

const CORE_TUNNEL_START := PURPLE_ROOM_CENTER
const CORE_TUNNEL_END := Vector3(0.0, 2.0, -5.0)
const CORE_TUNNEL_RADIUS := 1.75

const CORE_ROOM_CENTER := CORE_TUNNEL_END
const CORE_ROOM_RADIUS := 3.5

const BLUE_DEPOSIT_1_CENTER := BLUE_ROOM_CENTER + Vector3(-3.8, 0.5, 0.0)
const BLUE_DEPOSIT_2_CENTER := BLUE_ROOM_CENTER + Vector3(3.8, -0.5, 0.0)
const BLUE_DEPOSIT_3_CENTER := BLUE_ROOM_CENTER + Vector3(0.0, -3.8, -0.5)
const BLUE_DEPOSIT_RADIUS := 1.6

const BLUE_VEIN_A_START := BLUE_DEPOSIT_1_CENTER + Vector3(0.0, -1.6, 0.0)
const BLUE_VEIN_A_END := BLUE_DEPOSIT_1_CENTER + Vector3(0.0, 1.8, -0.5)
const BLUE_VEIN_A_BRANCH_END := BLUE_DEPOSIT_1_CENTER + Vector3(0.8, 2.5, 0.8)
const BLUE_VEIN_B_START := BLUE_DEPOSIT_2_CENTER + Vector3(0.0, -1.5, -0.8)
const BLUE_VEIN_B_END := BLUE_DEPOSIT_2_CENTER + Vector3(0.0, 1.8, 0.7)
const BLUE_VEIN_B_BRANCH_END := BLUE_DEPOSIT_2_CENTER + Vector3(-0.8, 2.3, 1.2)
const BLUE_VEIN_C_START := BLUE_DEPOSIT_3_CENTER + Vector3(-1.8, 0.0, 0.0)
const BLUE_VEIN_C_END := BLUE_DEPOSIT_3_CENTER + Vector3(1.8, 0.0, -0.6)
const BLUE_VEIN_RADIUS := 0.9

const PURPLE_DEPOSIT_1_CENTER := PURPLE_ROOM_CENTER + Vector3(-4.3, 0.0, 0.0)
const PURPLE_DEPOSIT_2_CENTER := PURPLE_ROOM_CENTER + Vector3(3.8, 0.5, 0.0)
const PURPLE_DEPOSIT_3_CENTER := PURPLE_ROOM_CENTER + Vector3(0.0, 3.8, -0.5)
const PURPLE_DEPOSIT_RADIUS := 1.8

const PURPLE_VEIN_A_START := PURPLE_DEPOSIT_1_CENTER + Vector3(0.0, -2.0, -0.5)
const PURPLE_VEIN_A_END := PURPLE_DEPOSIT_1_CENTER + Vector3(0.0, 2.2, 0.6)
const PURPLE_VEIN_A_BRANCH_END := PURPLE_DEPOSIT_1_CENTER + Vector3(1.2, 2.8, -0.7)
const PURPLE_VEIN_B_START := PURPLE_DEPOSIT_2_CENTER + Vector3(0.0, -1.8, 0.8)
const PURPLE_VEIN_B_END := PURPLE_DEPOSIT_2_CENTER + Vector3(0.0, 2.1, -0.5)
const PURPLE_VEIN_C_START := PURPLE_DEPOSIT_3_CENTER + Vector3(-2.0, 0.0, 0.6)
const PURPLE_VEIN_C_END := PURPLE_DEPOSIT_3_CENTER + Vector3(2.0, 0.0, -0.8)
const PURPLE_VEIN_RADIUS := 1.15

const YELLOW_DEPOSIT_CENTER := CORE_ROOM_CENTER + Vector3(0.0, 0.0, -3.8)
const YELLOW_DEPOSIT_RADIUS := 2.0
const YELLOW_FORMATION_START := YELLOW_DEPOSIT_CENTER + Vector3(0.0, -2.2, 0.0)
const YELLOW_FORMATION_END := YELLOW_DEPOSIT_CENTER + Vector3(0.0, 2.3, 0.0)
const YELLOW_BRANCH_LEFT := YELLOW_DEPOSIT_CENTER + Vector3(-1.8, 1.1, 0.4)
const YELLOW_BRANCH_RIGHT := YELLOW_DEPOSIT_CENTER + Vector3(1.8, 1.1, 0.4)
const YELLOW_FORMATION_RADIUS := 1.25


static func get_debug_rooms() -> Array[Dictionary]:
	return [
		{
			"name": "Landing Crater",
			"center": LANDING_CENTER,
			"radius": LANDING_RADIUS,
			"color": Color(0.55, 0.75, 1.0, 0.22),
		},
		{
			"name": "Blue Ore Chamber",
			"center": BLUE_ROOM_CENTER,
			"radius": BLUE_ROOM_RADIUS,
			"color": Color(0.05, 0.55, 1.0, 0.30),
		},
		{
			"name": "Purple Ore Cavern",
			"center": PURPLE_ROOM_CENTER,
			"radius": PURPLE_ROOM_RADIUS,
			"color": Color(0.65, 0.15, 1.0, 0.30),
		},
		{
			"name": "Yellow Core Chamber",
			"center": CORE_ROOM_CENTER,
			"radius": CORE_ROOM_RADIUS,
			"color": Color(1.0, 0.78, 0.05, 0.34),
		},
	]


static func get_debug_tunnels() -> Array[Dictionary]:
	return [
		{
			"name": "Entrance Tunnel",
			"start": ENTRANCE_START,
			"end": ENTRANCE_END,
			"radius": ENTRANCE_RADIUS,
			"color": Color(0.25, 0.85, 1.0, 0.25),
		},
		{
			"name": "Purple Descent",
			"start": PURPLE_TUNNEL_START,
			"end": PURPLE_TUNNEL_END,
			"radius": PURPLE_TUNNEL_RADIUS,
			"color": Color(0.55, 0.20, 1.0, 0.25),
		},
		{
			"name": "Core Descent",
			"start": CORE_TUNNEL_START,
			"end": CORE_TUNNEL_END,
			"radius": CORE_TUNNEL_RADIUS,
			"color": Color(1.0, 0.62, 0.05, 0.25),
		},
	]


static func get_debug_ore_deposits() -> Array[Dictionary]:
	return [
		{
			"name": "Blue Vein Zone A",
			"center": BLUE_DEPOSIT_1_CENTER,
			"radius": BLUE_DEPOSIT_RADIUS,
			"color": Color(0.02, 0.45, 1.0, 0.55),
		},
		{
			"name": "Blue Vein Zone B",
			"center": BLUE_DEPOSIT_2_CENTER,
			"radius": BLUE_DEPOSIT_RADIUS,
			"color": Color(0.02, 0.45, 1.0, 0.55),
		},
		{
			"name": "Blue Vein Zone C",
			"center": BLUE_DEPOSIT_3_CENTER,
			"radius": BLUE_DEPOSIT_RADIUS,
			"color": Color(0.02, 0.45, 1.0, 0.55),
		},
		{
			"name": "Purple Seam Zone A",
			"center": PURPLE_DEPOSIT_1_CENTER,
			"radius": PURPLE_DEPOSIT_RADIUS,
			"color": Color(0.62, 0.08, 1.0, 0.58),
		},
		{
			"name": "Purple Seam Zone B",
			"center": PURPLE_DEPOSIT_2_CENTER,
			"radius": PURPLE_DEPOSIT_RADIUS,
			"color": Color(0.62, 0.08, 1.0, 0.58),
		},
		{
			"name": "Purple Seam Zone C",
			"center": PURPLE_DEPOSIT_3_CENTER,
			"radius": PURPLE_DEPOSIT_RADIUS,
			"color": Color(0.62, 0.08, 1.0, 0.58),
		},
		{
			"name": "High-Value Yellow Core",
			"center": YELLOW_DEPOSIT_CENTER,
			"radius": YELLOW_DEPOSIT_RADIUS,
			"color": Color(1.0, 0.75, 0.02, 0.68),
		},
	]


static func get_zone_lights() -> Array[Dictionary]:
	return [
		{
			"name": "Blue Chamber Light",
			"position": BLUE_ROOM_CENTER + Vector3(0.0, 1.0, 0.0),
			"color": Color(0.08, 0.35, 1.0),
			"energy": 2.2,
			"range": 7.0,
		},
		{
			"name": "Purple Cavern Light",
			"position": PURPLE_ROOM_CENTER + Vector3(0.0, 1.0, 0.0),
			"color": Color(0.55, 0.08, 1.0),
			"energy": 2.6,
			"range": 8.0,
		},
		{
			"name": "Yellow Core Light",
			"position": YELLOW_DEPOSIT_CENTER + Vector3(0.0, 0.0, 1.5),
			"color": Color(1.0, 0.55, 0.04),
			"energy": 3.4,
			"range": 7.0,
		},
		{
			"name": "Purple Route Guide",
			"position": BLUE_ROOM_CENTER.lerp(PURPLE_ROOM_CENTER, 0.62),
			"color": Color(0.42, 0.12, 1.0),
			"energy": 1.2,
			"range": 4.0,
		},
		{
			"name": "Core Route Guide",
			"position": PURPLE_ROOM_CENTER.lerp(CORE_ROOM_CENTER, 0.62),
			"color": Color(1.0, 0.35, 0.04),
			"energy": 1.3,
			"range": 4.0,
		},
	]
