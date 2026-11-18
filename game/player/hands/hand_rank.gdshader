shader_type canvas_item;
// Las manos del mago cambian con su rango (ver HandRankStyle y RankDef): la gema del brazalete
// cambia de color, la manga gana un ribete de oro bajo el brazalete, runas que brillan en el puño y
// otra tela. Se reconoce cada parte por los colores de la paleta del sprite de Sprite AI (gema
// azul, manga violeta plana) y por la altura dentro del cuadro (192 px): todo a píxel de textura.
// Al subir de rango (`flash`), una línea de luz sube por la manga y la gema destella.

uniform vec4 gem_color : source_color = vec4(0.18, 0.59, 0.89, 1.0);
uniform vec4 trim_color : source_color = vec4(0.0);
uniform vec4 rune_color : source_color = vec4(0.0);
uniform vec4 sleeve_color : source_color = vec4(1.0);
uniform float prismatic = 0.0;
uniform float flash = 0.0;
// Animación escalonada como el resto del pixel art.
uniform float anim_fps = 12.0;

const vec3 SLEEVE = vec3(61.0, 2.0, 46.0) / 255.0;
const float FRAME = 192.0;
// La manga empieza bajo el brazalete; arriba hay líneas de la mano con el mismo color.
const float SLEEVE_TOP = 124.0;
const float GEM_TOP = 100.0;

varying vec4 v_mod;

void vertex() {
	v_mod = COLOR;
}

bool is_gold(vec4 c) {
	return c.a > 0.5 && c.r > 0.3 && c.r > c.b * 3.0 && c.g > c.b * 1.5;
}

bool is_sleeve(vec4 c, float y) {
	return c.a > 0.5 && y > SLEEVE_TOP && distance(c.rgb, SLEEVE) < 0.08;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453);
}

vec3 hue(float h) {
	return clamp(abs(fract(h + vec3(0.0, 2.0, 1.0) / 3.0) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
}

void fragment() {
	vec2 texel = floor(UV / TEXTURE_PIXEL_SIZE);
	vec2 local = vec2(mod(texel.x, FRAME), texel.y);
	float t = floor(TIME * anim_fps) / anim_fps;
	vec4 c = texture(TEXTURE, UV);
	vec3 rgb = c.rgb;
	bool gem = c.a > 0.5 && local.y > GEM_TOP && c.b > c.r + 0.25 && c.b > c.g;
	if (gem) {
		float lum = dot(c.rgb, vec3(0.3, 0.5, 0.2));
		vec3 tint = gem_color.rgb;
		if (prismatic > 0.5) {
			tint = mix(hue(t * 0.25 + local.y * 0.04), vec3(1.0), 0.35);
		}
		// Sombra, medio y brillo de la gema original (tres tonos), con el color nuevo.
		rgb = lum < 0.42 ? tint * 0.55 : (lum < 0.65 ? tint : mix(tint, vec3(1.0), 0.6));
		rgb = mix(rgb, vec3(1.0), flash * 0.8);
	} else if (is_sleeve(c, local.y)) {
		// Tela nueva (blanco = la de siempre).
		rgb = sleeve_color.r > 0.99 && sleeve_color.g > 0.99 ? SLEEVE : sleeve_color.rgb;
		vec2 px = TEXTURE_PIXEL_SIZE;
		// Ribete en las dos primeras filas de manga bajo el brazalete: por encima, tras la línea
		// negra, tiene que haber oro (así no sale bajo los pliegues de la manga).
		int run = 0;
		for (int i = 1; i <= 2; i++) {
			vec4 up = texture(TEXTURE, UV - vec2(0.0, px.y * float(i)));
			if (!is_sleeve(up, local.y - float(i)) || run < i - 1) {
				break;
			}
			run = i;
		}
		bool gold_above = false;
		for (int i = 1; i <= 6; i++) {
			vec4 up = texture(TEXTURE, UV - vec2(0.0, px.y * float(run + i)));
			gold_above = gold_above || is_gold(up);
		}
		bool top = run == 0 && gold_above;
		bool second = run == 1 && gold_above;
		if ((top || second) && trim_color.a > 0.0) {
			// Ribete de dos píxeles: claro arriba, oscuro abajo.
			rgb = top ? trim_color.rgb : trim_color.rgb * 0.62;
		} else if (rune_color.a > 0.0) {
			// Runas en el puño: un glifo de 3 x 4 por celda de 5 x 6 (bits del hash de la celda).
			vec2 cell = floor(local / vec2(5.0, 6.0));
			vec2 in_cell = local - cell * vec2(5.0, 6.0);
			float band = local.y - SLEEVE_TOP;
			if (band > 22.0 && band < 52.0 && in_cell.x >= 1.0 && in_cell.x <= 3.0
					&& in_cell.y >= 1.0 && in_cell.y <= 4.0) {
				float bit = (in_cell.y - 1.0) * 3.0 + (in_cell.x - 1.0);
				float h = hash(cell);
				float on = step(0.5, fract(h * exp2(bit + 1.0))) * step(0.35, hash(cell + 7.0));
				float pulse = 0.65 + 0.35 * sin(t * 2.5 + cell.x * 1.7 + cell.y * 0.9);
				rgb = mix(rgb, rune_color.rgb * pulse, on * rune_color.a);
			}
		}
		// La luz de la subida de rango recorre la manga de abajo arriba.
		float sweep = SLEEVE_TOP - 20.0 + flash * (FRAME - SLEEVE_TOP + 20.0);
		float line = 1.0 - smoothstep(0.0, 4.0, abs(local.y - sweep));
		rgb = mix(rgb, vec3(1.0), line * step(0.01, flash) * 0.85);
		rgb = mix(rgb, mix(trim_color.rgb, vec3(1.0), 0.5), flash * 0.25);
	}
	COLOR = vec4(rgb, c.a) * v_mod;
}
