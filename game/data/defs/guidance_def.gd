class_name GuidanceDef
extends Resource
## Cuándo deja el HUD de explicar las teclas y cómo guía al jugador hacia su siguiente objetivo
## (ver `Guidance` y `ObjectiveGuide`). Valores en `data/ui/guidance.tres`.

@export_group("Instrucciones que se aprenden")
## Las primeras veces se explica la acción entera ("[F] RECOGER ASTILLA"); después sólo queda
## una tecla pequeña junto a la mira, y a partir de la segunda cifra ya no se enseña nada.
@export var pickup_learn: int = 4
@export var pickup_forget: int = 20
## Mantener F para echar a la tolva y tocar F para la palanca.
@export var feed_learn: int = 2
@export var feed_forget: int = 8
@export var lever_learn: int = 2
@export var lever_forget: int = 8
## Abrir el Grimorio junto al atril.
@export var grimoire_learn: int = 2
@export var grimoire_forget: int = 6
## Veces que el aviso grande de "¡BOLSA LLENA!" sale con texto (luego, sonido y bolsa que late).
@export var bag_full_hints: int = 2

@export_group("Guía")
## Mientras se hayan comprado menos niveles que esto, cualquier mejora pagable guía al
## Santuario; después, sólo las mejoras que no se habían visto en el Grimorio.
@export var guide_any_upgrade_until: int = 3
## Radio (m) en el que se buscan fragmentos sueltos para guiar hacia ellos.
@export var shard_radius_m: float = 30.0
## El objetivo se desvanece al acercarse: invisible a `fade_near_m` y entero a `fade_far_m`.
@export var fade_near_m: float = 3.0
@export var fade_far_m: float = 7.0
## La estela de destellos del suelo cubre como mucho estos metros por delante del mago.
@export var trail_length_m: float = 18.0
## Segundos que se ve la etiqueta de un objetivo que no es urgente (después, sólo la distancia).
@export var tag_sec: float = 3.5
