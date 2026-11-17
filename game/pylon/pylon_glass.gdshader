shader_type spatial;
// Maná líquido dentro del Pilón: por debajo de `fill` se ve en bandas (superficie brillante que
// ondula, rosa, violeta y fondo profundo) con remolinos que suben y burbujas; por encima no se
// dibuja nada (el vidrio es otra malla, transparente). Animación a 12 fps.
render_mode unshaded, cull_back;

uniform float height = 5.0;
// 0..1 de la altura del vidrio.
uniform float fill = 0.05;
// Agitación de la superficie (sube al entregar y se calma).
uniform float wave = 0.0;
// Brillo extra momentáneo al recibir maná.
uniform float pulse = 0.0;
uniform vec4 c_surface : source_color = vec4(0.79, 0.96, 1.0, 1.0);
uniform vec4 c_top : source_color = vec4(1.0, 0.48, 0.85, 1.0);
uniform vec4 c_mid : source_color = vec4(0.78, 0.61, 1.0, 1.0);
uniform vec4 c_deep : source_color = vec4(0.4, 0.31, 0.68, 1.0);
uniform vec4 c_glass : source_color = vec4(0.65, 0.85, 0.9, 1.0);

varying vec3 local_pos;

void vertex() {
	// El cilindro va centrado en su origen: y = 0 pasa a ser la base del vidrio.
	local_pos = VERTEX + vec3(0.0, height * 0.5, 0.0);
}

float bayer4(vec2 frag) {
	ivec2 p = ivec2(mod(frag, 4.0));
	int i = p.x + p.y * 4;
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i]) + 0.5) / 16.0;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float t = floor(TIME * 12.0) / 12.0;
	float y = local_pos.y / height;
	float ang = atan(local_pos.z, local_pos.x);
	float surf = fill + (sin(ang * 3.0 + t * 4.0) * 0.006 + sin(ang * 5.0 - t * 2.7) * 0.004) * (1.0 + wave * 5.0);
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	if (y < surf) {
		float d = (surf - y) * height;
		vec3 col = c_deep.rgb;
		if (d < 0.07) {
			col = c_surface.rgb * 1.6;
		} else if (d < 0.35) {
			col = c_top.rgb;
		} else if (d < 1.1) {
			col = c_mid.rgb;
		}
		// Remolinos que suben en espiral.
		float swirl = fract(ang / TAU * 3.0 + y * height * 0.35 - t * 0.25);
		if (swirl < 0.12 && d > 0.07) {
			col = mix(col, c_surface.rgb, 0.55);
		}
		// Burbujas: celdas que suben.
		vec2 cell = vec2(floor(ang / TAU * 24.0), floor(y * height * 6.0 - t * 4.0));
		if (hash(cell) > 0.93 && d > 0.15) {
			col = c_surface.rgb * 1.3;
		}
		col *= 1.0 + pulse * 0.6 + rim * 0.25;
		ALBEDO = col;
	} else {
		discard;
	}
}
