shader_type spatial;
// Círculo mágico de la capa de magia HD (niveles 6 a 10 de los hechizos): anillos, una banda de runas
// inventadas (trazos sobre una rejilla de 3x3 elegidos por hash), un hexagrama, marcas y un sello central.
// Todo procedural sobre un quad. Luz pura (alfa 0 premultiplicado): florece con el glow.
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.6, 0.2, 1.0);
uniform vec4 color_hot : source_color = vec4(1.0, 0.95, 0.75, 1.0);
uniform float intensity = 1.0;
// Giro de los anillos exteriores (rad); los interiores giran al revés.
uniform float spin = 0.0;
// 0..1: el círculo se dibuja barriendo el ángulo al aparecer.
uniform float appear = 1.0;
// 0..1: destello al lanzar (todo más brillante y grueso).
uniform float flash = 0.0;
uniform float fade = 1.0;
uniform float rune_seed = 1.0;
// Runas en la banda (y la mitad en el anillo interior).
uniform float rune_count = 18.0;

float hash11(float n) {
	return fract(sin(n * 127.1 + rune_seed * 31.7) * 43758.5453);
}

float band(float r, float a, float b, float soft) {
	return smoothstep(a - soft, a, r) * (1.0 - smoothstep(b, b + soft, r));
}

float seg(vec2 p, vec2 a, vec2 b, float w) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return 1.0 - smoothstep(w * 0.6, w, length(pa - ba * h));
}

// Una runa: hasta 6 trazos entre puntos de una rejilla 3x3, según el hash de su índice.
float rune(vec2 q, float id, float w) {
	float m = 0.0;
	for (int k = 0; k < 6; k++) {
		float h = hash11(id * 7.0 + float(k) * 1.37);
		if (h < 0.42) {
			continue;
		}
		float h2 = hash11(id * 13.0 + float(k) * 2.11);
		float h3 = hash11(id * 3.0 + float(k) * 5.3);
		vec2 a = vec2(floor(h2 * 3.0), floor(fract(h2 * 7.0) * 3.0)) * 0.5;
		vec2 b = vec2(floor(h3 * 3.0), floor(fract(h3 * 5.0) * 3.0)) * 0.5;
		if (distance(a, b) < 0.1) {
			b = vec2(1.0) - a;
		}
		m = max(m, seg(q, a, b, w));
	}
	return m;
}

vec2 rot(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Todas las líneas del círculo con grosor `w` (se llama dos veces: trazo y contorno oscuro).
float circle_lines(vec2 p, float r, float w) {
	vec2 po = rot(p, spin);
	float ao = atan(po.y, po.x);
	float ang01 = fract(ao / TAU + 0.5);
	float m = 0.0;
	m = max(m, band(r, 0.95, 0.975, w));
	m = max(m, band(r, 0.855, 0.872, w) * 0.95);
	float tick = step(fract(ang01 * 72.0), 0.2) * band(r, 0.982, 1.0, w * 0.5);
	m = max(m, tick * 0.85);
	float cell = ang01 * rune_count;
	vec2 q = vec2(fract(cell), (r - 0.882) / 0.064);
	q = (q - 0.5) * vec2(1.35, 1.15) + 0.5;
	if (q.x > 0.0 && q.x < 1.0 && q.y > 0.0 && q.y < 1.0) {
		m = max(m, rune(q, floor(cell), w * 9.0));
	}
	vec2 pi = rot(p, -spin * 1.6);
	float ai = atan(pi.y, pi.x);
	float hexa = 0.0;
	for (int k = 0; k < 6; k++) {
		float th = float(k / 2) * TAU / 3.0 + (k % 2 == 0 ? 0.0 : PI);
		vec2 n = vec2(cos(th), sin(th));
		hexa = max(hexa, 1.0 - smoothstep(w * 0.5, w * 1.1, abs(dot(pi, n) - 0.42)));
	}
	m = max(m, hexa * step(r, 0.845) * 0.9);
	m = max(m, band(r, 0.4, 0.415, w) * 0.95);
	m = max(m, band(r, 0.29, 0.3, w) * 0.7);
	float ai01 = fract(ai / TAU + 0.5);
	float cell2 = ai01 * rune_count * 0.5;
	vec2 q2 = vec2(fract(cell2), (r - 0.305) / 0.09);
	if (q2.y > 0.0 && q2.y < 1.0) {
		m = max(m, rune(q2, floor(cell2) + 50.0, w * 11.0) * 0.85);
	}
	m = max(m, 1.0 - smoothstep(0.0, w * 1.2, abs(abs(pi.x) + abs(pi.y) - 0.16)));
	m = max(m, 1.0 - smoothstep(0.035, 0.035 + w, r));
	return m;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	if (r > 1.04) {
		discard;
	}
	// Nunca más fino que ~1,5 píxeles en pantalla (los círculos grandes y lejanos no se pierden).
	float w = max(0.016, fwidth(r) * 1.6) * (1.0 + flash * 0.6);
	float core = circle_lines(p, r, w);
	float outline = circle_lines(p, r, w * 2.6);
	// Aparece barriendo el ángulo desde arriba.
	float a_rev = fract(atan(p.x, p.y) / TAU + 1.0);
	float shown = step(a_rev, appear * 1.001);
	core *= shown;
	outline *= shown;
	// Trazo brillante (luz) sobre un contorno oscuro y semiopaco: se lee aunque detrás haya fuego
	// o el cristal blanco.
	float halo = 0.0;
	// Colores sin HDR (el resplandor de la capa de magia los convertiría en un disco blanco); sólo
	// el centro del trazo pasa un poco de 1 para que brille.
	vec3 base = min(color.rgb, vec3(1.0));
	vec3 hot = mix(base, min(color_hot.rgb, vec3(1.0)), clamp(core * 0.35 + flash, 0.0, 1.0));
	vec3 ink = base * 0.1;
	float k = intensity * (1.0 + flash * 2.0);
	vec3 c = mix(ink * outline, hot * k * (0.75 + 0.35 * core), core);
	ALBEDO = c * fade;
	ALPHA = clamp(outline * 0.55 * (1.0 - flash), 0.0, 1.0) * fade;
}
