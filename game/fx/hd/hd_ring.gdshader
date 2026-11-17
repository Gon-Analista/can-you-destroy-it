shader_type spatial;
// Onda de choque HD: anillo suave que se abre (aditivo) con borde de ruido.
render_mode unshaded, blend_premul_alpha, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled, shadows_disabled;

#include "res://fx/hd/hd_noise.gdshaderinc"

uniform vec4 color : source_color = vec4(1.0, 0.7, 0.35, 1.0);
uniform float intensity = 2.0;
uniform float progress = 0.0;
uniform float seed = 0.0;

void vertex() {
	HD_BILLBOARD
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float k = progress;
	float radius = mix(0.15, 0.95, 1.0 - pow(1.0 - k, 3.0));
	float width = mix(0.18, 0.025, k);
	float n = hd_noise(vec3(cos(a) * 3.0, sin(a) * 3.0, seed));
	float d = abs(r - radius - (n - 0.5) * 0.06);
	float ring = smoothstep(width, 0.0, d);
	ALBEDO = color.rgb * ring * intensity * (1.0 - k) * (1.0 - k);
	ALPHA = 0.0;
}
