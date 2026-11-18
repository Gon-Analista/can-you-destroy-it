shader_type spatial;
// Bola de Fuego en vuelo (capa de magia HD, ver FireballFlight). Una esfera que hierve, no un
// recorte plano: la superficie es una esfera falsa (normal sacada del quad) con ruido 3D que
// rueda hacia atrás, así las celdas de fuego se curvan con el volumen y se apiñan en el limbo.
// Calor en bandas nítidas y saturadas: borde rojo oscuro (recorta contra el cielo y el cristal
// claros), rojo, naranja, amarillo y un núcleo blanco pequeño, el único que florece. Alrededor,
// una corona de lametones y lenguas que se escapan hacia `flow` (hacia atrás de la trayectoria en
// pantalla). `layer` 0 es la corona de detrás (más grande, más lenta y más roja: da
// profundidad); 1 es la bola con sus lenguas. Todo se apaga antes del borde del quad.
// Alfa premultiplicado: el fuego tapa con su color y el núcleo además suma luz.
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

#include "res://fx/hd/hd_noise.gdshaderinc"

uniform sampler2D ramp : source_color, filter_linear, repeat_disable;
uniform int layer = 1;
// Radio de la bola en unidades del quad (1 = medio quad).
uniform float radius = 0.34;
uniform float intensity = 1.0;
uniform float seed = 0.0;
// Hacia dónde se escapan las lenguas en pantalla (UV: y crece hacia abajo).
uniform vec2 flow = vec2(0.0, 1.0);
// 0..3: lenguas más largas cuanto más deprisa cruza la pantalla.
uniform float flow_strength = 1.0;
// 0..1: nivel del hechizo (más caliente, más amarillo, núcleo más vivo, lenguas más rabiosas).
uniform float heat = 0.0;
// Velocidad a la que hierve y rueda la superficie.
uniform float speed = 1.0;
// 0..1: llegada (se hincha, se enfría y se deshace).
uniform float burst = 0.0;
uniform float fade = 1.0;

varying float hd_near;

void vertex() {
	HD_BILLBOARD
	HD_NEAR_FADE(0.45, 1.0)
}

float border_mask(vec2 p) {
	vec2 a = abs(p);
	return (1.0 - smoothstep(0.8, 0.97, a.x)) * (1.0 - smoothstep(0.8, 0.97, a.y));
}

// Banda nítida con antialias.
float band(float v, float th) {
	float w = max(fwidth(v), 0.002) * 0.9;
	return smoothstep(th - w, th + w, v);
}

// Tono de la rampa con la energía limitada a 1 (sólo el núcleo florece); `sat` lo aviva.
vec3 ramp_hue(float x, float sat) {
	vec3 c = texture(ramp, vec2(x, 0.5)).rgb;
	c /= max(1.0, max(c.r, max(c.g, c.b)));
	return pow(c, vec3(sat));
}

// Gira `v` un ángulo `a` alrededor del eje unitario `k` (Rodrigues).
vec3 rotate_axis(vec3 v, vec3 k, float a) {
	float c = cos(a);
	float s = sin(a);
	return v * c + cross(k, v) * s + k * dot(k, v) * (1.0 - c);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	bool back = layer == 0;
	float t = TIME * speed * (back ? 0.75 : 1.0) + seed * 7.0;
	vec2 fd = normalize(flow + vec2(0.0001));
	vec2 sd = vec2(-fd.y, fd.x);
	float fs = clamp(flow_strength, 0.0, 3.0);
	float R = radius * (1.0 + burst * 0.55);
	// La bola va aguas arriba para que quepan sus lenguas.
	float shift = (back ? 0.55 : 0.4) * R * (0.4 + 0.3 * fs) * (1.0 - burst);
	vec2 c = p + fd * shift;
	float u = dot(c, sd) / R;
	float v = dot(c, fd) / R;
	float r = length(c) / R;

	// --- Campo de calor: 1 en el centro, 0 en el contorno. Gota estirada hacia `flow`.
	float alp = max(v, 0.0);
	float len = (1.0 + 0.8 * fs) * (back ? 1.4 : 1.0) * (1.0 + heat * 0.35) * (1.0 - burst * 0.5);
	vec2 dd = vec2(u * (1.0 + alp * 0.2), v < 0.0 ? v * 1.08 : v / len);
	float H = 1.0 - length(dd);
	// Lenguas: ruido que corre con el flujo y muerde cada vez más hacia la punta.
	float n1 = hd_fbm(vec3(u * 1.5 + seed, v * 0.65 - t * 2.3, t * 0.35));
	float n2 = hd_fbm(vec3(u * 3.4 + 4.0, v * 1.4 - t * 3.8, t * 0.6 + seed));
	float tip = smoothstep(0.0, 2.2, v);
	H += (n1 - 0.5) * (0.4 + 2.2 * tip) + (n2 - 0.5) * (0.22 + 0.85 * tip);
	// Lametones alrededor de todo el contorno (más hacia atrás: el frente empuja el aire y va
	// más liso). Rompen el círculo: ninguna silueta de moneda.
	vec2 ring = c / max(length(c), 0.0001);
	float lick = hd_fbm(vec3(ring * (back ? 1.7 : 2.6) + seed * 1.3, r * 1.6 - t * 2.8));
	float rear = smoothstep(-1.0, 0.7, v);
	float rim = smoothstep(0.35, 1.0, r);
	H += (lick - 0.5) * (back ? 1.5 : 1.2) * rim * (0.15 + 0.85 * rear);
	// Cerca del borde del quad todo se afina hasta desaparecer.
	H -= (1.0 - border_mask(p * 1.04)) * 0.9;
	// Al llegar: se hincha en cúmulos y se rompe en jirones; al apagarse, se deshace.
	H -= burst * (0.2 + 0.7 * (1.0 - n1)) * smoothstep(0.2, 0.9, burst);
	H -= (1.0 - fade * hd_near) * (0.45 + 0.4 * (1.0 - n2));
	float m = H;
	// Las puntas se enfrían antes que la raíz.
	float h = H - tip * 0.12;
	float sphere = 0.0;
	if (!back) {
		// --- Volumen: esfera falsa con ruido 3D que rueda hacia atrás (del frente a las lenguas).
		// Sólo mueve las bandas de dentro: celdas que hierven y se apiñan en el limbo.
		float rr = min(r, 1.0);
		vec3 n = vec3(u, -v, sqrt(max(1.0 - rr * rr, 0.0)));
		vec3 q = rotate_axis(n, vec3(1.0, 0.0, 0.0), t * 0.9) * 1.8 + vec3(seed * 2.0, 0.0, 0.0);
		float w = hd_fbm(q + vec3(0.0, 0.0, t * 0.25));
		float cells = hd_fbm(q * 2.2 + vec3(w * 1.8, w * 1.2, t * 0.35));
		sphere = 1.0 - smoothstep(0.75, 1.05, r);
		// Luz de arriba a la izquierda, como el resto del juego: le da cuerpo.
		vec3 nl = vec3(c / R, n.z);
		float lit = dot(nl, normalize(vec3(-0.45, -0.6, 0.65))) * 0.08;
		h += ((cells - 0.5) * 0.95 + lit) * sphere;
	}
	h += heat * 0.1 - burst * 0.35;
	if (back) {
		// La corona de detrás, más roja: hace de fondo y sombra de la bola.
		h = h * 0.8 - 0.03;
	}

	// --- Capas de color nítidas: contorno rojo oscuro, rojo, naranja, amarillo anaranjado,
	// amarillo y, en el centro, el núcleo blanco pequeño (el único que florece).
	float a0 = band(m, 0.0);
	// Los tonos se avivan en lineal (a la pantalla llegan en sRGB, mucho más claros): sin esto el
	// rojo salía naranja, el naranja ámbar y el amarillo crema, y la bola parecía de melocotón.
	vec3 c0 = pow(texture(ramp, vec2(1.0, 0.5)).rgb, vec3(1.6)) * 0.95;
	// Rojo, naranja, ámbar y amarillo de verdad (sin el amarillo, todo era una mancha naranja).
	vec3 c1 = ramp_hue(0.6, 2.0);
	vec3 c2 = ramp_hue(0.3, 2.2);
	vec3 c3 = ramp_hue(0.12, 2.6);
	vec3 c4 = ramp_hue(0.0, 3.5);
	vec3 col = mix(c0, c1, band(h, 0.06));
	col = mix(col, c2, band(h, 0.18));
	col = mix(col, c3, band(h, 0.33));
	col = mix(col, c4, band(h, 0.5));
	col *= intensity;
	float core = 0.0;
	if (!back) {
		// Núcleo blanco pequeño, algo adelantado (el frente es lo más caliente), que tiembla.
		vec2 cc = c / R + fd * 0.12;
		float rc = 0.2 + heat * 0.07 + (hd_fbm(vec3(ring * 2.0, t * 1.7)) - 0.5) * 0.12;
		core = band(1.0 - length(cc) / rc, 0.0) * band(h, 0.55) * sphere;
		core *= 1.0 - smoothstep(0.0, 0.4, burst);
		vec3 hot = texture(ramp, vec2(0.0, 0.5)).rgb;
		col = mix(col, hot * (0.6 + heat * 0.4), core);
	}
	col *= 0.95 + 0.05 * sin(t * 13.0) * sin(t * 7.3);
	float a = clamp(a0 * smoothstep(0.0, 0.3, fade * hd_near) * border_mask(p), 0.0, 1.0);
	ALBEDO = col * a;
	ALPHA = a * (1.0 - core * 0.5);
}
