shader_type spatial;
// Bocanada de la nube de la Tormenta Elemental (capa de magia HD): bola de nube con el borde
// roto por ruido que se revuelve despacio, oscura por abajo y más clara arriba a la izquierda
// (de donde viene el sol). `flash` (por instancia) la ilumina por dentro con el color del
// relámpago; `ember` la tiñe de fuego por abajo y `fade` la apaga. Alfa premultiplicado: tapa
// el cielo con su color (no suma luz). Sin depth_test_disabled: el cristal la tapa.
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

#include "res://fx/hd/hd_noise.gdshaderinc"

uniform vec4 color_dark : source_color = vec4(0.13, 0.11, 0.24, 1.0);
uniform vec4 color_light : source_color = vec4(0.46, 0.42, 0.66, 1.0);
uniform vec4 flash_color : source_color = vec4(0.85, 0.85, 1.0, 1.0);
uniform vec4 ember_color : source_color = vec4(1.0, 0.45, 0.15, 1.0);
uniform float density = 0.92;
instance uniform float flash = 0.0;
instance uniform float ember = 0.0;
instance uniform float fade = 1.0;
instance uniform float seed = 0.0;

varying float hd_near;

void vertex() {
	HD_BILLBOARD
	HD_NEAR_FADE(0.4, 1.2)
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float t = TIME * 0.12;
	float n = hd_fbm(vec3(p * 1.7 + seed, t + seed * 0.3));
	float r = length(p * vec2(1.0, 1.25)) + (n - 0.5) * 0.75;
	float a = (1.0 - smoothstep(0.45, 0.95, r)) * density * fade * hd_near;
	// Luz de arriba a la izquierda y algo de relieve con el ruido.
	float lit = clamp(0.55 - p.y * 0.45 - p.x * 0.18 + (n - 0.5) * 0.7, 0.0, 1.0);
	vec3 col = mix(color_dark.rgb, color_light.rgb, lit);
	// Fuego por debajo (las bolas que caen iluminan la panza de la nube).
	col = mix(col, ember_color.rgb * 1.6, ember * smoothstep(0.0, 0.8, p.y) * 0.8);
	// El relámpago ilumina desde dentro: más en el centro de la bocanada.
	float inside = flash * (1.0 - smoothstep(0.1, 1.0, r));
	col += flash_color.rgb * inside * 2.2;
	ALBEDO = col * a;
	ALPHA = clamp(a, 0.0, 1.0);
}
