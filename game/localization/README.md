# Idiomas

Todos los textos del juego están en `strings.csv`: una fila por texto y una columna por idioma.

- La columna `keys` es la clave: el texto en español tal cual aparece en el código y en los
  recursos (`tr("NUEVA PARTIDA")`, `display_name = "Bola de Fuego"`...).
- La fila `LANGUAGE_NAME` es el nombre del idioma tal como sale en *Opciones → Idioma*.
- `%d`, `%s`, `%.1f` y `%%` se tienen que quedar en todas las traducciones, en el mismo orden
  (la prueba `tests/smoke/localization_smoke.gd` lo comprueba).

## Añadir un idioma

1. Añade una columna al CSV con el código del idioma (`fr`, `pt_BR`, `de`...) y rellénala
   (una hoja de cálculo sirve; guarda en UTF-8 con comas).
2. Abre el proyecto en Godot (o `godot --headless --path game --import`): genera
   `strings.<código>.translation`.

Nada más: `autoload/settings.gd` carga todos los `.translation` de esta carpeta, el idioma
aparece en Opciones y, si coincide con el del sistema, se elige solo la primera vez.
Para probarlo sin tocar las opciones: `godot --path game -- --lang fr`.

## Textos nuevos

Escribe el texto en español dentro de `tr("...")` (o en los campos de texto de un recurso) y
ejecuta `python3 tools/extract_strings.py`: añade las claves nuevas al CSV sin borrar las
traducciones que ya hay. Lo que falte por traducir se ve en español.

Las listas de textos fijas (frases del título, nombres de las páginas del Grimorio) se marcan
con un comentario `# i18n` justo encima de la constante para que el extractor las encuentre, y
se traducen al mostrarlas con `tr(LISTA[i])`.
