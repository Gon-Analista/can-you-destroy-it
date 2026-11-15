class_name HitStop
extends RefCounted
## Congelado breve del tiempo de juego al impactar (hit-stop). Si se encadenan varios,
## se respeta el que termina más tarde.

static var _until_msec: int = 0


static func trigger(tree: SceneTree, duration_sec: float, time_scale: float = 0.05) -> void:
	if duration_sec <= 0.0:
		return
	var end: int = Time.get_ticks_msec() + int(duration_sec * 1000.0)
	_until_msec = maxi(_until_msec, end)
	Engine.time_scale = time_scale
	# El temporizador ignora la escala de tiempo: dura `duration_sec` reales.
	tree.create_timer(duration_sec, true, false, true).timeout.connect(_release)


static func _release() -> void:
	if Time.get_ticks_msec() >= _until_msec:
		Engine.time_scale = 1.0
