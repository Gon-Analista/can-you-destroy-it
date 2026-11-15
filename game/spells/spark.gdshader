shader_type spatial;
// Chispa: rombo brillante con rayos en cruz y halo. Billboard aditivo, parpadeo nervioso.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform vec4 color_core : source_color = vec4(1.0, 0.96, 0.76, 1.0);
uniform vec4 color_glow : source_color = vec4(1.0, 0.65, 0.23, 1.0);
uniform float intensity = 1.0;
uniform float flicker_seed = 0.0;

void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float flick = 0.8 + 0.2 * sin(TIME * 47.0 + flicker_seed * 13.0) * sin(TIME * 31.0 + flicker_seed);
	float diamond = step(abs(p.x) + abs(p.y), 0.32 * flick);
	float rays = (step(abs(p.x), 0.07) + step(abs(p.y), 0.07)) * step(length(p), 0.95 * flick);
	float halo = step(length(p), 0.55 * flick);
	vec3 c = color_glow.rgb * (rays * 0.9 + halo * 0.35) + color_core.rgb * diamond;
	ALBEDO = c * intensity;
	ALPHA = clamp(max(diamond, max(rays * 0.9, halo * 0.4)), 0.0, 1.0);
}
