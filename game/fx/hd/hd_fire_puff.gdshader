shader_type spatial;
// Bocanada de fuego (partícula) de la cola de la Bola de Fuego: una nube de llama con el borde
// roto que nace caliente (amarilla), se enfría a naranja y rojo oscuro, se deshace en jirones y
// acaba en una voluta de humo fina. Muchas seguidas, soltadas en el mundo, dibujan la cola de
// cometa con profundidad de verdad (las de cerca, más grandes). Colores en bandas nítidas, como
// `hd_fireball`. Alfa premultiplicado; sin `depth_test_disabled` (la tapa el cristal).
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

#include "res://fx/hd/hd_noise.gdshaderinc"

uniform sampler2D ramp : source_color, filter_linear, repeat_disable;
uniform float intensity = 1.0;
// 0..1: nivel del hechizo (bocanadas más calientes).
uniform float heat = 0.0;
uniform vec4 smoke_color : source_color = vec4(0.24, 0.18, 0.18, 1.0);

varying float hd_near;
varying float age;
varying float pseed;
varying float palpha;

void vertex() {
	HD_BILLBOARD
	HD_NEAR_FADE(1.2, 3.5)
	// Partículas: CUSTOM.x = ángulo al azar (semilla), CUSTOM.y = edad (0..1).
	pseed = INSTANCE_CUSTOM.x;
	age = INSTANCE_CUSTOM.y;
	palpha = COLOR.a;
}

float band(float v, float th) {
	float w = max(fwidth(v), 0.002) * 0.9;
	return smoothstep(th - w, th + w, v);
}

vec3 ramp_hue(float x, float sat) {
	vec3 c = texture(ramp, vec2(x, 0.5)).rgb;
	c /= max(1.0, max(c.r, max(c.g, c.b)));
	return pow(c, vec3(sat));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float cs = cos(pseed);
	float sn = sin(pseed);
	p = mat2(vec2(cs, sn), vec2(-sn, cs)) * p;
	float s = fract(pseed * 0.159) * 17.0;
	float n = hd_fbm(vec3(p * 1.7 + s, age * 1.6 + s));
	float n2 = hd_fbm(vec3(p * 3.6 + 7.0 + s, age * 2.8));
	float r = length(p);
	// La nube se come a sí misma al envejecer: jirones cada vez más sueltos.
	float m = (1.0 - r / 0.78) + (n - 0.5) * (1.0 + age * 0.7) + (n2 - 0.5) * 0.45 - age * 0.55;
	// Pegada a la cámara se deshace en jirones (translúcida, el rojo sobre el cielo se vería rosa).
	m -= (1.0 - hd_near) * (0.6 + 0.5 * (1.0 - n2));
	float h = m * 1.2 + (1.0 - age) * 0.8 - 0.45 + heat * 0.12 + (n2 - 0.5) * 0.45;
	vec3 c0 = texture(ramp, vec2(1.0, 0.5)).rgb * 0.8;
	vec3 c1 = ramp_hue(0.6, 1.0);
	vec3 c2 = ramp_hue(0.3, 1.2);
	vec3 c3 = ramp_hue(0.12, 1.5);
	vec3 c4 = ramp_hue(0.0, 1.5);
	vec3 col = mix(mix(mix(c0, c1, band(h, 0.15)), c2, band(h, 0.32)), c3, band(h, 0.5));
	col = mix(col, c4, band(h, 0.75));
	// Borde rojo oscuro: cada bocanada se lee aunque se solapen.
	col = mix(c0, col, band(m, 0.1)) * intensity;
	// Al final se apaga a jirones finos (rojo oscuro y, en la punta, humo) que se deshacen. Opacos:
	// a medio fundir, sobre el cielo claro se verían rosas.
	float smoke = smoothstep(0.6, 0.85, age + (n - 0.5) * 0.3);
	col = mix(col, smoke_color.rgb, smoke * 0.7);
	float a = band(m - smoothstep(0.4, 1.0, age) * (0.3 + 0.5 * n2), 0.0);
	a = clamp(a * palpha, 0.0, 1.0);
	ALBEDO = col * a;
	ALPHA = a;
}
