class_name RankCrest
extends RefCounted
## Escudo pixel art de cada rango del mago (17 x 19 px): un blasón con el borde de su metal (plata
## los primeros, oro después) y el emblema del rango (chispa, copo, rayo, montaña con meteoro,
## ojo arcano y corona). Se pinta una vez por rango con sus colores (`RankDef`) y se reutiliza
## en el HUD (x1), el Espejo (x2) y la ceremonia (x4), siempre a escala entera.

const SIZE := Vector2i(17, 19)
## o contorno, r borde, R borde en sombra, m campo oscuro; los puntos de dentro son el campo.
const SHIELD: PackedStringArray = [
	"..ooooooooooooo..",
	".orrrrrrrrrrrrro.",
	".orRmmmmmmmmmRro.",
	".orm.........mro.",
	".orm.........mro.",
	".orm.........mro.",
	".orm.........mro.",
	".orm.........mro.",
	".orm.........mro.",
	".orm.........mro.",
	".orm.........mro.",
	"..orm.......mro..",
	"..orm.......mro..",
	"...orm.....mro...",
	"....orm...mro....",
	".....ormmmro.....",
	"......orrro......",
	".......oro.......",
	"........o........",
]
## Emblemas (9 x 10, en la esquina (4, 3) del escudo), uno tras otro de 10 en 10 filas:
## e color, l claro, w blanco.
const EMBLEM_ROWS: int = 10
const EMBLEMS: PackedStringArray = [
	# Aprendiz: la chispita.
	"....l....",
	"....l....",
	"...lel...",
	"...lel...",
	"..lewel..",
	"..ewwwe..",
	".lewwwel.",
	".eewwwee.",
	"..eeeee..",
	"...eee...",
	# Iniciado: el copo de la Escarcha.
	"....w....",
	".l..l..l.",
	"..e.l.e..",
	"...lwl...",
	"wlllwlllw",
	"...lwl...",
	"..e.l.e..",
	".l..l..l.",
	"....w....",
	".........",
	# Hechicero: el rayo.
	".....lw..",
	"....lw...",
	"...lw....",
	"..lwl....",
	".lwwwwl..",
	"....wl...",
	"...wl....",
	"..wl.....",
	".wl......",
	".l.......",
	# Magus: la montaña y el meteoro.
	"......lw.",
	".....le..",
	"....e....",
	".........",
	"....l....",
	"...lwl...",
	"..lweel..",
	".lweeeel.",
	"lweeeeeel",
	"eeeeeeeee",
	# Archimago: el ojo arcano que irradia.
	"....w....",
	".l..l..l.",
	"..l...l..",
	"...lll...",
	".lleeell.",
	"leeewweel",
	".lleeell.",
	"...lll...",
	"..l...l..",
	".l..l..l.",
	# Leyenda: la corona con su estrella.
	"....w....",
	"...lwl...",
	"....l....",
	"l...e...l",
	"ll.lel.ll",
	"lelleelle",
	"leeweweel",
	"lllllllll",
	"ewewewewe",
	"lllllllll",
]
const C_OUTLINE := Color("#14183a")

static var _cache: Dictionary[int, ImageTexture] = {}


## Textura del escudo del rango `rank` (se crea la primera vez).
static func texture(rank: int) -> ImageTexture:
	if _cache.has(rank):
		return _cache[rank]
	var def: RankDef = WizardRanks.def_of(rank)
	var img := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var field: Color = def.color_dark.lerp(def.color, 0.22)
	var pal: Dictionary[String, Color] = {
		"o": C_OUTLINE,
		"r": def.rim,
		"R": def.rim.darkened(0.3),
		"m": def.color_dark,
		"e": def.color,
		"l": def.color_light,
		"w": Color.WHITE,
	}
	for y: int in SHIELD.size():
		var row: String = SHIELD[y]
		var first: int = row.find("m")
		var last: int = row.rfind("m")
		for x: int in row.length():
			var ch: String = row[x]
			if ch != ".":
				img.set_pixel(x, y, pal[ch])
			elif first >= 0 and x > first and x < last:
				# Campo con un brillo arriba a la izquierda (la luz del juego viene de ahí).
				var lit: bool = x + y < 12
				img.set_pixel(x, y, field.lightened(0.08) if lit else field)
	var first_row: int = clampi(def.emblem, 0, EMBLEMS.size() / EMBLEM_ROWS - 1) * EMBLEM_ROWS
	for y: int in EMBLEM_ROWS:
		var row: String = EMBLEMS[first_row + y]
		for x: int in row.length():
			var ch: String = row[x]
			if ch != ".":
				img.set_pixel(4 + x, 3 + y, pal[ch])
	var tex := ImageTexture.create_from_image(img)
	_cache[rank] = tex
	return tex


## Dibuja el escudo en `ci` con la esquina en `at` (redondeada a píxel) y escala entera `px`.
static func draw(
	ci: CanvasItem, rank: int, at: Vector2, px: int, tint: Color = Color.WHITE
) -> void:
	var r := Rect2(at.round(), Vector2(SIZE * maxi(px, 1)))
	ci.draw_texture_rect(texture(rank), r, false, tint)
