shader_type spatial;
// Lágrima del Núcleo (GDD 6.1): cristal violeta casi negro, en pixel art (mundo a 640x360).
// Facetas con luz por bandas desde arriba a la izquierda, borde violeta que brilla de cara a la
// cámara y un corazón dentro que late (`beat`, 0..1, lo mueve CoreTears). `highlight` al apuntarla.
// Normales y vista en el mundo (como shard.gdshader): sin descartar caras, NORMAL llega girada en
// las caras traseras según el orden de los vértices.
render_mode unshaded, cull_disabled, shadows_disabled;

uniform vec3 col_deep : source_color = vec3(0.07, 0.02, 0.13);
uniform vec3 col_body : source_color = vec3(0.2, 0.07, 0.36);
uniform vec3 col_light : source_color = vec3(0.48, 0.25, 0.82);
uniform vec3 col_rim : source_color = vec3(0.86, 0.6, 1.0);
uniform vec3 col_heart : source_color = vec3(1.0, 0.48, 0.85);

instance uniform float beat = 0.0;
instance uniform float highlight = 0.0;
instance uniform float flash = 0.0;

varying vec3 world_nrm;
varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(world_nrm);
	vec3 v = normalize(CAMERA_POSITION_WORLD - world_pos);
	// Luz fija desde arriba a la izquierda (como el Cristal Madre), en 3 bandas.
	vec3 l = normalize(vec3(-0.55, 0.8, 0.25));
	float d = dot(n, l) * 0.5 + 0.5;
	vec3 c = col_deep;
	c = mix(c, col_body, step(0.45, d));
	c = mix(c, col_light, step(0.8, d));
	// El corazón: brilla desde dentro en las facetas que miran a la cámara, más con cada latido.
	float facing = abs(dot(n, v));
	c = mix(c, col_heart, step(0.985, facing) * beat);
	// Borde: el contorno de la lágrima se enciende con el latido (un escalón, sin degradado).
	float rim = step(facing, 0.38);
	c = mix(c, col_rim, rim * (0.35 + beat * 0.65));
	// Apuntada: el borde parpadea en blanco (no todo el cuerpo: tiene que seguir leyéndose oscura).
	float blink = step(0.5, fract(TIME * 3.0));
	c = mix(c, vec3(1.0), rim * highlight * blink);
	c = mix(c, vec3(1.0, 0.9, 1.0), flash);
	ALBEDO = c;
}
