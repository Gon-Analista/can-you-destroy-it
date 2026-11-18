class_name HitStop
extends RefCounted
## Congelado breve del tiempo de juego al impactar (hit-stop). Si se encadenan varios,
## se respeta el que termina más tarde.
##
## Importante: la liberación nunca puede perderse. Si el temporizador termina antes de lo previsto
## (redondeo de milisegundos), se reprograma por el tiempo que falte; y si algo falla, un tope de
## seguridad devuelve la escala a 1 sí o sí.

const MAX_FREEZE_SEC: float = 0.5

## Velocidad normal del juego (1; el menú de depuración la sube a x2 o x5).
static var base_scale: float = 1.0
static var _until_msec: int = 0
static var _tree: SceneTree


static func trigger(tree: SceneTree, duration_sec: float, time_scale: float = 0.05) -> void:
	if duration_sec <= 0.0:
		return
	_tree = tree
	duration_sec = minf(duration_sec, MAX_FREEZE_SEC)
	var end: int = Time.get_ticks_msec() + int(ceil(duration_sec * 1000.0))
	_until_msec = maxi(_until_msec, end)
	Engine.time_scale = time_scale * base_scale
	_schedule(duration_sec)


## True mientras el hit-stop está activo.
static func is_active() -> bool:
	return Time.get_ticks_msec() < _until_msec


static func _schedule(seconds: float) -> void:
	# El temporizador ignora la escala de tiempo: dura `seconds` reales.
	_tree.create_timer(maxf(seconds, 0.001), true, false, true).timeout.connect(_release)


static func _release() -> void:
	var remaining_ms: int = _until_msec - Time.get_ticks_msec()
	if remaining_ms > 0 and remaining_ms <= int(MAX_FREEZE_SEC * 1000.0):
		_schedule(remaining_ms / 1000.0)
		return
	Engine.time_scale = base_scale
