class_name HudEase
extends RefCounted

## Newton steps taken to invert the x curve, which reaches float precision at four.
const STEPS := 4


## A cubic bezier whose outer control points sit at 0 and 1, which is every curve
## the mockups ease on - so only the x mapping does any work and y is smoothstep.
static func cubic(x: float, x1: float, x2: float) -> float:
	var target := clampf(x, 0.0, 1.0)
	if target <= 0.0 or target >= 1.0:
		return target
	var cx := 3.0 * x1
	var bx := 3.0 * (x2 - x1) - cx
	var ax := 1.0 - cx - bx
	var t := target
	for _step in STEPS:
		var slope := (3.0 * ax * t + 2.0 * bx) * t + cx
		if absf(slope) < 0.00001:
			break
		t -= (((ax * t + bx) * t + cx) * t - target) / slope
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
