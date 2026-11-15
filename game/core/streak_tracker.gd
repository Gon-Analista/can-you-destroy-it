class_name StreakTracker
extends RefCounted
## Racha de golpes seguidos. Lógica pura (testeable): se le pasa el tiempo actual.

var window_sec: float
var streak: int = 0
var _last_hit_time: float = -INF


func _init(p_window_sec: float) -> void:
	window_sec = p_window_sec


## Registra un golpe y devuelve la racha resultante.
func register_hit(now: float) -> int:
	if now - _last_hit_time <= window_sec:
		streak += 1
	else:
		streak = 1
	_last_hit_time = now
	return streak


## True si la racha sigue viva en `now`.
func is_alive(now: float) -> bool:
	return streak > 0 and now - _last_hit_time <= window_sec


## Pone la racha a cero si caducó. Devuelve true si acaba de romperse.
func expire(now: float) -> bool:
	if streak > 0 and not is_alive(now):
		streak = 0
		return true
	return false
