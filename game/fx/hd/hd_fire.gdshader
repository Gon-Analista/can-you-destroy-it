shader_type spatial;
// Bola de energía HD: cuerpo turbulento (fbm animado a 60 fps) con lenguas que suben, núcleo
// blanco ardiente (HDR, florece con el glow) y borde oscuro de color que se recorta contra el
// fondo. `style` 0 = fuego (lenguas hacia arriba), 1 = arcano (remolino en espiral).
// Alfa normal (cuerpo opaco con color) en una capa premultiplicada: no se lava sobre el cielo.
render_mode unshaded, blend_premul_alpha, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled, shadows_disabled;

#include "res://fx/hd/hd_noise.gdshaderinc"

uniform sampler2D ramp : source_color, filter_linear, repeat_disable;
uniform float intensity = 2.2;
uniform float core_boost = 1.6;
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

void vertex() {
	HD_BILLBOARD
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float t = TIME * speed * mix(0.7, 1.4, charge) + seed * 11.0;
	vec2 q = p;
	if (style == 1) {
		// Remolino: rota más cuanto más cerca del centro.
		float r0 = length(q);
		float a = atan(q.y, q.x) + (1.0 - r0) * 3.5 + t * 0.8;
		q = vec2(cos(a), sin(a)) * r0;
	}
	float n = hd_fbm(vec3(q * 2.6 + vec2(0.0, style == 0 ? -t * 0.9 : 0.0), t * 0.45));
	float n2 = hd_fbm(vec3(q * 5.1 + vec2(3.0, style == 0 ? -t * 1.7 : 0.0), t * 0.8 + 4.0));
	// Lenguas de fuego: el borde superior se estira hacia arriba.
	float lick = style == 0 ? max(0.0, p.y) * 0.55 * n2 : 0.0;
	float radius = mix(0.5, 0.62, charge) * (1.0 + burst * 0.5);
	float r = length(p - vec2(0.0, lick * 0.6));
	float edge = radius + (n - 0.5) * turbulence + lick;
	float body = smoothstep(edge, edge - 0.12, r);
	// Calor: 1 en el centro, 0 en el borde, con vetas de ruido.
	float heat = clamp(1.0 - r / max(edge, 0.01) + (n2 - 0.5) * 0.35, 0.0, 1.0);
	heat *= 1.0 - burst * 0.6;
	vec3 col = texture(ramp, vec2(1.0 - heat, 0.5)).rgb;
	float core = pow(heat, 4.0);
	col *= intensity * (1.0 + core * core_boost * mix(0.6, 1.0, charge));
	// Al estallar el cuerpo se agujerea con el ruido.
	float holes = smoothstep(burst * 0.9, burst * 0.9 + 0.15, n2 + 0.2);
	// Premultiplicado: el borde tapa con su color; el núcleo, además, suma luz (alfa < color).
	// Lo más frío del borde se vuelve luz translúcida en vez de tapar el fondo.
	float a = clamp(body * holes * fade, 0.0, 1.0);
	ALBEDO = col * a;
	ALPHA = a * smoothstep(0.05, 0.5, heat) * (1.0 - core * 0.7);
}
