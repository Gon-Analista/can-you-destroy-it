# Créditos y licencias

## Fuentes

| Recurso | Archivo | Autor | Licencia |
|---|---|---|---|
| Fusion Pixel Font (letras latinas de Ark Pixel Font) | `game/ui/fonts/fusion_pixel_*.woff2` | TakWolf y colaboradores | SIL Open Font License 1.1 (`game/ui/fonts/FUSION_PIXEL_OFL.txt`) |
| Pixelify Sans (sólo el logotipo) | `game/ui/fonts/pixelify_sans_bold.woff2` | The Pixelify Sans Project Authors (Stefie Justprince) | SIL Open Font License 1.1 (`game/ui/fonts/PIXELIFY_SANS_OFL.txt`) |

Pixelify Sans viene del paquete de Fontsource (`@fontsource/pixelify-sans`). Fusion Pixel viene del
paquete npm `@vp-tw/cjk-web-fonts-fusion-pixel-font` (subconjuntos de la versión 2026.08.11);
`tools/make_ui_fonts.py` junta los bloques latinos y genera las negritas.

## Arte generado con Sprite AI

Las manos del mago (`game/player/hands/`) y el orbe mágico (`game/fx/textures/magic_orb.png`) se generaron con
Sprite AI (https://www.sprite-ai.art) desde la cuenta del equipo. Registro y ids en `docs/sprite_ai.md`.
Pendiente: confirmar los términos de uso comercial de Sprite AI antes de publicar.

## Arte y sonido propios

El resto del arte y todo el sonido del prototipo son propios, generados por código en este repo
(`game/core/mesh_kit.gd`, `game/world/`, `game/crystal/`, `tools/sfx_synth.py`).

`docs/referencias/` contiene imágenes de referencia, no se usan como recursos del juego.
