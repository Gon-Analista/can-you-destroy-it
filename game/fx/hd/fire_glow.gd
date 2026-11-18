class_name FireGlow
extends RefCounted
## Luz cálida de la Bola de Fuego sobre el Cristal Madre. El cristal no usa la iluminación del
## motor (shader `unshaded`): lee esta luz de dos parámetros globales de shader (`fire_glow`,
## `fire_glow_color`). Si hay varias bolas a la vez, gana la más fuerte de cada fotograma.

static var _frame: int = -1
static var _best: float = -1.0


## Pone la luz en `pos` con radio `radius` (m) y fuerza 0..1 (0 la apaga).
static func put(pos: Vector3, radius: float, color: Color, strength: float) -> void:
	var f: int = Engine.get_process_frames()
	if f != _frame:
		_frame = f
		_best = -1.0
	if strength <= _best:
		return
	_best = strength
	RenderingServer.global_shader_parameter_set(&"fire_glow", Vector4(pos.x, pos.y, pos.z, radius))
	RenderingServer.global_shader_parameter_set(
		&"fire_glow_color", Color(color.r, color.g, color.b, clampf(strength, 0.0, 1.0))
	)
