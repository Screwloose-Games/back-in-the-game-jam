class_name HudArt
extends RefCounted

## Every HUD texture, and where Figma puts it.
##
## The art is exported straight out of HUDInterface_02/03/04 in the Screwloose Game
## Jam file, one PNG per named component, so the asset names here are the layer names
## there: RETICLE, STATUS, MINIMAP, OXYGEN, POWER_BG, POWER_LINES, Screw_01. When a
## component is redrawn, re-export it over the same filename and nothing in code
## moves.
##
## WHY EVERY POSITION IS A CENTRE. Figma expands an export's bounding box to include
## strokes and effects, so a node stated as 333.75x270.85 comes out as a 339x276 PNG
## with the extra spread symmetrically around it. Anchoring by top-left would shift
## every asset by half its bleed; anchoring by centre puts it exactly where the
## mockup has it, whatever the bleed turns out to be. So the numbers below are the
## centres of Figma's stated rects, and HudWidget.draw_design_texture draws each
## texture at its natural size around one.
##
## BORDER is the one component with no texture. Figma states it at 1836x1024 and the
## repo's art gate blocks any PNG over 1024 in either dimension - and a stretched
## border is the wrong thing anyway, since it has to meet the screen edges at any
## aspect ratio. It stays drawn; see hud_border.gd.

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

## HUD 02 and 04 export byte-identical cell strips, so they share one file. HUD 03's
## is narrower - its POWER_BG carries the terminal nub that the other two put in the
## strip.
const POWER_LINES := preload("res://assets/art/ui/hud/power/ui_hud_power_lines.png")
const POWER_LINES_03 := preload("res://assets/art/ui/hud/power/ui_hud_power_lines_03.png")

const SCREW := preload("res://assets/art/ui/hud/border/ui_hud_screw.png")

## MINIMAP is 333.75 x 270.85. RADAR_BACKGROUND fills it, but the four RADAR_LINES
## ellipses are concentric about a point below the box's middle - the dish is drawn
## in perspective, so its rings sit low. Contacts belong on the rings, not on the
## background, which is why this is the centre everything dynamic is placed against.
const MINIMAP_SIZE := Vector2(333.75, 270.85)
const MINIMAP_BACKGROUND_CENTRE := Vector2(166.88, 135.43)
const MINIMAP_RINGS_CENTRE := Vector2(166.75, 161.53)

## Half-extents of RADAR_LINES04, the outermost ring. A contact at the rim sits here.
const MINIMAP_RINGS_EXTENT := Vector2(166.13, 103.53)

const MINIMAP_LINES01_CENTRE := Vector2(166.75, 161.53)
const MINIMAP_LINES02_CENTRE := Vector2(166.75, 161.53)
const MINIMAP_LINES03_CENTRE := Vector2(166.75, 161.53)
const MINIMAP_LINES04_CENTRE := Vector2(166.75, 161.53)

## RADAR_REFLECTION, up and to the right of the dish centre.
const MINIMAP_REFLECTION_CENTRE := Vector2(236.54, 46.24)

## Figma states Screw_01 28px in from the frame corner on both axes.
const SCREW_INSET := 46.0


static func status_texture(status: int) -> Texture2D:
	match status:
		HudState.Status.STRAINED:
			return STATUS_YELLOW
		HudState.Status.CRITICAL:
			return STATUS_RED
		_:
			return STATUS_GREEN
