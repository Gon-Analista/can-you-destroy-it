shader_type spatial;
// Iluminación por bandas (toon) para todo el mundo low-poly. Colores por vértice opcionales.
render_mode diffuse_lambert, specular_disabled;

uniform vec4 albedo : source_color = vec4(1.0);
uniform bool use_vertex_color = true;
uniform float bands = 3.0;
// Cuánto aclara el borde iluminado (rim) para separar siluetas.
uniform float rim = 0.0;
uniform vec4 rim_color : source_color = vec4(1.0, 0.96, 0.85, 1.0);
// Luz propia (0 = nada): las criaturas mágicas (familiares) conservan su color en la sombra.
uniform float self_light = 0.0;

void fragment() {
	vec3 c = albedo.rgb;
	if (use_vertex_color) {
		// Los colores por vértice llegan en sRGB: pasarlos a lineal o todo sale lavado.
		vec3 v = COLOR.rgb;
		c *= mix(pow((v + 0.055) / 1.055, vec3(2.4)), v / 12.92, lessThan(v, vec3(0.04045)));
	}
	ALBEDO = c;
	EMISSION = c * self_light;
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
}
