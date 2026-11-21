class_name VariantCast
extends RefCounted
## Pasa un `Variant` de origen dinámico (un JSON o un ConfigFile cargados, un `get()` o `call()`
## por nombre en los tests) a un tipo concreto, con el mismo resultado que `int()`, `float()` y
## `bool()` pero tipado, para que el analizador no avise de argumento inseguro.
## Con números y booleanos convierte como el constructor (`int(3.7)` = 3, trunca hacia cero); un
## texto se lee como número igual que `int("7")`; lo demás (p. ej. `null`) da error como antes.


static func to_int(value: Variant) -> int:
	if value is String:
		return str(value).to_int()
	var out: int = value
	return out


static func to_float(value: Variant) -> float:
	if value is String:
		return str(value).to_float()
	var out: float = value
	return out


static func to_bool(value: Variant) -> bool:
	var out: bool = value
	return out
