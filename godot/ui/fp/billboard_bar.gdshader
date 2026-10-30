shader_type spatial;
render_mode unshaded, fog_disabled, depth_draw_never, depth_test_disabled, cull_disabled;
// The health bar variant of billboard.gdshader: the same billboard, but never fogged and drawn over
// everything (depth test off), as Python blits the bar to the screen after the sprites, so a tall Act
// whose bar would sit above the ceiling line still shows it.
uniform sampler2D sprite_tex : filter_nearest, repeat_disable;

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
	ALBEDO = OUTPUT_IS_SRGB ? c.rgb : srgb_to_linear(c.rgb);
}
