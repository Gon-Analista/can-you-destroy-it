shader_type spatial;
// Columna de luz de la subida de rango (capa de magia HD), vista desde dentro: el mago está en su
// centro. En vez de una pared de luz (taparía la pantalla), haces finos que suben alrededor con
// bandas de maná, más intensos abajo y que se pierden hacia el cielo. Suma luz (alfa 0
// premultiplicado) y respeta la profundidad (dev guidelines 5.4).
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(0.8, 0.6, 1.0, 1.0);
uniform vec4 color_hot : source_color = vec4(1.0, 0.95, 1.0, 1.0);
uniform float intensity = 0.0;
// 0..1: lo alto que ha subido la luz.
uniform float reach = 1.0;
uniform float rays = 28.0;
// Altura de la columna (m), para medir de la base a la punta.
uniform float height = 90.0;

varying float v_h;
varying vec2 v_xz;

void vertex() {
	v_h = VERTEX.y / height + 0.5;
	v_xz = VERTEX.xz;
}

float hash(float n) {
	return fract(sin(n * 91.7) * 43758.5453);
}

void fragment() {
	float h = clamp(v_h, 0.0, 1.0);
	// La vuelta se mide aquí (por vértice, la cara de la costura interpolaría de 1 a 0).
	float v_around = atan(v_xz.y, v_xz.x) / TAU + 0.5;
	float cell = floor(v_around * rays);
	float f = fract(v_around * rays);
	float r = hash(cell);
	// Cada haz con su ancho y su brillo; algunos huecos para que se vea el valle entre ellos.
	float width = mix(0.12, 0.45, r);
	float beam = 1.0 - smoothstep(width * 0.5, width * 0.5 + 0.08, abs(f - 0.5));
	beam *= step(0.25, r);
	// Bandas que suben a distinta velocidad por haz.
	float bands = 0.6 + 0.4 * step(0.5, fract(h * 9.0 - TIME * (1.2 + r * 1.4) + r * 3.0));
	float rise = 1.0 - smoothstep(reach - 0.06, reach, h);
	float fade = pow(1.0 - h, 1.6) * rise;
	float base = 1.0 + 1.5 * (1.0 - smoothstep(0.0, 0.04, h));
	// Color del rango; sólo el pie de cada haz se acerca al blanco.
	vec3 c = mix(color.rgb, color_hot.rgb, (1.0 - smoothstep(0.0, 0.08, h)) * 0.7);
	ALBEDO = c * beam * bands * fade * base * intensity;
	ALPHA = 0.0;
}
