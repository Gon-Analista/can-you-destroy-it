class_name ImpactStyle
extends RefCounted
## Firma de cada elemento al golpear: cómo estalla (`HdImpact`), cómo lo siente la cámara
## (`CameraRig`), cuánto se congela el tiempo y qué capa de sonido lleva el golpe (`MotherCrystal`).
## Antes todos estallaban igual (bola de fuego, onda y humo gris) y sólo cambiaba el color.
##
## - Fuego: llamarada que se hincha, brasas que suben y humo.
## - Arcano: remolino que se traga sus propias chispas y dos ondas (la segunda es su eco).
## - Hielo: cristal que se abre de golpe, esquirlas que caen pesadas, nieve y escarcha.
## - Rayo: fogonazo seco que parpadea, chispas rectas y muy rápidas, sin humo.
## - Roca: golpe sordo, polvo pegado al suelo y gravilla que cae.
## - Viento: dos ondas grandes y rápidas y motas que giran en remolino.

enum { FIRE, ARCANE, ICE, BOLT, ROCK, WIND }

const ELEMENT_STYLE: Dictionary[StringName, int] = {
	&"spark": FIRE,
	&"arcane": ARCANE,
	&"frost": ICE,
	&"bolt": BOLT,
	&"earth": ROCK,
	&"wind": WIND,
}

## Una fila por estilo (mismo orden que el enum). Tiempos en segundos; multiplicadores sobre el
## estallido de siempre (el del fuego, que se queda como estaba).
## - snap: cuánto de golpe se abre la bola (más alto, más seco); dur: lo que dura la bola;
##   fire_k: tamaño de la bola; turb: turbulencia de su forma.
## - flash: brillo del destello; flash_t: lo que dura; rays / ray_count: rayos del destello;
##   strobe: el destello parpadea (rayo).
## - ring: tamaño de la onda; ring_speed: rapidez; ring2: retraso de una segunda onda
##   (< 0 = sin ella).
## - smoke: cantidad de humo (0 = nada); smoke_col: su color; smoke_rise: cuánto sube (< 0 se
##   arrastra por el suelo); smoke_size: tamaño de las bocanadas.
## - spark_speed / spark_grav / spark_life / spark_pull / spark_swirl: chispas (rapidez, gravedad,
##   vida, tirón hacia el centro y giro en remolino).
## - ember: cantidad de motas; ember_grav: gravedad (> 0 suben, < 0 caen); ember_life; ember_swirl.
## - star_pts / star_sharp / star_twist / star_jag / star_size / star_t: chispa de golpe
##   (`hd_hitspark.gdshader`): puntas, lo finas que son, curva en remolino, quiebro de rayo,
##   tamaño y duración.
## - trauma / fov: sacudida (x la de siempre) y golpe de campo de visión (grados; > 0 se abre).
## - stop: congelado del tiempo en golpes de una mano (s); el de los combinados no cambia.
const PROFILES: Array[Dictionary] = [
	{  # FIRE
		"star_pts": 7.0,
		"star_sharp": 5.0,
		"star_twist": 0.0,
		"star_jag": 0.0,
		"star_size": 1.10,
		"star_t": 0.26,
		"snap": 3.0,
		"dur": 0.55,
		"fire_k": 1.0,
		"turb": 0.5,
		"flash": 1.0,
		"flash_t": 0.3,
		"rays": 1.0,
		"ray_count": 8.0,
		"strobe": false,
		"ring": 1.0,
		"ring_speed": 1.0,
		"ring2": -1.0,
		"smoke": 1.0,
		"smoke_col": Color(0.44, 0.39, 0.4),
		"smoke_rise": 1.0,
		"smoke_size": 1.0,
		"spark_speed": 1.0,
		"spark_grav": -9.0,
		"spark_life": 0.7,
		"spark_pull": 0.0,
		"spark_swirl": 0.0,
		"ember": 1.0,
		"ember_grav": 0.8,
		"ember_life": 1.2,
		"ember_swirl": 0.0,
		"trauma": 1.0,
		"fov": -0.8,
		"stop": 0.02,
	},
	{  # ARCANE
		"star_pts": 8.0,
		"star_sharp": 6.0,
		"star_twist": 2.5,
		"star_jag": 0.0,
		"star_size": 1.20,
		"star_t": 0.34,
		"snap": 3.0,
		"dur": 0.7,
		"fire_k": 1.1,
		"turb": 0.8,
		"flash": 1.1,
		"flash_t": 0.42,
		"rays": 1.4,
		"ray_count": 5.0,
		"strobe": false,
		"ring": 0.85,
		"ring_speed": 0.8,
		"ring2": 0.16,
		"smoke": 0.35,
		"smoke_col": Color(0.5, 0.36, 0.7),
		"smoke_rise": 0.3,
		"smoke_size": 0.8,
		"spark_speed": 1.1,
		"spark_grav": 0.0,
		"spark_life": 0.8,
		"spark_pull": -14.0,
		"spark_swirl": 6.0,
		"ember": 1.6,
		"ember_grav": 0.0,
		"ember_life": 1.6,
		"ember_swirl": 3.0,
		"trauma": 0.7,
		"fov": 1.4,
		"stop": 0.025,
	},
	{  # ICE
		"star_pts": 6.0,
		"star_sharp": 10.0,
		"star_twist": 0.0,
		"star_jag": 0.0,
		"star_size": 1.25,
		"star_t": 0.28,
		"snap": 7.0,
		"dur": 0.5,
		"fire_k": 1.15,
		"turb": 0.2,
		"flash": 1.2,
		"flash_t": 0.2,
		"rays": 1.8,
		"ray_count": 6.0,
		"strobe": false,
		"ring": 0.9,
		"ring_speed": 1.5,
		"ring2": -1.0,
		"smoke": 0.8,
		"smoke_col": Color(1.35, 1.5, 1.75),
		"smoke_rise": -0.4,
		"smoke_size": 0.9,
		"spark_speed": 1.25,
		"spark_grav": -16.0,
		"spark_life": 0.6,
		"spark_pull": 0.0,
		"spark_swirl": 0.0,
		"ember": 1.4,
		"ember_grav": -0.9,
		"ember_life": 1.8,
		"ember_swirl": 0.0,
		"trauma": 0.9,
		"fov": -1.4,
		"stop": 0.045,
	},
	{  # BOLT
		"star_pts": 5.0,
		"star_sharp": 14.0,
		"star_twist": 0.0,
		"star_jag": 2.5,
		"star_size": 1.50,
		"star_t": 0.20,
		"snap": 6.0,
		"dur": 0.3,
		"fire_k": 0.9,
		"turb": 0.9,
		"flash": 1.6,
		"flash_t": 0.2,
		"rays": 2.2,
		"ray_count": 12.0,
		"strobe": true,
		"ring": 1.1,
		"ring_speed": 2.0,
		"ring2": -1.0,
		"smoke": 0.0,
		"smoke_col": Color(0.6, 0.55, 0.8),
		"smoke_rise": 1.0,
		"smoke_size": 1.0,
		"spark_speed": 2.2,
		"spark_grav": -2.0,
		"spark_life": 0.32,
		"spark_pull": 0.0,
		"spark_swirl": 0.0,
		"ember": 0.5,
		"ember_grav": 0.3,
		"ember_life": 0.5,
		"ember_swirl": 0.0,
		"trauma": 1.3,
		"fov": -2.0,
		"stop": 0.035,
	},
	{  # ROCK
		"star_pts": 6.0,
		"star_sharp": 1.8,
		"star_twist": 0.0,
		"star_jag": 0.0,
		"star_size": 0.95,
		"star_t": 0.22,
		"snap": 4.0,
		"dur": 0.6,
		"fire_k": 1.25,
		"turb": 0.3,
		"flash": 0.55,
		"flash_t": 0.2,
		"rays": 0.0,
		"ray_count": 6.0,
		"strobe": false,
		"ring": 1.3,
		"ring_speed": 0.75,
		"ring2": -1.0,
		"smoke": 2.2,
		"smoke_col": Color(0.8, 0.64, 0.45),
		"smoke_rise": -0.5,
		"smoke_size": 1.5,
		"spark_speed": 0.85,
		"spark_grav": -22.0,
		"spark_life": 0.9,
		"spark_pull": 0.0,
		"spark_swirl": 0.0,
		"ember": 1.2,
		"ember_grav": -7.0,
		"ember_life": 1.0,
		"ember_swirl": 0.0,
		"trauma": 1.9,
		"fov": -0.5,
		"stop": 0.05,
	},
	{  # WIND
		"star_pts": 3.0,
		"star_sharp": 5.0,
		"star_twist": 4.5,
		"star_jag": 0.0,
		"star_size": 1.30,
		"star_t": 0.30,
		"snap": 3.0,
		"dur": 0.42,
		"fire_k": 1.2,
		"turb": 0.6,
		"flash": 0.7,
		"flash_t": 0.25,
		"rays": 0.0,
		"ray_count": 6.0,
		"strobe": false,
		"ring": 1.6,
		"ring_speed": 1.6,
		"ring2": 0.09,
		"smoke": 0.0,
		"smoke_col": Color(0.85, 0.95, 0.9),
		"smoke_rise": 1.0,
		"smoke_size": 1.0,
		"spark_speed": 1.3,
		"spark_grav": 0.0,
		"spark_life": 0.7,
		"spark_pull": 2.0,
		"spark_swirl": 22.0,
		"ember": 1.5,
		"ember_grav": 0.4,
		"ember_life": 1.0,
		"ember_swirl": 9.0,
		"trauma": 0.6,
		"fov": 2.0,
		"stop": 0.0,
	},
]


## Valores de un estilo (los de `PROFILES`, tipados).
class Profile:
	var star_pts: float
	var star_sharp: float
	var star_twist: float
	var star_jag: float
	var star_size: float
	var star_t: float
	var snap: float
	var dur: float
	var fire_k: float
	var turb: float
	var flash: float
	var flash_t: float
	var rays: float
	var ray_count: float
	var strobe: bool
	var ring: float
	var ring_speed: float
	var ring2: float
	var smoke: float
	var smoke_col: Color
	var smoke_rise: float
	var smoke_size: float
	var spark_speed: float
	var spark_grav: float
	var spark_life: float
	var spark_pull: float
	var spark_swirl: float
	var ember: float
	var ember_grav: float
	var ember_life: float
	var ember_swirl: float
	var trauma: float
	var fov: float
	var stop: float


static var _cache: Array[Profile] = []


## Estilo de un golpe: los de una mano, por su elemento (la Llama mágica rosa de la Chispa sigue
## siendo fuego); los combinados, por la forma de su hechizo (`SpellVisualDef.style`).
static func of(hit: SpellHit) -> int:
	if hit.recipe == null and ELEMENT_STYLE.has(hit.element):
		return ELEMENT_STYLE[hit.element]
	return of_tier(hit.tier)


static func of_tier(tier: SpellTier) -> int:
	if tier and tier.visual:
		return clampi(tier.visual.style, 0, PROFILES.size() - 1)
	return FIRE


## Congelado del tiempo de un golpe de una mano con la firma de su elemento: el hielo y la roca
## pesan, el viento no se para.
static func stop_sec(hit: SpellHit) -> float:
	return profile(of(hit)).stop


static func profile(style: int) -> Profile:
	if _cache.is_empty():
		for d: Dictionary in PROFILES:
			var pf := Profile.new()
			for key: String in d:
				pf.set(key, d[key])
			_cache.append(pf)
	return _cache[clampi(style, 0, _cache.size() - 1)]
