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
