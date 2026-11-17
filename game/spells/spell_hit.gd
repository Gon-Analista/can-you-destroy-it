class_name SpellHit
extends RefCounted
## Datos de un impacto contra el Cristal Madre.

var position: Vector3
var normal: Vector3
var damage: int
var resonant: bool
var tier: SpellTier
var streak: int = 0
## Si el golpe viene de una combinación (Bola de Fuego...), su receta: área y sonido propios.
var recipe: SpellRecipe
## Elemento del golpe (id de ElementDef): decide cómo reacciona el cristal (el fuego quema).
var element: StringName = &""
## Golpe de precalentamiento (pantalla de carga): se dibuja pero no hace nada.
var warmup: bool = false
