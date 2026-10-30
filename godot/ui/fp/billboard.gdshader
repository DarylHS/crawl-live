shader_type spatial;
render_mode unshaded, fog_disabled, depth_draw_opaque, cull_disabled;
// A first-person sprite, shaded the way crawler/ui/firstperson.py shades them: no lighting at all,
// only fog, brightness = max(min_bright, (1 - depth / light) ^ 1.3) where depth is the distance
// straight ahead of the camera (Python's tz). Everything past the light radius stays at the 0.12
// floor, so a monster's eyes survive at the edge of sight. The scene's depth fog is switched off
// for these (fog_disabled), the maths here does it instead.
//
// The quad is a Sprite3D mesh; this shader turns it into a billboard that turns about the Y axis
// only (parallel to the screen, so every pixel of it is at the same depth, as in Python), keeping
// the node's scale. Binary alpha: a pixel is drawn whole or not at all. Colours are mixed the way
// pygame mixes them: the texture value times the brightness, in sRGB. The Compatibility renderer (measured) shows
// ALBEDO as it is (OUTPUT_IS_SRGB); Forward+ and Mobile need the value converted to linear first.

uniform sampler2D sprite_tex : filter_nearest, repeat_disable;
uniform float light = 8.5;
uniform float min_bright = 0.12;
uniform bool fogged = true;

vec3 srgb_to_linear(vec3 s) {
	return mix(pow((s + vec3(0.055)) / 1.055, vec3(2.4)), s / 12.92, lessThan(s, vec3(0.04045)));
}

void vertex() {
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 right = normalize(INV_VIEW_MATRIX[0].xyz);
	vec3 back = normalize(cross(right, up));
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), 1.0);
	mat4 m = mat4(vec4(right * scale.x, 0.0), vec4(up * scale.y, 0.0), vec4(back, 0.0), MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * m;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}


void fragment() {
	vec4 c = texture(sprite_tex, UV);
	if (c.a < 0.5) {
		discard;
	}
	float k = 1.0;
	if (fogged) {
		float depth = -VERTEX.z;
		k = max(min_bright, pow(clamp(1.0 - depth / light, 0.0, 1.0), 1.3));
	}
	vec3 s = c.rgb * k;
	ALBEDO = OUTPUT_IS_SRGB ? s : srgb_to_linear(s);
}
