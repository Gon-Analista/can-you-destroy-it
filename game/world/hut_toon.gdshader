shader_type spatial;
// Toon de la casucha del aprendiz (copia de fx/toon.gdshader): por dentro no llega la luz azul
// del cielo, así que en vez de la luz ambiente del entorno usa una propia, cálida, dentro de la
// caja de la casucha (`interior_min`..`interior_max`, en local) y la del cielo fuera.
render_mode diffuse_lambert, specular_disabled, ambient_light_disabled;

uniform vec4 albedo : source_color = vec4(1.0);
uniform bool use_vertex_color = true;
uniform float bands = 3.0;
// Cuánto aclara el borde iluminado (rim) para separar siluetas.
uniform float rim = 0.0;
uniform vec4 rim_color : source_color = vec4(1.0, 0.96, 0.85, 1.0);
uniform vec4 interior_ambient : source_color = vec4(0.42, 0.29, 0.22, 1.0);
uniform vec4 exterior_ambient : source_color = vec4(0.42, 0.5, 0.66, 1.0);
uniform vec3 interior_min = vec3(-2.35, 0.0, -2.15);
uniform vec3 interior_max = vec3(2.35, 2.75, 2.15);
// Luz del momento del día (DayNight).
global uniform vec4 world_tint;

varying vec3 local_pos;
varying vec3 local_nrm;

void vertex() {
	local_pos = VERTEX;
	local_nrm = NORMAL;
}

void fragment() {
	vec3 c = albedo.rgb;
	if (use_vertex_color) {
		// Los colores por vértice llegan en sRGB: pasarlos a lineal o todo sale lavado.
		vec3 v = COLOR.rgb;
		c *= mix(pow((v + 0.055) / 1.055, vec3(2.4)), v / 12.92, lessThan(v, vec3(0.04045)));
	}
	ALBEDO = c;
	// Cara de dentro: dentro de la caja y mirando hacia dentro (las de fuera de las paredes miran fuera).
	vec3 q = local_pos + local_nrm * 0.05;
	bool inside = all(greaterThan(q, interior_min)) && all(lessThan(q, interior_max));
	vec3 amb = inside ? interior_ambient.rgb : exterior_ambient.rgb * world_tint.rgb;
	EMISSION = c * amb;
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
