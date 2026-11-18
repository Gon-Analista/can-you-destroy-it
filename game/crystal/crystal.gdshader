shader_type spatial;
// Cristal Madre: bandas de paleta, corazón violeta, brillo que recorre las facetas,
// grietas persistentes (voronoi 3D) y destellos de impacto. Sin iluminación de motor: control total del color.
// El cristal se excava de verdad (CrystalVolume): cada vértice lleva en UV.x su profundidad bajo la
// superficie original. Esa profundidad decide la capa (paleta y dibujo propios) y si la cara es
// "interior" (excavada): ahí el cristal se oscurece, centellea y las capas hondas brillan solas.
render_mode unshaded, cull_back;

#include "res://crystal/crystal_common.gdshaderinc"

uniform vec4 col_crack : source_color = vec4(0.95, 1.0, 1.0, 1.0);
uniform vec4 col_flash : source_color = vec4(0.85, 1.0, 1.0, 1.0);
uniform vec4 col_resonant : source_color = vec4(1.0, 0.87, 0.55, 1.0);
// Destello de los golpes de fuego (Bola de Fuego, Meteoro): el blanco azulado tapaba el fuego.
uniform vec4 col_fire_flash : source_color = vec4(1.0, 0.58, 0.24, 1.0);
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
// Luz cálida del fuego que se acerca (FireGlow): xyz = posición, w = radio (m); color con la
// fuerza en el alfa (0: apagada).
global uniform vec4 fire_glow;
global uniform vec4 fire_glow_color;
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
// Paleta de cada capa, de fuera a dentro: Corteza, Manto Geódico, Venas, Corazón y Núcleo.
uniform vec4 pal_highlight[5] : source_color;
uniform vec4 pal_light[5] : source_color;
uniform vec4 pal_mid[5] : source_color;
uniform vec4 pal_dark[5] : source_color;
// Profundidad (m) a la que empieza cada capa (el Núcleo es la esfera `core_sphere`).
uniform float layer_depth[5];
// Cuánto se oscurece lo excavado y cuánto brilla por sí sola cada capa.
uniform float layer_shade[5];
uniform float layer_glow[5];
uniform vec4 core_sphere = vec4(0.0, 5.0, 0.0, 3.6);
// Bolsas de geoda: xyz = centro, w = radio (0: vacía). Su pared es de amatista.
uniform vec4 geodes[32];
uniform vec4 col_amethyst : source_color = vec4(0.72, 0.36, 0.95, 1.0);
// Venas Resonantes: cada vena brilla con el color de su elemento (por sector alrededor del eje).
uniform vec4 vein_colors[5] : source_color;
// 0..1: la vena de cada lado se enciende al golpearla con su elemento (ver CrystalVeins).
uniform float vein_pulse[5];
uniform vec4 weak_zones[8];
uniform float weak_radius[8];
uniform float weak_kind[8];
uniform float weak_sec[8];
uniform vec4 col_frost : source_color = vec4(0.85, 0.97, 1.0, 1.0);
uniform vec4 col_ice_line : source_color = vec4(1.0, 1.0, 1.0, 1.0);

varying vec3 world_pos;
varying vec3 world_nrm;
varying float v_depth;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_depth = UV.x;
}

// Capa de un punto: por profundidad (con algo de ruido para que el borde no sea una línea).
int layer_of(float depth, vec3 p) {
	float j = (hash13(floor(p * 1.4)) - 0.5) * 0.6;
	if (distance(p, core_sphere.xyz) < core_sphere.w + j) {
		return 4;
	}
	int li = 0;
	for (int i = 1; i < 4; i++) {
		if (depth + j >= layer_depth[i]) {
			li = i;
		}
	}
	return li;
}

vec3 layer_bands(int li, float level) {
	if (level > 0.84) {
		return pal_highlight[li].rgb;
	} else if (level > 0.64) {
		return pal_light[li].rgb;
	} else if (level > 0.44) {
		return pal_mid[li].rgb;
	}
	return pal_dark[li].rgb;
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

// Celda de voronoi más cercana: (hash de la celda, distancia al borde).
vec2 voronoi_cell(vec3 p) {
	vec3 ip = floor(p);
	vec3 fp = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	vec3 best = vec3(0.0);
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 g = vec3(float(x), float(y), float(z));
				vec3 r = g + hash33(ip + g) - fp;
				float d = dot(r, r);
				if (d < f1) {
					f2 = f1;
					f1 = d;
					best = ip + g;
				} else if (d < f2) {
					f2 = d;
				}
			}
		}
	}
	return vec2(hash13(best * 3.17), sqrt(f2) - sqrt(f1));
}

void fragment() {
	vec3 n = normalize(world_nrm);
	vec3 v = normalize(CAMERA_POSITION_WORLD - world_pos);
	vec3 L = normalize(-sun_dir);
	float facet = hash13(floor(n * 6.0 + 0.5) * 7.13);
	float level = dot(n, L) * 0.5 + 0.5 + (facet - 0.5) * 0.3;
	// Placas: la cara grande se parte en láminas de cristal con su propio brillo, y alguna veta
	// fina entre ellas (en lo excavado, más pequeñas: esquirlas).
	float interior_k = smoothstep(0.5, 1.7, v_depth);
	vec2 plate = voronoi_cell(world_pos * mix(0.16, 0.6, interior_k));
	level += (plate.x - 0.5) * 0.16;
	int li = layer_of(v_depth, world_pos);
	vec3 c = layer_bands(li, level);
	float fres = 1.0 - clamp(dot(n, v), 0.0, 1.0);
	c = mix(c, pal_light[li].rgb, step(0.9, fres) * 0.55);
	// Vetas entre placas sólo en algunas (no un mosaico entero) y estrías de crecimiento a lo
	// largo de las caras verticales, una cada pocos metros.
	float seam = (1.0 - smoothstep(0.0, 0.03, plate.y)) * step(0.55, plate.x);
	c = mix(c, pal_highlight[li].rgb, seam * step(0.45, level) * 0.22);
	c = mix(c, pal_dark[li].rgb, seam * step(level, 0.45) * 0.18);
	vec3 tang = normalize(cross(vec3(0.0, 1.0, 0.0), n) + vec3(1e-4));
	float stripe = step(fract(dot(world_pos, tang) * 0.42 + plate.x * 7.0), 0.035);
	c = mix(c, pal_light[li].rgb, stripe * (1.0 - abs(n.y)) * (1.0 - interior_k) * 0.25);
	// Escarcha: destellos diminutos que se encienden al moverse la luz (sólo por fuera).
	float fr = hash13(floor(world_pos * 9.0));
	float spark = step(0.993, fr) * step(0.5, fract(fr * 53.0 + now * 0.35 + dot(v, vec3(0.7))));
	c = mix(c, vec3(1.0), spark * (1.0 - interior_k) * 0.9);
	// Cara excavada (bajo la superficie original): estamos dentro del cristal.
	float interior = smoothstep(0.5, 1.7, v_depth);
	c *= 1.0 - layer_shade[li] * interior;
	float glow = layer_glow[li] * interior;

	if (li == 1) {
		// Manto Geódico: motas de amatista atrapadas en el hielo.
		vec3 q = world_pos * 6.0;
		float h = hash13(floor(q));
		vec3 f = fract(q) - 0.5;
		float dot_m = step(0.965, h) * step(max(abs(f.x), max(abs(f.y), abs(f.z))), 0.32);
		c = mix(c, mix(col_amethyst.rgb, vec3(1.0, 0.85, 1.0), step(0.99, h)), dot_m * (0.45 + 0.55 * interior));
	} else if (li == 2) {
		// Venas Resonantes: vetas de colores (una por elemento según el lado del cristal).
		float e = voronoi_edge(world_pos * 0.42);
		float sector = floor((atan(world_pos.z, world_pos.x) + PI) / TAU * 5.0);
		int si = int(mod(sector, 5.0));
		vec3 vc = vein_colors[si].rgb;
		float pulse = vein_pulse[si];
		float vein = 1.0 - smoothstep(0.03 + pulse * 0.05, 0.09 + pulse * 0.1, e);
		c = mix(c, vc * (1.0 + interior * 0.8 + pulse * 1.4), vein * 0.85);
		glow = max(glow, pulse * vein);
	} else if (li == 3) {
		// Corazón Cristalino: blanco azulado, casi luminoso.
		c = mix(c, pal_highlight[li].rgb, 0.25 * interior);
	} else if (li == 4) {
		// Núcleo: violeta oscuro que late.
		c *= 0.8 + 0.4 * core_pulse;
	}
	// Centelleo del interior: puntos que se encienden y se apagan.
	vec3 cellp = floor(world_pos * 10.0);
	float tw = hash13(cellp);
	float blink = step(0.99, tw) * step(0.7, fract(tw * 91.0 + now * 0.6));
	c = mix(c, pal_highlight[li].rgb * 1.6, blink * interior);

	// Bolsas de geoda: pared de amatista con cristales que brillan.
	for (int i = 0; i < 32; i++) {
		if (geodes[i].w > 0.0) {
			float d = distance(world_pos, geodes[i].xyz);
			float m = 1.0 - smoothstep(geodes[i].w * 1.05, geodes[i].w * 1.35, d);
			if (m > 0.0) {
				vec3 am = level > 0.7 ? vec3(1.0, 0.8, 1.0) : (level > 0.45 ? col_amethyst.rgb : col_amethyst.rgb * 0.55);
				c = mix(c, am, m);
				glow = max(glow, 0.5 * m);
			}
		}
	}

	// Corazón violeta en la base, que se adivina desde fuera.
	float core = smoothstep(core_top, core_bottom, world_pos.y) * (1.0 - interior);
	core *= 0.8 + 0.2 * core_pulse;
	c = mix(c, col_core.rgb, core * (level > 0.84 ? 0.35 : 0.7));

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
	vec3 lit = c * world_tint.rgb;
	c = mix(lit, c * (1.0 + glow * 0.6), clamp(glow, 0.0, 1.0));
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

	// La Bola de Fuego que se acerca tiñe el cristal de naranja, en bandas como el resto.
	if (fire_glow_color.a > 0.0) {
		float gk = clamp(1.0 - distance(world_pos, fire_glow.xyz) / max(fire_glow.w, 0.01), 0.0, 1.0);
		gk = pow(gk, 1.4) * fire_glow_color.a;
		gk = floor(gk * 4.0 + hash13(floor(world_pos * 6.0)) * 0.5) * 0.25;
		// Hacia el color del fuego con el brillo de la faceta: multiplicar el azul claro por
		// naranja apenas se notaba (salía blanco o gris).
		// Tono saturado (el color de la luz al cuadrado) y bandas que llegan a cubrir: mezclar poco
		// un naranja con el azul daba un gris malva.
		float lum = dot(c, vec3(0.3, 0.55, 0.15));
		vec3 warm = fire_glow_color.rgb * fire_glow_color.rgb * (0.5 + lum * 0.9);
		c = mix(c, warm, clamp(gk, 0.0, 0.8));
	}

	// Destellos y ondas de impacto.
	vec3 flash = vec3(0.0);
	for (int i = 0; i < 6; i++) {
		float age = now - hits[i].w;
		if (hits[i].w >= 0.0 && age >= 0.0 && age < 1.6) {
			float d = distance(world_pos, hits[i].xyz);
			// hit_resonant: 0 normal, 1 resonante, 2 fuego.
			bool res = hit_resonant[i] > 0.5 && hit_resonant[i] < 1.5;
			vec3 fc = res ? col_resonant.rgb : (hit_resonant[i] > 1.5 ? col_fire_flash.rgb : col_flash.rgb);
			float size = hit_radius * (res ? 1.8 : 1.0);
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
