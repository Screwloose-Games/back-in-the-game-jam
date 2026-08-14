class_name HudArt
extends RefCounted

const RETICLE_02 := preload("res://assets/art/ui/hud/reticle/ui_hud_reticle_02.png")
const RETICLE_03 := preload("res://assets/art/ui/hud/reticle/ui_hud_reticle_03.png")
const RETICLE_04 := preload("res://assets/art/ui/hud/reticle/ui_hud_reticle_04.png")

## HUD_UI Status Green/Yellow/Red, the three faces the designer drew. Indexed by
## HudState.Status, which is why that enum has exactly three values.
const STATUS_GREEN := preload("res://assets/art/ui/hud/status/ui_hud_status_green.png")
const STATUS_YELLOW := preload("res://assets/art/ui/hud/status/ui_hud_status_yellow.png")
const STATUS_RED := preload("res://assets/art/ui/hud/status/ui_hud_status_red.png")

const MINIMAP_BACKGROUND := preload("res://assets/art/ui/hud/minimap/ui_hud_minimap_background.png")
const MINIMAP_LINES01 := preload("res://assets/art/ui/hud/minimap/ui_hud_minimap_lines01.png")
const MINIMAP_LINES02 := preload("res://assets/art/ui/hud/minimap/ui_hud_minimap_lines02.png")
const MINIMAP_LINES03 := preload("res://assets/art/ui/hud/minimap/ui_hud_minimap_lines03.png")
const MINIMAP_LINES04 := preload("res://assets/art/ui/hud/minimap/ui_hud_minimap_lines04.png")
const MINIMAP_REFLECTION := preload("res://assets/art/ui/hud/minimap/ui_hud_minimap_reflection.png")
const ENEMY_DOT := preload("res://assets/art/ui/hud/minimap/ui_hud_enemy_dot.png")

const OXYGEN_RING := preload("res://assets/art/ui/hud/oxygen/ui_hud_oxygen_ring.png")
const OXYGEN_BORDER := preload("res://assets/art/ui/hud/oxygen/ui_hud_oxygen_border.png")
const OXYGEN_LINES := preload("res://assets/art/ui/hud/oxygen/ui_hud_oxygen_lines.png")

const POWER_BG_02 := preload("res://assets/art/ui/hud/power/ui_hud_power_bg_02.png")
const POWER_BG_03 := preload("res://assets/art/ui/hud/power/ui_hud_power_bg_03.png")
const POWER_BG_04 := preload("res://assets/art/ui/hud/power/ui_hud_power_bg_04.png")

const POWER_LINES := preload("res://assets/art/ui/hud/power/ui_hud_power_lines.png")
const POWER_LINES_03 := preload("res://assets/art/ui/hud/power/ui_hud_power_lines_03.png")

const SCREW := preload("res://assets/art/ui/hud/border/ui_hud_screw.png")

const MINIMAP_SIZE := Vector2(333.75, 270.85)
const MINIMAP_BACKGROUND_CENTRE := Vector2(166.88, 135.43)
const MINIMAP_RINGS_CENTRE := Vector2(166.75, 161.53)

const MINIMAP_RINGS_EXTENT := Vector2(166.13, 103.53)

const MINIMAP_HEIGHT_EXTENT := 100.0

const MINIMAP_LINES01_CENTRE := Vector2(166.75, 161.53)
const MINIMAP_LINES02_CENTRE := Vector2(166.75, 161.53)
const MINIMAP_LINES03_CENTRE := Vector2(166.75, 161.53)
const MINIMAP_LINES04_CENTRE := Vector2(166.75, 161.53)

const MINIMAP_REFLECTION_CENTRE := Vector2(236.54, 46.24)

const SCREW_INSET := 46.0


static func status_texture(status: int) -> Texture2D:
	match status:
		HudState.Status.STRAINED:
			return STATUS_YELLOW
		HudState.Status.CRITICAL:
			return STATUS_RED
		_:
			return STATUS_GREEN
