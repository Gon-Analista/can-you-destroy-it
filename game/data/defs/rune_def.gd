class_name RuneDef
extends UpgradeNode
## Runa de la Mesa de Runas (GDD 4.3 y 5.3): se compra y se sube de nivel con maná como cualquier
## estrella (`costs`, `prerequisites`), pero sólo hace algo mientras está inscrita en una ranura
## de la mesa (ver RuneBook). `values` es la fuerza de cada nivel (proyectiles de más, rebotes,
## fondo del túnel, probabilidad del eco o maná de más con la Cosecha) y `damage_values`, el daño
## de lo que sale de más (fracción del golpe) o, en la Cosecha, el daño que se queda.
## Las runas tocan los hechizos que salen de las manos: los sueltos enteros y, a `combo_scale`, los
## combinados que vuelan desde las palmas (Bola de Fuego, Choque Térmico, lanzas). La Cosecha
## cambia todo lo que lanza el mago.

enum Kind { MULTISHOT, BOUNCE, PIERCE, ECHO, HARVEST }

@export var kind: Kind = Kind.MULTISHOT
## Glifo 8x8 de la runa ('#' color, '+' brillo, '.' vacío): mesa, manos y pantalla.
@export var glyph: PackedStringArray = PackedStringArray()
@export var color: Color = Color("#c79bff")
## Color caliente (HDR) de sus destellos y círculos.
@export var color_hot: Color = Color(2.0, 1.8, 2.2)
## Daño de lo que sale de más en cada nivel (fracción), o el daño que deja la Cosecha (x).
## [sin comprar, nivel 1, nivel 2...].
@export var damage_values: PackedFloat32Array = PackedFloat32Array()
## Cuánto pesa en los combinados que salen de las manos (0 = no los toca): multiplica el daño de
## lo que sale de más y la probabilidad del eco.
@export_range(0.0, 1.0) var combo_scale: float = 0.5
## Qué hace en los combinados, en una frase (pantalla de la mesa).
@export_multiline var combo_note: String = ""
## Sonidos al activarse (uno al azar, con variación de tono).
@export var sfx: Array[AudioStream] = []


## Fracción de daño (o multiplicador, en la Cosecha) del nivel `level`.
func damage_at(level: int) -> float:
	if damage_values.is_empty():
		return 0.0
	return damage_values[clampi(level, 0, damage_values.size() - 1)]
