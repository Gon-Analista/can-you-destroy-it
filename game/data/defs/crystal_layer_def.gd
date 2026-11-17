class_name CrystalLayerDef
extends Resource
## Capa del Cristal Madre (GDD 6). Las capas están por profundidad dentro del volumen del
## cristal (las horneó tools/crystal_volume.py, que reparte la esencia con `from_ratio` y
## `to_ratio`): se llega a ellas excavando. Cada una tiene su color, su voz y sus reglas.

@export var id: StringName
@export var display_name: String
@export_range(0.0, 1.0) var from_ratio: float = 0.0
@export_range(0.0, 1.0) var to_ratio: float = 0.1
@export var tint: Color = Color.WHITE
@export var hardness: float = 1.0
## Sólo cede ante hechizos combinados (Corazón Cristalino, GDD 6).
@export var needs_combo: bool = false
## No cede ante nada (el Núcleo, hasta la Gran Convergencia).
@export var immune: bool = false
## Aviso cuando un golpe rebota en esta capa.
@export var too_hard_hint: String = ""

@export_group("Paleta")
@export var col_highlight: Color = Color(0.91, 0.99, 1.0)
@export var col_light: Color = Color(0.647, 0.855, 0.898)
@export var col_mid: Color = Color(0.271, 0.561, 0.722)
@export var col_dark: Color = Color(0.157, 0.294, 0.525)
@export var col_core: Color = Color(0.235, 0.137, 0.42)

@export_group("Sensación")
## Tono del golpe al cristal (1 = el de la Corteza; más grave cuanto más dentro).
@export var hit_pitch: float = 1.0
## Geodas a la vez en la superficie (bolsas que revientan soltando fragmentos grandes).
@export var geode_count: int = 0
## Fragmentos grandes que suelta cada geoda.
@export var geode_shards: int = 8

@export_group("Venas")
## Venas Resonantes (GDD 6): elemento al que es débil la vena de cada lado del cristal, en el
## orden de los sectores del shader (ver CrystalVeins). Vacío = la capa no tiene venas.
@export var vein_elements: Array[StringName] = []
## Nombre de cada vena (el de su elemento), para los avisos.
@export var vein_names: PackedStringArray = PackedStringArray()
## Daño extra de un golpe con el elemento débil de la vena.
@export var vein_damage_mult: float = 1.0
## Fragmentos Resonantes que suelta como mucho un golpe en la vena.
@export var vein_shards: int = 0
## Su valor, como parte del daño del golpe (0.5 = la mitad más en Resonantes). Si no llega a uno,
## sale uno con esa probabilidad: de media siempre vale lo mismo.
@export var vein_bonus: float = 0.5
