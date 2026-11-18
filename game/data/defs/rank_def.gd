class_name RankDef
extends Resource
## Un rango del mago (GDD 8): Aprendiz, Iniciado, Hechicero, Magus, Archimago y Leyenda. Se gana
## por lo que se ha hecho, no por el tiempo: un desbloqueo clave (despertar un elemento) con el
## Pilón a cierto punto, o el Pilón mucho más lleno aunque no se haya despertado (red de seguridad
## para quien se salte el desbloqueo). Leyenda pide el cristal destruido hasta el Núcleo.
## Los rangos van en orden (`WizardRanks.RANKS`); cada uno pide también el anterior.
## Los minutos a los que llegan se comprueban con `tools/balance_sim.py --log`.

@export var id: StringName
## Nombre del rango ("Iniciado"); el título de la ceremonia es "¡ERES %s!".
@export var display_name: String = ""
## Frase de la ceremonia y del Espejo (qué significa el rango).
@export_multiline var motto: String = ""

@export_group("Requisitos")
## Mejora clave (p. ej. &"awaken_frost"); vacía = no hace falta ninguna.
@export var key_upgrade: StringName = &""
## Pilón (0..1) que hace falta además de la mejora clave.
@export_range(0.0, 1.0, 0.0001) var key_pylon: float = 0.0
## Pilón (0..1) que da el rango por sí solo, sin la mejora clave (> 1 = nunca).
@export_range(0.0, 2.0, 0.0001) var pylon_alone: float = 2.0
## Fracción del cristal destruida que hace falta (Leyenda: hasta el Núcleo).
@export_range(0.0, 1.0, 0.001) var min_destroyed: float = 0.0
## Terminar la partida (el cristal sin esencia) lo da aunque falte lo demás.
@export var or_finished: bool = false
## Cómo se gana, para el Espejo ("Despierta el Rayo").
@export var requirement: String = ""

@export_group("Aspecto")
## Color del rango (escudo, título, columna de luz).
@export var color: Color = Color("#a5dae5")
@export var color_light: Color = Color("#e8fbff")
@export var color_dark: Color = Color("#284b86")
## Borde del escudo (plata en los primeros rangos, oro después).
@export var rim: Color = Color("#c9d3e8")
## Emblema del escudo (ver `RankCrest.EMBLEMS`).
@export var emblem: int = 0
## Capas de música que suenan con este rango (AudioDirector.set_music_layers).
@export_range(1, 5) var music_layers: int = 1

@export_group("Manos")
## Gema del brazalete (la original es azul).
@export var hand_gem: Color = Color("#2f97e3")
## Ribete de la manga (alfa 0 = sin ribete).
@export var hand_trim: Color = Color(0, 0, 0, 0)
## Runas que brillan en el puño de la manga (alfa 0 = sin runas).
@export var hand_runes: Color = Color(0, 0, 0, 0)
## Tinte de la tela de la manga (blanco = la original).
@export var hand_sleeve: Color = Color.WHITE
## La gema cambia de color con el tiempo (Leyenda).
@export var hand_prismatic: bool = false
