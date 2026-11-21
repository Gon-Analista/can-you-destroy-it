class_name PlayStats
extends RefCounted
## Cifras de la partida para el Espejo del Archimago (GDD 4.3): cuentas que sólo suben (hechizos,
## fragmentos, maná ganado...), mejores marcas (racha) y el tiempo jugado. Vive en `Progression`
## y se guarda con ella. Las claves las pone quien cuenta (ver `GameState.STAT_*`).

var counts: Dictionary[StringName, int] = {}
## Tiempo jugado (s), sin contar menús ni pausa.
var play_time: float = 0.0


## Suma `n` a la cifra `key` (p. ej. &"spells_cast").
func count(key: StringName, n: int = 1) -> void:
	counts[key] = counts.get(key, 0) + n


## Guarda `value` en la cifra `key` si supera la marca (p. ej. &"best_streak").
func record_best(key: StringName, value: int) -> void:
	if value > counts.get(key, 0):
		counts[key] = value


## Valor de una cifra (0 si aún no se ha contado).
func tally(key: StringName) -> int:
	return counts.get(key, 0)


func to_dict() -> Dictionary:
	return {"counts": counts.duplicate(), "play_time": play_time}


func load_dict(data: Dictionary) -> void:
	counts.clear()
	var saved: Dictionary = data.get("counts", {})
	for key: Variant in saved:
		counts[StringName(str(key))] = maxi(VariantCast.to_int(saved[key]), 0)
	play_time = maxf(VariantCast.to_float(data.get("play_time", 0.0)), 0.0)
