shader_type spatial;
// Estela HD de un hechizo en vuelo: cinta de cara a la cámara (la malla la hace SpellTrail).
// Cuerpo de color con ruido que corre hacia la cola, núcleo HDR en el eje y fundido suave.
// UV.x = edad (0 cabeza, 1 cola); UV.y = través.
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

#include "res://fx/hd/hd_noise.gdshaderinc"

uniform sampler2D ramp : source_color, filter_linear, repeat_disable;
uniform float intensity = 2.0;
uniform float seed = 0.0;
uniform float fade = 0.0;

void fragment() {
	float age = UV.x;
	float across = abs(UV.y * 2.0 - 1.0);
	float t = TIME * 3.0 + seed * 7.0;
	float n = hd_fbm(vec3(age * 6.0 - t, UV.y * 2.5, seed));
	float width = (1.0 - age) * (0.75 + n * 0.5);
	float body = smoothstep(width, width - 0.25, across);
	float heat = clamp((1.0 - across / max(width, 0.01)) * (1.0 - age * 0.9) + (n - 0.5) * 0.3, 0.0, 1.0);
	vec3 col = texture(ramp, vec2(1.0 - heat, 0.5)).rgb * intensity * (1.0 + pow(heat, 3.0) * 2.5);
	float a = clamp(body * (1.0 - age) * (1.0 - fade) * 1.2, 0.0, 1.0);
	ALBEDO = col * a;
	ALPHA = a * (1.0 - heat * 0.6);
}
