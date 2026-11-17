shader_type spatial;
// Columna de luz del Pilón (capa de magia HD) al pasar una marca: un haz que sube al cielo, más
// blanco en el centro y en la base, con bandas de maná que suben. Suma luz (alfa premultiplicado
// con ALPHA = 0) y respeta la profundidad: el cristal lo tapa (ver dev guidelines 5.4).
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform vec4 color_core : source_color = vec4(0.85, 0.66, 1.0, 1.0);
uniform vec4 color_edge : source_color = vec4(0.62, 0.36, 1.0, 1.0);
uniform vec4 color_top : source_color = vec4(0.5, 0.9, 1.0, 1.0);
uniform float intensity = 0.0;
// Altura del haz (m), para medir de la base a la punta.
uniform float height = 140.0;
// 0..1: lo alto que ha subido el haz (crece al encenderse).
uniform float reach = 1.0;

varying float v_h;

void vertex() {
	v_h = VERTEX.y / height + 0.5;
}

void fragment() {
	float h = clamp(v_h, 0.0, 1.0);
	// Centro brillante, bordes suaves: según lo de frente que se ve la cara del cilindro.
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float core = pow(facing, 5.0);
	float body = pow(facing, 0.8);
	float fade_top = pow(1.0 - h, 1.3) * (1.0 - smoothstep(reach - 0.08, reach, h));
	float bands = 0.75 + 0.25 * step(0.5, fract(h * 14.0 - TIME * 1.6));
	vec3 edge = mix(color_edge.rgb, color_top.rgb, smoothstep(0.1, 0.8, h));
	vec3 c = mix(edge * body * 0.7, color_core.rgb, core);
	float base = 1.0 + 0.8 * (1.0 - smoothstep(0.0, 0.05, h));
	ALBEDO = c * fade_top * bands * base * intensity;
	ALPHA = 0.0;
}
