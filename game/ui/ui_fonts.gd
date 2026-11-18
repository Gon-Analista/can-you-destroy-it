class_name UiFonts
extends RefCounted
## Fuentes de toda la interfaz, en un solo sitio.
##
## Fusion Pixel (sus letras latinas son las de Ark Pixel; OFL, ver FUSION_PIXEL_OFL.txt):
## proporcional, con minúsculas, tildes, ñ, ¡ y ¿. Mayúsculas de 7 px a 10 px y de 9 px a 12 px.
## Se usan sólo a su tamaño de diseño o a múltiplos enteros (1 px de la fuente = 1 px del juego)
## y sin antialiasing, así quedan nítidas y en la misma rejilla que el mundo a cualquier escala
## entera. La negrita es "de píxel" (cada trazo un píxel más ancho), generada con
## `tools/make_ui_fonts.py`. Pixelify Sans queda sólo para el logotipo del título.

## Texto corrido (descripciones, frases del tutorial, opciones).
const BODY: FontFile = preload("res://ui/fonts/fusion_pixel_10.woff2")
## Texto corto sobre el mundo (HUD, avisos, botones, etiquetas): se lee mejor sobre fondos movidos.
const BOLD: FontFile = preload("res://ui/fonts/fusion_pixel_10_bold.woff2")
## Títulos, avisos grandes y números (a HEAD o a BIG).
const TITLE: FontFile = preload("res://ui/fonts/fusion_pixel_12_bold.woff2")
## Logotipo del juego (título y pantalla de carga).
const LOGO: FontFile = preload("res://ui/fonts/pixelify_sans_bold.woff2")

## Tamaño de BODY y BOLD.
const SMALL: int = 10
## Tamaño de TITLE.
const HEAD: int = 12
## TITLE al doble: números y nombres grandes.
const BIG: int = 24
## Alto de una línea de SMALL (10 px por encima de la base y 2 por debajo).
const LINE: int = 12
## Alto de una línea de HEAD.
const HEAD_LINE: int = 14
## Espacio entre líneas de un párrafo (el de Godot por defecto, 3, separa demasiado) y distancia
## de una línea a la siguiente.
const LINE_GAP: int = 1
const PITCH: int = LINE + LINE_GAP
## Contorno de 1 px del juego (el tamaño va en píxeles de la fuente a ambos lados).
const OUTLINE: int = 2


## Texto sobre el mundo: contorno de 1 px y sombra que cae 1 px, para leerse sobre el cielo claro,
## el cristal y el bosque por igual.
static func outline(l: Label, col: Color) -> void:
	l.add_theme_color_override(&"font_outline_color", col)
	l.add_theme_constant_override(&"outline_size", OUTLINE)
	l.add_theme_color_override(&"font_shadow_color", Color(col, 0.6))
	l.add_theme_constant_override(&"shadow_offset_x", 1)
	l.add_theme_constant_override(&"shadow_offset_y", 1)
	l.add_theme_constant_override(&"shadow_outline_size", OUTLINE)


## Párrafo que se parte en líneas a lo ancho de la etiqueta, con PITCH entre líneas. Las líneas
## se calculan con el texto entero aunque se esté escribiendo letra a letra (si no, las palabras
## saltaban de línea mientras aparecían y el número de líneas salía corto).
static func paragraph(l: Label) -> void:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	l.add_theme_constant_override(&"line_spacing", LINE_GAP)
