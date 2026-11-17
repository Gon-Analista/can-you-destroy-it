shader_type spatial;
// Estallido de impacto en píxeles sólidos: un núcleo caliente que se hincha y se apaga, y un
// anillo de lenguas de fuego (o de magia) que se abre y se rompe. 8 fotogramas escalonados,
// como una animación dibujada a mano; colores de la rampa del hechizo; fundido tramado.
// Se dibuja sin prueba de profundidad para no quedar medio enterrado en la faceta.
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled, shadows_disabled;

uniform sampler2D ramp : source_color, filter_nearest, repeat_disable;
// 0..1 a lo largo de la animación.
uniform float progress = 0.0;
uniform float seed = 0.0;

void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
}

float bayer4(vec2 frag) {
	ivec2 p = ivec2(mod(frag, 4.0));
	int i = p.x + p.y * 4;
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i]) + 0.5) / 16.0;
}

void fragment() {
	float k = floor(progress * 8.0) / 8.0;
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float tongues = 0.09 * sin(a * 7.0 + seed * 6.0) + 0.06 * sin(a * 13.0 - seed * 3.0);
	// Núcleo: se hincha deprisa y se encoge.
	float core_r = mix(0.3, 0.55, smoothstep(0.0, 0.25, k)) * (1.0 - smoothstep(0.3, 0.75, k));
	// Anillo: se abre hacia fuera, cada vez más fino y más frío.
	float ring_r = mix(0.28, 0.95, sqrt(k));
	float ring_w = mix(0.24, 0.05, k);
	float d_ring = abs(r - ring_r - tongues * (0.4 + k));
	// Rayos cortos al principio: el golpe "salta".
	float rays = step(0.92, abs(sin(a * 4.0 + seed * 2.0))) * step(r, mix(0.75, 1.0, k)) * step(k, 0.25);
	float v = -1.0;
	if (r < core_r + tongues * 0.4) {
		v = r / max(core_r, 0.01) * 0.3 + k * 0.45;
	} else if (d_ring < ring_w) {
		v = 0.3 + d_ring / ring_w * 0.25 + k * 0.45;
	} else if (rays > 0.5) {
		v = 0.1 + r * 0.3;
	}
	if (v < 0.0) {
		discard;
	}
	vec4 c = texture(ramp, vec2(clamp(v, 0.0, 1.0), 0.5));
	float alpha = c.a * (1.0 - smoothstep(0.55, 1.0, k));
	if (alpha < 0.98) {
		alpha = step(bayer4(FRAGCOORD.xy), alpha);
	}
	if (alpha < 0.5) {
		discard;
	}
	ALBEDO = c.rgb;
	ALPHA = 1.0;
}
