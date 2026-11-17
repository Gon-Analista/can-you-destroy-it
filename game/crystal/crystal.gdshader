shader_type spatial;
// Cristal Madre: bandas de paleta, corazón violeta, brillo que recorre las facetas,
// grietas persistentes (voronoi 3D) y destellos de impacto. Sin iluminación de motor: control total del color.
render_mode unshaded, cull_back;

#include "res://crystal/crystal_common.gdshaderinc"

uniform vec4 col_crack : source_color = vec4(0.95, 1.0, 1.0, 1.0);
uniform vec4 col_flash : source_color = vec4(0.85, 1.0, 1.0, 1.0);
uniform vec4 col_resonant : source_color = vec4(1.0, 0.87, 0.55, 1.0);
uniform float core_top = 4.0;
uniform float core_bottom = 0.0;
uniform float core_pulse = 0.0;
uniform float shimmer_speed = 0.1;
uniform float now = 0.0;
// xyz = posición del impacto, w = instante del impacto (en `now`). w < 0: vacío.
uniform vec4 hits[6];
// w > 0 marca un golpe resonante (dorado).
uniform float hit_resonant[6];
uniform float hit_radius = 1.5;
// xyz = centro de la grieta, w = radio (0: vacío).
uniform vec4 cracks[16];
uniform float crack_scale = 1.7;
uniform float global_flash = 0.0;
// Luz del momento del día (DayNight): el cristal no usa la iluminación del motor.
global uniform vec4 world_tint;
// Quemaduras del fuego: xyz = centro, w = instante (en `now`); w < 0: vacío.
uniform vec4 burns[12];
// Radio de cada quemadura (m).
uniform float burn_radius[12];
// Al rojo vivo: vetas de lava; al enfriarse, hollín.
uniform vec4 col_lava : source_color = vec4(1.0, 0.45, 0.12, 1.0);
uniform vec4 col_lava_hot : source_color = vec4(1.0, 0.85, 0.45, 1.0);
uniform vec4 col_soot : source_color = vec4(0.2, 0.13, 0.2, 1.0);
// Zonas debilitadas: xyz = centro, w = instante (en `now`); w < 0: vacío. `weak_kind`: 1 =
// congelada (Escarcha), 2 = quebradiza (Choque Térmico). Duran `weak_sec[i]` segundos.
uniform vec4 weak_zones[8];
uniform float weak_radius[8];
uniform float weak_kind[8];
uniform float weak_sec[8];
uniform vec4 col_frost : source_color = vec4(0.85, 0.97, 1.0, 1.0);
uniform vec4 col_ice_line : source_color = vec4(1.0, 1.0, 1.0, 1.0);

varying vec3 world_pos;
varying vec3 world_nrm;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Distancia al borde de celda (F2 - F1): líneas finas de fractura.
float voronoi_edge(vec3 p) {
	vec3 ip = floor(p);
	vec3 fp = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 g = vec3(float(x), float(y), float(z));
				vec3 r = g + hash33(ip + g) - fp;
				float d = dot(r, r);
				if (d < f1) {
					f2 = f1;
					f1 = d;
				} else if (d < f2) {
					f2 = d;
				}
			}
		}
	}
	return sqrt(f2) - sqrt(f1);
}

void fragment() {
	vec3 n = normalize(world_nrm);
	vec3 v = normalize(CAMERA_POSITION_WORLD - world_pos);
	float level;
	vec3 c = crystal_bands(n, v, level);

	// Corazón violeta en la base.
	float core = smoothstep(core_top, core_bottom, world_pos.y);
	core *= 0.8 + 0.2 * core_pulse;
	c = mix(c, col_core.rgb, core * (level > 0.84 ? 0.45 : 0.9));

	// Brillo que sube por las facetas (el cristal "respira").
	float sh = fract(world_pos.y * 0.05 + world_pos.x * 0.015 - now * shimmer_speed);
	c = mix(c, col_highlight.rgb, step(sh, 0.018) * step(0.44, level) * 0.6);

	// Grietas: sólo se calcula el voronoi si el fragmento cae dentro de alguna.
	float crack_mask = 0.0;
	for (int i = 0; i < 16; i++) {
		if (cracks[i].w > 0.0) {
			float d = distance(world_pos, cracks[i].xyz);
			crack_mask = max(crack_mask, 1.0 - smoothstep(cracks[i].w * 0.55, cracks[i].w, d));
		}
	}
	if (crack_mask > 0.0) {
		float e = voronoi_edge(world_pos * crack_scale);
		float line = step(e, 0.07 * crack_mask);
		c = mix(c, col_crack.rgb, line);
		c = mix(c, col_dark.rgb, step(e, 0.16 * crack_mask) * (1.0 - line) * 0.35);
	}

	// Luz del día o de la noche (el corazón y lo que brilla, encima, no se apagan).
	c *= world_tint.rgb;
	c = mix(c, col_core.rgb * 1.2, core * (1.0 - world_tint.g) * 0.5);

	// Quemaduras (elemento fuego): la zona se pone al rojo con vetas de lava que brillan (HDR,
	// florecen con el glow), se enfrían en unos segundos y dejan hollín que se va borrando.
	float burn_heat = 0.0;
	float burn_soot = 0.0;
	for (int i = 0; i < 12; i++) {
		if (burns[i].w >= 0.0) {
			float age = now - burns[i].w;
			float d = distance(world_pos, burns[i].xyz);
			float wobble = hash33(floor(world_pos * 3.0)).x * 0.25;
			float m = 1.0 - smoothstep(burn_radius[i] * 0.45, burn_radius[i] * (1.0 + wobble), d);
			burn_heat = max(burn_heat, m * exp(-age / 2.2));
			burn_soot = max(burn_soot, m * exp(-age / 30.0));
		}
	}
	if (burn_soot > 0.01) {
		c = mix(c, col_soot.rgb, burn_soot * 0.55);
		float e = voronoi_edge(world_pos * 2.6);
		float vein = 1.0 - smoothstep(0.0, 0.12, e);
		vec3 lava = mix(col_lava.rgb, col_lava_hot.rgb, burn_heat) * (1.0 + burn_heat * 1.6);
		c = mix(c, lava, clamp(vein * burn_heat * 1.4 + burn_heat * 0.35, 0.0, 1.0));
	}

	// Escarcha: capa blanca azulada con vetas de hielo que brillan; quebradizo: grietas
	// incandescentes entre el hielo (vapor del choque térmico).
	float frost = 0.0;
	float shatter = 0.0;
	for (int i = 0; i < 8; i++) {
		if (weak_zones[i].w >= 0.0) {
			float age = now - weak_zones[i].w;
			if (age < weak_sec[i]) {
				float d = distance(world_pos, weak_zones[i].xyz);
				float edge = hash33(floor(world_pos * 4.0)).y * 0.3;
				float m = 1.0 - smoothstep(weak_radius[i] * 0.5, weak_radius[i] * (1.0 + edge), d);
				// Aparece en un instante y se derrite al final.
				m *= smoothstep(0.0, 0.15, age) * (1.0 - smoothstep(weak_sec[i] - 1.2, weak_sec[i], age));
				if (weak_kind[i] > 1.5) {
					shatter = max(shatter, m);
				} else {
					frost = max(frost, m);
				}
			}
		}
	}
	if (frost + shatter > 0.01) {
		float e = voronoi_edge(world_pos * 4.2);
		float line = 1.0 - smoothstep(0.0, 0.06, e);
		float k = max(frost, shatter);
		c = mix(c, col_frost.rgb * mix(world_tint.rgb, vec3(1.0), 0.5), k * 0.65);
		c = mix(c, col_ice_line.rgb * 1.4, line * frost * 0.9);
		vec3 hot = mix(col_lava.rgb, col_lava_hot.rgb, 0.5) * 2.0;
		c = mix(c, hot, line * shatter);
	}

	// Destellos y ondas de impacto.
	vec3 flash = vec3(0.0);
	for (int i = 0; i < 6; i++) {
		float age = now - hits[i].w;
		if (hits[i].w >= 0.0 && age >= 0.0 && age < 1.6) {
			float d = distance(world_pos, hits[i].xyz);
			vec3 fc = hit_resonant[i] > 0.0 ? col_resonant.rgb : col_flash.rgb;
			float size = hit_radius * (hit_resonant[i] > 0.0 ? 1.8 : 1.0);
			float core_glow = (1.0 - smoothstep(0.0, size * (0.5 + age * 2.0), d)) * exp(-age * 9.0);
			float ring = (1.0 - step(0.22, abs(d - age * 9.0))) * exp(-age * 3.0);
			flash = max(flash, fc * clamp(core_glow * 1.4 + ring * 0.7, 0.0, 1.0));
		}
	}
	c = mix(c, flash / max(max(flash.r, max(flash.g, flash.b)), 0.001),
		clamp(max(flash.r, max(flash.g, flash.b)), 0.0, 1.0));
	c = mix(c, col_flash.rgb, global_flash);
	ALBEDO = c;
}
