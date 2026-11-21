class_name ChargeStages
extends RefCounted
## Carga por etapas de los hechizos combinados: la carga (0..1 en `SpellRecipe.charge_sec`) se
## parte en `count` etapas iguales, una por círculo mágico. Cada vez que se completa una, el
## círculo encaja con su golpe (ver `ChargeFeedback`); la última es la potencia completa.
##
## El poder al soltar es el de la última etapa completada, medido sobre la misma curva de
## siempre: la etapa `s` de `n` vale lo que valía la carga continua `s / n`
## (`SpellRecipe.damage_for`). Con 0 etapas (niveles bajos) la carga sigue siendo continua.
##
## Ritmo: cada etapa dura al menos `BalanceConfig.charge_stage_min_sec` (si no, a nivel 10 la Bola
## de Fuego encajaría 5 círculos en 0,7 s, un redoble sin tiempo de sentir cada uno). El tiempo
## de más se descuenta de la recarga en proporción a la carga soltada (`cooldown_after`), así que
## el ciclo carga + recarga para cualquier carga `k` es el de siempre (`k * charge_sec` +
## recarga): el daño por segundo y el simulador de balance no cambian.
##
## Lógica pura (sin escena ni autoloads) para poder probarla en `charge_stages_smoke.gd`.

## Tope de etapas (y de círculos de carga en las manos, `MagicCircles.MAX_CHARGE_CIRCLES`).
const MAX_STAGES: int = 5

## Etapas de la carga actual (0 = carga continua, sin etapas).
var count: int = 0
## Etapas ya completadas (0..count).
var reached: int = 0
## Segundos de la carga completa (`SpellRecipe.charge_sec`, alargada si hay muchas etapas).
var duration: float = 0.7
## Segundos de más respecto a `SpellRecipe.charge_sec` (se devuelven de la recarga).
var stretch: float = 0.0


## Etapas de un combinado de nivel `level` (1..10) según la tabla de balance
## (`BalanceConfig.charge_stages_by_level`, una entrada por nivel).
static func count_for_level(level: int, table: PackedInt32Array) -> int:
	if table.is_empty() or level < 1:
		return 0
	return clampi(table[clampi(level, 1, table.size()) - 1], 0, MAX_STAGES)


## Premio de la carga completa de un combinado de nivel `level` (`BalanceConfig.
## full_charge_bonus_by_level`) para un hechizo con `payoff` (`SpellRecipe.charge_payoff`: 1 = se
## carga, 0 = de toque).
static func full_bonus(level: int, table: PackedFloat32Array, payoff: float) -> float:
	if table.is_empty() or level < 1:
		return 1.0
	var full: float = table[clampi(level, 1, table.size()) - 1]
	return maxf(1.0, 1.0 + (full - 1.0) * clampf(payoff, 0.0, 1.0))


## Multiplicador de daño por la carga para el daño (`k` ya cuantizada, 0..1): el premio completo
## se reparte geométricamente entre las etapas (cada círculo que encaja multiplica lo mismo).
static func bonus(k: float, full: float) -> float:
	return pow(maxf(full, 1.0), clampf(k, 0.0, 1.0))


## Etapa completada con la carga `k` (0..1) si hay `n` etapas.
static func stage_at(k: float, n: int) -> int:
	if n <= 0:
		return 0
	# El margen evita que el redondeo deje la última etapa sin completar con k = 1.
	return clampi(floori(clampf(k, 0.0, 1.0) * float(n) + 0.0001), 0, n)


## Carga equivalente (0..1) para el daño: la de la última etapa completada.
static func quantize(k: float, n: int) -> float:
	if n <= 0:
		return clampf(k, 0.0, 1.0)
	return float(stage_at(k, n)) / float(n)


## Etapa en la que aparece el círculo `circle` (0..circles-1) si hay `circles` círculos y `n`
## etapas: se reparten en grupos, el último círculo con la última etapa.
static func stage_of_circle(circle: int, circles: int, n: int) -> int:
	if n <= 0 or circles <= 0:
		return 0
	return clampi(ceili(float((circle + 1) * n) / float(circles)), 1, n)


## Duración de la carga completa con `n` etapas: la del hechizo, o más si así cada etapa no
## llegaría a `min_stage_sec`.
static func duration_for(charge_sec: float, n: int, min_stage_sec: float) -> float:
	return maxf(charge_sec, float(clampi(n, 0, MAX_STAGES)) * min_stage_sec)


## Empieza una carga nueva con `n` etapas, para un hechizo que se carga en `charge_sec` y con
## etapas de al menos `min_stage_sec`.
func reset(n: int, charge_sec: float = 0.7, min_stage_sec: float = 0.0) -> void:
	count = clampi(n, 0, MAX_STAGES)
	reached = 0
	duration = maxf(duration_for(charge_sec, count, min_stage_sec), 0.001)
	stretch = duration - charge_sec


## Carga (0..1) tras `seconds` manteniendo.
func charge_at(seconds: float) -> float:
	return clampf(seconds / duration, 0.0, 1.0)


## Recarga tras soltar con la carga `k`: la de siempre (`cooldown`) menos el tiempo de más que
## costó llegar a esa carga, sin bajar de `floor_sec`.
func cooldown_after(cooldown: float, k: float, floor_sec: float) -> float:
	return maxf(cooldown - stretch * clampf(k, 0.0, 1.0), minf(floor_sec, cooldown))


## Avanza con la carga `k`. Devuelve la etapa recién completada (si en un fotograma largo se
## completan dos, sólo la más alta: un único golpe) o 0 si no se completó ninguna.
func advance(k: float) -> int:
	var s: int = stage_at(k, count)
	if s <= reached:
		return 0
	reached = s
	return s


## Carga para el daño al soltar con la carga `k`.
func power_charge(k: float) -> float:
	return quantize(k, count)


func is_staged() -> bool:
	return count > 0


func is_full() -> bool:
	return count > 0 and reached >= count
