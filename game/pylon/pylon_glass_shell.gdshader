shader_type spatial;
// Vidrio del Pilón: transparente (no entra en el prepaso de profundidad, así el contorno de
// post-proceso no lo convierte en una reja), más opaco en los bordes y con un reflejo vertical.
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 c_glass : source_color = vec4(0.79, 0.96, 1.0, 1.0);

void fragment() {
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	// Bandas duras en vez de un degradado suave.
	float a = rim > 0.75 ? 0.55 : (rim > 0.45 ? 0.22 : 0.08);
	vec3 col = c_glass.rgb;
	float streak = step(0.5, NORMAL.x) * step(NORMAL.x, 0.68);
	if (streak > 0.5) {
		col = vec3(1.3);
		a = 0.6;
	}
	ALBEDO = col;
	ALPHA = a;
}
