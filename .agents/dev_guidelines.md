# Dev Guidelines: Can you destroy it?

> El **cómo** trabajamos. Léelo entero antes de tocar código o assets. El **qué** está en
> `.agents/project_context.md` y en el GDD (`Can_You_Destroy_It_GDD.pdf`).

Tres prioridades, en este orden cuando choquen:

1. **Calidad visual y sensación.** Este juego vive de que cada golpe se vea y se sienta increíble.
2. **Rendimiento.** 60 fps estables en Steam Deck, sin tirones, aunque haya miles de fragmentos.
3. **Simplicidad del código.** La solución más simple que cumpla 1 y 2.

---

## 1. Antes de empezar cualquier tarea

1. Lee `project_context.md` y las secciones del GDD que toque la tarea.
2. **Investiga la mejor tecnología disponible** si la tarea introduce un sistema nuevo (ver sección 2).
3. Define cómo vas a verificar el resultado: qué se ve en pantalla, qué test, qué medición de rendimiento.
4. Si la tarea cambia una decisión del proyecto, actualiza el **registro de decisiones** de `project_context.md`.

## 2. Elegir tecnología: buscar siempre lo mejor

No implementes de memoria un sistema no trivial (shaders de pixel art, destrucción, partículas, guardado,
integración con Steam, audio adaptativo, input, localización...). Antes:

- **Consulta la documentación de Godot 4.7** y sus notas de versión: el motor cambia rápido y puede que ya exista
  una solución integrada (p. ej. 4.7 trae salida HDR y `AreaLight3D`; Jolt viene integrado como motor de física).
- **Busca alternativas actuales**: Asset Store de Godot, GitHub, charlas y artículos recientes de la comunidad.
- **Compara 2 o 3 opciones** con estos criterios:
  - compatible con **Godot 4.7** (probado, no "debería funcionar");
  - licencia compatible con un juego comercial (MIT, BSD, Apache, zlib, CC0);
  - mantenimiento activo (commits e issues recientes);
  - coste de rendimiento medido;
  - cuánto código o dependencia añade.
- **Prefiere lo integrado en el motor** frente a un addon, y un addon pequeño y mantenido frente a uno enorme.
- Anota la elección y el porqué en el registro de decisiones de `project_context.md`.
- Todo addon va en `addons/` con su licencia, y se lista en la sección 13 de este archivo.

Tecnologías ya previstas (validar la versión al integrarlas):

| Necesidad | Opción preferida | Notas |
|---|---|---|
| Física (fragmentos, facetas) | Jolt (integrado en Godot) | Más estable y rápido con muchos cuerpos. |
| Tests | gdUnit4 | Alternativa: GUT. Verificar compatibilidad con 4.7. |
| Lint y formato | gdtoolkit (`gdlint`, `gdformat`) | Ejecutar antes de cada commit. |
| Steam (logros, nube) | GodotSteam (GDExtension) | Sólo a partir de M4. |
| Arte pixel | Aseprite (fuentes `.aseprite`) + exportación PNG | Importar con filtro nearest. |
| Mallas del prototipo | `core/mesh_kit.gd` (prismas, conos, cajas con normales planas y color por vértice) | Corrige el orden de vértices solo. |
| Contorno pixel art | `fx/outline.gdshader`: post-proceso de profundidad + normales | Técnica estándar de "3D pixel art" en Godot 4. |
| SFX del prototipo | `tools/sfx_synth.py` (numpy + scipy + ffmpeg) | Reproducible con semillas fijas. |
| Fuentes | Silkscreen (8 px) y Pixelify Sans, OFL | Importadas sin antialiasing, hinting ni subpíxel. |
| Sprites pixel art (manos, efectos) | **Sprite AI** (MCP `sprite-ai` en `.mcp.json`, o `tools/sprite_ai/sai.py`) | No hay artista: es la fuente de arte 2D. Ver sección 15 y `docs/sprite_ai.md`. |
| VFX de hechizos | `spells/vfx/spell_orb.gd` + un `SpellVisualDef` (`.tres`) | Núcleo, cintas, destellos y luz; píxeles sólidos y animación a `anim_fps`. Probar en `tests/vfx_gallery/`. |

## 3. Proyecto Godot

- **Versión fija:** Godot **4.7** estable. No subir de versión sin anotarlo en el registro de decisiones y probar todo.
- **Renderer:** Forward+ (PC y Steam Deck). Evaluar Mobile sólo si el rendimiento en Deck lo exige.
- **Física:** Jolt, tick de física a 60 Hz.
- **Proyecto en la carpeta `game/`** (`game/project.godot`), para que docs y herramientas queden fuera del árbol del motor.
- Configuración ya aplicada en `game/project.godot`: viewport 640x360, stretch `viewport` con escalado `integer`,
  filtro nearest por defecto, Jolt, avisos de tipado como error y mapa de entrada base. No cambiarla sin anotarlo.

### 3.1 Estructura de carpetas (por funcionalidad, no por tipo)

```
game/
  project.godot
  addons/                 # addons de terceros, cada uno con su LICENSE
  autoload/               # singletons (ver 4.3)
  core/                   # utilidades sin dependencias de escena (math, formatting, pools)
  data/                   # recursos .tres de diseño: elementos, hechizos, mejoras, capas, balance
  world/                  # valle, fondo parallax, iluminación, cielo
  crystal/                # Cristal Madre, facetas, capas, fragmentos
  pylon/                  # Pilón de Maná
  sanctum/                # Santuario y sus estaciones
  player/                 # controlador primera persona, manos, recogida
  spells/                 # elementos, proyectiles, combinaciones, runas
  familiars/
  ui/                     # HUD, Grimorio, menús, fuentes
  fx/                     # shaders, partículas, post-proceso compartido
  audio/                  # buses, música, sfx compartidos
  localization/           # CSV de traducciones
  tests/
```

Cada funcionalidad agrupa su `.tscn`, `.gd`, shaders y assets propios. Lo compartido va en `core/`, `fx/`, `audio/`.

## 4. Código (GDScript)

### 4.1 Estilo

- Sigue la **guía de estilo oficial de GDScript**. Formatea con `gdformat` y pasa `gdlint`.
- **Tipado estático en todo**: variables, parámetros, retornos, arrays tipados (`Array[Shard]`) y diccionarios
  tipados. Activa en el proyecto los avisos de declaraciones sin tipo y de tipos inferidos inseguros
  como **error**. El tipado también mejora el rendimiento.
- Archivos y carpetas en `snake_case`; `class_name` en `PascalCase`; constantes en `UPPER_SNAKE_CASE`;
  miembros privados con `_`; señales en pasado (`shard_delivered`, `facet_broken`).
- Nombres de código en **inglés** usando el glosario de `project_context.md`. Comentarios y textos de commit en español.
- Usa `@export` para todo lo que se ajuste desde el editor; usa `@onready` para referencias a nodos (nunca `get_node` en bucles).

### 4.2 Arquitectura

- **Lógica separada de presentación.** El estado del juego (esencia, maná, Pilón, mejoras) vive en clases puras
  testeables sin escenas. Las escenas escuchan señales y dibujan.
- **Datos fuera del código.** Todo número de diseño (daños, costes, curvas, valores de fragmentos, tiempos)
  vive en recursos (`ElementDef`, `SpellRecipe`, `UpgradeNode`, `CrystalLayerDef`, `BalanceConfig`). Cero
  números mágicos de balance en scripts.
- **Composición de escenas** pequeñas y reutilizables; "llama hacia abajo, señala hacia arriba".
- **Números grandes:** la esencia total es 1.000.000 y cabe en `int`. Si un multiplicador lo supera, se satura;
  no introducir una librería de números grandes sin necesidad demostrada.

### 4.3 Autoloads (mínimos)

| Autoload | Responsabilidad |
|---|---|
| `Events` | Bus de señales globales (golpe, fragmento entregado, mejora comprada, hito del Pilón). |
| `GameState` | Estado de la partida y reglas puras (esencia, maná, Pilón, mejoras compradas). |
| `SaveSystem` | Guardar y cargar. |
| `AudioDirector` | Música por capas, pools de SFX, buses. |
| `Settings` | Opciones del jugador (vídeo, audio, accesibilidad, controles). |

No añadir más autoloads sin anotarlo en el registro de decisiones.

### 4.4 Guardado

- JSON en `user://save.json` con `version` para migraciones; escritura atómica (archivo temporal + renombrar).
- Autoguardado cada 30 s y al comprar mejoras o salir. Nunca perder más de 30 s de progreso.
- Compatible con Steam Cloud a partir de M4.

## 5. Calidad visual (pixel art)

El listón es la referencia `docs/referencias/estilo_referencia.png`. Si algo se ve peor que eso, no está terminado.

### 5.1 Reglas de pixel art

- **Resolución interna fija** (640x360 propuesta) y escalado sólo por **enteros** con filtro **nearest**.
  Hoy todo el juego (mundo, manos y UI) se dibuja a 640x360 mediante el stretch del proyecto. Si la UI de texto
  necesita más resolución, mover el mundo a un `SubViewport` y dejar la UI a resolución nativa con fuentes pixel
  escaladas por enteros (anotarlo en el registro de decisiones).
- **Filtro nearest en todas las texturas**: en 2D ya es el valor por defecto del proyecto; en 3D hay que ponerlo en
  cada material (`texture_filter = Nearest`).
  Sin mipmaps en sprites.
- **Densidad de texel constante**: 1 píxel de textura = 1 píxel de pantalla a la distancia de juego habitual.
  Nada de "mixels" (píxeles de tamaños distintos en pantalla).
- No rotar ni escalar sprites pixel en tiempo real salvo en múltiplos que conserven la rejilla. Si hace falta una
  rotación, se dibuja como frame de animación.
- **Paleta limitada**: la paleta del proyecto vive en `game/fx/palette.tres` (o textura de paleta). Todo asset
  nuevo la respeta. El post-proceso puede cuantizar a la paleta.
- Iluminación 3D con **shading por bandas** (toon), **contorno** por post-proceso y sombras con bordes duros.
- Luz principal desde **arriba a la izquierda**, como en la referencia del cristal.
- Fondo lejano (cielo, montañas, castillo, aldea) como capas 2D con parallax y perspectiva atmosférica.

### 5.2 Sensación ("juice"): checklist de cada acción del jugador

Toda acción visible debe tener, como mínimo:

- [ ] **Anticipación** (las manos se cargan, tiemblan, brillan).
- [ ] **Impacto** (destello, partículas, grieta, *hit-stop* de 1 a 3 frames en golpes fuertes).
- [ ] **Reacción del mundo** (la faceta se agrieta o cae, polvo, luz).
- [ ] **Sonido** con variación de tono (nunca el mismo sample idéntico dos veces seguidas).
- [ ] **Escala con el poder**: el mismo efecto a nivel 1 y a nivel 50 debe verse distinto.
- [ ] Sacudida de cámara **sólo** si el golpe la merece y respetando la opción de accesibilidad.

### 5.3 Todo es reactivo

Regla del proyecto: **ningún cambio de estado sin respuesta visual y sonora**. Cada hechizo, impacto, recogida,
compra o hito debe cumplir la especificación del GDD 10.3 (manos, proyectil, objetivo, partículas y luz, cámara,
sonido y HUD) y la de racha y golpe resonante (GDD 10.4). Si falta una capa, no está terminado.

- La reacción escala con el poder: definir los valores visuales en recursos (`SpellTier`), no en el código.
- La dopamina viene de la **variación** (tono que sube con la racha, golpes resonantes aleatorios, hitos) y de
  la **respuesta inmediata** (buffer de entrada, hit-stop, números que ruedan).
- Respeta la accesibilidad: la sacudida de cámara pasa siempre por `Settings.screen_shake`.

### 5.4 Trampas conocidas del pipeline

- **Colores por vértice en sRGB.** En shaders propios, `COLOR` llega en sRGB: convertirlo a lineal (ver
  `fx/toon.gdshader`) o todo sale lavado.
- **Partículas y contorno.** El quad de contorno usa `render_priority = -100` para dibujarse antes que el resto de
  transparentes; si no, taparía las partículas.
- **Fuentes pixel.** Importar sin antialiasing, hinting ni subpíxel y usarlas sólo a su tamaño nativo o múltiplos.
- **Magia aditiva sobre fondos claros.** `blend_add` sobre el cristal o el cielo satura a blanco y se pierde el
  color. Para magia, píxeles sólidos (`blend_mix`, alfa 0 o 1 con tramado) y HDR > 1 sólo donde deba brillar.
- **Render sin GPU (agentes).** Para capturas en contenedores: instalar `mesa-vulkan-drivers` y ejecutar con
  `xvfb-run`; sin Vulkan, Godot cae a OpenGL y el contorno (Forward+) no compila.
- **Bucle de audio.** Activarlo en la importación del OGG (`loop=true`), no duplicando el recurso en código.
- **Aviso al salir en headless.** Un `AudioStreamPlayer` con un OGG en bucle deja avisos de "leaked instances" al
  cerrar con `--quit-after`; es del motor y también ocurre en un proyecto vacío. Ignorarlo.

### 5.5 Definición de "terminado" para algo visual

- Probado a la resolución interna y escalado x2, x3 y x4, y en 1280x800 (Steam Deck).
- Sin mixels, sin texturas borrosas, sin parpadeos.
- Captura o GIF en `docs/capturas/` y enlazado en el `CHANGELOG.md`. Para grabar sin ratón:

```bash
godot --path game --write-movie /tmp/captura/f.png --fixed-fps 60 --quit-after 180 -- --autoplay --tier=1
```

- Comparado lado a lado con la referencia de estilo.

## 6. Rendimiento

### 6.1 Presupuestos

| Métrica | Objetivo |
|---|---|
| FPS en Steam Deck (1280x800) | **60 estables**, sin caídas en el peor momento (Tormenta + Vórtice + familiares). |
| FPS en PC medio | 144 con vsync desactivado. |
| Tiempo de frame (Deck) | < 16,6 ms; CPU de scripts < 4 ms. |
| `RigidBody3D` activos a la vez | ≤ 150. El resto, dormidos o convertidos a instancias de `MultiMesh`. |
| Fragmentos en el suelo | Ilimitados visualmente vía `MultiMeshInstance3D`; se fusionan en "montones" si pasan de un umbral. |
| Draw calls | < 1.500 en la escena más cargada. |
| Arranque | < 5 s hasta poder jugar. |
| Memoria | < 1,5 GB. |

### 6.2 Reglas

- **Pools de objetos** para proyectiles, fragmentos, partículas y números flotantes. Nada de `instantiate()` / `queue_free()` en el bucle caliente.
- **Cero asignaciones por frame** en `_process` / `_physics_process`: sin crear arrays, diccionarios ni strings
  (formatea textos de UI sólo cuando el valor cambia).
- **Partículas en GPU** (`GPUParticles3D/2D`) con límites de cantidad; partículas en CPU sólo si hacen falta colisiones precisas.
- **Facetas del cristal pre-fracturadas** (no fractura en tiempo real). Una faceta suelta es un cuerpo físico unos
  segundos y después se congela o se convierte en instancia estática.
- Sólo usar `_process` donde haga falta; desactivar el procesado de nodos inactivos (`set_process(false)`).
- Usar señales y temporizadores en vez de sondear cada frame.
- Shaders sencillos: el look pixel art no necesita efectos caros. Medir cualquier post-proceso nuevo.
- Iluminación global costosa (SDFGI, VoxelGI) **desactivada** salvo que se mida y se justifique.
- Audio con polifonía limitada por sonido (un "tink" no puede sonar 300 veces en el mismo frame).

### 6.3 Medir siempre

- Usa el **Profiler**, el **Visual Profiler** y los **Monitors** de Godot antes y después de cambios que puedan afectar.
- Mantén una **escena de estrés** (`game/tests/stress/stress_scene.tscn`): cristal completo, 500 fragmentos en
  movimiento, todos los hechizos a la vez. Todo cambio de rendimiento se valida ahí y se anota el resultado en el PR.
- Optimiza con datos, no con suposiciones; pero respeta los presupuestos desde el primer día.

## 7. Audio

- Buses: `Master`, `Music`, `SFX`, `UI`, `Ambience`. Volumen de cada uno en Opciones.
- Variaciones con `AudioStreamRandomizer` (tono y sample) para golpes, fragmentos y entregas.
- La música añade capas con cada rango de mago (Aprendiz -> Leyenda).
- El "tink" del cristal es la firma del juego: cada capa del cristal tiene su propio timbre.

## 8. Diseño de juego en el código

- Ningún cambio de balance sin actualizar los recursos de `game/data/` (y el GDD si cambia una regla).
- Herramienta de **simulación de balance** (script headless) que simule la partida con jugador "medio" y reporte
  el tiempo a cada hito; objetivo total 2 a 3 h y nunca > 3 min sin mejora comprable.
- **Modo debug** (sólo en builds de desarrollo): multiplicador de tiempo, dar maná, saltar a capa, mostrar FPS y contadores.

## 9. UI, accesibilidad y localización

- Todos los textos con `tr()` desde el día 1. Idiomas iniciales: **español e inglés** (CSV en `game/localization/`).
- Opciones de accesibilidad: intensidad de sacudida de cámara (0 a 100 %), reducir destellos, remapeo de teclas,
  carga de hechizo por mantener o alternar, tamaño de UI.
- Los elementos se distinguen por **forma y animación**, no sólo por color.
- Soporte de mando (Steam Deck) además de ratón y teclado.

## 10. Tests

- **gdUnit4** para la lógica pura: cálculo de daño, costes de mejoras, combinaciones, guardado y carga, progreso del Pilón.
  Mientras no esté integrado, existe un test rápido sin addons:

```bash
godot --headless --path game --script res://tests/smoke/progression_smoke.gd
```

- `tests/smoke/progression_smoke.gd` cubre `Progression` y `StreakTracker`; `tests/smoke/hit_stop_smoke.gd`, que el tiempo
  siempre vuelve a la normalidad tras un hit-stop.
- Toda regla de juego nueva llega con su test.
- Antes de cada commit, como mínimo: el proyecto abre sin errores en headless, `gdlint` limpio y tests en verde.

```bash
godot --headless --path game --import
```

```bash
gdlint game && gdformat --check game
```

## 11. Assets

- Fuentes de arte (`.aseprite`, `.blend`, `.psd`) en `art_source/`, fuera de `game/`; en `game/` sólo los exportados.
- Usar **Git LFS** para audio (`.wav`, `.ogg`), fuentes de arte y modelos. PNG pequeños pueden ir sin LFS.
- Nombres en `snake_case` y descriptivos: `crystal_facet_large_03.png`, `sfx_crystal_tink_cortex_02.ogg`.
- Todo asset de terceros con licencia registrada en `CREDITS.md`.
- `docs/referencias/` son **referencias**, nunca se usan como asset del juego.

## 12. Git y flujo de trabajo

- Al terminar una tarea: **commit y push a `main`** (decisión del equipo). Commits pequeños con mensaje en
  español en imperativo ("Añade pool de fragmentos"); se puede usar una rama de trabajo local, pero el resultado
  se integra en `main` y se sube.
- **Cada push se documenta en `CHANGELOG.md`** (raíz del repo), en el mismo push: fecha, título, qué cambia,
  cómo se probó, capturas o GIF si es visual, pendientes y problemas conocidos. La entrada más reciente va arriba.
- Al terminar, comentar el push al equipo con un resumen (el mismo de la entrada del changelog).
- No subir `game/.godot/` ni builds (`.gitignore`).
- Mantener al día `project_context.md` (estado del repo, registro de decisiones) en el mismo commit que el cambio.

## 13. Addons en uso

| Addon | Versión | Licencia | Para qué |
|---|---|---|---|
| *(ninguno todavía)* | | | |

Recursos de terceros (fuentes) en `CREDITS.md`.

## 15. Arte 2D con Sprite AI

No hay artista: el arte 2D a mano (manos del mago, efectos, iconos) se genera con **Sprite AI**. Guía completa,
costes y registro de todo lo generado en `docs/sprite_ai.md`. Lo esencial:

- **La clave nunca va al repo.** En local, variable de entorno `SPRITE_AI_API_KEY` (la lee `.mcp.json`). En la
  nube, secreto de red del entorno `can-you-destroy-it` para `www.sprite-ai.art`, que el proxy inyecta solo.
- **Cuentas**: el plan gratis trae 15 tokens por cuenta y el equipo puede crear más. Al cambiar de cuenta se
  actualiza la variable o el secreto (en la nube, pedírselo al agente: abre un formulario seguro). Antes de
  generar, consultar el saldo con `sprite_get_balance` (gratis).
- **Ahorro**: imagen base (`sprite_generate`, 1 token) + poses con `sprite_restyle` modo `pose` (2 tokens) y la
  animación entre poses por código en Godot. `sprite_generate_animation` (14-20 tokens) sólo si de verdad hace falta.
- **Primera persona**: pedirlo explícitamente y con `camera_perspective: top_down`; revisar la lateralidad
  (mano izquierda con la palma hacia la cámara = pulgar a la izquierda) antes de integrar.
- **Coherencia**: todas las poses salen del mismo sprite base (restyle), no de generates sueltos.
- Cada sprite nuevo se anota en la tabla de `docs/sprite_ai.md` (archivo, qué es, id, coste).
- Los sprites se usan a tamaño 1:1 (sin escalar ni rotar) con filtro nearest, como el resto del pixel art.

## 14. Herramientas para agentes: Godot MCP

El repo incluye `.mcp.json` con el servidor **godot-mcp** (`@coding-solo/godot-mcp@0.1.1`, MIT). Permite a los
agentes abrir el editor, ejecutar el proyecto, leer la salida de depuración, crear escenas, añadir nodos y
consultar UIDs.

- Requisitos: Node.js 18 o superior y Godot 4.7 instalado. Si no lo encuentra solo, definir la variable de entorno
  `GODOT_PATH` con la ruta al ejecutable de Godot.
- La ruta de proyecto que hay que pasarle es la carpeta `game/`.
- Úsalo para **verificar** cada cambio: ejecutar el proyecto y revisar errores y avisos antes de dar algo por terminado.
- Las escenas que cree deben cumplir igualmente estas guías (tipado, estructura de carpetas, filtro nearest).
- Versión fijada a propósito: actualizarla sólo tras revisar sus cambios.
