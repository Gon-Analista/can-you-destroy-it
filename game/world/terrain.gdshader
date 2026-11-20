shader_type spatial;
// Toon con textura pixel art procedural en espacio de mundo para el paisaje (suelo, rocas,
// montañas, árboles). El color base llega por vértice y el alfa del vértice elige el dibujo:
//   1.0 liso (como fx/toon) · 0.9 hierba · 0.8 tierra · 0.7 roca · 0.6 hojas · 0.5 corteza
//   0.4 roca con nieve por encima de `snow_line`.
// Los texeles se alinean a una rejilla del mundo (sin texturas que se emborronen) y su tamaño se
// dobla con la distancia para que un texel nunca baje de un píxel de pantalla (sin parpadeo).
// Las bandas de luz y los cambios de tono se tramean con Bayer 4x4 sobre esa misma rejilla.
render_mode diffuse_lambert, specular_disabled;

uniform float texels_per_m = 14.0;
uniform float bands = 3.0;
uniform float rim = 0.0;
uniform vec4 rim_color : source_color = vec4(1.0, 0.96, 0.85, 1.0);
// Fuerza del tramado en los bordes de las bandas de luz (0 = bordes limpios).
uniform float band_dither = 0.22;
// Altura de la nieve si la malla no la trae en UV.x (las montañas la traen, cada una la suya).
uniform float snow_line = 70.0;
uniform vec4 snow_color : source_color = vec4(0.95, 0.965, 1.0, 1.0);
uniform vec4 rock_tone : source_color = vec4(0.49, 0.525, 0.79, 1.0);

varying vec3 v_world;
varying vec3 v_wnormal;
varying float v_dither;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

float bayer4(vec2 c) {
	ivec2 i = ivec2(mod(c, 4.0));
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i.y * 4 + i.x]) + 0.5) / 16.0;
}

vec3 to_linear(vec3 v) {
	return mix(pow((v + 0.055) / 1.055, vec3(2.4)), v / 12.92, lessThan(v, vec3(0.04045)));
}

// Tono claro (más cálido) y oscuro (más frío) de un color, como en una rampa de pixel art.
vec3 tone_light(vec3 c) {
	return clamp(c * vec3(1.13, 1.12, 0.96) + vec3(0.035, 0.04, 0.0), 0.0, 1.0);
}

vec3 tone_dark(vec3 c) {
	return c * vec3(0.76, 0.83, 0.97);
}

// Elige entre oscuro / base / claro con un umbral tramado.
vec3 ramp3(vec3 base, float t, float dither, float spread) {
	float v = t + (dither - 0.5) * spread;
	if (v > 0.64) {
		return tone_light(base);
	}
	if (v < 0.36) {
		return tone_dark(base);
	}
	return base;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 base = COLOR.rgb;
	int kind = int(round((1.0 - COLOR.a) * 10.0));
	vec3 c = base;
	vec3 n = normalize(v_wnormal);
	vec3 an = abs(n);
	// Proyección: planta para el suelo; para lo demás, el plano que más mira a la cámara.
	vec2 uv = v_world.xz;
	bool side = false;
	if (kind >= 3 && an.y < 0.7) {
		side = true;
		uv = an.x > an.z ? vec2(v_world.z, v_world.y) : vec2(v_world.x, v_world.y);
	}
	// Tamaño de un píxel de pantalla a esta distancia: el texel se dobla para no bajar de él.
	float dist = length(v_world - CAMERA_POSITION_WORLD);
	float pix = dist * 2.0 / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	float base_tex = 1.0 / texels_per_m;
	float lod = max(0.0, ceil(log2(pix * 1.15 / base_tex)));
	float tex = base_tex * exp2(lod);
	vec2 cell = floor(uv / tex);
	vec2 cw = (cell + 0.5) * tex;
	float d = bayer4(cell);
	float h = hash12(cell + lod * 37.0);
	float detail = 1.0 - smoothstep(2.0, 4.0, lod);
	v_dither = d;
	if (kind == 1) {
		// Hierba: manchas grandes tramadas, matas sueltas y alguna florecilla; en las cuestas, roca.
		float t = vnoise(cw * 0.07) * 0.65 + vnoise(cw * 0.33 + 17.0) * 0.35;
		c = ramp3(base, t, d, 0.3);
		float clump = hash12(floor(cell / vec2(1.0, 2.0)) + 3.1 + lod * 11.0);
		if (clump > 0.95) {
			c = tone_light(c);
		} else if (clump < 0.04) {
			c = tone_dark(c);
		}
		if (lod < 1.0 && h > 0.996) {
			c = hash12(cell + 91.0) > 0.5 ? vec3(1.0, 0.9, 0.5) : vec3(0.97, 0.97, 1.0);
		}
		float steep = smoothstep(0.68, 0.52, n.y) + (d - 0.5) * 0.4;
		if (steep > 0.5) {
			float s = vnoise(vec2(cw.x + cw.y, v_world.y * 3.0) * 0.6);
			c = ramp3(rock_tone.rgb, s, d, 0.4);
		}
	} else if (kind == 2) {
		// Tierra: vetas suaves y guijarros de 2x2 texeles con luz arriba a la izquierda.
		float t = vnoise(cw * 0.18) * 0.65 + vnoise(cw * 0.8 + 5.0) * 0.35;
		c = ramp3(base, t, d, 0.25);
		vec2 big = floor(cell / 2.0);
		if (hash12(big + 7.7 + lod) > 0.975) {
			vec2 sub = cell - big * 2.0;
			vec3 pebble = vec3(0.84, 0.76, 0.66);
			c = (sub.x + (1.0 - sub.y) < 1.5) ? pebble : tone_dark(pebble);
		} else if (h > 0.985) {
			c = tone_dark(base);
		}
	} else if (kind == 3 || kind == 6) {
		// Roca: estratos horizontales alargados, motas y grietas oscuras.
		vec2 st = side ? vec2(uv.x * 0.18, uv.y * 0.9) : uv * 0.3;
		float t = vnoise(st + 2.0) * 0.7 + vnoise(cw * 0.9) * 0.3;
		c = ramp3(base, t, d, 0.3);
		float crack = vnoise(cw * vec2(0.6, 2.4) + 9.0);
		if (abs(crack - 0.5) < 0.025 * detail) {
			c = tone_dark(tone_dark(base));
		} else if (h > 0.94) {
			c = tone_light(c);
		}
		if (kind == 6) {
			float line = UV.x > 0.0 ? UV.x : snow_line;
			float edge = line + (vnoise(v_world.xz * 0.05) - 0.5) * 22.0 + (d - 0.5) * 6.0;
			if (v_world.y > edge && n.y > 0.25 + (d - 0.5) * 0.2) {
				float sn = vnoise(cw * 0.4);
				c = sn + (d - 0.5) * 0.3 < 0.3 ? snow_color.rgb * vec3(0.84, 0.89, 1.0) : snow_color.rgb;
			}
		}
	} else if (kind == 4) {
		// Hojas: racimos redondos (luz arriba), huecos oscuros y brillos sueltos.
		float t = vnoise(cw * 1.4) * 0.6 + vnoise(cw * 3.1 + 4.0) * 0.4;
		t += n.y * 0.25;
		c = ramp3(base, t, d, 0.35);
		if (h > 0.93) {
			c = tone_light(tone_light(base));
		} else if (h < 0.06) {
			c = tone_dark(tone_dark(base));
		}
	} else if (kind == 5) {
		// Corteza: vetas verticales.
		float t = vnoise(vec2(uv.x * 6.0, uv.y * 0.6));
		c = ramp3(base, t, d, 0.3);
	}
	ALBEDO = to_linear(c);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION;
	float q = clamp(floor(ndl * bands + 0.35 + (v_dither - 0.5) * band_dither * 2.0), 0.0, bands) / bands;
	DIFFUSE_LIGHT += q * LIGHT_COLOR / PI;
	if (rim > 0.0) {
		float r = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		DIFFUSE_LIGHT += step(0.72, r) * step(0.2, ndl) * rim * rim_color.rgb * LIGHT_COLOR / PI;
	}
}
