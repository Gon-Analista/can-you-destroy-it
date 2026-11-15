# Changelog

Cada push a `main` se documenta aquí, el más reciente arriba (ver `.agents/dev_guidelines.md`, sección 12).

## 2026-11-15 · Sonidos de la Bola de Fuego

**Qué hay nuevo** (sólo audio; la integración en el juego la hace la sesión de las manos)

- **`tools/sfx_fireball.py`**: sintetiza los sonidos de la Bola de Fuego y de descubrir una combinación, reutilizando
  `sfx_synth.py`. Deterministas. En `game/audio/sfx/`:
  - `sfx_spell_combine_01`: las manos se juntan; dos tonos a una 5.ª (E5 y A4) se deslizan al unísono en La y suena una campanita.
  - `sfx_fireball_charge_loop` (bucle de 2 s, `loop=true` ya en la importación): rugido de fuego con chisporroteo.
    Pensado para subir `pitch_scale` de 0,85 a 1,25 y el volumen con la carga.
  - `sfx_fireball_cast_01..03`: golpe grave + llamarada con barrido de filtro.
  - `sfx_fireball_impact_01..03`: explosión (sub con caída de tono, estallido, brasas) + lluvia de esquirlas afinadas en
    La mayor (A, C#, E), para casar con la música y el "tink".
  - `sfx_combo_discovered_01`: fanfarria corta del GDD 10 (IV - V - I en La mayor, metal sintético + arpegio de campanas + timbal).
- Demo de la secuencia completa: `docs/audio/bola_de_fuego_preview.ogg` (juntar → cargar → lanzar → impacto → fanfarria).

**Cómo se probó**

- Duraciones y niveles medidos (picos entre -1 y -4 dB); costura del bucle de carga por debajo del salto medio entre
  muestras (sin clic); espectrograma del impacto revisado. Los SFX existentes no cambian (`git status` limpio en ellos).
- Pendiente de escucha humana.

## 2026-11-15 · Integración en main: música del valle por capas

- Entra en `main` la música de la sesión de hechizos/música (rama `claude/keen-lovelace-7haa9v`, ver la entrada siguiente):
  5 capas por rango de mago en bucle, sincronizadas con `AudioStreamSynchronized`; en debug, tecla **M** para sumar capas.
- Verificado tras integrar: importación sin errores, `progression_smoke`, `hit_stop_smoke` y `music_layers_smoke` OK,
  juego en modo demo con `--music-layers=5` y galería de VFX sin errores de script, `gdlint` limpio.
- Pendiente: que alguien la escuche y la valide; opción de volumen de música en Opciones.

## 2026-11-15 · Música del valle por capas

**Qué hay nuevo**

- **`tools/music_synth.py`**: compone y sintetiza la música del valle ("Valle del Cristal") con Python (numpy + scipy),
  de forma determinista. Teoría aplicada (detalle en el propio script):
  - **La mayor**, la tonalidad del "tink" del cristal y de su escala pentatónica de racha: los golpes armonizan con la música.
  - **Color mágico**: II mayor lidio (B/A, con el D#) y iv menor prestado (Dm6) para un momento agridulce.
  - **Forma**: 16 compases a 84 BPM (45,7 s). Pregunta de 8 compases con semicadencia (Esus4 → E) y respuesta más aguda
    que termina en dominante y resuelve en el compás 1, así el bucle se siente como una vuelta.
  - Melodía escrita a mano sobre la pentatónica; sólo 4 notas fuera del acorde, todas cortas y en tiempo débil (de paso).
  - Pad y contramelodía con **conducción de voces automática** (mínimo movimiento entre acordes, notas guía 3.ª y 7.ª).
  - Bucle sin costura: las colas de reverb se suman al principio.
- **5 capas** en `game/audio/music/` (OGG estéreo, bucle activado), una por rango del mago:
  1 Aprendiz (pad, bajo y caja de música), 2 Iniciado (arpa en corcheas), 3 Hechicero (percusión suave),
  4 Magus (contramelodía de flauta), 5 Archimago (destellos de celesta y coro).
- **`AudioDirector.play_music(capas, activas)`** y **`set_music_layers(n, fundido)`**: usan `AudioStreamSynchronized`
  (integrado en Godot) para que todas las capas vayan en sincronía exacta y entren o salgan con fundido.
- `main.gd` arranca la música en Aprendiz (1 capa). En debug, la tecla **M** suma una capa (1 → 5 → 1) y
  `-- --music-layers=N` arranca con N capas.
- Escucha rápida: `docs/audio/musica_valle_capas_preview.ogg` (3 min; entra una capa nueva cada media vuelta).

**Cómo se probó**

- Análisis automático: notas de la melodía frente a cada acorde, nivel de cada capa, salto en la costura del bucle
  (del orden del salto medio entre muestras: sin clic) y espectrograma de la mezcla.
- `tests/smoke/music_layers_smoke.gd` (nuevo): bucle activado, misma duración en las 5 capas y fundidos de volumen. OK.
- El juego arranca en headless con `--music-layers=5` sin errores. `gdlint` limpio en los archivos tocados.
- Nadie lo ha escuchado todavía con oídos humanos: es lo primero que hay que validar.

**Pendiente**

- Conectar las capas al sistema de rangos cuando exista (ahora se queda en Aprendiz salvo con la tecla M).
- Opción de volumen de música en `Settings` (el bus `Music` ya existe).
- Variantes para el Santuario y la Gran Convergencia (misma herramienta, otra progresión).

## 2026-11-15 · Manos verticales que se juntan sobre el hechizo

**Qué hay nuevo**

- **Manos en vertical** (Sprite AI, cuenta 3): el antebrazo sube desde abajo y la mano está en alto, con los dedos
  hacia el centro. Sustituyen a las manos horizontales desde los lados del push anterior.
- **Se juntan dinámicamente desde donde estaban**: tras lanzar quedan abajo y separadas, con la palma abierta;
  mientras recarga suben y se juntan, y los dedos se curvan frame a frame (6 frames) hasta acunar el hechizo.
  Al lanzar dan un empujón hacia arriba y vuelven abajo con rebote.
- **El Orbe Arcano flota sobre las palmas** y crece con la carga; estalla al lanzar y se vuelve a formar.
- **Arreglo en `SpellOrb.appear()`** (código del otro agente): si se llamaba antes de que acabara el estallido,
  el núcleo y las cintas se quedaban ocultos y el orbe no volvía a verse. Ahora `appear()` los restaura.

**Capturas**: `docs/capturas/manos_verticales_orbe.gif`, `docs/capturas/manos_verticales_orbe.png`.

**Cómo se probó**

- Godot 4.7 headless sin errores de script; `progression_smoke` y `hit_stop_smoke`: OK; `gdlint` limpio.
- Render Forward+ en modo demo (nivel 1, 280 frames): el orbe aparece en todos los ciclos y las manos suben y se
  juntan desde abajo. Traza de estado del orbe frame a frame para localizar el fallo de `appear()`.

**Pendiente**

- Cuenta 3 de Sprite AI: 0 tokens.
- Las manos siguen teniendo la palma algo hacia la cámara; con más tokens, una variante vista más desde el lado del pulgar.

## 2026-11-15 · Las manos se juntan para el hechizo + integración del Orbe Arcano

Integra en `main` el trabajo del otro agente (rama `claude/keen-lovelace-7haa9v`: hechizos por capas, `SpellOrb`,
Orbe Arcano y galería de VFX, ver su entrada más abajo) y lo usa en el juego.

**Qué hay nuevo**

- **Manos nuevas que se juntan** (Sprite AI, cuenta 2): las 4 poses anteriores tenían la palma hacia la cámara y se
  veían en diagonal hacia fuera. Ahora una animación de 7 frames de la mano izquierda (la derecha es su reflejo)
  pasa de abierta a ahuecada: los antebrazos entran desde los lados y las palmas se miran, como en la referencia.
- **La carga lo gobierna todo**: mientras recarga, las manos se acercan al centro y se van cerrando frame a frame;
  al estar listas sujetan el hechizo a tope y laten; al lanzar se abren hacia fuera con rebote.
- **Orbe Arcano entre las palmas**: el `SpellOrb` del otro agente crece con la carga, estalla (`release`) al lanzar y
  vuelve a formarse; la chispa sale de su centro.
- Sprites procesados: manga alargada hasta el borde de la pantalla y huecos internos rellenados (se veía el orbe
  3D a través de las palmas). Detalles y registro en `docs/sprite_ai.md`.
- La galería de VFX se adapta a las manos nuevas (oculta el orbe de las manos para mostrar el suyo).

**Capturas**: `docs/capturas/manos_juntas_orbe.png`.

**Cómo se probó**

- Godot 4.7 headless: juego y galería sin errores de script; `progression_smoke` y `hit_stop_smoke`: OK; `gdlint` limpio.
- Render Forward+ en modo demo (nivel 2): ciclo cargar, lanzar, estallar y volver a formar revisado frame a frame.

**Pendiente**

- Las mangas alargadas repiten la tela (bandas horizontales); con otra cuenta de Sprite AI se puede generar un
  antebrazo más largo.
- El color del orbe no cambia todavía con el nivel de la chispa (el `SpellVisualDef` es fijo).
- Cuenta 2 de Sprite AI: 0 tokens.

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
## 2026-11-15 · Hechizos por capas: el Orbe Arcano

Primer paso hacia hechizos con la calidad de la referencia (`docs/referencias/estilo_referencia.png`):
la magia girando entre las manos en espirales rosa, violeta y cian con destellos blancos.

**Qué hay nuevo**

- **`SpellVisualDef`** (`game/data/defs/spell_visual_def.gd`): el aspecto de un hechizo como pila de capas,
  todo en datos. Cada elemento, combinación y nivel será un `.tres`, no código nuevo.
- **`SpellOrb`** (`game/spells/vfx/`): nodo reutilizable con 4 capas:
  1. **Núcleo** (`spell_core.gdshader`): galaxia de brazos en espiral leída de una rampa de color con
     interpolación constante (bandas duras), centro blanco HDR que activa el glow, destello en cruz y halo tramado (Bayer 4x4).
  2. **Cintas** (`spell_ribbon.gdshader`): órbitas inclinadas con cometas (cabeza blanca, cuerpo de color, cola tramada).
     Se dibujan en dos pasadas (mitad trasera antes del núcleo y delantera después), así rodean el núcleo de verdad
     y se ocultan detrás de las manos por profundidad.
  3. **Destellos**: estrellas pixel con flipbook de parpadeo (`fx/textures/particle_twinkle.png`, 7 frames de 9x9) a 1 texel = 1 píxel.
  4. **Luz**: tiñe las palmas del color del hechizo (el shader toon la pone en bandas).
  - API: `charge` (0..1: tamaño, velocidad de giro, destellos y luz), `release()` (estallido: las órbitas se abren,
    el núcleo se disuelve tramando y salta una lluvia de destellos; emite `released`) y `appear()`.
- **Orbe Arcano** (`game/data/spells/vfx_arcane_orb.tres`): primer hechizo configurado con la paleta del GDD.
- **Galería de VFX** (`game/tests/vfx_gallery/`): carga el juego real (valle, cristal, manos y contorno) y pone el orbe
  entre las manos con un ciclo cargar → mantener → soltar. Opciones `--def=`, `--charge=`, `--yaw=`, `--pitch=`, `--hud`, `--report`;
  teclas Espacio (soltar), 1-5 (carga) y 0 (ciclo).

**Decisiones de estilo** (ver registro de decisiones)

- Magia con **píxeles sólidos** (`blend_mix`) en vez de mezcla aditiva: sobre el cristal y el cielo claros, lo aditivo lo lavaba todo a blanco.
  Sólo el centro y las cabezas de los cometas son HDR para el glow.
- **Animación escalonada a 12 fps** (shaders, órbitas y partículas): lo procedural se lee como pixel art animado a mano.

**Capturas**: `docs/capturas/hechizo_orbe_arcano.gif` (ciclo completo, recorte x3) y `docs/capturas/hechizo_orbe_arcano.png`.

```bash
godot --path game res://tests/vfx_gallery/vfx_gallery.tscn --write-movie /tmp/orbe/f.png --fixed-fps 60 --quit-after 300
```

**Cómo se probó**

- Godot 4.7, Forward+ con Vulkan por software (llvmpipe): galería grabada frame a frame y revisada junto a la referencia en varias iteraciones.
- `tests/smoke/progression_smoke.gd` y `hit_stop_smoke.gd`: OK. Galería en headless sin errores de script.
- `gdlint` y `gdformat` limpios en los archivos nuevos.
- Coste: 1 quad de núcleo, 6 cintas de 144 triángulos (2 pasadas), 2 sistemas de partículas GPU y 1 luz omni sin sombras.
  La escena con el orbe da 40 draw calls (`--report`). Falta medir fps en un Steam Deck real.

**Pendiente**

- Integrarlo en el juego: lo hará quien trabaja en las manos (pose de combinar con las palmas enfrentadas). Basta con
  añadir un `SpellOrb` como hijo de la cámara o de las manos, asignar `def` y mover `charge` mientras se carga.
- Llevar el mismo sistema a la Chispa (proyectil) y crear las defs de Escarcha, Rayo, Tierra y las combinaciones.
- Capa 5 (distorsión de pantalla) para hechizos grandes como la Gran Convergencia: aún sin hacer y con su coste por medir.
- La galería oculta los orbes de chispa de las palmas (`hands.gd`) para ver el hechizo limpio; en el juego siguen igual.

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
