shader_type spatial;
// Nubes 3D (CrystalClouds): sin luz del motor, como las del cielo (sky.gdshader). El color de cada
// cara viene por vértice (luz arriba, sombra lavanda abajo) y lo tiñe la hora del día.
render_mode unshaded, specular_disabled;

// Luz del momento del día (DayNight).
global uniform vec4 world_tint;

void fragment() {
	// Los colores por vértice llegan en sRGB: pasarlos a lineal o todo sale lavado.
	vec3 v = COLOR.rgb;
	vec3 c = mix(pow((v + 0.055) / 1.055, vec3(2.4)), v / 12.92, lessThan(v, vec3(0.04045)));
	ALBEDO = c * world_tint.rgb;
}
