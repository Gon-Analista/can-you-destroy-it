shader_type spatial;
// Chispa de golpe HD ("hit spark" de anime): estrella de puntas largas y finas con el centro al
// blanco y un contorno oscuro que la recorta sobre el cristal y el cielo claros. Nace de golpe,
// las puntas se estiran y se afilan y se apaga en ~0,25 s. La forma va por elemento
// (`ImpactStyle`): puntas (`points`), curvas en remolino (`twist`), quebradas como un rayo (`jag`)
// y lo gordas que son (`sharp`).
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

#include "res://fx/hd/hd_noise.gdshaderinc"

uniform vec4 color : source_color = vec4(1.0, 0.6, 0.25, 1.0);
uniform vec4 hot : source_color = vec4(1.0, 0.95, 0.85, 1.0);
uniform vec4 ink : source_color = vec4(0.1, 0.05, 0.15, 1.0);
uniform float intensity = 2.0;
// Opacidad total (la estrella del orbe en vuelo se enciende al alejarse de las manos).
uniform float opacity = 1.0;
uniform float points = 4.0;
uniform float sharp = 6.0;
uniform float twist = 0.0;
uniform float jag = 0.0;
uniform float outline = 0.12;
uniform float progress = 0.0;
uniform float seed = 0.0;

varying float hd_near;

float h1(float n) {
	return fract(sin(n * 127.1 + seed * 31.7) * 43758.5453);
}

void vertex() {
	HD_BILLBOARD
	HD_NEAR_FADE(0.2, 0.5)
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float k = progress;
	float grow = smoothstep(0.0, 0.18, k);
	// Las puntas se afilan y adelgazan al apagarse.
	float thin = mix(1.0, 3.5, smoothstep(0.2, 1.0, k));
	float a = atan(p.y, p.x) + seed + twist * r;
	float sector = a * points / 6.2831853;
	float idx = floor(sector + 0.5);
	// Cada punta con su largo (unas largas y otras cortas, como un dibujo a mano).
	float len = mix(0.5, 0.98, h1(mod(idx, points))) * grow * mix(1.0, 1.1, k);
	// Punta en cuña: ancha junto al centro y afilada en la punta (y más fina al apagarse).
	float perp = r * sin(abs(sector - idx) * 6.2831853 / points);
	if (jag > 0.0) {
		perp = abs(perp + (hd_noise(vec3(r * 14.0, idx, seed)) - 0.5) * jag * 0.08 * r);
	}
	float half_w = 0.55 / sharp * (1.0 - r / max(len, 0.001)) / thin;
	float core_r = 0.16 * grow * (1.0 - k);
	float d = min(perp / max(half_w, 0.0001), r / max(core_r, 0.0001));
	d = r > len ? 9.0 : d;
	float inside = 1.0 - smoothstep(0.85, 1.0, d);
	float rim = (1.0 - smoothstep(1.0 + outline * 4.0, 1.0 + outline * 6.0, d)) * (1.0 - inside);
	rim *= 1.0 - smoothstep(len * 0.9, len * 1.02, r);
	float fade = 1.0 - smoothstep(0.55, 1.0, k);
	vec3 c = mix(color.rgb, hot.rgb, 1.0 - smoothstep(0.0, 0.6, max(d * 0.6, r / max(len, 0.001)))) * intensity;
	float e = inside * fade * hd_near * opacity;
	float o = rim * fade * hd_near * 0.85 * opacity;
	ALBEDO = c * e + ink.rgb * o;
	ALPHA = clamp(e + o, 0.0, 1.0);
}
