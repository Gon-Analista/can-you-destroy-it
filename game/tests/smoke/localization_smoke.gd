extends SceneTree
## Idiomas: se cargan todos los del CSV, cada uno tiene nombre, ninguna traducción está vacía,
## los "%d"/"%s" de cada texto coinciden con los del español (si no, el juego peta al formatear)
## y cambiar de idioma cambia lo que devuelve tr().
## godot --headless --path game --script res://tests/smoke/localization_smoke.gd

const CSV_PATH: String = "res://localization/strings.csv"

var _frames: int = 0
var _ok: bool = true


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 2:
		return false
	var settings: Node = root.get_node(^"Settings")
	var codes: PackedStringArray = settings.call("locales")
	_check(codes.has("es") and codes.has("en"), "español e inglés cargados (%s)" % ", ".join(codes))
	var f := FileAccess.open(CSV_PATH, FileAccess.READ)
	var header: PackedStringArray = f.get_csv_line()
	_check(header[0] == "keys", "primera columna 'keys'")
	for col: int in range(1, header.size()):
		_check(codes.has(header[col]), "idioma %s cargado" % header[col])
	var spec := RegEx.create_from_string("%[-+0-9.]*[a-z%]")
	var rows: int = 0
	while not f.eof_reached():
		var row: PackedStringArray = f.get_csv_line()
		if row.size() < 2:
			continue
		rows += 1
		var want: Array = _specs(spec, row[0])
		for col: int in range(1, row.size()):
			_check(row[col] != "", "%s traducido a %s" % [row[0], header[col]])
			_check(_specs(spec, row[col]) == want, "formato de '%s' en %s" % [row[0], header[col]])
	_check(rows > 100, "hay textos (%d)" % rows)
	settings.call("set_locale", "en")
	_check(TranslationServer.translate("NUEVA PARTIDA") == "NEW GAME", "tr en inglés")
	_check(str(settings.call("language_name", "en")) == "ENGLISH", "nombre del inglés")
	settings.call("set_locale", "es")
	_check(TranslationServer.translate("NUEVA PARTIDA") == "NUEVA PARTIDA", "tr en español")
	settings.set("locale", "")
	settings.call("save_settings")
	print("localization_smoke: ", "OK" if _ok else "FALLO")
	quit(0 if _ok else 1)
	return false


func _specs(spec: RegEx, text: String) -> Array:
	var out: Array = []
	for m: RegExMatch in spec.search_all(text):
		out.append(m.get_string())
	return out


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		push_error("FALLO: " + what)
