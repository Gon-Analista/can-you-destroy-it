shader_type spatial;
// Estela de un hechizo en vuelo: cinta orientada a la cámara con bandas de color duras
// (rampa con interpolación constante) que se encoge y se trama hacia la cola. Píxeles sólidos
// (blend_mix), como el núcleo de `SpellOrb`: lo aditivo se perdería contra el cielo y el cristal.
// UV.x = edad (0 cabeza, 1 cola); UV.y = través de la cinta.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform sampler2D ramp : source_color, filter_nearest, repeat_disable;
uniform float anim_fps = 12.0;
uniform float seed = 0.0;
// Cuánto "lame" el fuego los bordes (ruido que deforma las bandas).
uniform float flicker = 0.22;
// 0..1: la estela se apaga tramando (al llegar el proyectil).
uniform float fade = 0.0;

float bayer4(vec2 frag) {
	ivec2 p = ivec2(mod(frag, 4.0));
	int i = p.x + p.y * 4;
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i]) + 0.5) / 16.0;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	float t = floor(TIME * anim_fps) / anim_fps + seed;
	float age = UV.x;
	float across = abs(UV.y * 2.0 - 1.0);
	// Lenguas de fuego: ruido que corre hacia la cola.
	float n = noise(vec2(age * 9.0 - t * 7.0, UV.y * 3.0 + seed * 5.0));
	// La cinta se estrecha hacia la cola (el ancho real lo da la malla; aquí se recorta).
	float body = 1.0 - age * 0.85;
	if (across > body + (n - 0.5) * flicker) {
		discard;
	}
	// Banda: el centro de la cabeza es el más caliente; lejos del eje y hacia la cola, más frío.
	float v = across * 0.55 + age * 0.75 + (n - 0.5) * flicker;
	vec4 c = texture(ramp, vec2(clamp(v, 0.0, 1.0), 0.5));
	float alpha = c.a * (1.0 - fade);
	if (alpha < 0.98) {
		alpha = step(bayer4(FRAGCOORD.xy), alpha);
	}
	if (alpha < 0.5) {
		discard;
	}
	ALBEDO = c.rgb;
	ALPHA = 1.0;
}
