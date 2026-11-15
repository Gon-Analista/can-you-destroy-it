shader_type sky;
// Cielo pixel art: degradado en bandas con tramado (dither) ordenado y nubes de 3 tonos.

uniform vec4 top_color : source_color = vec4(0.16, 0.33, 0.78, 1.0);
uniform vec4 mid_color : source_color = vec4(0.224, 0.471, 0.855, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.655, 0.796, 0.827, 1.0);
uniform vec4 cloud_light : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 cloud_mid : source_color = vec4(0.86, 0.9, 0.98, 1.0);
uniform vec4 cloud_shadow : source_color = vec4(0.66, 0.67, 0.82, 1.0);
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform float cloud_cover = 0.52;
uniform float cloud_speed = 0.004;

float bayer4(vec2 p) {
	ivec2 i = ivec2(mod(p, 4.0));
	int idx = i.x + i.y * 4;
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[idx]) + 0.5) / 16.0;
}

void sky() {
	vec3 d = EYEDIR;
	float h = clamp(d.y, 0.0, 1.0);
	float dither = AT_CUBEMAP_PASS ? 0.5 : bayer4(FRAGCOORD.xy);
	float steps = 9.0;
	float g = floor(pow(h, 0.55) * steps + dither) / steps;
	vec3 col = mix(horizon_color.rgb, mid_color.rgb, smoothstep(0.0, 0.45, g));
	col = mix(col, top_color.rgb, smoothstep(0.45, 1.0, g));

	if (d.y > 0.0) {
		vec2 uv = d.xz / (d.y + 0.12) * 0.05 + vec2(TIME * cloud_speed, TIME * cloud_speed * 0.3);
		float n = texture(cloud_noise, uv).r * 0.7 + texture(cloud_noise, uv * 2.7 + 0.31).r * 0.3;
		// Más nubes cerca del horizonte, como en la referencia.
		float cover = cloud_cover - (1.0 - h) * 0.12;
		float shade = texture(cloud_noise, uv + vec2(0.0, -0.012)).r;
		if (n > cover) {
			vec3 cc = cloud_light.rgb;
			if (shade < n - 0.025) {
				cc = cloud_mid.rgb;
			}
			if (n < cover + 0.03 || shade < n - 0.06) {
				cc = cloud_shadow.rgb;
			}
			col = mix(col, cc, step(0.02, h));
		}
	}
	if (d.y < 0.0) {
		col = horizon_color.rgb;
	}
	COLOR = col;
}
