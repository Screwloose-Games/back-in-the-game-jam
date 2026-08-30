shader_type canvas_item;
render_mode blend_mix, unshaded;

// The helmet HUD striking like a tube, over the live world.
//
// A DELIBERATE DERIVATIVE OF elevator_screen_fullscreen.gdshader, not a port of
// it. The tube curve is copied verbatim and must stay that way -- power_on opens
// a raster from a centre line and the two screens in this game have to agree
// about what switching on looks like. Everything the terminal draws BEHIND its
// picture is gone instead: no plate, no grime, no glass, no alarm breath. A
// visor is a window, so the ground here is transparent and the mine shows
// through it. Painting the terminal's near-black ground over the match cut would
// black out the one frame the whole cutscene is built to arrive at.
//
// ALPHA COMES FROM THE CONTENT, not from a uniform. The SubViewport behind this
// is transparent_bg, so the HUD's own coverage is already in content_tex.a; the
// bloom carries its own, or a glyph's halo would be a hard-edged rectangle.

uniform sampler2D content_tex : filter_linear, repeat_disable;

// The crop. Both aspects are pushed together by hud_boot_crt.gd so that s == UV
// and the HUD is neither letterboxed nor stretched at any window size.
uniform float frame_aspect = 1.7777778;
uniform float content_aspect = 1.7777778;
uniform float frame_height : hint_range(0.1, 2.0) = 1.0;

// The tube, 0 (dark) to 1 (settled). The one animated uniform.
uniform float power_on : hint_range(0.0, 1.0) = 0.0;

uniform float scanline_count = 130.0;
uniform float scanline_depth : hint_range(0.0, 1.0) = 0.35;
uniform float aperture_depth : hint_range(0.0, 1.0) = 0.12;
uniform float screen_aspect = 1.7777778;
uniform float roll_speed = 0.11;
uniform float roll_width : hint_range(0.01, 1.0) = 0.22;
uniform float roll_gain : hint_range(0.0, 1.0) = 0.22;
uniform float flicker_hz = 12.7;
uniform float flicker_depth : hint_range(0.0, 0.5) = 0.055;
uniform float fringe = 0.0008;
uniform float curvature : hint_range(0.0, 1.0) = 0.16;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.35;
uniform float halo_radius = 0.006;
uniform float halo_gain : hint_range(0.0, 4.0) = 0.55;
uniform float bloom_gain : hint_range(0.0, 4.0) = 0.28;
uniform float emission_energy : hint_range(0.0, 4.0) = 1.05;

// The white-out as the raster strikes, and how wide a slice of power_on it
// occupies. A tube does not open evenly; it overshoots and settles.
uniform float strike_gain : hint_range(0.0, 4.0) = 1.6;
uniform float strike_at : hint_range(0.0, 1.0) = 0.34;
uniform float strike_width : hint_range(0.01, 0.5) = 0.12;


float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}


// Barrel warp about the tube centre, so the corners pull in and the HUD sits on
// curved glass rather than on the flat front of the screen.
vec2 curve(vec2 s) {
	vec2 c = s * 2.0 - 1.0;
	c *= 1.0 + curvature * vec2(c.y * c.y, c.x * c.x) * 0.5;
	return c * 0.5 + 0.5;
}


// Content with a chromatic split. Samples outside the tube read zero rather than
// clamping to the border texel, so the warp cannot smear an edge pixel outward.
vec4 sample_content(vec2 s) {
	float inside = step(0.0, s.x) * step(s.x, 1.0) * step(0.0, s.y) * step(s.y, 1.0);
	vec2 r = clamp(s + vec2(fringe, 0.0), vec2(0.0), vec2(1.0));
	vec2 g = clamp(s, vec2(0.0), vec2(1.0));
	vec2 b = clamp(s - vec2(fringe, 0.0), vec2(0.0), vec2(1.0));
	vec4 rgba = vec4(
		texture(content_tex, r).r,
		texture(content_tex, g).g,
		texture(content_tex, b).b,
		texture(content_tex, g).a
	);
	return rgba * inside;
}


// Eight taps on a ring plus four inside it. A ViewportTexture carries no mipmaps,
// so there is no textureLod to lean on and the spread is gathered by hand.
vec4 halo(vec2 s, float r) {
	vec4 sum = vec4(0.0);
	float d = r * 0.7071;
	sum += texture(content_tex, clamp(s + vec2(r, 0.0), vec2(0.0), vec2(1.0)));
	sum += texture(content_tex, clamp(s - vec2(r, 0.0), vec2(0.0), vec2(1.0)));
	sum += texture(content_tex, clamp(s + vec2(0.0, r), vec2(0.0), vec2(1.0)));
	sum += texture(content_tex, clamp(s - vec2(0.0, r), vec2(0.0), vec2(1.0)));
	sum += texture(content_tex, clamp(s + vec2(d, d), vec2(0.0), vec2(1.0)));
	sum += texture(content_tex, clamp(s + vec2(d, -d), vec2(0.0), vec2(1.0)));
	sum += texture(content_tex, clamp(s + vec2(-d, d), vec2(0.0), vec2(1.0)));
	sum += texture(content_tex, clamp(s + vec2(-d, -d), vec2(0.0), vec2(1.0)));
	float h = r * 0.45;
	sum += texture(content_tex, clamp(s + vec2(h, 0.0), vec2(0.0), vec2(1.0))) * 2.0;
	sum += texture(content_tex, clamp(s - vec2(h, 0.0), vec2(0.0), vec2(1.0))) * 2.0;
	sum += texture(content_tex, clamp(s + vec2(0.0, h), vec2(0.0), vec2(1.0))) * 2.0;
	sum += texture(content_tex, clamp(s - vec2(0.0, h), vec2(0.0), vec2(1.0))) * 2.0;
	return sum * 0.0625;
}


void fragment() {
	vec2 s_raw = vec2(
		0.5 + (UV.x - 0.5) * frame_height * frame_aspect / content_aspect,
		0.5 + (UV.y - 0.5) * frame_height
	);

	float t = TIME;
	vec2 s = curve(s_raw);

	vec4 content = sample_content(s);
	vec3 lit = content.rgb;

	float lines = 0.5 + 0.5 * cos(s.y * scanline_count * TAU);
	float grille = 0.5 + 0.5 * cos(s.x * scanline_count * screen_aspect * TAU);
	float band = smoothstep(
		1.0, 0.0, abs(fract(s.y - t * roll_speed) - 0.5) / roll_width
	);
	float hum = 1.0
		+ flicker_depth * sin(t * flicker_hz * TAU) * sin(t * flicker_hz * 0.37 * TAU);

	float modulation = mix(1.0, lines, scanline_depth);
	modulation *= mix(1.0, grille, aperture_depth);
	modulation *= 1.0 + band * roll_gain;
	modulation *= hum;
	lit *= modulation;

	vec4 spread = halo(s, halo_radius);
	vec3 bloom = spread.rgb * halo_gain + lit * bloom_gain;

	vec2 v = abs(s * 2.0 - 1.0);
	float edge = 1.0 - vignette_strength * dot(v * v, vec2(0.5));
	float rim = step(0.0, s.x) * step(s.x, 1.0) * step(0.0, s.y) * step(s.y, 1.0);

	// COPIED VERBATIM FROM elevator_screen_fullscreen.gdshader. A tube warms up by
	// opening a raster from a centre line, so power_on does that rather than
	// fading brightness. Below about 0.35 there is a line only.
	float open = smoothstep(0.0, 0.7, power_on);
	float raster = smoothstep(0.0, 0.06, open - abs(s.y - 0.5) * 2.0);
	float boot = raster * smoothstep(0.02, 0.45, power_on);

	// The overshoot. A narrow window of power_on where the whole raster line is
	// brighter than the picture it is about to become -- the flash a CRT gives
	// before it settles. Rides the raster, so it opens from the centre line too.
	float strike = exp(-pow((power_on - strike_at) / strike_width, 2.0)) * strike_gain;

	vec3 picture = (lit + bloom) * edge * rim * boot * emission_energy;
	picture += vec3(0.72, 0.86, 0.95) * raster * strike * edge * rim;

	// Coverage is the HUD's own, widened by whatever the bloom put outside it, and
	// gated by the same boot curve as the colour so the two cannot disagree about
	// when the tube is dark.
	float coverage = clamp(max(content.a, luma(bloom)) * modulation, 0.0, 1.0);
	coverage = clamp(coverage + raster * strike * 0.5, 0.0, 1.0);
	COLOR = vec4(picture, coverage * boot * rim);
}
