// Ruido suave para los efectos HD (valor 3D + fbm). Barato: 4 octavas.
float hd_hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float hd_noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hd_hash(i + vec3(0, 0, 0)), hd_hash(i + vec3(1, 0, 0)), f.x),
			mix(hd_hash(i + vec3(0, 1, 0)), hd_hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hd_hash(i + vec3(0, 0, 1)), hd_hash(i + vec3(1, 0, 1)), f.x),
			mix(hd_hash(i + vec3(0, 1, 1)), hd_hash(i + vec3(1, 1, 1)), f.x), f.y),
		f.z);
}

float hd_fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * hd_noise(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return v;
}

// Billboard: el quad siempre de cara a la cámara conservando la escala del nodo.
#define HD_BILLBOARD float hd_s = length(MODEL_MATRIX[0].xyz); MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * hd_s, INV_VIEW_MATRIX[1] * hd_s, INV_VIEW_MATRIX[2] * hd_s, MODEL_MATRIX[3]);

// Tras HD_BILLBOARD: 0 cuando la cámara está metida en el quad y 1 cuando está a `hi` tamaños
// del quad o más. Pegados a la cámara, los efectos se apagan en vez de
// cubrir toda la pantalla. El shader declara `varying float hd_near;`.
#define HD_NEAR_FADE(lo, hi) hd_near = smoothstep(lo, hi, length(MODELVIEW_MATRIX[3].xyz) / max(hd_s, 0.0001));
