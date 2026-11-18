class_name TearDrops
extends RefCounted
## Reglas puras de las Lágrimas del Núcleo (GDD 6.1): cuándo suelta una Lágrima un golpe. Sin
## nodos: se puede testear aislado (tests/smoke/core_tears_smoke.gd) y lo copia el simulador
## (tools/balance_sim.py).
##
## - Sólo cuentan los hechizos combinados que arrancan Corazón Cristalino (capa 3).
## - Cada uno tiene daño / `tear_essence` de probabilidad (con tope `tear_chance_max`), por el
##   multiplicador del Ojo del Núcleo.
## - Piedad: los segundos entre golpes al Corazón (como mucho `tear_active_gap_sec` cada vez) se
##   suman en `Progression.tear_pity`; al llegar a `tear_pity_sec`, la siguiente sale seguro.
## - Con el Núcleo expuesto y sin Lágrimas para la Gran Convergencia, los combinados que rebotan
##   en el Núcleo sólo cargan la piedad, con `core_tear_pity_sec` de tope.

const HEART_LAYER: int = 3
const CORE_LAYER: int = 4

var balance: BalanceConfig
## Momento del último golpe que contó (en el reloj de quien llama), -1 = ninguno.
var _last_hit: float = -1.0


func _init(p_balance: BalanceConfig) -> void:
	balance = p_balance


## Probabilidad de que un golpe de `damage` en el Corazón suelte una Lágrima.
func chance_for(damage: int, chance_mult: float = 1.0) -> float:
	if damage <= 0 or balance.tear_essence <= 0.0:
		return 0.0
	return clampf(float(damage) / balance.tear_essence * chance_mult, 0.0, balance.tear_chance_max)


## Un golpe combinado ha arrancado Corazón: suma su tiempo a la piedad y decide si suelta una
## Lágrima (`roll` en 0..1, el azar de quien llama). Si la suelta, la piedad vuelve a 0.
func register_heart_hit(
	prog: Progression, now: float, damage: int, roll: float, chance_mult: float = 1.0
) -> bool:
	_add_active(prog, now)
	if prog.tear_pity >= balance.tear_pity_sec or roll < chance_for(damage, chance_mult):
		prog.tear_pity = 0.0
		return true
	return false


## Un combinado rebota en el Núcleo expuesto: si a la partida le faltan Lágrimas para la Gran
## Convergencia (`needed` > 0), la piedad corre y el Núcleo llora una cada `core_tear_pity_sec`.
func register_core_hit(prog: Progression, now: float, needed: int) -> bool:
	if needed <= 0:
		return false
	_add_active(prog, now)
	if prog.tear_pity >= balance.core_tear_pity_sec:
		prog.tear_pity = 0.0
		return true
	return false


func _add_active(prog: Progression, now: float) -> void:
	if _last_hit >= 0.0:
		prog.tear_pity += clampf(now - _last_hit, 0.0, balance.tear_active_gap_sec)
	_last_hit = now
