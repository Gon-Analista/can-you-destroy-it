shader_type spatial;
// Guía de objetivos en la capa de magia HD (GuideTrail):
// - mode 0: destello del suelo, estrella de 4 puntas con halo (billboard completo);
// - mode 1: columna de luz sobre el objetivo, de cara a la cámara pero siempre vertical, con
//   bandas que suben.
// Alfa premultiplicado: el centro tapa un poco (se lee sobre la hierba clara y el cielo) y el
// halo suma luz. Respeta la profundidad (el cristal la tapa con sus oclusores).
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

#include "res://fx/hd/hd_noise.gdshaderinc"

uniform int mode = 0;
uniform float intensity = 1.6;
instance uniform vec4 tint : source_color = vec4(1.0, 0.82, 0.48, 1.0);
instance uniform float fade = 1.0;
instance uniform float seed = 0.0;

void vertex() {
	if (mode == 1) {
		// De cara a la cámara pero siempre vertical (gira sólo alrededor de Y).
		vec3 origin = MODEL_MATRIX[3].xyz;
		vec3 cam = INV_VIEW_MATRIX[3].xyz;
		vec3 to_cam = vec3(cam.x - origin.x, 0.0, cam.z - origin.z);
		to_cam = length(to_cam) > 0.001 ? normalize(to_cam) : vec3(0.0, 0.0, 1.0);
		vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam));
		float w = length(MODEL_MATRIX[0].xyz);
		float h = length(MODEL_MATRIX[1].xyz);
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			vec4(right * w, 0.0), vec4(0.0, h, 0.0, 0.0), vec4(to_cam, 0.0), vec4(origin, 1.0));
	} else {
		HD_BILLBOARD
	}
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	vec3 col = tint.rgb;
	float glow;
	float core;
	if (mode == 1) {
		// Columna: fuerte abajo, se apaga hacia arriba; bandas que suben despacio.
		float across = pow(clamp(1.0 - abs(p.x), 0.0, 1.0), 2.2);
		float up = 1.0 - UV.y;
		float height = pow(1.0 - up, 1.6) * smoothstep(0.0, 0.06, 1.0 - up);
		float bands = 0.65 + 0.35 * sin(up * 26.0 - TIME * 3.2 + seed);
		float n = hd_noise(vec3(p.x * 3.0, up * 6.0 - TIME * 0.9, seed));
		glow = across * height * bands * (0.7 + 0.6 * n);
		core = pow(clamp(1.0 - abs(p.x) * 3.0, 0.0, 1.0), 2.0) * height * 0.35;
	} else {
		// Destello: halo redondo + cruz de 4 puntas que titila.
		float r = length(p);
		float halo = pow(clamp(1.0 - r, 0.0, 1.0), 2.6);
		float tw = 0.75 + 0.25 * sin(TIME * 9.0 + seed * 6.28);
		float cross_x = pow(clamp(1.0 - abs(p.y) * 9.0, 0.0, 1.0), 2.0) * (1.0 - abs(p.x));
		float cross_y = pow(clamp(1.0 - abs(p.x) * 9.0, 0.0, 1.0), 2.0) * (1.0 - abs(p.y));
		glow = halo * 0.7 + (cross_x + cross_y) * tw;
		core = smoothstep(0.32, 0.0, r);
	}
	float a = clamp(core * fade, 0.0, 1.0) * 0.55;
	vec3 lit = mix(col, vec3(1.0), clamp(core, 0.0, 1.0) * 0.6);
	ALBEDO = lit * (glow * intensity * fade) + lit * a;
	ALPHA = a;
}
