class_name CritterConfig
extends Resource
## Reglas de los bichos del valle (`CritterHerd`): cuántos hay, cada cuánto salen, dónde, cuándo
## se asustan y los topes de efectos al reventar (`data/critters/critter_config.tres`).

@export var species: Array[CritterDef] = []

@export_group("Población")
## Bichos vivos a la vez: de `alive_start` con el Pilón vacío a `alive_end` con el Pilón lleno.
@export var alive_start: int = 7
@export var alive_end: int = 12
## Los que hay ya al cargar la partida.
@export var initial_count: int = 6
## Segundos entre apariciones (al azar en el rango) cuando faltan bichos.
@export var respawn_min_sec: float = 15.0
@export var respawn_max_sec: float = 40.0

@export_group("Dónde")
## Anillo del claro en el que viven (m desde el cristal): fuera de su base y antes del bosque.
@export var ring_min: float = 46.0
@export var ring_max: float = 92.0
## Aparecen fuera de la vista inmediata del mago: a esta distancia como poco (m), y si caen dentro
## de la pantalla, a `in_view_min_distance` como poco.
@export var min_player_distance: float = 12.0
@export var in_view_min_distance: float = 26.0
## Y no demasiado lejos (para que se vean de vez en cuando); también los del principio.
@export var max_player_distance: float = 75.0
## Los que se quedan más lejos que esto del mago (y fuera de la pantalla) se esconden para salir
## luego cerca de él.
@export var despawn_distance: float = 105.0
## Pasean sólo un poco alrededor de donde salieron (m).
@export var wander_radius: float = 3.0
## Separación con edificios, caminos y otros bichos (m).
@export var clearance: float = 0.8

@export_group("Sustos")
## Si el mago se acerca a menos de esto (m), chillan y corretean lejos de él.
@export var startle_radius: float = 4.0
## Un hechizo que cae a menos de esto (m) también los asusta.
@export var spell_startle_radius: float = 7.0
## Metros que corretean al asustarse.
@export var flee_distance: float = 4.0

@export_group("Al reventar")
## Segundos de anticipación (se hincha, ojos fuera, chillido) antes del ¡PUM!.
@export var anticipation_sec: float = 0.22
## Radio (m) del golpe suelto de un hechizo sin área contra el suelo que revienta bichos.
@export var point_radius: float = 1.0
## Una explosión de área (Bola de Fuego, Meteoro...) salpica a los vecinos: los que están a
## menos de esto (m) del que revienta revientan también, un poco después (reacción en cadena).
@export var chain_radius: float = 1.8
@export var chain_delay_sec: float = 0.12
## Rayos: a cuántos bichos más salta y hasta qué distancia (m).
@export var bolt_jumps: int = 3
@export var bolt_reach: float = 9.0
## Terremoto: ancho (m) del pasillo de suelo, del mago al blanco, en el que revientan.
@export var quake_width: float = 3.0
## Ventana (s) para contar varios en el mismo golpe ("¡DOBLE BICHO!").
@export var combo_window_sec: float = 0.7

@export_group("Efectos")
## Topes de piezas a la vez (pools): trozos de baba, manchas del suelo, ojos que ruedan y huesos.
@export var max_chunks: int = 72
@export var max_splats: int = 28
@export var max_eyes: int = 16
@export var max_bits: int = 10
## Segundos que duran las manchas en el suelo y cuánto miran los ojos al mago antes de irse.
@export var splat_sec: float = 22.0
@export var eye_stare_sec: float = 4.5
## Pausa de impacto (s) y golpe de cámara al reventar.
@export var hit_stop_sec: float = 0.045
@export var camera_trauma: float = 0.18
