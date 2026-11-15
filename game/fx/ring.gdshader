shader_type spatial;
// Anillo de impacto que se expande (billboard aditivo).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(0.8, 1.0, 1.0, 1.0);
uniform float progress = 0.0;
uniform float thickness = 0.12;

void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
}

void fragment() {
	float d = length(UV * 2.0 - 1.0);
	float r = progress * 0.9;
	float ring = step(abs(d - r), thickness * (1.0 - progress * 0.7));
	float fade = 1.0 - progress;
	ALBEDO = color.rgb * ring * fade;
	ALPHA = ring * fade;
}
