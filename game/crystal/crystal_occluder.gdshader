shader_type spatial;
// Oclusor del Cristal Madre en la capa de magia HD: no pinta nada (alfa 0 premultiplicado) pero
// escribe profundidad, para que los hechizos y destellos detrás de una pared de cristal (dentro
// de un túnel, una geoda sin abrir...) queden tapados. Se dibuja antes que la magia
// (render_priority muy baja) y metido hacia dentro `inset` metros: lo que estalla sobre la
// superficie no se recorta.
render_mode unshaded, blend_premul_alpha, depth_draw_always, cull_disabled, shadows_disabled, fog_disabled;

uniform float inset = 1.0;

void vertex() {
	VERTEX -= NORMAL * inset;
}

void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
}
