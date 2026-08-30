shader_type spatial;

// The elevator quota terminal. ONE quad carries the whole plate: the rusted bezel
// is lit like any other surface, and the inner rectangle named by screen_rect is
// torn out and rebuilt from a SubViewport plus a tube simulation.
//
// LIT, NOT UNSHADED, and that is the opposite of battery_bar.gdshader. The gauge on
// the life-support cube is unshaded because its job is to stay readable while your
// lamp is failing. This is a bezel bolted to a wall: if it ignored the car's lamp it
// would float off the wall it is bolted to. The screen keeps its independence a
// different way -- inside screen_rect the ALBEDO goes near-black and the picture is
// written to EMISSION, which lighting never touches.
//
// THE HALO IS NOT A STYLE CHOICE. WorldEnvironment glow is on in prototypes/* and
// off in levels/asteroid_level. There is no post-process to bloom this, so the
// spread has to be gathered here or the screen does not glow at all.
//
// Every uniform is a float. Integer uniforms behave differently on the GL
// Compatibility path, and nothing here needs to be one.
render_mode cull_back;

uniform sampler2D plate_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D content_tex : filter_linear, repeat_disable;

// The inner glass in plate UV: x, y, w, h. Measured off the plate by finding the
// darkest gutter -- the bevel shadow between the inner lip and the glass -- rather
// than eyeballed. See tools/measure_screen_rect.py.
uniform vec4 screen_rect = vec4(0.112797, 0.140655, 0.769129, 0.705202);
uniform float screen_aspect = 1.5929;

// The baked readout is erased by a luminance clamp rather than a flat fill: the
// baked text is bright and the baked grime is dark, so clamping every texel to
// grime_ceiling saturates the lettering to clean glass and leaves the dirt intact.
// That is what keeps this dark and grungy instead of dark and empty.
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

uniform float bezel_metallic : hint_range(0.0, 1.0) = 0.45;
uniform float bezel_roughness : hint_range(0.0, 1.0) = 0.72;
uniform vec3 bezel_tint : source_color = vec3(1.0);

uniform float power_on : hint_range(0.0, 1.0) = 1.0;
// The DENIED breath, lifted from the reference SVG: a 1.6 s cycle taking the red
// bloom from 0.18 to 0.66 opacity while its blur widens 7px -> 15px. Gentle, not
// glitchy -- which is why glitch_amount is small and the tear fires rarely.
uniform float alarm : hint_range(0.0, 1.0) = 1.0;
uniform float alarm_period = 1.6;
uniform float alarm_min : hint_range(0.0, 2.0) = 0.18;
uniform float alarm_max : hint_range(0.0, 2.0) = 0.66;
uniform float alarm_radius : hint_range(0.0, 0.12) = 0.022;
uniform float content_gamma : hint_range(0.4, 2.4) = 1.0;


float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}


vec2 to_screen(vec2 uv) {
	return (uv - screen_rect.xy) / screen_rect.zw;
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
// Twelve fetches on a prop covering a few hundred pixels is not the frame budget; a
// screen with no glow in a level with no glow is.
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
	vec4 plate = texture(plate_tex, UV);

	ALBEDO = plate.rgb * bezel_tint;
	METALLIC = bezel_metallic;
	ROUGHNESS = bezel_roughness;
	EMISSION = vec3(0.0);

	vec2 s_raw = to_screen(UV);
	float on_screen = (
		step(0.0, s_raw.x) * step(s_raw.x, 1.0) * step(0.0, s_raw.y) * step(s_raw.y, 1.0)
	);
	// A real branch, not a mix. The screen path is a dozen texture fetches and the
	// condition is coherent across enormous runs of pixels, so the divergence costs
	// nothing and the bezel pays for none of it. (Godot forbids an early return in
	// fragment(), so this is a block rather than a guard clause.)
	if (on_screen > 0.5) {
		float grime = min(luma(plate.rgb), grime_ceiling) / grime_ceiling;
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

		// One halo gather, radius eased toward alarm_radius on the breath. Only the
		// red component takes the opacity pulse, so DENIED breathes while the teal
		// body copy holds steady -- exactly what the reference SVG animates.
		float breath = 0.5 - 0.5 * cos(t * TAU / max(alarm_period, 0.001));
		float pulse = mix(alarm_min, alarm_max, breath);
		vec3 spread = halo(s, mix(halo_radius, alarm_radius, alarm * breath));
		float redness = clamp(spread.r - max(spread.g, spread.b), 0.0, 1.0);
		vec3 red_bloom = vec3(redness * 1.35 + 0.08, redness * 0.18, redness * 0.10);
		vec3 bloom = spread * halo_gain + red_bloom * alarm * pulse + lit * bloom_gain;

		vec2 v = abs(s * 2.0 - 1.0);
		float edge = 1.0 - vignette_strength * dot(v * v, vec2(0.5));
		// Whatever the curvature pushed past the rim is the bezel shadow, not the
		// tube. Without this the warp shows a stretched edge texel instead of a gap.
		float rim = step(0.0, s.x) * step(s.x, 1.0) * step(0.0, s.y) * step(s.y, 1.0);

		// A tube warms up by opening a raster from a centre line, so power_on does
		// that rather than fading brightness. Below about 0.35 there is a line only.
		float open = smoothstep(0.0, 0.7, power_on);
		float raster = smoothstep(0.0, 0.06, open - abs(s.y - 0.5) * 2.0);
		float boot = raster * smoothstep(0.02, 0.45, power_on);

		ALBEDO = mix(plate.rgb * 0.15, glass, rim);
		METALLIC = 0.0;
		ROUGHNESS = 0.35;
		SPECULAR = 0.30;
		EMISSION = (lit + bloom) * edge * rim * boot * emission_energy;
	}
}
