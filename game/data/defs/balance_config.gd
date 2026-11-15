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
## Tiempo máximo entre golpes para mantener la racha.
@export var streak_window_sec: float = 2.6
## Rachas que disparan campanilla y celebración.
@export var streak_milestones: PackedInt32Array = PackedInt32Array([5, 10, 25, 50, 100])
## Probabilidad de golpe resonante (crítico) sin mejoras.
@export_range(0.0, 1.0) var resonant_chance: float = 0.07
@export var resonant_damage_mult: int = 3
