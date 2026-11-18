shader_type spatial;
// Halo de luz HD: brillo radial suave que se suma con rayos opcionales. Alfa premultiplicado
// con ALPHA = 0: suma luz sin tapar el fondo (la capa de magia se compone premultiplicada).
// `cover` > 0 tiñe en vez de sumar: sobre el cristal o el cielo claros, sumar naranja lo lava a
// blanco; tapando el fondo en proporción, el halo se ve del color del fuego.
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

#include "res://fx/hd/hd_noise.gdshaderinc"

uniform vec4 color : source_color = vec4(1.0, 0.6, 0.25, 1.0);
uniform float intensity = 1.0;
uniform float falloff = 2.2;
// Rayos de luz (0 = sin rayos).
uniform float rays = 0.0;
uniform float ray_count = 6.0;
uniform float seed = 0.0;
uniform float cover = 0.0;

varying float hd_near;

void vertex() {
	HD_BILLBOARD
	HD_NEAR_FADE(0.25, 0.6)
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float g = pow(clamp(1.0 - r, 0.0, 1.0), falloff);
	if (rays > 0.0) {
		float a = atan(p.y, p.x);
		float rr = pow(abs(sin(a * ray_count * 0.5 + seed + TIME * 0.6)), 24.0);
		rr += pow(abs(sin(a * ray_count * 0.5 * 1.7 - seed * 2.0 - TIME * 0.4)), 40.0) * 0.6;
		g += rr * rays * clamp(1.0 - r, 0.0, 1.0);
	}
	float e = g * intensity * hd_near;
	ALBEDO = color.rgb * e;
	ALPHA = clamp(e * cover, 0.0, 1.0);
}
