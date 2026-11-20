class_name ValleyPalette
extends RefCounted
## Paletas del valle para probar (y elegir) una luz de día que no canse la vista.
## Cada paleta cambia tres cosas, todas sin tocar los assets:
## - Los fotogramas de día del ciclo (cielo, sol, ambiente, niebla y tinte del cristal) en `day`:
##   un diccionario hora -> [columna de DayNight.KEYS, valor] que pisa a la original.
## - El ajuste del entorno (`sat`, `contrast`, `bright`).
## - Un etalonaje global con una LUT 3D generada aquí (`grade`): satura menos los colores más
##   chillones, gira el verde hacia azulado u oliva, tiñe sombras y luces y comprime los blancos.
##   Así la hierba neón y el camino naranja bajan sin repintar cada material.
## `actual` deja el juego como estaba.

const LUT_SIZE: int = 33

const PALETTES: Dictionary = {
	&"actual": {},
	# Suave: lo mismo de siempre con menos volumen. Menos sol, cielo menos eléctrico, verdes y
	# naranjas menos saturados y sin contraste extra.
	&"suave":
	{
		"sat": 1.0,
		"contrast": 1.0,
		"bright": 0.98,
		"day":
		{
			0.33: {1: "#3a5fb0", 2: "#5a86cf", 3: "#b4cdd6", 5: "#fff0d8", 6: 1.25, 7: "#93a2dc"},
			0.5: {1: "#3456a8", 2: "#5381cc", 3: "#b0cbd8", 5: "#fff3e0", 6: 1.35, 7: "#93a2dc"},
			0.68: {1: "#3a5fb0", 2: "#5a86cf", 3: "#bccfd2", 5: "#ffe8c8", 6: 1.25, 7: "#9ea2d8"},
		},
		"grade":
		{
			"chroma_knee": 0.34,
			"chroma_keep": 0.65,
			"green_shift": 0.02,
			"green_sat": 0.85,
			"green_val": 0.9,
			"orange_sat": 0.8,
			"white_knee": 0.8,
			"white_keep": 0.6,
		},
	},
	# Valle en sombra: la luz de la noche llevada al día. Sombras azul pizarra, verdes hondos que
	# tiran a azulado, luz crema y un cielo azul más profundo; los faroles y la magia resaltan.
	&"azulada":
	{
		"sat": 1.0,
		"contrast": 1.08,
		"bright": 0.95,
		"day":
		{
			0.33:
			{
				1: "#26408f",
				2: "#3d63b0",
				3: "#9ab4cc",
				4: "#eef0ff",
				5: "#ffe9cc",
				6: 1.1,
				7: "#7a86d6",
				8: 0.42,
				9: "#8ea6cc",
				10: "#e6ecff",
			},
			0.5:
			{
				1: "#223c8a",
				2: "#3a60ae",
				3: "#98b2cc",
				4: "#eef0ff",
				5: "#ffefd8",
				6: 1.2,
				7: "#7a86d6",
				8: 0.42,
				9: "#8ea6cc",
				10: "#e6ecff",
			},
			0.68:
			{
				1: "#26408f",
				2: "#3d63b0",
				3: "#a6b6cc",
				4: "#f2eefa",
				5: "#ffe2c0",
				6: 1.1,
				7: "#8486d2",
				8: 0.42,
				9: "#98a6c8",
				10: "#eeeaff",
			},
		},
		"grade":
		{
			"chroma_knee": 0.3,
			"chroma_keep": 0.62,
			"green_shift": 0.05,
			"green_sat": 0.85,
			"green_val": 0.78,
			"orange_sat": 0.72,
			"shadow_tint": Color(0.8, 0.88, 1.15),
			"high_tint": Color(1.04, 1.0, 0.94),
			"white_knee": 0.75,
			"white_keep": 0.55,
		},
	},
	# Pastel: tarde de acuarela. Clara pero sin brillo duro: cielo celeste lechoso, verdes salvia,
	# tierra arena y sombras malva.
	&"pastel":
	{
		"sat": 0.92,
		"contrast": 0.94,
		"bright": 1.0,
		"day":
		{
			0.33:
			{
				1: "#5a7cc0",
				2: "#88a8d8",
				3: "#d8dfe0",
				4: "#ffffff",
				5: "#fff0e0",
				6: 1.15,
				7: "#a8a8dc",
				8: 0.44,
				9: "#c4d0e0",
				10: "#f6f2ff",
			},
			0.5:
			{
				1: "#5576bc",
				2: "#84a6d8",
				3: "#d4dee2",
				4: "#ffffff",
				5: "#fff4e8",
				6: 1.25,
				7: "#a8a8dc",
				8: 0.44,
				9: "#c4d0e0",
				10: "#f6f2ff",
			},
			0.68:
			{
				1: "#5a7cc0",
				2: "#8aa6d6",
				3: "#e0dcdc",
				4: "#fff6f0",
				5: "#ffe8d0",
				6: 1.15,
				7: "#b4a8d8",
				8: 0.44,
				9: "#d0cce0",
				10: "#fff2f2",
			},
		},
		"grade":
		{
			"chroma_knee": 0.26,
			"chroma_keep": 0.55,
			"green_shift": 0.0,
			"green_sat": 0.78,
			"green_val": 0.95,
			"orange_sat": 0.68,
			"shadow_tint": Color(1.02, 0.94, 1.08),
			"lift": 0.04,
			"white_knee": 0.82,
			"white_keep": 0.6,
		},
	},
}

static var _luts: Dictionary = {}


static func has(id: StringName) -> bool:
	return PALETTES.has(id)


static func ids() -> Array:
	return PALETTES.keys()


## Pisa en `keys` (copia de DayNight.KEYS) los fotogramas de día de la paleta `id`.
static func day_keys(id: StringName, keys: Array[Array]) -> Array[Array]:
	var p: Dictionary = PALETTES.get(id, {})
	if not p.has("day"):
		return keys
	var out: Array[Array] = []
	for row: Array in keys:
		var r: Array = row.duplicate()
		var over: Dictionary = (p["day"] as Dictionary).get(float(row[0]), {})
		for col: int in over:
			r[col] = over[col]
		out.append(r)
	return out


## Aplica el ajuste y la LUT de la paleta `id` al entorno.
static func apply_env(id: StringName, env: Environment, base: Dictionary) -> void:
	var p: Dictionary = PALETTES.get(id, {})
	env.adjustment_saturation = p.get("sat", base["sat"])
	env.adjustment_contrast = p.get("contrast", base["contrast"])
	env.adjustment_brightness = p.get("bright", base["bright"])
	env.adjustment_color_correction = lut(id) if p.has("grade") else base["lut"]


static func lut(id: StringName) -> Texture3D:
	if _luts.has(id):
		return _luts[id]
	var g: Dictionary = PALETTES[id]["grade"]
	var slices: Array[Image] = []
	var n: int = LUT_SIZE
	for b: int in n:
		var img := Image.create_empty(n, n, false, Image.FORMAT_RGB8)
		for gi: int in n:
			for r: int in n:
				var c := Color(float(r) / (n - 1), float(gi) / (n - 1), float(b) / (n - 1))
				img.set_pixel(r, gi, _grade(c, g))
		slices.append(img)
	var tex := ImageTexture3D.new()
	tex.create(Image.FORMAT_RGB8, n, n, n, false, slices)
	_luts[id] = tex
	return tex


## El etalonaje de un color (sRGB, 0..1).
static func _grade(c: Color, g: Dictionary) -> Color:
	var h: float = c.h
	var s: float = c.s
	var v: float = c.v
	# Tono: los verdes (h ~ 0,17..0,45) giran hacia azulado (+) u oliva (-) y saturan menos;
	# los naranjas y amarillos (h ~ 0,03..0,15) también bajan.
	var green: float = _band(h, 0.16, 0.24, 0.42, 0.5)
	var orange: float = _band(h, 0.0, 0.04, 0.12, 0.17)
	var blue: float = _band(h, 0.5, 0.55, 0.7, 0.76)
	h = fposmod(h + float(g.get("green_shift", 0.0)) * green, 1.0)
	v *= lerpf(1.0, float(g.get("green_val", 1.0)), green * smoothstep(0.1, 0.4, s))
	s *= lerpf(1.0, float(g.get("green_sat", 1.0)), green)
	s *= lerpf(1.0, float(g.get("orange_sat", 1.0)), orange)
	# Croma: por encima de la rodilla la saturación (por valor) crece a medias.
	var chroma: float = s * v
	var knee: float = g.get("chroma_knee", 1.0)
	if chroma > knee and v > 0.0:
		# El azul del cielo se respeta más: es lo que da aire al día.
		var keep: float = lerpf(float(g.get("chroma_keep", 1.0)), 1.0, blue * 0.7)
		chroma = knee + (chroma - knee) * keep
		s = chroma / v
	# Blancos: los valores altos se comprimen (menos deslumbre en el cristal y las nubes).
	var wk: float = g.get("white_knee", 1.0)
	if v > wk:
		v = wk + (v - wk) * float(g.get("white_keep", 1.0))
	var out := Color.from_hsv(h, clampf(s, 0.0, 1.0), clampf(v, 0.0, 1.0))
	# Tinte de sombras y luces según la luminancia.
	var lum: float = out.get_luminance()
	var st: Color = g.get("shadow_tint", Color.WHITE)
	var ht: Color = g.get("high_tint", Color.WHITE)
	var tint: Color = st.lerp(ht, smoothstep(0.15, 0.75, lum))
	out = Color(out.r * tint.r, out.g * tint.g, out.b * tint.b)
	var lift: float = g.get("lift", 0.0)
	out = Color(
		lift + out.r * (1.0 - lift), lift + out.g * (1.0 - lift), lift + out.b * (1.0 - lift)
	)
	return Color(clampf(out.r, 0.0, 1.0), clampf(out.g, 0.0, 1.0), clampf(out.b, 0.0, 1.0))


## 0 fuera de [a, d], 1 en [b, c] y rampas suaves entre medias.
static func _band(x: float, a: float, b: float, c: float, d: float) -> float:
	return smoothstep(a, b, x) * (1.0 - smoothstep(c, d, x))
