shader_type spatial;
// Núcleo de un hechizo: espiral de brazos en bandas de color (rampa con interpolación constante),
// destello en cruz en el centro y halo exterior tramado. Billboard de píxeles sólidos: nada de
// mezcla aditiva, que sobre fondos claros (el cristal, el cielo) lo lava todo a blanco.
// Sólo el centro es HDR (> 1) para que el glow del entorno lo haga brillar.
// La animación va a `anim_fps` fotogramas por segundo, escalonada como pixel art.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform sampler2D ramp : source_color, filter_nearest, repeat_disable;
uniform float arms = 3.0;
uniform float twist = 7.0;
uniform float spin = 0.35;
uniform float swirl = 0.12;
uniform float flare_length = 0.5;
uniform vec4 flare_color = vec4(1.8, 1.8, 2.0, 1.0);
uniform float anim_fps = 12.0;
uniform float seed = 0.0;
// 0..1: carga del hechizo (gira más rápido y el centro arde más).
uniform float charge = 1.0;
uniform float spin_boost = 2.2;
// 0..1: estallido al soltar (el centro se expande y se apaga).
uniform float burst = 0.0;

void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
}

// Matriz de Bayer 4x4: tramado ordenado para el halo (el GDD lo permite en brillos).
float bayer4(vec2 frag) {
	ivec2 p = ivec2(mod(frag, 4.0));
	int i = p.x + p.y * 4;
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i]) + 0.5) / 16.0;
}

void fragment() {
	float t = floor(TIME * anim_fps) / anim_fps + seed;
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float speed = spin * mix(1.0, spin_boost, charge) * TAU;
	// Brazos en espiral: deforman el radio con el que se lee la rampa.
	float arm = sin(arms * a + twist * r - t * speed);
	float v = r + arm * swirl * smoothstep(0.08, 0.45, r);
	// Latido suave del centro (escalonado como el resto).
	v *= 1.0 + 0.06 * sin(t * 9.0);
	v = mix(v, v * 0.55, burst);
	vec4 c = texture(ramp, vec2(clamp(v, 0.0, 1.0), 0.5));
	float alpha = c.a;
	// Bandas semitransparentes: tramado en vez de mezcla suave.
	if (alpha < 0.98) {
		alpha = step(bayer4(FRAGCOORD.xy), alpha);
	}
	vec3 col = c.rgb;
	// Destello en cruz: rayos de 1 píxel de ancho que se acortan hacia la punta.
	float flick = 0.85 + 0.15 * sin(t * 23.0 + seed * 7.0);
	float len = flare_length * flick * (0.7 + 0.3 * charge) * (1.0 + burst * 0.8);
	float px = fwidth(p.x) * 1.0;
	float ray_h = step(abs(p.y), px) * step(abs(p.x), len);
	float ray_v = step(abs(p.x), px) * step(abs(p.y), len);
	float rays = max(ray_h, ray_v);
	col = max(col, flare_color.rgb * rays);
	alpha = max(alpha, rays);
	// El estallido se apaga tramando, no con transparencia suave.
	float fade = 1.0 - burst * burst;
	alpha *= step(bayer4(FRAGCOORD.xy + 2.0), fade);
	if (alpha < 0.5) {
		discard;
	}
	ALBEDO = col;
	ALPHA = 1.0;
}
