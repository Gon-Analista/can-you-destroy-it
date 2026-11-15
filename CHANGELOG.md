# Changelog

Cada push a `main` se documenta aquí, el más reciente arriba (ver `.agents/dev_guidelines.md`, sección 12).

## 2026-11-15 · Manos pixel art en primera persona (Sprite AI), 3 tamaños de fragmento y recogida

**Qué hay nuevo**

- **Manos del mago nuevas**: sprites pixel art 2D en primera persona generados con Sprite AI, en 4 poses
  (abierta, carga con el orbe entre los dedos, lanzar, reposo). La izquierda es el sprite original (pulgar hacia
  fuera) y la derecha su reflejo. Animación por código a píxel entero: respiración, paso al caminar, empujón con
  rebote al lanzar, cambio de pose según la recarga y tirón al recoger. La chispa sale de la palma que se ve.
- **Orbe mágico** de Sprite AI flotando sobre la palma mientras se carga; brilla al estar listo.
- **3 tamaños de fragmento** según el daño del golpe: **astilla** (aguja fina, daño 1-2), **fragmento** (el de
  antes, daño 3-9) y **fragmento grande** (daño 10+). Un golpe resonante sube un tamaño. Datos en `game/data/shards/`.
- **Recoger fragmentos con F**: el que apuntas (o el más cercano delante) se resalta y aparece "[F] RECOGER
  ASTILLA"; al recogerlo vuela a la mano encogiéndose, suena un "bloop" (más grave cuanto más grande), sale "+1"
  y la **bolsa** (abajo a la derecha) cuenta por tipo. Mantener F recoge en cadena. Todavía no se entregan.
- **Sprite AI integrado**: `.mcp.json` con el servidor `sprite-ai` (clave por variable `SPRITE_AI_API_KEY`, nunca en
  el repo), cliente `tools/sprite_ai/sai.py`, guía y registro de sprites en `docs/sprite_ai.md`, sección 15 de las guías.
- **Documentación**: GDD v0.4 (tamaños de fragmento, control F, manos 2D), contexto y guías actualizados, créditos.

**Capturas**: `docs/capturas/manos_2d_golpe.png`, `docs/capturas/manos_2d_recoger.png`.

**Cómo se probó**

- Godot 4.7 headless sin errores de script; `progression_smoke` (con la bolsa) y `hit_stop_smoke`: OK; `gdlint` limpio.
- Render Forward+ con el modo demo nuevo `--collect` (camina al cristal y mantiene F): recoge y la bolsa cuenta.

**Pendiente y problemas conocidos**

- Los 15 tokens de la cuenta 1 de Sprite AI están gastados; más poses o efectos necesitan otra cuenta.
- La bolsa no tiene límite de capacidad todavía (el GDD pide empezar con 1) ni se entrega al Pilón (M1b).
- Confirmar los términos de uso comercial de Sprite AI.

## 2026-11-15 · Hotfix: el tiempo se quedaba congelado tras un golpe fuerte

- **Bug**: tras un hit-stop (golpe resonante o daño 5+), a veces el juego no volvía a la velocidad normal.
  Causa: si el temporizador terminaba 1 ms antes de lo previsto (redondeo), la escala de tiempo no se restauraba nunca.
- **Arreglo** (`game/fx/hit_stop.gd`): si el temporizador llega antes, se reprograma por lo que falte; tope de 0,5 s por congelado;
  y red de seguridad en `main.gd` que restaura la escala si no hay hit-stop activo.
- **Test de regresión**: `tests/smoke/hit_stop_smoke.gd` (OK). Autoplay a nivel 5 durante 15 s: escala de tiempo 1.0 al final.

## 2026-11-15 · Prototipo M1a "El golpe": arte base, la chispa y la reacción del cristal

**Qué hay nuevo**

- **Arte base pixel art** siguiendo el GDD y las referencias, todo generado por código y renderizado a 640x360:
  - valle con suelo ondulado, ~900 pinos, montañas nevadas, colina con castillo de tejados azules y aldea de tejados rojos;
  - cielo pixel art con degradado tramado y nubes de tres tonos, niebla de profundidad;
  - Cristal Madre según la referencia (racimo de 15 prismas, bandas de paleta, corazón violeta en la base, brillo que recorre las facetas);
  - manos del mago en primera persona (mangas violeta, brazaletes dorados, palmas hacia arriba) con animación procedural;
  - contorno de 1 píxel por post-proceso y luz por bandas.
- **Un hechizo: la Chispa**, con 5 niveles de poder (en debug, teclas 1-5) que cambian daño, cadencia, velocidad, tamaño, color, fragmentos, partículas, luz, grietas y sacudida.
- **Reacción completa del cristal** (GDD 10.3): destello y onda en la faceta, grieta persistente, temblor, pulso del corazón, fragmentos físicos que rebotan y brillan, estrellas, esquirlas, anillo, luz, sacudida de cámara y hit-stop.
- **Dopamina** (GDD 10.4): racha cuyo "tink" sube por una escala pentatónica, hitos de racha con aviso y campanilla, golpe resonante (7 %, daño x3, destello dorado), buffer de clic de 0,3 s.
- **Sonido**: 20 efectos sintetizados (`tools/sfx_synth.py`), ambiente del valle y zumbido del cristal en bucle.
- **HUD**: Esencia con número rodante, mira con anillo de carga y marcador de impacto, racha, avisos y números flotantes. Fuentes Silkscreen y Pixelify Sans (OFL, ver `CREDITS.md`).
- **Documentación**: GDD v0.3 (nuevas secciones 10.3 y 10.4, HUD y render actualizados), contexto del proyecto, guías (regla "todo es reactivo", trampas del pipeline, flujo de push a `main` con changelog).

**Capturas**: `docs/capturas/prototipo_golpe.png`, `docs/capturas/prototipo_chispa_nivel1.gif`, `docs/capturas/prototipo_chispa_nivel4.gif`.

**Cómo se probó**

- Godot 4.7 headless: importación y ejecución sin errores de script.
- `tests/smoke/progression_smoke.gd`: OK (añadidos tests de racha).
- `gdlint` y `gdformat`: sin problemas.
- Render con Forward+ (Vulkan por software) y modo demo `--autoplay` a niveles 1 y 4; revisión visual frame a frame.

**Pendiente y problemas conocidos**

- No se ha medido el rendimiento en GPU real ni en Steam Deck (el render de prueba es por software).
- Al cerrar en headless aparecen avisos de "leaked instances" de audio OGG en bucle: es del motor (pasa también en un proyecto vacío).
- Aún no se pueden recoger ni entregar fragmentos; no hay Pilón físico ni mejoras compradas (siguiente hito, M1b).

## 2026-11-15 · Proyecto Godot 4.7 y godot-mcp

- Proyecto en `game/` con configuración pixel art (640x360, escalado entero), autoloads, reglas de progreso con test y escena provisional.
- `.mcp.json` con `@coding-solo/godot-mcp@0.1.1`.

## 2026-11-15 · GDD v0.2, guías y contexto

- GDD v0.2 con estilo pixel art y Godot 4.7; `AGENTS.md`, `.agents/project_context.md` y `.agents/dev_guidelines.md`.
