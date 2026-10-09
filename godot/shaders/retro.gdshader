shader_type canvas_item;
// Retro look over the 3D view (the HUD draws on top, untouched): chunky pixels, a colour
// grade, and a limited palette with ordered dithering. Every value comes from the "look"
// section of tuning.json.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float pixel_size = 1.0;     // screen pixels per game pixel (1 = full resolution)
uniform float levels = 0.0;         // colour steps per channel (0 = no palette limit)
uniform float dither = 0.0;         // 0 = hard bands, 1 = full ordered dithering
uniform float saturation = 1.0;
uniform float contrast = 1.0;
uniform float brightness = 0.0;
uniform vec3 tint = vec3(1.0);

// 4x4 Bayer threshold in [0, 1), computed instead of looked up (array indexing isn't
// reliable on every renderer).
float bayer2(vec2 a) {
	a = floor(a);
	return fract(dot(a, vec2(0.5, a.y * 0.75)));
}
float bayer4(vec2 a) {
	return bayer2(0.5 * a) * 0.25 + bayer2(a);
}

void fragment() {
	// One sample per game pixel, from its centre.
	vec2 cell = floor(FRAGCOORD.xy / pixel_size);
	vec2 uv = (cell + 0.5) * pixel_size * SCREEN_PIXEL_SIZE;
	// Always the full-detail screen: at block edges the 2x2 pixel quads see a big jump in uv
	// and would otherwise pick a lower mip (black on some renderers).
	vec3 c = textureLod(screen_tex, uv, 0.0).rgb;

	float luma = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(luma), c, saturation);
	c = (c - 0.5) * contrast + 0.5 + brightness;
	c *= tint;

	if (levels > 1.5) {
		float b = bayer4(cell) + 0.5 / 16.0 - 0.5;
		float steps = levels - 1.0;
		c = floor(c * steps + 0.5 + b * dither) / steps;
	}
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
