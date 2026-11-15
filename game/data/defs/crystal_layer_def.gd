class_name CrystalLayerDef
extends Resource
## Capa del Cristal Madre, definida por el rango de esencia destruida (0.0 a 1.0).

@export var id: StringName
@export var display_name: String
@export_range(0.0, 1.0) var from_ratio: float = 0.0
@export_range(0.0, 1.0) var to_ratio: float = 0.1
@export var tint: Color = Color.WHITE
@export var hardness: float = 1.0
