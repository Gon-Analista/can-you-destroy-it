shader_type spatial;
// Fragmento de cristal: misma paleta que el Cristal Madre y un destello periódico para que
// los pedazos en el suelo "llamen" al jugador.
render_mode unshaded, cull_back;

#include "res://crystal/crystal_common.gdshaderinc"

instance uniform float glint_seed = 0.0;
instance uniform float spawn_flash = 0.0;
uniform vec4 col_glint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

varying vec3 world_nrm;
varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(world_nrm);
	vec3 v = normalize(CAMERA_POSITION_WORLD - world_pos);
	float level;
	// Los fragmentos se ven pequeños: se aclaran una banda para que se lean sobre la hierba.
	vec3 c = crystal_bands(n, v, level);
	if (level <= 0.44) {
		c = col_mid.rgb;
	}
	float cycle = fract(TIME * 0.35 + glint_seed);
	float glint = step(cycle, 0.035) * step(0.5, level);
	c = mix(c, col_glint.rgb, max(glint, spawn_flash));
	ALBEDO = c;
}
