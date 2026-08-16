shader_type spatial;

// The life support cube's charge readout. Draws SEGMENTS cells across a quad and
// lights the first `lit_segments` of them, pulsing when told to.
//
// This shader decides nothing. How many segments are lit, what colour they are
// and whether they blink all arrive as uniforms from battery_bar.gd, so the rule
// that four segments is green and one is red exists once, in GDScript, where a
// test can reach it.
//
// Unshaded is load-bearing rather than a look: the point of a gauge on the box
// is that it reads while your own lamp is failing, and a lit material would
// answer that question with how bright your lamp is. No EMISSION for the same
// reason it is absent from power_gauge.tres - in unshaded mode Godot writes
// ALBEDO straight out and never adds it, so an emission colour here would be a
// setting that looks like it is doing the work and is not.
//
// cull_disabled because the player spawns 12 cm above the cube's centre - inside
// its own height, so both quads are edge-on and back-facing at the moment the
// level starts. The cube's body occludes the far side by depth anyway, so
// drawing both sides shows nothing new and makes the bar rasterize from any
// angle, including that one.
render_mode unshaded, cull_disabled;

const int SEGMENTS = 5;

// Half the gap between one cell and the next, as a fraction of a cell.
const float GAP_X = 0.14;

// The unlit border along the short axis of the bar.
const float GAP_Y = 0.18;

// How many cells read as charged, 0 to SEGMENTS. A float rather than an int
// because integer uniforms are the sort of thing that behaves differently on the
// GL Compatibility path, and nothing here needs it to be one.
uniform float lit_segments : hint_range(0.0, 5.0) = 5.0;

uniform vec4 lit_color : source_color = vec4(0.35, 1.0, 0.45, 1.0);

uniform vec4 unlit_color : source_color = vec4(0.1, 0.12, 0.15, 1.0);

uniform vec4 backing_color : source_color = vec4(0.03, 0.04, 0.05, 1.0);

// 1.0 while the bar is alarming. Kept as a float so it can be multiplied rather
// than branched on.
uniform float blink : hint_range(0.0, 1.0) = 0.0;

uniform float blink_rate = 2.4;

uniform float blink_depth : hint_range(0.0, 1.0) = 0.45;


void fragment() {
	// Nudged off 1.0 so the last texel of the bar lands in cell SEGMENTS - 1
	// rather than in a cell that does not exist.
	float along = clamp(UV.x, 0.0, 0.999999) * float(SEGMENTS);
	float index = floor(along);
	float within = fract(along);

	float body = step(GAP_X, within) * step(within, 1.0 - GAP_X);
	body *= step(GAP_Y, UV.y) * step(UV.y, 1.0 - GAP_Y);

	float lit = step(index + 0.5, lit_segments);

	// Same pulse as power_bar.gd and hud_oxygen_ring.gd, so the box and the HUD
	// alarm in one language. Only the lit cells dim; the dark ones have nothing
	// to take away and a pulsing background would read as a flickering panel.
	float pulse = 0.5 + 0.5 * sin(TIME * TAU * blink_rate);
	float dim = mix(1.0, mix(blink_depth, 1.0, pulse), blink * lit);

	vec3 cell = mix(unlit_color.rgb, lit_color.rgb, lit) * dim;
	ALBEDO = mix(backing_color.rgb, cell, body);
}
