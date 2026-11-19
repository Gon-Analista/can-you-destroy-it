class_name RuneGlyphs
extends RefCounted
## Glifos pixel art 8x8 de las runas (`RuneDef.glyph`: '#' color, '+' brillo, '.' vacío), para la
## pantalla de la mesa (dibujados con rectángulos, a x1, x2 o x3) y como texturas de 10x10 con
## contorno oscuro para las manos y la mesa del Santuario (una por runa y color, en caché).

## Sello de la mesa cerrada y ranura con candado.
const SEAL: PackedStringArray = [
	"..####..", ".#....#.", "#.#..#.#", "#..##..#", "#..##..#", "#.#..#.#", ".#....#.", "..####.."
]
const LOCK: PackedStringArray = [
	"..###...", ".#...#..", ".#...#..", "#######.", "##+++##.", "###+###.", "###+###.", "#######."
]
const C_SHADOW := Color("#14102a")

static var _textures: Dictionary[String, ImageTexture] = {}


## Dibuja `rows` en `canvas` a `px` píxeles por celda con sombra de 1 px abajo a la derecha.
static func draw(
	canvas: CanvasItem, rows: PackedStringArray, at: Vector2, px: int, col: Color, alpha := 1.0
) -> void:
	var hi: Color = Color(col.lightened(0.55), alpha)
	var base := Color(col, alpha)
	var shadow := Color(C_SHADOW, alpha)
	for y: int in rows.size():
		var row: String = rows[y]
		for x: int in row.length():
			if row[x] != ".":
				canvas.draw_rect(
					Rect2(at + Vector2(x * px + 1, y * px + 1), Vector2(px, px)), shadow
				)
	for y: int in rows.size():
		var row: String = rows[y]
		for x: int in row.length():
			var ch: String = row[x]
			if ch != ".":
				canvas.draw_rect(
					Rect2(at + Vector2(x * px, y * px), Vector2(px, px)), hi if ch == "+" else base
				)


## Textura 10x10 del glifo con contorno de 1 px (`outline`) y el color `col` (brillo más claro).
static func texture(rows: PackedStringArray, col: Color, outline: Color = C_SHADOW) -> ImageTexture:
	var key: String = "%s|%s|%s" % ["".join(rows), col.to_html(), outline.to_html()]
	if _textures.has(key):
		return _textures[key]
	var img := Image.create(10, 10, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y: int in rows.size():
		for x: int in rows[y].length():
			if rows[y][x] == ".":
				continue
			for d: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
				var p := Vector2i(x + 1, y + 1) + d
				if img.get_pixelv(p).a < 0.5:
					img.set_pixelv(p, outline)
	for y: int in rows.size():
		for x: int in rows[y].length():
			var ch: String = rows[y][x]
			if ch != ".":
				img.set_pixel(x + 1, y + 1, col.lightened(0.55) if ch == "+" else col)
	var tex := ImageTexture.create_from_image(img)
	_textures[key] = tex
	return tex
