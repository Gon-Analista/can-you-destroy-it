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
## Tamaño del hechizo (mejora de Tamaño): crece al salir de la mano y agranda el impacto, el
## cráter, la quemadura, la zona helada y los fragmentos. 1 = el de siempre.
var size: float = 1.0
## Dirección de vuelo al llegar (las lanzas perforan por ella).
var direction: Vector3 = Vector3.FORWARD
## Golpe menor de un hechizo múltiple (lluvia, haz): sin pausa de impacto ni destello global.
var minor: bool = false
## Eco fantasma del Arcano (repite otro golpe).
var echo: bool = false
## Lo lanza un familiar: no cuenta para la racha ni sacude la cámara del mago.
var familiar: bool = false
## Vena Resonante en la que cayó (sector del cristal, ver CrystalVeins) o -1 si no cayó en una.
var vein: int = -1
## True si dio en la vena con su elemento débil (daño extra y Fragmentos Resonantes).
var vein_weak: bool = false
## False si no lo lanzó el jugador (rayo del Pilón, familiares): no cuenta para la racha ni mueve
## la mirilla, la cámara o la levitación, y no da avisos.
var by_player: bool = true
## Nivel del hechizo (1..10): en las combinaciones, el de su Potencia. Sólo cambia el aspecto.
var level: int = 1
## Runas (RuneCaster, al lanzar): rebotes que le quedan al golpe y el daño de cada rebote
## (fracción del golpe del que sale); fracción de su daño que sigue por dentro del cristal
## (Perforación; 0 = no perfora) y fondo de ese túnel (m).
var rune_bounces: int = 0
var rune_bounce_frac: float = 0.0
var rune_pierce: float = 0.0
var rune_depth: float = 0.0
## Chispa de más o rebote de una runa: no vuelve a disparar las runas al lanzarse.
var rune_spawn: bool = false
