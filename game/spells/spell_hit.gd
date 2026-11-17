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
## Su elemento (para el efecto en el cristal); null en las combinaciones.
var element_def: ElementDef
## True si cayó en una zona debilitada (congelada o quebradiza) y hizo daño extra.
var weakened: bool = false
## Multiplicador que se aplicó por la zona debilitada.
var weak_mult: float = 1.0
## Capa del cristal en la que cayó (0 = Corteza); la pone MotherCrystal.
var layer: int = 0
