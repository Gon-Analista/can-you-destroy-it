class_name PixelTextures
extends RefCounted
## Texturas pixel art de partículas (blanco + alfa; el color lo pone cada sistema).
## Son PNG en fx/textures/ para que se puedan retocar en Aseprite.

const STAR: Texture2D = preload("res://fx/textures/particle_star.png")
const CHIP: Texture2D = preload("res://fx/textures/particle_chip.png")


## Estrella de 4 puntas (7x7): el destello mágico básico.
static func star() -> Texture2D:
	return STAR


## Punto de 3x3 con borde suave (polvo / esquirlas).
static func chip() -> Texture2D:
	return CHIP
