shader_type sky;
// Cielo pixel art: degradado en bandas con tramado (dither) ordenado, nubes de 3 tonos, sol y
// luna de píxeles y estrellas que titilan de noche. Los colores los mueve DayNight.

uniform vec4 top_color : source_color = vec4(0.16, 0.33, 0.78, 1.0);
uniform vec4 mid_color : source_color = vec4(0.224, 0.471, 0.855, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.655, 0.796, 0.827, 1.0);
uniform vec4 cloud_light : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 cloud_mid : source_color = vec4(0.86, 0.9, 0.98, 1.0);
uniform vec4 cloud_shadow : source_color = vec4(0.66, 0.67, 0.82, 1.0);
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform float cloud_cover = 0.52;
uniform float cloud_speed = 0.004;
// Hacia dónde están el sol y la luna (dirección desde la cámara).
uniform vec3 sun_dir = vec3(0.3, 0.6, -0.7);
uniform vec4 sun_color : source_color = vec4(1.0, 0.95, 0.75, 1.0);
uniform vec3 moon_dir = vec3(-0.3, -0.6, 0.7);
uniform vec4 moon_color : source_color = vec4(0.85, 0.9, 1.0, 1.0);
// 0..1: estrellas visibles (noche).
uniform float stars = 0.0;
// Tinte de las nubes (anaranjadas al atardecer, azuladas de noche).
uniform vec4 cloud_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// 0..1: auroras de maná (de noche, crecen con el Pilón; ver ValleyMilestones y DayNight).
uniform float aurora = 0.0;
uniform vec4 aurora_low : source_color = vec4(0.36, 1.0, 0.82, 1.0);
uniform vec4 aurora_mid : source_color = vec4(0.78, 0.55, 1.0, 1.0);
uniform vec4 aurora_high : source_color = vec4(1.0, 0.48, 0.85, 1.0);

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

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

	// Estrellas: celdas en la esfera; alguna titila (a saltos, como pixel art).
	if (stars > 0.01 && d.y > 0.0) {
		vec3 cell = floor(d * 140.0);
		float hs = hash13(cell);
		if (hs > 0.992) {
			float tw = step(0.35, fract(hs * 91.7 + floor(TIME * 2.0) * 0.37));
			vec3 sc = mix(vec3(1.0, 0.95, 0.8), vec3(0.75, 0.85, 1.0), fract(hs * 13.1));
			col = mix(col, sc * 1.3, stars * tw * smoothstep(0.02, 0.2, d.y));
		}
	}
	// Auroras de maná: cortinas onduladas, verde y cian abajo, violeta y rosa arriba, con rayos
	// verticales; se mueven a saltos y se tiñen por bandas con tramado (pixel art).
	if (aurora > 0.01 && d.y > 0.02) {
		float az = atan(d.x, d.z);
		float tt = floor(TIME * 6.0) / 6.0;
		float center = 0.3 + 0.07 * sin(az * 3.0 + tt * 0.12) + 0.035 * sin(az * 7.0 - tt * 0.21);
		float dist = d.y - center;
		float curtain = smoothstep(-0.035, 0.0, dist) * (1.0 - smoothstep(0.0, 0.24, dist));
		float rays = 0.5 + 0.5 * sin(az * 55.0 + sin(az * 9.0 + tt * 0.35) * 3.0);
		rays *= 0.65 + 0.35 * sin(az * 21.0 - tt * 0.5);
		vec2 flat_dir = normalize(d.xz + vec2(1e-4));
		// Más intensas hacia el norte (detrás del cristal), tenues alrededor.
		float side = 0.35 + 0.65 * smoothstep(-0.3, 0.8, -flat_dir.y);
		float a = curtain * (0.35 + 0.65 * rays) * side * aurora;
		float k = clamp(dist / 0.24, 0.0, 1.0);
		vec3 ac = mix(aurora_low.rgb, aurora_mid.rgb, smoothstep(0.05, 0.5, k));
		ac = mix(ac, aurora_high.rgb, smoothstep(0.5, 1.0, k));
		float q = floor(a * 4.0 + dither) / 4.0;
		col = mix(col, ac * 1.15, clamp(q, 0.0, 0.8));
	}
	// Sol y luna: discos de píxeles con un halo en bandas.
	float sd = dot(d, normalize(sun_dir));
	if (sd > 0.9985) {
		col = sun_color.rgb * 1.6;
	} else if (sd > 0.996) {
		col = mix(col, sun_color.rgb, 0.45);
	} else if (sd > 0.985) {
		col = mix(col, sun_color.rgb, 0.12);
	}
	float md = dot(d, normalize(moon_dir));
	if (md > 0.9988) {
		col = moon_color.rgb * 1.2;
	} else if (md > 0.996) {
		col = mix(col, moon_color.rgb, 0.15);
	}

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
			col = mix(col, cc * cloud_tint.rgb, step(0.02, h));
		}
	}
	if (d.y < 0.0) {
		col = horizon_color.rgb;
	}
	COLOR = col;
}
