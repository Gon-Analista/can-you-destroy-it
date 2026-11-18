shader_type spatial;
// Roca del Meteoro (capa de magia HD): basalto oscuro con luz de arriba a la izquierda en bandas,
// la cara que va por delante al rojo por el roce con el aire, borde encendido por el fuego que
// la envuelve y grietas de lava (voronoi 3D en espacio de objeto) que laten.
// Alfa premultiplicado con alfa 1: tapa como algo sólido y se ordena con el resto de la magia.
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_back, fog_disabled, shadows_disabled;

#include "res://fx/hd/hd_noise.gdshaderinc"

uniform vec4 rock_color : source_color = vec4(0.17, 0.12, 0.11, 1.0);
uniform vec4 rock_light : source_color = vec4(0.42, 0.3, 0.26, 1.0);
uniform vec4 hot_color : source_color = vec4(1.0, 0.36, 0.08, 1.0);
uniform vec4 crack_color : source_color = vec4(1.0, 0.62, 0.2, 1.0);
// Energía HDR de las grietas (florecen con el resplandor).
uniform float crack_energy = 1.7;
// 0..1: lo encendida que está (se enciende al caer y sigue ardiendo).
uniform float heat = 1.0;
// Dirección del vuelo en el mundo: esa cara arde.
uniform vec3 travel_dir = vec3(0.0, -1.0, 0.0);
uniform float seed = 0.0;

varying vec3 obj_pos;
varying vec3 world_n;

void vertex() {
	obj_pos = VERTEX;
	world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Distancia al borde de la celda de voronoi más cercana (F2 - F1): 0 en las grietas.
float crack_edge(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 g = vec3(float(x), float(y), float(z));
				vec3 o = vec3(
					hd_hash(i + g + vec3(seed)),
					hd_hash(i + g + vec3(17.0, seed, 3.0)),
					hd_hash(i + g + vec3(5.0, 11.0, seed))
				);
				float d = length(g + o - f);
				if (d < d1) {
					d2 = d1;
					d1 = d;
				} else if (d < d2) {
					d2 = d;
				}
			}
		}
	}
	return d2 - d1;
}

void fragment() {
	vec3 n = normalize(world_n);
	// Luz principal arriba a la izquierda (como el resto del valle), en tres bandas.
	vec3 sun = normalize(vec3(-0.55, 0.75, 0.35));
	float lam = max(dot(n, sun), 0.0);
	lam = floor(lam * 3.0 + 0.5) / 3.0;
	vec3 col = mix(rock_color.rgb, rock_light.rgb, lam);
	// La cara de delante, al rojo vivo; el resto, con brasas sueltas.
	float lead = smoothstep(0.1, 0.85, dot(n, normalize(travel_dir)));
	float spots = smoothstep(0.55, 0.75, hd_fbm(obj_pos * 3.0 + vec3(seed)));
	col = mix(col, hot_color.rgb, (lead * 0.7 + spots * 0.3) * heat);
	// Borde encendido por el fuego que la envuelve.
	float rim = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.5);
	col += hot_color.rgb * rim * 0.6 * heat;
	// Grietas de lava: dos escalas, más anchas donde la roca está más caliente.
	float e1 = crack_edge(obj_pos * 2.2);
	float e2 = crack_edge(obj_pos * 5.0 + vec3(3.0));
	float w = 0.05 + 0.06 * lead;
	float cr = max(1.0 - smoothstep(0.0, w, e1), (1.0 - smoothstep(0.0, w * 0.7, e2)) * 0.6);
	float pulse = 0.8 + 0.2 * sin(TIME * 9.0 + hd_noise(obj_pos * 4.0) * 6.0);
	vec3 lava = mix(hot_color.rgb, crack_color.rgb, 1.0 - smoothstep(0.0, w * 0.5, e1));
	col = mix(col, lava * crack_energy * pulse, cr * heat);
	ALBEDO = col;
	ALPHA = 1.0;
}
