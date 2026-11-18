class_name FireGlow
extends RefCounted
## Luz cálida de la Bola de Fuego sobre el Cristal Madre. El cristal no usa la iluminación del
## motor (shader `unshaded`): lee esta luz de dos parámetros globales de shader (`fire_glow`,
## `fire_glow_color`). Si hay varias bolas a la vez, gana la más fuerte de cada fotograma; sólo
## la que la tiene puede apagarla (`clear`).

static var _frame: int = -1
static var _best: float = -1.0
## Instancia que tiene la luz ahora (0: ninguna) y su fuerza.
static var _owner: int = 0
static var _strength: float = 0.0


## `owner` pone la luz en `pos` con radio `radius` (m) y fuerza 0..1.
static func put(owner: Object, pos: Vector3, radius: float, color: Color, strength: float) -> void:
	var f: int = Engine.get_process_frames()
	if f != _frame:
		_frame = f
		_best = -1.0
	if strength <= _best:
		return
	_best = strength
	_owner = owner.get_instance_id()
	_strength = clampf(strength, 0.0, 1.0)
	RenderingServer.global_shader_parameter_set(&"fire_glow", Vector4(pos.x, pos.y, pos.z, radius))
	RenderingServer.global_shader_parameter_set(
		&"fire_glow_color", Color(color.r, color.g, color.b, _strength)
	)


## Apaga la luz si la tiene `owner` (al llegar, al pararse o al salir del árbol). Otra bola que
## siga en vuelo la recoge al fotograma siguiente.
static func clear(owner: Object) -> void:
	if _owner != owner.get_instance_id():
		return
	_owner = 0
	_best = -1.0
	_strength = 0.0
	RenderingServer.global_shader_parameter_set(&"fire_glow_color", Color(1.0, 0.5, 0.2, 0.0))


## Fuerza de la luz ahora (0: apagada). Para los tests.
static func strength() -> float:
	return _strength
