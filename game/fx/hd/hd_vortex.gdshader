shader_type spatial;
// Vórtice de maná (nodo hito de la Telequinesis): un remolino de luz en espiral sobre un quad
// horizontal alrededor del mago. Brazos de espiral logarítmica que giran y se cierran hacia el
// centro, vetas de viento con ruido, un anillo exterior que respira y motas que corren por los
// brazos. Luz casi pura (alfa bajo premultiplicado) para que florezca con el glow sin tapar el
// suelo. Capa de magia HD: sin depth_test_disabled (lo tapa lo que tenga delante).
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

#include "res://fx/hd/hd_noise.gdshaderinc"

uniform vec4 color : source_color = vec4(0.45, 0.85, 1.0, 1.0);
uniform vec4 color_hot : source_color = vec4(1.0, 0.55, 0.95, 1.0);
uniform float intensity = 1.0;
// Giro acumulado (rad): lo avanza el script, más deprisa cuanto más aspira.
uniform float spin = 0.0;
// 0..1: cuánto aspira (vacío = casi invisible, sólo el anillo).
uniform float activity = 1.0;
// Brazos de la espiral y cuánto se enroscan.
uniform float arms = 5.0;
uniform float twist = 8.0;
// Radio (en UV, 0..1) del hueco del centro: el mago está ahí y no se tapa los pies.
uniform float hole = 0.3;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float a = atan(p.y, p.x);
	// Espiral: el ángulo se tuerce con log(r) (se cierra hacia dentro) y gira con `spin`.
	float lr = log(max(r, 0.001));
	float phase = a * arms + lr * twist * arms * 0.5 - spin * arms;
	float wisp = hd_noise(vec3(cos(a) * 2.0 + spin * 0.15, sin(a) * 2.0, lr * 1.6 - spin * 0.4));
	float arm = pow(0.5 + 0.5 * cos(phase + (wisp - 0.5) * 2.4), 10.0);
	// Vetas finas (viento) que corren entre los brazos.
	float streak = pow(0.5 + 0.5 * cos(phase * 3.0 + wisp * 6.0), 18.0) * 0.5;
	// Desvanece hacia fuera y en el hueco del centro.
	float outer = smoothstep(1.0, 0.55, r);
	float inner = smoothstep(hole, hole + 0.3, r);
	float body = (arm * 0.7 + streak) * outer * inner * activity;
	// Anillo exterior que respira (se ve aunque aspire poco: el vórtice está "en guardia").
	float ring_r = 0.9 + 0.03 * sin(spin * 1.7);
	float ring = smoothstep(0.045, 0.0, abs(r - ring_r)) * (0.05 + 0.95 * activity);
	// Motas que corren por los brazos hacia el centro.
	float mote = smoothstep(0.82, 1.0, hd_noise(vec3(phase * 0.8, lr * 6.0 + spin * 2.5, 3.1)));
	mote *= outer * inner * activity;
	// Más caliente (rosa) cerca del centro, cian por fuera.
	vec3 col = mix(color_hot.rgb, color.rgb, smoothstep(0.15, 0.8, r));
	vec3 light = col * (body * 1.1 + ring * 0.9) + color_hot.rgb * mote * 1.6;
	// Luz casi pura: un poco de alfa sólo en el anillo (el suelo no se oscurece).
	ALBEDO = light * intensity * 0.55;
	ALPHA = clamp(ring * 0.08 * intensity, 0.0, 0.2);
}
