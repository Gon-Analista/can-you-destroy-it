# Sprite AI: arte pixel art por IA

Como no hay artista, los sprites a mano (por ahora, las manos del mago y el orbe) se generan con
**Sprite AI** (https://www.sprite-ai.art), que tiene un servidor MCP.

## La clave nunca va al repo

- **En local (Claude Code)**: define la variable de entorno `SPRITE_AI_API_KEY` con tu clave `sai_sk_…`.
  El `.mcp.json` del repo ya trae el servidor `sprite-ai` y lee la clave de esa variable.
- **En sesiones en la nube**: la clave se guarda como **secreto de red del entorno** `can-you-destroy-it`
  para el host `www.sprite-ai.art`; el proxy la inyecta solo. No hace falta definir nada.
- **Cuenta nueva** (el plan gratis trae 15 tokens): genera la clave en sprite-ai.art y actualiza la
  variable local o el secreto del entorno (en la nube: pedírselo al agente, que abre el formulario seguro).
  Nunca la pegues en un archivo del repo, en un commit ni en el chat.

## Cómo llamarlo sin MCP

`tools/sprite_ai/sai.py` es un cliente mínimo del mismo servidor (útil si el MCP no está cargado):

```bash
python3 tools/sprite_ai/sai.py call sprite_get_balance
```

```bash
python3 tools/sprite_ai/sai.py call sprite_capabilities
```

```bash
python3 tools/sprite_ai/sai.py call sprite_generate '{"prompt": "...", "asset_type": "prop", "width": 192, "height": 192}'
```

La respuesta incluye la imagen en base64 y una URL de descarga sin autenticación.

## Costes (plan gratis: 15 tokens)

| Herramienta | Coste | Uso en este proyecto |
|---|---|---|
| `sprite_generate` | 1 | Imagen nueva desde texto. |
| `sprite_restyle` (modo `pose`, normal) | 2 | Otra pose del mismo personaje: **la forma barata de hacer animaciones**. |
| `sprite_generate_animation` | 14-20 | Hoja animada. Se lleva casi una cuenta entera: evitar. |
| `sprite_rotate` | 12 | 8 direcciones. No aplica a primera persona. |
| `sprite_combine` | 3 | Meter un objeto de un sprite en otro. |
| `sprite_normal_map` | 1 por frame | Normal map para iluminar el sprite en Godot. |

**Estrategia**: generar 1 imagen base (1 token) y sacar poses con `restyle` en modo `pose` (2 tokens cada
una). La animación entre poses se hace en Godot por código (empujones, rebotes, balanceo a píxel entero).
Así una cuenta da 1 base + 7 poses.

## Reglas para que salga bien

- **Primera persona**: pedir explícitamente "seen from the wizard own eyes", antebrazo entrando por abajo,
  `camera_perspective: top_down`. Con la vista por defecto (`side`) sale de perfil y no sirve.
- El prompt describe el sujeto y sus materiales; nada de "pixel art" ni palabras de animación
  ("animate", "walk cycle"…): el generador las rechaza.
- Una mano izquierda con la palma hacia la cámara tiene el **pulgar a la izquierda**. Comprobar la
  lateralidad antes de usar un sprite y reflejar para la otra mano.
- Tamaño: las manos van a 192x192 sobre una pantalla de 640x360, sin escalar. Por encima de 256 ya no se
  puede animar ni cambiar de pose.
- Mantener la paleta de la referencia (mangas violeta oscuro, oro, gemas azules, piel cálida).

## Registro de lo generado

Los ids sirven para seguir trabajando sobre el mismo sprite (más poses, normal maps…) desde la cuenta que los creó.

| Archivo | Qué es | Id (cuenta 1) | Coste |
|---|---|---|---|
| `game/player/hands/hand_l_open.png` | Mano izquierda, palma abierta (base) | `f704df86-8189-4ee8-b255-a8542f07865c` | 1 |
| `game/player/hands/hand_l_charge.png` | Dedos recogidos sujetando el orbe | `5a87cc68-ec51-4e75-add8-8c8cf8d89946` | 2 |
| `game/player/hands/hand_l_cast.png` | Dedos abiertos empujando (lanzar) | `789853d2-f2e8-4465-914a-b654b2a1e070` | 2 |
| `game/player/hands/hand_l_rest.png` | Mano relajada (recargando) | `373a54d2-eeb4-4f21-992c-1012b9c4a90f` | 2 |
| `game/fx/textures/magic_orb.png` | Orbe mágico 48x48 | `aaad1030-c887-4f38-a0bd-06519b38dfb8` | 1 |
| `art_source/sprite_ai/side_*.png` | Primer intento de perfil (descartado para primera persona) | `60fcf7d9-…` y restyles | 7 |

Cuenta 1: 15 de 15 tokens gastados.
