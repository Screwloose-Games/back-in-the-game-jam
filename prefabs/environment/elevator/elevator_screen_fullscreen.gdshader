shader_type canvas_item;

// The quota terminal's tube, full-screen. A canvas_item port of the inner branch of
// elevator_screen.gdshader -- same helpers, same uniforms, same defaults -- so that a
// hard cut between this and the 3D plate is a cut with nothing in it.
//
// PORTED VERBATIM ON PURPOSE. TIME is the same clock in a spatial and a canvas_item
// shader, so the roll band's phase, the hum and tear()'s slot land identically on both
// sides of the cut -- but only while the formulas are character-for-character the same.
// Tidying one of them here is how the cut acquires a visible seam.
//
// WHAT IS GONE: the bezel. There is no ALBEDO/EMISSION split on a canvas item, and
// nothing outside the glass is in frame anyway, so plate_tex survives only to feed the
// grime term -- which matters MORE here than on the plate, because full-screen that
// mottle is the entire background of the shot rather than a few hundred pixels of it.
//
// TWO GAINS, AND EACH NAMES A REAL DIFFERENCE. A CanvasLayer skips everything the
// 3D shot goes through: the car's lighting, the WorldEnvironment's ACES tonemap and
// its glow. ground_gain stands in for the first - on the plate the glass ground is
// ALBEDO and is LIT, and here it is a flat colour nobody shines a lamp on, which
// left the tube reading twice as dark in the half of frame that is not lettering.
// tone_gain is the second: ACES rolls the highlights off, so the 2D text cores come
// out hotter than the plate's unless they are pulled back.
//
// BOTH ARE TUNED BY EYE AGAINST THE CAPTURE PAIR, not reasoned about.
// tools/capture_shots.gd renders the last prologue frame and the first frame after
// the cut for exactly this.

uniform sampler2D content_tex : filter_linear, repeat_disable;
uniform sampler2D plate_tex : source_color, filter_linear_mipmap, repeat_disable;

uniform vec4 screen_rect = vec4(0.112797, 0.140655, 0.769129, 0.705202);
uniform float screen_aspect = 1.5929;

uniform vec4 glass_color : source_color = vec4(0.020, 0.055, 0.052, 1.0);
uniform float grime_ceiling : hint_range(0.005, 0.5) = 0.045;
uniform float grime_strength : hint_range(0.0, 1.0) = 0.70;

uniform float scanline_count = 130.0;
uniform float scanline_depth : hint_range(0.0, 1.0) = 0.35;
uniform float aperture_depth : hint_range(0.0, 1.0) = 0.12;
uniform float roll_speed = 0.11;
uniform float roll_width : hint_range(0.01, 1.0) = 0.22;
uniform float roll_gain : hint_range(0.0, 1.0) = 0.22;
uniform float flicker_hz = 12.7;
uniform float flicker_depth : hint_range(0.0, 0.5) = 0.055;
uniform float glitch_rate : hint_range(0.0, 8.0) = 1.4;
uniform float glitch_amount : hint_range(0.0, 0.2) = 0.035;
uniform float fringe : hint_range(0.0, 0.02) = 0.0008;
uniform float curvature : hint_range(0.0, 0.6) = 0.16;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.55;

uniform float halo_radius : hint_range(0.0, 0.12) = 0.010;
uniform float halo_gain : hint_range(0.0, 4.0) = 0.85;
uniform float bloom_gain : hint_range(0.0, 4.0) = 0.28;
uniform float emission_energy : hint_range(0.0, 8.0) = 1.05;

uniform float power_on : hint_range(0.0, 1.0) = 1.0;
uniform float alarm : hint_range(0.0, 1.0) = 1.0;
uniform float alarm_period = 1.6;
uniform float alarm_min : hint_range(0.0, 2.0) = 0.18;
uniform float alarm_max : hint_range(0.0, 2.0) = 0.66;
uniform float alarm_radius : hint_range(0.0, 0.12) = 0.022;
uniform float content_gamma : hint_range(0.4, 2.4) = 1.0;

// THE CROP, AND WHY IT IS THREE NUMBERS RATHER THAN A COVER FIT. The frame has to
// hold exactly what the 3D camera holds at CLOSEUP_DISTANCE, and a generic cover-fit
// only agrees with that at 16:9 -- at 4:3 it is out by 12% of frame width, and the
// project stretches with aspect=expand, so the window aspect is not a constant.
// frame_height is the fraction of the glass's height the 3D frustum sees; the other
// two turn that into a width. All three are pushed by elevator_monitor_shot.gd, from
// the same knobs the camera pose is baked from.
uniform float content_aspect = 1.5929;
uniform float frame_aspect = 1.7777778;
uniform float frame_height = 1.0;

// The animated property, not modulate. See elevator_monitor_shot.gd.
uniform float shot_alpha : hint_range(0.0, 1.0) = 0.0;
uniform float tone_gain : hint_range(0.0, 4.0) = 1.0;
uniform float ground_gain : hint_range(0.0, 8.0) = 1.0;


float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}


float hash11(float x) {
	return fract(sin(x * 127.1) * 43758.5453);
}


// Barrel warp about the tube centre. The point is that the corners pull in so the
// rim shadow reads as glass depth rather than as a decal.
vec2 curve(vec2 s) {
	vec2 c = s * 2.0 - 1.0;
	c *= 1.0 + curvature * vec2(c.y * c.y, c.x * c.x) * 0.5;
	return c * 0.5 + 0.5;
}


// A band of rows shoved sideways, a few times a second and not on a beat. Most time
// slots do nothing: a tear that fires every slot is a broken screen, one that fires
// occasionally is a screen that has been left on too long.
float tear(float sy, float t) {
	float slot = floor(t * glitch_rate);
	float live = step(0.72, hash11(slot));
	float top = hash11(slot + 3.7) * 0.9;
	float band = step(top, sy) * step(sy, top + 0.09);
	return live * band * (hash11(slot + 11.3) * 2.0 - 1.0);
}


// Content with a chromatic split. Samples outside the tube read black rather than
// clamping to the border texel, so a tear cannot smear a glyph across the glass.
vec3 sample_content(vec2 s) {
	float inside = step(0.0, s.x) * step(s.x, 1.0) * step(0.0, s.y) * step(s.y, 1.0);
	vec2 r = clamp(s + vec2(fringe, 0.0), vec2(0.0), vec2(1.0));
	vec2 g = clamp(s, vec2(0.0), vec2(1.0));
	vec2 b = clamp(s - vec2(fringe, 0.0), vec2(0.0), vec2(1.0));
	vec3 rgb = vec3(
		texture(content_tex, r).r, texture(content_tex, g).g, texture(content_tex, b).b
	);
	return rgb * inside;
}


// Eight taps on a ring plus four inside it. A ViewportTexture carries no mipmaps, so
// there is no textureLod to lean on and the spread has to be gathered by hand.
vec3 halo(vec2 s, float r) {
	vec3 sum = vec3(0.0);
	float d = r * 0.7071;
	sum += texture(content_tex, clamp(s + vec2(r, 0.0), vec2(0.0), vec2(1.0))).rgb;
	sum += texture(content_tex, clamp(s - vec2(r, 0.0), vec2(0.0), vec2(1.0))).rgb;
	sum += texture(content_tex, clamp(s + vec2(0.0, r), vec2(0.0), vec2(1.0))).rgb;
	sum += texture(content_tex, clamp(s - vec2(0.0, r), vec2(0.0), vec2(1.0))).rgb;
	sum += texture(content_tex, clamp(s + vec2(d, d), vec2(0.0), vec2(1.0))).rgb;
	sum += texture(content_tex, clamp(s + vec2(d, -d), vec2(0.0), vec2(1.0))).rgb;
	sum += texture(content_tex, clamp(s + vec2(-d, d), vec2(0.0), vec2(1.0))).rgb;
	sum += texture(content_tex, clamp(s + vec2(-d, -d), vec2(0.0), vec2(1.0))).rgb;
	float h = r * 0.45;
	sum += texture(content_tex, clamp(s + vec2(h, 0.0), vec2(0.0), vec2(1.0))).rgb * 2.0;
	sum += texture(content_tex, clamp(s - vec2(h, 0.0), vec2(0.0), vec2(1.0))).rgb * 2.0;
	sum += texture(content_tex, clamp(s + vec2(0.0, h), vec2(0.0), vec2(1.0))).rgb * 2.0;
	sum += texture(content_tex, clamp(s - vec2(0.0, h), vec2(0.0), vec2(1.0))).rgb * 2.0;
	return sum * 0.0625;
}


void fragment() {
	vec2 s_raw = vec2(
		0.5 + (UV.x - 0.5) * frame_height * frame_aspect / content_aspect,
		0.5 + (UV.y - 0.5) * frame_height
	);

	// The grime is sampled off the plate at the UNCURVED coordinate, exactly as the
	// spatial shader does, so the dirt belongs to the glass rather than to the warp.
	vec2 plate_uv = screen_rect.xy + clamp(s_raw, vec2(0.0), vec2(1.0)) * screen_rect.zw;
	vec3 plate = texture(plate_tex, plate_uv).rgb;
	float grime = min(luma(plate), grime_ceiling) / grime_ceiling;
	vec3 glass = glass_color.rgb * mix(1.0 - grime_strength, 1.0, grime);

	float t = TIME;
	vec2 s = curve(s_raw);
	s.x += tear(s.y, t) * glitch_amount;

	vec3 lit = pow(max(sample_content(s), vec3(0.0)), vec3(content_gamma));

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

	// One halo gather, radius eased toward alarm_radius on the breath. Only the red
	// component takes the opacity pulse, so DENIED breathes while the teal body copy
	// holds steady -- exactly what the reference SVG animates.
	float breath = 0.5 - 0.5 * cos(t * TAU / max(alarm_period, 0.001));
	float pulse = mix(alarm_min, alarm_max, breath);
	vec3 spread = halo(s, mix(halo_radius, alarm_radius, alarm * breath));
	float redness = clamp(spread.r - max(spread.g, spread.b), 0.0, 1.0);
	vec3 red_bloom = vec3(redness * 1.35 + 0.08, redness * 0.18, redness * 0.10);
	vec3 bloom = spread * halo_gain + red_bloom * alarm * pulse + lit * bloom_gain;

	vec2 v = abs(s * 2.0 - 1.0);
	float edge = 1.0 - vignette_strength * dot(v * v, vec2(0.5));
	// Whatever the curvature pushed past the rim is the bezel shadow, not the tube.
	// Without this the warp shows a stretched edge texel instead of a gap.
	float rim = step(0.0, s.x) * step(s.x, 1.0) * step(0.0, s.y) * step(s.y, 1.0);

	// A tube warms up by opening a raster from a centre line, so power_on does that
	// rather than fading brightness. Below about 0.35 there is a line only.
	float open = smoothstep(0.0, 0.7, power_on);
	float raster = smoothstep(0.0, 0.06, open - abs(s.y - 0.5) * 2.0);
	float boot = raster * smoothstep(0.02, 0.45, power_on);

	vec3 picture = mix(plate * 0.15, glass, rim) * ground_gain;
	picture += (lit + bloom) * edge * rim * boot * emission_energy;
	COLOR = vec4(picture * tone_gain, shot_alpha);
}
