shader_type spatial;
// Estela HD de un hechizo en vuelo: cinta de cara a la cámara (la malla la hace SpellTrail).
// Llama que se deshilacha hacia la cola: borde roto por ruido que corre hacia atrás, calor en
// bandas suaves (como `hd_fire`) con el eje más caliente y la cola que se enfría y se funde.
// UV.x = edad (0 cabeza, 1 cola); UV.y = través.
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

#include "res://fx/hd/hd_noise.gdshaderinc"

uniform sampler2D ramp : source_color, filter_linear, repeat_disable;
uniform float intensity = 1.25;
uniform float seed = 0.0;
uniform float fade = 0.0;

void fragment() {
	float age = UV.x;
	float across = abs(UV.y * 2.0 - 1.0);
	float t = TIME * 3.0 + seed * 7.0;
	float n = hd_fbm(vec3(age * 6.0 - t, UV.y * 2.5, seed));
	float n2 = hd_fbm(vec3(age * 15.0 - t * 1.7, UV.y * 6.0, seed + 3.0));
	// Cabeza redondeada (nunca un corte recto donde empieza la cinta) y cola que se afina.
	float cap = sqrt(smoothstep(0.0, 0.08, age));
	float width = cap * pow(1.0 - age, 0.8) * (0.6 + n * 0.7);
	// Borde roto: jirones que se escapan hacia la cola.
	float d = across / max(width, 0.01) + (n2 - 0.5) * (0.25 + age * 0.6);
	float body = smoothstep(1.0, 0.8, d);
	float heat = clamp((1.0 - d) * (1.0 - age * 0.85) + (n - 0.5) * 0.3, 0.0, 1.0);
	float hb = (floor(heat * 4.0) + smoothstep(0.3, 0.7, fract(heat * 4.0))) / 4.0;
	heat = mix(heat, hb, 0.6);
	vec3 col = texture(ramp, vec2(1.0 - heat, 0.5)).rgb;
	// Fuera del eje la energía no pasa de ~1: el resplandor sólo coge el centro de la llama.
	col = min(col, vec3(1.3, 0.95, 0.8)) * intensity * (0.85 + pow(heat, 3.0) * 0.8);
	// Opaca casi hasta el final (lo que adelgaza es el ancho): a medio fundir, el rojo oscuro
	// sobre el cielo claro se vería rosa.
	float a = clamp(body * smoothstep(1.0, 0.65, age) * (1.0 - fade), 0.0, 1.0);
	ALBEDO = col * a;
	// Casi opaca: sobre el cristal claro no se lava (sólo el eje caliente suma algo de luz).
	ALPHA = a * (1.0 - heat * 0.3);
}
