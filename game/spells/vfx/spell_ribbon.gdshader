shader_type spatial;
// Cinta orbital: anillo de malla que siempre mira a la cámara y dibuja "cometas" que recorren la
// órbita. Cabeza blanca, cuerpo del color de la cinta y cola tramada, en bandas duras.
// Al pasar por detrás de las manos o del cristal, la profundidad la oculta (da volumen 3D).
// Se dibuja en dos pasadas: la mitad trasera antes del núcleo y la delantera después, así la
// órbita rodea el núcleo de verdad (`front`). Píxeles sólidos, sin mezcla aditiva.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(0.78, 0.6, 1.0, 1.0);
uniform vec4 head_color = vec4(1.6, 1.6, 1.7, 1.0);
uniform float hdr = 1.0;
uniform float dashes = 2.0;
uniform float tail = 0.42;
// Vueltas por segundo.
uniform float speed = 0.55;
// Grosor en metros (se compensa la escala del nodo).
uniform float width = 0.0045;
uniform float phase = 0.0;
uniform float anim_fps = 12.0;
uniform float fade = 1.0;
// false: sólo la mitad de la órbita detrás del centro del orbe; true: sólo la de delante.
uniform bool front = false;

varying float depth_vs_center;

void vertex() {
	// VERTEX es el punto de la órbita y NORMAL su tangente (ver SpellOrb._build_ring_mesh).
	vec3 cam = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	vec3 to_cam = normalize(cam - VERTEX);
	vec3 side = normalize(cross(NORMAL, to_cam));
	float s = length(MODEL_MATRIX[0].xyz);
	VERTEX += side * (UV.y * 2.0 - 1.0) * width * 0.5 / s;
	// > 0: más cerca de la cámara que el centro del orbe (el origen del anillo).
	depth_vs_center = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z - NODE_POSITION_VIEW.z;
}

float bayer4(vec2 frag) {
	ivec2 p = ivec2(mod(frag, 4.0));
	int i = p.x + p.y * 4;
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i]) + 0.5) / 16.0;
}

void fragment() {
	if ((depth_vs_center > 0.0) != front) {
		discard;
	}
	float t = floor(TIME * anim_fps) / anim_fps;
	float u = fract(UV.x * dashes - t * speed * dashes + phase);
	// k: 1 en la cabeza del cometa, 0 al final de la cola.
	float k = (u - (1.0 - tail)) / tail;
	if (k <= 0.0) {
		discard;
	}
	// La cola se estrecha: 1 píxel menos de grosor hacia el final.
	float across = abs(UV.y * 2.0 - 1.0);
	if (across > 0.35 + k) {
		discard;
	}
	vec3 c;
	float a = 1.0;
	if (k > 0.9) {
		c = head_color.rgb;
	} else if (k > 0.6) {
		c = mix(color.rgb, vec3(1.0), 0.45) * hdr;
	} else if (k > 0.3) {
		c = color.rgb;
	} else {
		c = color.rgb * 0.8;
		a = step(bayer4(FRAGCOORD.xy), k * 3.0);
	}
	a *= step(bayer4(FRAGCOORD.xy + 1.0), fade);
	if (a < 0.5) {
		discard;
	}
	ALBEDO = c;
	ALPHA = 1.0;
}
