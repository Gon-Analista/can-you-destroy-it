#!/usr/bin/env python3
"""Saca todos los textos del juego a game/localization/strings.csv (para traducir).

Uso:
    python3 tools/extract_strings.py

Las claves son los textos en español tal cual aparecen en el código y en los datos. Recoge:
- en los scripts: tr("..."), _tr("..."), _label("..."), _button("..."), _slider("...") y las constantes
  (texto o lista de textos) marcadas con `# i18n` en la línea anterior;
- en los recursos .tres: display_name, display_name_plural, description, value_format,
  too_hard_hint, riddle, motto, requirement, combo_note, level_names y vein_names.

Conserva las traducciones que ya haya en el CSV (no borra columnas ni filas que sigan en uso) y
añade las claves nuevas con su texto español y las demás columnas vacías (el juego muestra la
clave si falta una traducción).

Para añadir un idioma: añade una columna al CSV con su código (p. ej. "fr", "pt_BR") y rellénala.
La fila LANGUAGE_NAME lleva el nombre del idioma tal como se muestra en Opciones. No hay que
tocar código: el juego carga todos los idiomas que encuentre (ver autoload/settings.gd).
"""
import csv
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "game"
CSV_PATH = ROOT / "localization" / "strings.csv"

CALL_RE = re.compile(r'\b(?:tr|_tr|_label|_button|_slider)\(\s*"((?:[^"\\]|\\.)*)"')
I18N_BLOCK_RE = re.compile(r"#\s*i18n\s*\n\s*const\s+\w+[^=]*=\s*\[(.*?)\]\n", re.S)
I18N_CONST_RE = re.compile(r'#\s*i18n\s*\n\s*const\s+\w+[^=]*=\s*"((?:[^"\\]|\\.)*)"')
# Cadenas normales (no StringName &"..." ni colores "#rrggbb").
STR_RE = re.compile(r'(&?)"((?:[^"\\]|\\.)*)"')
TRES_FIELDS = re.compile(
    r'^(display_name|display_name_plural|description|value_format|too_hard_hint|riddle|motto|requirement|combo_note) = "((?:[^"\\]|\\.)*)"',
    re.M,
)
TRES_LIST = re.compile(r"^(?:level_names|vein_names) = PackedStringArray\((.*)\)", re.M)


def unescape(s: str) -> str:
    return s.encode("utf-8").decode("unicode_escape").encode("latin-1").decode("utf-8")


def collect() -> list[str]:
    keys: list[str] = []
    seen: set[str] = set()

    def add(k: str) -> None:
        k = unescape(k)
        bare = re.sub(r"%[-+0-9.]*[a-z%]", "", k)
        if k and k not in seen and not k.startswith("#") and any(c.isalpha() or c in "¡¿" for c in bare):
            seen.add(k)
            keys.append(k)

    for path in sorted(ROOT.rglob("*.gd")):
        if {"addons", "tests", ".godot"} & set(path.parts):
            continue
        text = path.read_text(encoding="utf-8")
        for mm in CALL_RE.finditer(text):
            add(mm.group(1))
        for mm in I18N_CONST_RE.finditer(text):
            add(mm.group(1))
        for block in I18N_BLOCK_RE.finditer(text):
            for sm in STR_RE.finditer(block.group(1)):
                if not sm.group(1):
                    add(sm.group(2))
    for path in sorted(ROOT.rglob("*.tres")):
        if ".godot" in path.parts:
            continue
        text = path.read_text(encoding="utf-8")
        for mm in TRES_FIELDS.finditer(text):
            add(mm.group(2))
        for mm in TRES_LIST.finditer(text):
            for sm in STR_RE.finditer(mm.group(1)):
                if not sm.group(1):
                    add(sm.group(2))
    return keys


def main() -> None:
    keys = collect()
    langs = ["es", "en"]
    rows: dict[str, dict[str, str]] = {}
    if CSV_PATH.exists():
        with CSV_PATH.open(encoding="utf-8", newline="") as f:
            reader = csv.DictReader(f)
            langs = [c for c in reader.fieldnames if c != "keys"]
            for r in reader:
                rows[r["keys"]] = {l: r.get(l, "") or "" for l in langs}
    out_keys = ["LANGUAGE_NAME"] + keys
    CSV_PATH.parent.mkdir(parents=True, exist_ok=True)
    with CSV_PATH.open("w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["keys"] + langs)
        for k in out_keys:
            r = rows.get(k, {})
            vals = []
            for l in langs:
                v = r.get(l, "")
                if not v and l == "es":
                    v = "ESPAÑOL" if k == "LANGUAGE_NAME" else k
                vals.append(v)
            w.writerow([k] + vals)
    missing = {l: sum(1 for k in out_keys if not rows.get(k, {}).get(l)) for l in langs if l != "es"}
    print(f"{len(out_keys)} textos en {CSV_PATH.relative_to(ROOT.parent)}; sin traducir: {missing}")


if __name__ == "__main__":
    main()
