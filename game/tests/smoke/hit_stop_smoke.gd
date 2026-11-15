extends SceneTree
## Regresión: el tiempo se quedaba congelado tras un hit-stop.
## Encadena hit-stops con duraciones que provocan redondeo y comprueba que la escala vuelve a 1.
## godot --headless --path game --script res://tests/smoke/hit_stop_smoke.gd

var _frames: int = 0


func _init() -> void:
	for d: float in [0.025, 0.09, 0.0251, 0.001, 0.3]:
		HitStop.trigger(self, d)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 120:
		return false
	var ok: bool = is_equal_approx(Engine.time_scale, 1.0)
	print("hit_stop_smoke: %s" % ("OK" if ok else "FALLO (time_scale=%f)" % Engine.time_scale))
	quit(0 if ok else 1)
	return false
