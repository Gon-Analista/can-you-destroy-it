shader_type spatial;
// Bola de energía HD. `style` 0 = fuego, 1 = arcano (remolino en espiral).
// Fuego estilizado por capas: una bola que gira con lenguas de fuego que se escapan hacia
// `flow` (arriba cuando está quieta; hacia atrás en vuelo). El calor se lee en bandas suaves:
// borde rojo oscuro (recorta contra el cielo y el cristal), naranja, amarillo y un núcleo
// blanco pequeño, el único que pasa del umbral del resplandor. La bola se coloca aguas arriba
// del quad para que las lenguas quepan, y todo se funde a cero antes del borde del quad: nunca
// queda un corte recto.
// Alfa premultiplicado: el cuerpo tapa con su color y el núcleo además suma luz.
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

#include "res://fx/hd/hd_noise.gdshaderinc"

uniform sampler2D ramp : source_color, filter_linear, repeat_disable;
uniform float intensity = 1.0;
uniform float core_boost = 1.0;
uniform float turbulence = 0.35;
uniform float speed = 1.6;
uniform float seed = 0.0;
uniform int style = 0;
// 0..1: carga (más grande, más rápido, más brillante).
uniform float charge = 1.0;
// 0..1: estallido (se hincha y se deshace en llamas).
uniform float burst = 0.0;
// 0..1 de opacidad global.
uniform float fade = 1.0;
// Hacia dónde se arrastran las llamas en pantalla (UV: y crece hacia abajo). Quieto: hacia
// arriba; en vuelo, hacia atrás de la trayectoria. `flow_strength` alarga las lenguas.
uniform vec2 flow = vec2(0.0, -1.0);
uniform float flow_strength = 1.0;
// 1: la bola se aparta aguas arriba para que quepan las lenguas; 0: centrada en el quad.
uniform float center_shift = 1.0;
// 1: bola de fuego que gira (hechizos); 0: llamas que salen de una superficie (base ancha y
// plana, sin remolino), como el fuego que queda ardiendo en el cristal.
uniform float ball = 1.0;

varying float hd_near;

void vertex() {
	HD_BILLBOARD
	HD_NEAR_FADE(0.55, 1.1)
}

// Máscara que llega a 0 antes del borde del quad (cuadrada, para aprovechar las esquinas).
float border_mask(vec2 p) {
	vec2 a = abs(p);
	return (1.0 - smoothstep(0.78, 0.96, a.x)) * (1.0 - smoothstep(0.78, 0.96, a.y));
}

// Arcano: remolino turbulento (el aspecto de siempre, ahora sin cortes en el borde).
void arcane(vec2 p, float t, out vec3 col, out float a, out float alpha_mul) {
	float r0 = length(p);
	float ang = atan(p.y, p.x) + (1.0 - r0) * 3.5 + t * 0.8;
	vec2 q = vec2(cos(ang), sin(ang)) * r0;
	float n = hd_fbm(vec3(q * 2.6, t * 0.45));
	float n2 = hd_fbm(vec3(q * 5.1 + vec2(3.0, 0.0), t * 0.8 + 4.0));
	float radius = mix(0.46, 0.56, charge) * (1.0 + burst * 0.45);
	float edge = radius + (n - 0.5) * min(turbulence, 0.4);
	float body = smoothstep(edge, edge - 0.12, r0);
	float heat = clamp(1.0 - r0 / max(edge, 0.01) + (n2 - 0.5) * 0.35, 0.0, 1.0);
	heat *= 1.0 - burst * 0.6;
	col = texture(ramp, vec2(1.0 - heat, 0.5)).rgb;
	float core = pow(heat, 4.0);
	col *= intensity * (1.0 + core * core_boost * mix(0.6, 1.0, charge));
	float holes = smoothstep(burst * 0.9, burst * 0.9 + 0.15, n2 + 0.2);
	a = body * holes;
	alpha_mul = smoothstep(0.05, 0.5, heat) * (1.0 - core * 0.7);
}

// Tono de la rampa en `x` con la energía limitada a 1 (no florece).
// `sat` > 1 aviva el color sin pasar de 1 (las rampas HDR, al limitarlas, quedaban color crema:
// el interior del fuego se veía pastel en vez de amarillo anaranjado).
vec3 ramp_hue(float x, float sat) {
	vec3 c = texture(ramp, vec2(x, 0.5)).rgb;
	c /= max(1.0, max(c.r, max(c.g, c.b)));
	return pow(c, vec3(sat));
}

// Banda nítida con antialias (estilizado: capas de color limpias, sin degradados borrosos).
float band(float v, float th) {
	float w = max(fwidth(v), 0.002) * 0.9;
	return smoothstep(th - w, th + w, v);
}

// Fuego estilizado por capas. Campo de calor = gota (bola aguas arriba, llama estirada hacia
// `flow`) erosionada por ruido que corre con el flujo: las puntas se rompen en lenguas y
// jirones sueltos. Dentro de la bola el ruido gira (remolino). Cuatro capas de color con
// bordes nítidos (rojo oscuro, rojo anaranjado, naranja, amarillo) y un núcleo blanco pequeño;
// cada capa tiene sus propias lenguas, así se leen llamas dentro de llamas.
void fire(vec2 p, float t, float gone, out vec3 col, out float a, out float alpha_mul) {
	vec2 fd = normalize(flow + vec2(0.0001));
	vec2 side = vec2(-fd.y, fd.x);
	float fs = clamp(flow_strength, 0.0, 3.0);
	// Bola: radio con la carga; al estallar se hincha.
	float R = mix(0.25, 0.31, charge) * (1.0 + burst * 1.1);
	// Aguas arriba del centro del quad: las lenguas tienen sitio hacia `flow`.
	float shift = (0.18 + 0.07 * fs) * (1.0 - burst) * center_shift;
	vec2 c = p + fd * shift;
	float al = dot(c, fd);
	float ac = dot(c, side);
	float alp = max(al, 0.0);
	// Gota: hacia el flujo se estrecha y se alarga (más con `flow_strength`).
	float len = (1.0 + 1.1 * fs) * (1.0 - burst * 0.6);
	float flat_base = mix(1.9, 1.0, ball);
	vec2 d = vec2(ac * (1.0 + alp / R * 0.3) * mix(0.8, 1.0, ball), al < 0.0 ? al * flat_base : al / len);
	float base = 1.0 - length(d) / R;
	// Ruido que sube con las llamas (en unidades de la bola: 3-4 lenguas a lo ancho).
	float u = ac / R;
	float v = al / R;
	float n1 = hd_fbm(vec3(u * 1.5, v * 0.75 - t * 1.9, t * 0.3 + seed));
	float n2 = hd_fbm(vec3(u * 3.4 + 4.0, v * 1.6 - t * 3.3, t * 0.55 + seed));
	float r0 = length(c);
	float ang = t * 1.2 + (R - r0) / R * 3.0;
	mat2 rot = mat2(vec2(cos(ang), sin(ang)), vec2(-sin(ang), cos(ang)));
	float sw = hd_fbm(vec3(rot * c / max(R, 0.05) * 2.0, t * 0.35 + seed * 3.0));
	float in_ball = (1.0 - smoothstep(0.35 * R, 1.05 * R, r0)) * mix(0.45, 1.0, ball);
	// Las puntas se erosionan mucho más que la bola: lenguas separadas y jirones sueltos.
	float tip = smoothstep(-0.3, 1.6, v);
	float erode = (n1 - 0.5) * (0.45 + 2.6 * tip) * (0.6 + turbulence)
		+ (n2 - 0.5) * (0.2 + 0.9 * tip);
	float h = base + erode;
	// Cerca del borde del quad las lenguas se afinan hasta desaparecer (nunca un corte recto).
	h -= (1.0 - border_mask(p * 1.06)) * 0.9;
	// Al estallar: primero una bola que se hincha en cúmulos (coliflor) y luego se rompe en
	// jirones que se enfrían. Al apagarse (`gone`: fundido o pegado a la cámara) el fuego se
	// deshace en lenguas en vez de volverse translúcido (a medio fundir, el rojo sobre el
	// cristal claro se veía marrón).
	// (Rama por uniforme: sin estallido no se paga el ruido de los cúmulos.)
	if (burst > 0.0) {
		float lump = hd_fbm(vec3(u * 1.2 + seed, v * 1.2 + t * 0.4, t * 0.2));
		h += (lump - 0.5) * 0.7 * burst;
		h -= burst * (0.15 + 0.6 * (1.0 - n1)) * smoothstep(0.25, 0.9, burst);
	}
	h -= gone * (0.45 + 0.4 * (1.0 - n2));
	// Calor dentro: el remolino dibuja vetas en espiral (sin agujerear el centro, que siempre
	// es lo más caliente); cada capa tiene lenguas propias.
	float hv = h + (sw - 0.5) * 0.3 * in_ball + in_ball * 0.12 - tip * 0.08;
	float lag = (n2 - 0.5) * 0.24;
	float b0 = band(h, 0.0);
	float b1 = band(hv, 0.1);
	float b2 = band(hv + lag, 0.26);
	float b3 = band(hv - lag, 0.48);
	float b4 = band(hv + lag * 0.5, 0.72);
	// Se enfría a rojo (sin empezar en blanco: sobre el cristal claro, un estallido blanco y
	// grande florecía hasta tapar el golpe).
	float cold = smoothstep(0.35, 1.0, burst) * 0.5;
	// Capas con el tono de la rampa pero sin pasar de 1 (sólo el núcleo florece): borde rojo
	// oscuro, rojo anaranjado, naranja, amarillo anaranjado y amarillo pálido alrededor del núcleo.
	vec3 c0 = texture(ramp, vec2(1.0, 0.5)).rgb * 0.85;
	vec3 c1 = ramp_hue(clamp(0.66 + cold * 0.25, 0.0, 1.0), 1.0);
	vec3 c2 = ramp_hue(clamp(0.36 + cold * 0.4, 0.0, 1.0), 1.15);
	vec3 c3 = ramp_hue(clamp(0.15 + cold * 0.5, 0.0, 1.0), 2.0);
	vec3 c4 = ramp_hue(clamp(0.04 + cold * 0.5, 0.0, 1.0), 1.4);
	col = mix(mix(mix(mix(c0, c1, b1), c2, b2), c3, b3), c4, b4) * intensity;
	// Núcleo pequeño y blanco (HDR), sólo en la bola; la carga lo aviva.
	float core = band(hv, 0.95 + burst * 0.5) * in_ball * (1.0 - smoothstep(0.05, 0.3, burst));
	vec3 hot = texture(ramp, vec2(0.0, 0.5)).rgb;
	col = mix(col, hot * core_boost * mix(0.6, 0.9, charge), core);
	// Parpadeo del calor.
	col *= 0.94 + 0.06 * sin(t * 13.0 + seed * 5.0) * sin(t * 7.3);
	a = b0;
	// Borde opaco (recorta contra el cielo y el cristal); el núcleo además suma luz.
	alpha_mul = 1.0 - core * 0.5;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float t = TIME * speed * mix(0.75, 1.3, charge) + seed * 11.0;
	vec3 col;
	float a;
	float alpha_mul;
	if (style == 1) {
		arcane(p, t, col, a, alpha_mul);
	} else {
		fire(p, t, 1.0 - fade * hd_near, col, a, alpha_mul);
	}
	// El fuego se apaga deshaciéndose (ver `fire`); el arcano, fundiéndose.
	float f = style == 1 ? fade * hd_near : smoothstep(0.0, 0.3, fade * hd_near);
	a = clamp(a * f * border_mask(p), 0.0, 1.0);
	ALBEDO = col * a;
	ALPHA = a * alpha_mul;
}
