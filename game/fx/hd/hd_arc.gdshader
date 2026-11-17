shader_type spatial;
// Rayo de energía HD (la malla la hace CrystalArcs: cinta de cara a la cámara por segmentos).
// Núcleo blanco ardiente y borde del color del rayo, sumando luz (alfa premultiplicado con
// algo de cuerpo opaco para que se lea sobre el cielo claro). El alfa del color de vértice es
// la vida que le queda (se apaga parpadeando).
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform float intensity = 2.4;

void fragment() {
	float across = abs(UV.y * 2.0 - 1.0);
	float core = 1.0 - across;
	float life = COLOR.a;
	float flick = 0.75 + 0.25 * sin(TIME * 90.0 + UV.x * 37.0);
	vec3 col = mix(COLOR.rgb, vec3(1.6, 1.7, 1.9), pow(core, 10.0));
	float body = pow(core, 1.3) * life * flick;
	// Premultiplicado: el borde de color tapa un poco el fondo y el núcleo suma luz.
	float a = clamp(body * 0.55, 0.0, 1.0);
	ALBEDO = col * intensity * body;
	ALPHA = a * (1.0 - pow(core, 6.0));
}
