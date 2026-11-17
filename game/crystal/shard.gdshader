shader_type spatial;
// Fragmento de cristal: misma paleta que el Cristal Madre y un destello periódico para que
// los pedazos en el suelo "llamen" al jugador.
render_mode unshaded, cull_back;

#include "res://crystal/crystal_common.gdshaderinc"

instance uniform float glint_seed = 0.0;
instance uniform float spawn_flash = 0.0;
// 1 cuando el jugador apunta al fragmento y puede recogerlo.
instance uniform float highlight = 0.0;
// Fragmento Resonante: color de su vena (alfa 0 = fragmento normal). Late y no se apaga de noche.
instance uniform vec4 vein_glow : source_color = vec4(0.0);
uniform vec4 col_glint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
global uniform vec4 world_tint;

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
	if (highlight > 0.0) {
		// Resaltado: una banda más clara y destello que late.
		float pulse = 0.5 + 0.5 * sin(TIME * 10.0);
		c = mix(c, col_highlight.rgb, 0.35 + 0.25 * pulse);
	}
	// De noche se oscurecen pero conservan un poco de brillo propio (se ven en la hierba).
	vec3 tint = mix(world_tint.rgb, vec3(1.0), 0.35);
	if (vein_glow.a > 0.0) {
		// Resonante: el cuerpo toma el color de la vena por bandas y un latido sube por él.
		float beat = step(0.5, fract(TIME * 1.6 + glint_seed));
		vec3 vc = vein_glow.rgb;
		vec3 band = level > 0.64 ? mix(vc, vec3(1.0), 0.3) : (level > 0.44 ? vc : vc * 0.55);
		float rise = step(fract(world_pos.y * 2.2 - TIME * 1.8 + glint_seed), 0.18);
		c = mix(band, vec3(1.0), max(rise * 0.35, beat * 0.1));
		c = mix(c, col_glint.rgb, max(glint, spawn_flash));
		tint = vec3(1.0);
	}
	ALBEDO = c * tint;
}
