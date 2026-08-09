class_name MineralLayout
extends RefCounted

## Where every deposit sits, and what it is - the single source of truth for the
## visibility x reachability grid the prototype is built to test.
##
## The grid is the whole point. Read down the list: common deposits sit in plain
## sight and inside the tether's reach; richer ones are tucked behind a pillar,
## up a shaft, or in a dark alcove and cost a detour; the premiums sit at or past
## the mooring's reach, so taking them means unclipping and spending suit power.
## Value scales with how hard it is to get to, NEVER with colour - that is the
## design thesis this prototype is checking.
##
## `position` is world space. `normal` is the direction the ore faces into the
## room, used to orient the formation against its wall. Distances quoted in the
## notes are straight-line from BUOY_SPAWN; the tether reaches MARKER_REACH_RANGE
## (10 m by default), so anything past that is a deliberate unclip.

## Each entry: position, tier, formation, facing normal, and a one-line note on
## the grid cell it fills. Tiers and formations are DepositNode's enums so there
## is one vocabulary, not two that can disagree.
const DEPOSITS := [
	{
		"position": Vector3(3.0, 0.5, 0.5),
		"tier": DepositNode.Tier.COMMON,
		"formation": DepositNode.Formation.SEAM,
		"normal": Vector3(0.0, 0.0, 1.0),
		"note": "open wall by spawn, plainly visible and in reach - the baseline win",
	},
	{
		"position": Vector3(-2.0, 2.0, 2.0),
		"tier": DepositNode.Tier.COMMON,
		"formation": DepositNode.Formation.VEIN,
		"normal": Vector3(0.2, -0.2, 1.0),
		"note": "near and easy, a second legible common to set the reading",
	},
	{
		"position": Vector3(-3.6, 0.0, -2.0),
		"tier": DepositNode.Tier.RICH,
		"formation": DepositNode.Formation.VEIN,
		"normal": Vector3(-0.6, 0.0, 0.6),
		"note": "behind the left pillar - visible only once you fly around it",
	},
	{
		"position": Vector3(5.0, -2.0, -1.0),
		"tier": DepositNode.Tier.RICH,
		"formation": DepositNode.Formation.FLECKS,
		"normal": Vector3(-0.3, 0.2, 1.0),
		"note": "mid-depth flecks - the faint distance clue, still on the leash",
	},
	{
		"position": Vector3(-6.0, -1.0, -3.0),
		"tier": DepositNode.Tier.RICH,
		"formation": DepositNode.Formation.POCKET,
		"normal": Vector3(1.0, 0.2, 0.3),
		"note": "dark side alcove - reads only when the lamp is pointed in",
	},
	{
		"position": Vector3(5.0, 4.0, -2.0),
		"tier": DepositNode.Tier.RICH,
		"formation": DepositNode.Formation.CLUSTER,
		"normal": Vector3(0.0, -1.0, 0.2),
		"note": "up the vertical shaft - in reach but only if you climb",
	},
	{
		"position": Vector3(0.0, -2.0, -6.0),
		"tier": DepositNode.Tier.PREMIUM,
		"formation": DepositNode.Formation.CLUSTER,
		"normal": Vector3(0.0, 0.3, 1.0),
		"note": "far ledge right at the tether limit - the core unclip-or-not moment",
	},
	{
		"position": Vector3(8.0, 3.0, -6.0),
		"tier": DepositNode.Tier.PREMIUM,
		"formation": DepositNode.Formation.FLECKS,
		"normal": Vector3(-0.4, -0.2, 1.0),
		"note": "clearly past reach - tempting, and it drains you to get there",
	},
]
