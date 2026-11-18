shader_type spatial;
// Cristal del Espejo del Archimago (mundo pixel art, no la capa de magia): una niebla de estrellas
// que gira despacio con los colores del rango, estrellas que titilan, un brillo que cruza el
// cristal y un destello al subir de rango (`flash`). Animación escalonada a 12 fps.
render_mode unshaded, cull_back, shadows_disabled;

uniform vec4 color_deep : source_color = vec4(0.06, 0.08, 0.25, 1.0);
uniform vec4 color_mid : source_color = vec4(0.4, 0.3, 0.8, 1.0);
uniform vec4 color_light : source_color = vec4(0.9, 0.85, 1.0, 1.0);
uniform float flash = 0.0;
// Cerca, el cristal se aclara un poco (el espejo "despierta" al acercarse).
uniform float awake = 0.0;
uniform float anim_fps = 12.0;
// Forma del cristal (m): tamaño del quad y arco de medio punto arriba (centro y radio).
uniform vec2 size_m = vec2(1.32, 2.74);
uniform float arch_y = 2.0;
uniform float arch_r = 0.66;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 m = vec2((UV.x - 0.5) * size_m.x, (1.0 - UV.y) * size_m.y);
	if (m.y > arch_y && length(m - vec2(0.0, arch_y)) > arch_r) {
		discard;
	}
	float t = floor(TIME * anim_fps) / anim_fps;
	// Rejilla de píxeles del cristal (como una textura de 48 x 104).
	vec2 uv = (floor(UV * vec2(48.0, 104.0)) + 0.5) / vec2(48.0, 104.0);
	vec2 p = (uv - vec2(0.5, 0.55)) * vec2(1.0, 2.2);
	float r = length(p);
	float ang = atan(p.y, p.x) + t * 0.12 + r * 1.6;
	vec2 q = vec2(cos(ang), sin(ang)) * r * 2.4;
	float n = fbm(q + vec2(t * 0.05, 0.0));
	float mist = smoothstep(0.35, 0.85, n);
	vec3 col = mix(color_deep.rgb, color_mid.rgb, mist * (0.55 + 0.25 * awake));
	// Bandas (pixel art): tres tonos.
	col = mix(col, color_light.rgb, step(0.78, n) * 0.5);
	// Estrellas que titilan.
	vec2 cell = floor(UV * vec2(48.0, 104.0));
	float h = hash(cell);
	float tw = step(0.985, h) * step(0.5, fract(h * 37.0 + t * 0.7));
	col = mix(col, vec3(1.0), tw * 0.8);
	// Brillo diagonal que cruza el cristal cada 5 s.
	float sweep = fract(t / 5.0) * 2.4 - 0.7;
	float glint = 1.0 - smoothstep(0.0, 0.05, abs(uv.x + uv.y * 0.35 - sweep));
	col += vec3(0.25) * glint;
	// Más oscuro en los bordes (el marco hace sombra).
	float arch_d = m.y > arch_y ? arch_r - length(m - vec2(0.0, arch_y)) : 1.0;
	float edge_m = min(min(m.x + size_m.x * 0.5, size_m.x * 0.5 - m.x), min(m.y, arch_d));
	float edge = smoothstep(0.0, 0.16, edge_m);
	col *= 0.55 + 0.45 * edge;
	col = mix(col, color_light.rgb * 1.6, flash);
	ALBEDO = col;
}
