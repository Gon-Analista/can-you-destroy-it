// Paleta y bandas compartidas por el Cristal Madre y sus fragmentos.
uniform vec3 sun_dir = vec3(0.55, -0.65, -0.52);
uniform vec4 col_highlight : source_color = vec4(0.91, 0.99, 1.0, 1.0);
uniform vec4 col_light : source_color = vec4(0.647, 0.855, 0.898, 1.0);
uniform vec4 col_mid : source_color = vec4(0.271, 0.561, 0.722, 1.0);
uniform vec4 col_dark : source_color = vec4(0.157, 0.294, 0.525, 1.0);
uniform vec4 col_core : source_color = vec4(0.235, 0.137, 0.42, 1.0);

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

// Color del cristal en bandas de paleta según la orientación de la faceta.
vec3 crystal_bands(vec3 n, vec3 view_dir, out float level) {
	vec3 L = normalize(-sun_dir);
	float facet = hash13(floor(n * 6.0 + 0.5) * 7.13);
	level = dot(n, L) * 0.5 + 0.5 + (facet - 0.5) * 0.3;
	vec3 c;
	if (level > 0.84) {
		c = col_highlight.rgb;
	} else if (level > 0.64) {
		c = col_light.rgb;
	} else if (level > 0.44) {
		c = col_mid.rgb;
	} else {
		c = col_dark.rgb;
	}
	// Borde de silueta: el cristal "brilla" en los contornos, como en la referencia.
	float fres = 1.0 - clamp(dot(n, view_dir), 0.0, 1.0);
	c = mix(c, col_light.rgb, step(0.9, fres) * 0.55);
	return c;
}
