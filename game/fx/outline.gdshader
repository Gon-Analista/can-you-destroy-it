shader_type spatial;
// Post-proceso a pantalla completa: contorno oscuro donde salta la profundidad y luz suave
// en aristas convexas (normales). Técnica estándar de "3D pixel art" (profundidad + normales).
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest;
uniform vec4 outline_color : source_color = vec4(0.078, 0.094, 0.227, 1.0);
uniform float outline_strength = 0.75;
uniform float depth_threshold = 0.06;
uniform float normal_threshold = 0.55;
uniform float highlight_strength = 0.16;
uniform float max_distance = 140.0;

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);
}

float linear_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec4 view = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return -view.z / view.w;
}

vec3 view_normal(vec2 uv) {
	return normalize(texture(normal_tex, uv).xyz * 2.0 - 1.0);
}

void fragment() {
	vec2 px = 1.0 / VIEWPORT_SIZE;
	vec2 uv = SCREEN_UV;
	vec3 base = texture(screen_tex, uv).rgb;
	float d0 = linear_depth(uv, INV_PROJECTION_MATRIX);
	if (d0 > max_distance) {
		ALBEDO = base;
	} else {
		vec2 offs[4] = vec2[](vec2(px.x, 0.0), vec2(-px.x, 0.0), vec2(0.0, px.y), vec2(0.0, -px.y));
		float depth_edge = 0.0;
		float normal_edge = 0.0;
		vec3 n0 = view_normal(uv);
		for (int i = 0; i < 4; i++) {
			float di = linear_depth(uv + offs[i], INV_PROJECTION_MATRIX);
			// Sólo el lado cercano dibuja el contorno: líneas de 1 píxel.
			depth_edge = max(depth_edge, step(depth_threshold * d0, di - d0));
			vec3 ni = view_normal(uv + offs[i]);
			normal_edge = max(normal_edge, step(normal_threshold, 1.0 - dot(n0, ni)) * step(abs(di - d0), 0.02 * d0 + 0.05));
		}
		float fade = 1.0 - smoothstep(max_distance * 0.6, max_distance, d0);
		vec3 c = mix(base, outline_color.rgb, depth_edge * outline_strength * fade);
		c = mix(c, c + vec3(highlight_strength), normal_edge * (1.0 - depth_edge) * fade);
		ALBEDO = c;
	}
}
