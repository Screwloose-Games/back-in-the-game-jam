class_name HudPalette
extends RefCounted

## The handful of colours the HUD still draws rather than blits.
##
## This used to carry two schemes and pre-sampled gradient ramps, back when every
## meter was drawn from primitives. Now that the fills are exported PNGs out of
## Figma, the only things left with a colour in code are the border and the tether
## readout - so this is constants, and widgets reference them directly.
##
## Values transcribed from the Figma Properties panel.

## Stated on BORDER, on the POWER lettering, and on the STATUS frame.
const CHROME := Color("52e552")

## The chrome backed off, for the untethered readout - present, plainly not alarming.
const CHROME_DIM := Color(0.322, 0.898, 0.322, 0.45)

## Stated on TETHERED_METER.
const ALERT := Color("ff0000")

## Stated on Screw_01's border. Kept because it is the one dark value in the kit and
## anything drawn behind chrome should match it rather than pick a new near-black.
const SHADOW := Color("273335")

## What an objective blip is tinted to. Figma has no drawing for one - the minimap
## ships ENEMY_DOT and a static RADAR_REFLECTION and nothing else - so a contact dot
## is recoloured rather than invented, which keeps the two the same shape and size
## and lets colour alone carry the difference.
const OBJECTIVE := Color("6cff6c")
