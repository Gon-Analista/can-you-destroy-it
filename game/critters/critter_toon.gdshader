shader_type spatial;
// Toon de los bichos (como fx/toon.gdshader) con lo que necesitan al reventar: un tinte por
// instancia (chamuscado, congelado, el color de la baba de cada trozo), un destello blanco y un
// brillo húmedo de banda dura para la baba.
render_mode diffuse_lambert;

uniform vec4 albedo : source_color = vec4(1.0);
uniform bool use_vertex_color = true;
uniform float bands = 3.0;
uniform float rim = 0.45;
uniform vec4 rim_color : source_color = vec4(1.0, 0.96, 0.85, 1.0);
// Luz propia: los colores saturados se leen también en la sombra.
uniform float self_light = 0.22;
// Brillo húmedo (baba): una banda de luz dura donde da el sol.
uniform float wet = 0.0;
// Tinte (rgb) y cuánto se mezcla (a).
instance uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 0.0);
instance uniform float flash = 0.0;

void fragment() {
	vec3 c = albedo.rgb;
	if (use_vertex_color) {
		// Los colores por vértice llegan en sRGB: pasarlos a lineal o todo sale lavado.
		vec3 v = COLOR.rgb;
		c *= mix(pow((v + 0.055) / 1.055, vec3(2.4)), v / 12.92, lessThan(v, vec3(0.04045)));
	}
	c = mix(c, tint.rgb, tint.a);
	ALBEDO = c;
	EMISSION = c * self_light + vec3(flash);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION;
	float q = floor(ndl * bands + 0.35) / bands;
	DIFFUSE_LIGHT += q * LIGHT_COLOR / PI;
	if (rim > 0.0) {
		float r = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		DIFFUSE_LIGHT += step(0.72, r) * step(0.2, ndl) * rim * rim_color.rgb * LIGHT_COLOR / PI;
	}
	if (wet > 0.0) {
		vec3 h = normalize(LIGHT + VIEW);
		SPECULAR_LIGHT += step(0.9, dot(NORMAL, h)) * step(0.2, ndl) * wet * LIGHT_COLOR;
	}
}
