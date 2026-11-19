class_name BalanceConfig
extends Resource
## Números globales de balance. Nunca hardcodear estos valores en scripts.

@export var total_essence: int = 1_000_000
@export var spark_damage: int = 1
@export var spark_cooldown_sec: float = 1.5
@export var hand_capacity: int = 1
@export var first_upgrade_cost: int = 5
@export var autosave_interval_sec: float = 30.0

@export_group("Sensación del golpe")
## Si se pulsa durante el enfriamiento, el lanzamiento se guarda este tiempo
## y sale en cuanto se pueda.
@export var cast_buffer_sec: float = 0.3
## Margen para pulsar las dos manos "a la vez" y combinar. Un clic con las dos manos listas
## espera como mucho esto por el otro (si se suelta antes, sale en el acto).
@export var combine_window_sec: float = 0.09
## Tiempo máximo entre golpes para mantener la racha.
@export var streak_window_sec: float = 2.6
## Rachas que disparan campanilla y celebración.
@export var streak_milestones: PackedInt32Array = PackedInt32Array([5, 10, 25, 50, 100])
## Probabilidad de golpe resonante (crítico) sin mejoras.
@export_range(0.0, 1.0) var resonant_chance: float = 0.07
@export var resonant_damage_mult: int = 3

@export_group("Carga por etapas")
## Etapas (círculos mágicos) de la carga de un combinado según su nivel (una entrada por nivel,
## del 1 al 10; 0 = carga continua). Cada etapa completada encaja un círculo con sonido y golpe;
## el poder al soltar es el de la última etapa (ver `ChargeStages`). Empieza en el nivel 2, la
## primera Potencia de la Bola de Fuego (minuto 5 a 16 según el simulador), para que se
## descubra pronto y como premio visible de esa compra: un círculo que encaja con la carga
## completa y avisa de cuándo soltar; luego uno más cada dos niveles, hasta 5 a nivel 10.
@export
var charge_stages_by_level: PackedInt32Array = PackedInt32Array([0, 1, 1, 2, 2, 3, 3, 4, 4, 5])
## Duración mínima de cada etapa (s): si las etapas no caben en la carga del hechizo, la carga
## se alarga y ese tiempo se descuenta de la recarga (el ciclo y el daño por segundo no cambian).
@export var charge_stage_min_sec: float = 0.28
## Recarga mínima tras un combinado cuando se le descuenta el tiempo de más de la carga (s).
@export var charge_stage_cooldown_floor_sec: float = 0.25

@export_group("Resonancia del Pilón")
## Daño del rayo del Pilón con el Pilón casi vacío y lleno (crece con su nivel visible).
@export var pylon_bolt_damage_min: int = 25
@export var pylon_bolt_damage_max: int = 600
## Tiempo que el Pilón carga el rayo (brilla y zumba) antes de dispararlo.
@export var pylon_bolt_charge_sec: float = 0.9

@export_group("Lágrimas del Núcleo")
## Esencia que arrancan de media los combinados del Corazón por cada Lágrima: un golpe de daño D
## tiene D / tear_essence de probabilidad de soltar una (GDD 6.1). Ver tools/balance_sim.py.
@export var tear_essence: float = 12000.0
## Tope de esa probabilidad por golpe (un golpe enorme no da una Lágrima segura).
@export_range(0.0, 1.0) var tear_chance_max: float = 0.35
## Segundos de buen juego en el Corazón sin Lágrima tras los que la siguiente sale seguro.
@export var tear_pity_sec: float = 100.0
## Entre dos golpes al Corazón cuenta como buen juego como mucho esto (pasear no carga la
## piedad).
@export var tear_active_gap_sec: float = 6.0
## Con el Núcleo expuesto y sin Lágrimas para la Gran Convergencia, el Núcleo llora una cada
## tantos segundos de golpes combinados (nunca se queda la partida sin final).
@export var core_tear_pity_sec: float = 15.0
## Fracción del cristal destruida con la que el Núcleo queda expuesto (último 1 %, GDD 9).
@export_range(0.0, 1.0) var core_exposed_ratio: float = 0.99

@export_group("El final")
## Segundos que hay que mantener los dos botones para cargar la Gran Convergencia (GDD 9: "la
## carga dura varios segundos"). Va en cinco etapas, una por elemento.
@export var convergence_charge_sec: float = 5.5
## Con el cristal destruido a esta fracción se empieza a mirar cuánto queda de verdad a tiro
## (el volumen y la cuenta de esencia no cuadran del todo, y bajo el suelo hay celdas que no se
## pueden golpear): si lo que queda fuera del Núcleo y por encima del suelo es menos de
## `core_reveal_leftover` (fracción de la esencia total), el Núcleo queda expuesto igual.
@export_range(0.0, 1.0) var core_reveal_scan_from: float = 0.95
@export_range(0.0, 1.0) var core_reveal_leftover: float = 0.006
## Cada cuántos segundos se mira (en otro hilo).
@export var core_reveal_scan_sec: float = 15.0
## Segundos de fiesta en el valle tras romper el Núcleo antes de la pantalla final.
@export var ending_screen_delay_sec: float = 13.0

@export_group("Mesa de Runas")
## Pilón (progreso real) al que se abre la Mesa de Runas con su primera ranura (GDD 4.3).
@export_range(0.0, 1.0) var rune_table_pylon: float = 0.1
