class_name CritterDef
extends Resource
## Una especie de bicho del valle (`critters/`): monstruitos graciosos de ojos saltones que
## pasean por la hierba como animales, nunca atacan y revientan de forma muy cómica al darles con
## un hechizo. Aspecto, carácter y recompensa de cada especie (`data/critters/*.tres`).

## Forma del cuerpo (ver CritterRig): gelatina redonda, zanahoria con dientes, pompón peludo con
## patitas, babosa con ojos en antenas y cíclope saltarín.
enum Shape { BLOB, TOOTHY, FUZZY, SLUG, CYCLOPS }
## Cómo se mueve: a saltitos, andando como un pato, correteando o arrastrándose.
enum Gait { HOP, WADDLE, SCURRY, SLIDE }

@export var id: StringName
## Nombre de la especie (en español; se traduce con tr()). "Gelatín", "Dientón"...
@export var display_name: String
@export var shape: Shape = Shape.BLOB
@export var gait: Gait = Gait.HOP
## Alto del cuerpo (m).
@export var size: float = 0.9

@export_group("Colores")
@export var body_color: Color = Color("#7ee05a")
@export var belly_color: Color = Color("#c8ff9a")
## Detalles: patas, antenas, pelo, boca...
@export var accent_color: Color = Color("#3f9a3c")
## Color de la baba al reventar (los trozos y las manchas del suelo).
@export var goo_color: Color = Color("#8cff4f")
@export var cheek_color: Color = Color("#ff7ad9")

@export_group("Ojos")
## Radio de cada ojo (m). Grandes: es lo que se tiene que leer a 640x360.
@export var eye_radius: float = 0.17
## Tamaño de la pupila respecto al ojo.
@export_range(0.2, 0.9) var pupil_ratio: float = 0.55
## Cuánto bailan las pupilas (muelle poco amortiguado: ojos locos).
@export var eye_wobble: float = 1.0

@export_group("Carácter")
## Velocidad al pasear (m/s) y al huir asustado.
@export var walk_speed: float = 0.7
@export var flee_speed: float = 3.2
## Altura de cada saltito (m) y segundos que dura.
@export var hop_height: float = 0.35
@export var hop_sec: float = 0.42
## Segundos quieto entre paseo y paseo.
@export var idle_min_sec: float = 1.5
@export var idle_max_sec: float = 4.5
## Tono de sus chillidos (1 = normal; los pequeños, más agudos).
@export var voice_pitch: float = 1.0
## Gestos que hace a veces (ver Critter.Emote): 0 lengua, 1 estornudo, 2 bostezo, 3 baile.
@export var emotes: PackedInt32Array = [0, 1, 2, 3]

@export_group("Aparición")
## Peso al elegir especie (más = más frecuente).
@export var weight: float = 1.0
## Sólo aparece a partir de este punto del Pilón (0..1): especies nuevas y más raras al avanzar.
@export_range(0.0, 1.0) var min_pylon: float = 0.0

@export_group("Al reventar")
## Astillas que suelta (maná de propina, no rompe la economía).
@export var splinters: int = 2
## Trozos de baba (y manchas) que salen.
@export var chunks: int = 9
## Suelta un diente (Dientón) o un huesito.
@export var drops_tooth: bool = false
@export var drops_bone: bool = true
