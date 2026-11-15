# Project Context: Can you destroy it?

> Fuente de verdad del **qué** y el **por qué** del proyecto. El diseño completo está en
> `Can_You_Destroy_It_GDD.pdf` (raíz del repo). Si este archivo y el GDD se contradicen, manda el GDD.
> Si una tarea cambia una decisión, actualiza este archivo en el mismo commit.

---

## 1. El juego en 30 segundos

- **Género:** incremental / clicker activo en **primera persona**, finito (tiene final), **2 a 3 horas**.
- **Motor:** **Godot 4.7**, GDScript tipado. **Plataforma:** PC (Steam), Steam Deck como objetivo.
- **Estilo:** **pixel art** vibrante y luminoso (cielo azul intenso, bosques verdes, castillo de tejados azules,
  aldea de tejados rojos, magia violeta/rosa/cian). Referencias en `docs/referencias/`.
- **Premisa:** en un valle al pie de un castillo ha brotado un **Cristal Madre** gigante. Eres un aprendiz con
  una chispita ridícula. Le pegas, caen pedacitos, los **entregas al Pilón de Maná**, ganas maná, mejoras en
  tu **Santuario** y vuelves con hechizos cada vez más locos hasta destruirlo.
- **Referencias de diseño:** *One Million Coins* (recurso finito y visible, empiezas sin nada, ~2 h, árbol de
  mejoras con muchos nodos) y *Aerolicious* (destruir un bloque enorme pieza a pieza, ritmo relajante).

## 2. Pilares (todo se mide contra esto)

1. **Sentirse un mago.** Manos visibles en primera persona, la magia es el arma. Cada mejora se **ve y se oye**.
   El primer hechizo da vergüenza a propósito; el contraste con el final es el corazón del juego.
2. **Destrucción satisfactoria.** Cada golpe al cristal tiene que sentirse bien la milésima vez ("tink" + grieta + fragmento).
3. **Progreso siempre visible.** El cristal se vacía, el Pilón se llena, el Santuario crece, el valle cambia.
4. **Descubrir, no comprar.** Las combinaciones de hechizos se descubren probando.
5. **Corto y redondo.** 2 a 3 horas, ritmo sin baches y un final memorable (la Gran Convergencia).

## 3. Glosario (usar estos nombres en código, UI y commits)

| Término | Significado | Nombre en código |
|---|---|---|
| Cristal Madre | El objeto gigante que se destruye. 1.000.000 de Esencia. | `MotherCrystal` |
| Faceta | Pieza física del cristal que se desprende (≈ 4.000). | `CrystalFacet` |
| Capa | Corteza, Manto Geódico, Venas Resonantes, Corazón Cristalino, Núcleo. | `CrystalLayer` |
| Esencia | Vida restante del cristal. Sólo baja. | `essence` |
| Fragmento | Pedazo que cae al golpear. Por tamaño según el daño: **Astilla** (pequeña, `splinter`), **Fragmento** (mediano, `shard`), **Fragmento grande** (`chunk`). Especiales futuros: Geoda, Resonante, Lágrima del Núcleo. | `Shard`, `ShardType` (`data/shards/`) |
| Bolsa | Fragmentos recogidos y aún no entregados, por tipo. | `Progression.bag` |
| Pilón de Maná | Columna que se llena al entregar. Es la barra de victoria. Nunca baja. | `ManaPylon`, `pylon_progress` |
| Maná | Moneda gastable para mejoras. | `mana` |
| Santuario | Torre del mago: lugar físico donde se compran mejoras. Crece visualmente. | `Sanctum` |
| Grimorio | Árbol de mejoras (7 ramas, ≈ 200 nodos). | `Grimoire`, `UpgradeNode` |
| Elemento | Chispa, Escarcha, Rayo, Tierra, Arcano. | `Element` |
| Hechizo combinado | Resultado de combinar elementos (p. ej. Chispa + Chispa = Bola de Fuego). | `SpellRecipe` |
| Runa | Modificador de hechizo (multidisparo, rebote, perforación...). | `Rune` |
| Familiar | Ayudante que recoge / entrega / lanza automáticamente. | `Familiar` |
| Gran Convergencia | Hechizo final de los 5 elementos; único que daña al Núcleo. | `GrandConvergence` |

## 4. Bucle principal

```
Lanzar hechizo -> cae fragmento -> entregar al Pilón -> ganar maná -> mejorar en el Santuario -> (hechizos más fuertes)
```

- Entregar un fragmento suma su valor a `pylon_progress` (permanente) **y** a `mana` (gastable).
- La entrega evoluciona: manos (1 fragmento) -> bolsa -> telequinesis -> familiares -> vórtice.

## 5. Números clave (punto de partida, a balancear)

| Parámetro | Valor |
|---|---|
| Esencia total del Cristal | 1.000.000 (cabe en `int`, no hace falta BigNumber) |
| Daño inicial de la chispa | 1 por golpe, 1 lanzamiento cada 1,5 s |
| Capacidad inicial | 1 fragmento en la mano |
| Distancia Cristal -> Pilón | ≈ 10 m (≈ 4 s caminando) |
| Primera mejora | 5 maná, debe llegar en < 30 s |
| Coste por nivel | base x 1,15 a 1,25 según rama |
| Regla de ritmo | algo comprable cada < 60 s en la 1.ª hora; nunca > 3 min sin mejora |

Todos estos números viven en recursos de datos (`.tres`), nunca hardcodeados (ver dev guidelines).

## 6. Dirección visual (resumen)

- Mundo **3D renderizado a baja resolución** (640x360 propuesta) escalado por enteros, filtro nearest, shading
  por bandas, contorno por post-proceso. Fondo lejano (cielo, montañas, castillo, aldea) en **capas 2D con parallax**.
- **Manos**: sprites pixel art 2D en primera persona generados con **Sprite AI** (4 poses: abierta, carga,
  lanzar, reposo; mano izquierda reflejada para la derecha), animados por código a píxel entero.
  No hay artista: el arte 2D sale de Sprite AI (`docs/sprite_ai.md`).
- **Todo es reactivo**: cada impacto dispara la lista completa de respuestas del GDD 10.3 (manos, proyectil,
  cristal, fragmentos, partículas, luz, cámara, sonido y HUD). Racha y golpe resonante: GDD 10.4.
- **Cristal Madre:** racimo de cristales de hielo azul (luz arriba a la izquierda, sombras azul profundo,
  corazón violeta oscuro en la base). Ver `docs/referencias/cristal_referencia.png`.
- **Paleta base** (orientativa, sacada de las referencias):
  `#3978da` cielo · `#2a43a7` azul profundo · `#a5dae5` cristal luz · `#458fb8` cristal medio ·
  `#284b86` cristal sombra · `#654fae` violeta manga · `#c79bff` magia violeta · `#ff7ad9` magia rosa ·
  `#3f9a3c` bosque · `#c8423a` tejados · `#e6dddb` piedra castillo · `#d8a23a` oro.
- Alternativa si el prototipo M1 no convence: 2D puro con vista frontal y tres pantallas.

## 7. Estado actual del repo

| Ruta | Qué es |
|---|---|
| `Can_You_Destroy_It_GDD.pdf` | GDD v0.3 (fuente del diseño). |
| `CHANGELOG.md` | Registro de cada push a `main`. |
| `CREDITS.md` | Licencias de fuentes y recursos de terceros. |
| `tools/sfx_synth.py` | Sintetiza todos los SFX del prototipo (`python3 tools/sfx_synth.py`, requiere numpy, scipy y ffmpeg). |
| `tools/godot/make_spark_element.gd` | Volcado inicial de `data/elements/spark.tres`. |
| `docs/capturas/` | Capturas y GIF del prototipo. |
| `docs/sprite_ai.md` | Cómo usar Sprite AI, costes y registro de sprites generados. |
| `tools/sprite_ai/sai.py` | Cliente mínimo del MCP de Sprite AI. |
| `art_source/sprite_ai/` | Sprites descartados o fuentes de Sprite AI. |
| `tools/make_gdd.py` | Genera el PDF del GDD (`python3 tools/make_gdd.py Can_You_Destroy_It_GDD.pdf`). Requiere `reportlab` y `Pillow`. |
| `docs/referencias/` | Imágenes de referencia de cristal y estilo. **No son arte final.** |
| `AGENTS.md`, `.agents/` | Instrucciones para agentes. |
| `game/` | Proyecto Godot 4.7 (abrir `game/project.godot`). |
| `.mcp.json` | Servidor MCP de Godot para agentes (ver dev guidelines, sección 14). |

**Prototipo M1a "El golpe" jugable** (`game/main/main.tscn`):

- **Valle** procedural (`world/valley.gd`): suelo ondulado con colisión, ~900 pinos en `MultiMesh`, montañas
  nevadas, colina con castillo de tejados azules y aldea de tejados rojos; cielo pixel art con tramado y nubes
  (`world/sky.gdshader`); niebla de profundidad para la perspectiva atmosférica.
- **Cristal Madre** (`crystal/`): racimo de 15 prismas según la referencia, shader con bandas de paleta, corazón
  violeta, brillo que recorre las facetas, grietas persistentes (voronoi 3D) y destellos/ondas de impacto.
  `ShardPool` con 64 fragmentos físicos reciclados en 3 tamaños según el daño (astilla, fragmento, fragmento
  grande), que se congelan al quedarse quietos, se resaltan al apuntarlos y vuelan a la mano al recogerlos.
- **Mago** (`player/`): primera persona (ratón + WASD), manos 2D de Sprite AI con 4 poses y orbe mágico,
  recogida de fragmentos con F (apuntando o el más cercano delante), `SpellCaster` con
  enfriamiento, buffer, golpe resonante y pool de 12 chispas; `CameraRig` con sacudida por trauma y golpe de FOV.
- **Chispa** (`spells/`, `data/elements/spark.tres`): 5 niveles de poder (`SpellTier`) que cambian daño, cadencia,
  velocidad, tamaño, color, fragmentos, partículas, luz, grietas y sacudida.
- **Efectos** (`fx/`): shader toon, contorno de post-proceso (profundidad + normales), `ImpactFx` (estrellas,
  esquirlas, anillo y luz en pool), `HitStop`.
- **HUD** (`ui/`): Esencia con número rodante, mira con anillo de carga y marcador de impacto, racha, avisos,
  números flotantes, Pilón, FPS y ayuda de debug. Fuentes Silkscreen (texto pequeño) y Pixelify Sans (números).
- **Audio** (`audio/sfx/`): 20 OGG sintetizados (tink ×4, fragmentos, chispa, campanitas, acorde resonante,
  ambiente del valle y zumbido del cristal en bucle).
- **Debug** (sólo builds de desarrollo): teclas 1-5 cambian el nivel de la chispa; modo demo para grabar:
  `godot --path game -- --autoplay --tier=N` (añadir `--report` para imprimir draw calls y física).
- `tests/smoke/progression_smoke.gd`: reglas de `Progression` y `StreakTracker` (pasa).

**Aún no hay**: entregar fragmentos, Pilón físico, Santuario ni mejoras compradas (M1b). Los fragmentos recogidos
van a la bolsa (sin límite de capacidad por ahora; el GDD pide empezar con 1).

## 8. Hitos

| Hito | Contenido | Criterio de éxito |
|---|---|---|
| **M1a El golpe** ✅ | Arte base del valle y del cristal, una chispa con 5 niveles y la reacción completa del cristal (GDD 10.3 y 10.4). | Golpear el cristal ya da gusto sin nada más. |
| **M1b Prototipo** | Recoger y entregar fragmentos, Pilón, 5 mejoras. | Los primeros 5 minutos ya son divertidos. 60 fps estables. |
| **M2 Vertical slice** | Santuario básico, 2 elementos, 1 combinación, telequinesis, capa Corteza completa. | 30 minutos sin baches. |
| **M3 Contenido** | 5 elementos, todas las combinaciones, 7 ramas, familiares, todas las capas. | Se puede terminar de principio a fin. |
| **M4 Final y pulido** | Gran Convergencia, balance, audio, logros de Steam. | 2 a 3 h; el final emociona. |

## 9. Registro de decisiones

Añadir una línea por decisión relevante (fecha, decisión, motivo). No borrar entradas: si cambia, añadir otra.

| Fecha | Decisión | Motivo |
|---|---|---|
| 2026-11-15 | Motor: Godot 4.7, GDScript tipado. | Elección del equipo. |
| 2026-11-15 | Estilo pixel art según `docs/referencias/`. | Elección del equipo. |
| 2026-11-15 | Primera persona, 3D a baja resolución + manos 2D (propuesta, a validar en M1). | Permite caminar entre estaciones como One Million Coins manteniendo el look pixel art. |
| 2026-11-15 | Esencia total = 1.000.000; Pilón y maná separados. | Recurso finito y visible; gastar no quita progreso. |
| 2026-11-15 | Proyecto en `game/`; render a 640x360 con stretch `viewport` + escalado `integer` para todo (mundo y UI). | Lo más simple que da pixel art nítido; revisar si la UI necesita más resolución. |
| 2026-11-15 | godot-mcp 0.1.1 como herramienta de agentes (`.mcp.json`). | Permite ejecutar el proyecto y leer errores para verificar cambios. |
| 2026-11-15 | Arte del prototipo generado por código: mallas low-poly (`core/mesh_kit.gd`) + shader toon + contorno de post-proceso a 640x360. | Calidad pixel art coherente sin artista todavía; todo se puede retocar o sustituir. |
| 2026-11-15 | Manos en 3D low-poly en vez de sprites 2D (de momento). | Se integran con la luz y el contorno; los sprites 2D quedan como opción para el arte final. |
| 2026-11-15 | SFX sintetizados con `tools/sfx_synth.py` (OGG). | Sonido reactivo desde el día 1; reproducibles; se sustituirán por diseño de sonido profesional. |
| 2026-11-15 | Fuentes: Silkscreen 8 px (texto pequeño) y Pixelify Sans (números), ambas OFL, sin antialiasing. | Nítidas a 640x360. |
| 2026-11-15 | Números flotantes activados por defecto (antes: ocultos). Racha con escala pentatónica y golpe resonante del 7 %. | Más dopamina en el golpe, pedido explícito. |
| 2026-11-15 | Flujo de git: commit y push a `main`, cada push documentado en `CHANGELOG.md`. | Pedido del equipo. |
| 2026-11-15 | Manos 2D generadas con Sprite AI (reemplazan a las low-poly). Sin artista: Sprite AI es la fuente de arte 2D; la clave va en variable de entorno o secreto del entorno, nunca en el repo. | Calidad pixel art de la referencia; el equipo puede crear más cuentas gratis. |
| 2026-11-15 | Números flotantes activados (confirmado). | Pedido del equipo. |
| 2026-11-15 | 3 tamaños de fragmento según el daño (astilla < 3, fragmento 3-9, grande 10+; resonante sube uno) y recogida con F. | Pedido del equipo; el tamaño comunica la fuerza del golpe. |
| 2026-11-15 | Hit-stop con liberación garantizada y red de seguridad en `main.gd`. | Bug: el tiempo se quedaba congelado. |

## 10. Preguntas abiertas

- Confirmar 3D a baja resolución frente a 2D puro tras jugar el prototipo M1a.
- Arte 3D (valle, cristal): seguir procedural y pulir; el arte 2D sale de Sprite AI.
- Resolución interna final (640x360 propuesta) tras probarla en 1440p y Steam Deck.
- ¿Modo infinito o New Game+ tras el final?
- Precio y fecha objetivo en Steam.
