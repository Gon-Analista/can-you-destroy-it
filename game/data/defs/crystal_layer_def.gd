class_name CrystalLayerDef
extends Resource
## Capa del Cristal Madre (GDD 6), definida por el rango de esencia destruida (0.0 a 1.0).
## Al entrar en ella el cristal cambia de color, de voz y de lo que suelta.

@export var id: StringName
@export var display_name: String
@export_range(0.0, 1.0) var from_ratio: float = 0.0
@export_range(0.0, 1.0) var to_ratio: float = 0.1
@export var tint: Color = Color.WHITE
@export var hardness: float = 1.0

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
