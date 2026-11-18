shader_type spatial;
// El Núcleo expuesto (GDD 9): una esfera de luz violeta oscura. Por dentro, corrientes de luz que
// giran despacio (ruido en el espacio del objeto) y un latido; el borde brilla en violeta y rosa.
// En pixel art: bandas de color con tramado ordenado, sin degradados suaves. Luz propia (no la
// apaga la noche). `charge` (0..1) la va blanqueando mientras se carga la Gran Convergencia;
// `flash` destella cuando un golpe rebota.
render_mode unshaded, cull_back, shadows_disabled;

#include "res://fx/hd/hd_noise.gdshaderinc"

uniform vec4 col_deep : source_color = vec4(0.09, 0.03, 0.2, 1.0);
uniform vec4 col_mid : source_color = vec4(0.32, 0.1, 0.52, 1.0);
uniform vec4 col_light : source_color = vec4(0.72, 0.42, 1.0, 1.0);
uniform vec4 col_rim : source_color = vec4(1.0, 0.62, 0.96, 1.0);
uniform vec4 col_white : source_color = vec4(1.0, 0.96, 1.0, 1.0);
uniform float pulse = 0.0;
uniform float flash = 0.0;
uniform float charge = 0.0;
uniform float appear = 1.0;
uniform float now = 0.0;

varying vec3 v_obj;

float bayer4(vec2 p) {
	ivec2 i = ivec2(mod(p, 4.0));
	int idx = i.x + i.y * 4;
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[idx]) + 0.5) / 16.0;
}

void vertex() {
	v_obj = VERTEX;
}

void fragment() {
	vec3 n = normalize(v_obj);
	float t = floor(now * 12.0) / 12.0;
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	// Corrientes de luz que giran alrededor del eje (como un remolino dentro de la esfera).
	float ang = t * 0.35;
	mat2 rot = mat2(vec2(cos(ang), sin(ang)), vec2(-sin(ang), cos(ang)));
	vec3 q = n;
	q.xz = rot * q.xz;
	float flow = hd_fbm(q * 2.6 + vec3(0.0, t * 0.25, 0.0));
	float veins = 1.0 - abs(hd_noise(q * 5.0 + vec3(t * 0.4, 0.0, -t * 0.3)) * 2.0 - 1.0);
	veins = pow(veins, 6.0);
	float heart = pow(facing, 2.2);
	float rim = pow(1.0 - facing, 2.4);
	float beat = 0.5 + 0.5 * pulse;
	float e = flow * 0.55 + veins * (0.45 + 0.5 * beat) + heart * 0.25 * beat;
	e += charge * 0.6 + flash * 0.7;
	// Bandas con tramado (pixel art): 5 tonos.
	float d = bayer4(FRAGCOORD.xy) - 0.5;
	float k = clamp(floor(clamp(e, 0.0, 1.2) * 4.0 + d * 0.9) / 4.0, 0.0, 1.25);
	vec3 c = mix(col_deep.rgb, col_mid.rgb, smoothstep(0.0, 0.3, k));
	c = mix(c, col_light.rgb, smoothstep(0.3, 0.8, k));
	c = mix(c, col_white.rgb, smoothstep(0.85, 1.2, k));
	// Borde: halo violeta y rosa a escalones.
	float rk = floor(rim * 3.0 + d * 0.8) / 3.0;
	c = mix(c, col_rim.rgb * 1.3, clamp(rk, 0.0, 1.0) * (0.7 + 0.3 * beat));
	c = mix(c, col_white.rgb * 1.6, clamp(charge * charge * 0.7 + flash * 0.4, 0.0, 0.9));
	ALBEDO = c * (0.85 + 0.6 * beat);
	ALPHA = 1.0;
	// Al aparecer, se enciende de dentro afuera (umbral con tramado: sin transparencias suaves).
	if (appear < 1.0 && heart + d * 0.3 < 1.0 - appear * 1.3) {
		discard;
	}
}
