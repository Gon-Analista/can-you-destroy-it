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
| Faceta | Cara plana del cristal; al excavar quedan facetas nuevas. (El GDD hablaba de ≈ 4.000 piezas físicas; se cambió a un volumen excavable, ver decisiones.) | `CrystalVolume` |
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
| Daño inicial de la chispa | 0 (tutorial: "deshonra de mago"); juntar las dos manos hace 1; la primera Potencia (5 maná) sube a 2 |
| Capacidad inicial | Bolsa de 5 (sube a 15, 40 y 100) |
| Distancia Cristal -> Pilón | ≈ 10 m (≈ 4 s caminando) |
| Primera mejora | 5 maná; con el tutorial llega hacia el minuto 1 |
| Coste por nivel | base x 1,15 a 1,25 según rama |
| Regla de ritmo | algo comprable cada < 60 s en la 1.ª hora; nunca > 3 min sin mejora |

Todos estos números viven en recursos de datos (`.tres`), nunca hardcodeados (ver dev guidelines).

## 6. Dirección visual (resumen)

- Mundo **3D renderizado a baja resolución** (640x360 propuesta) escalado por enteros, filtro nearest, shading
  por bandas, contorno por post-proceso. Fondo lejano (cielo, montañas, castillo, aldea) en **capas 2D con parallax**.
- **Manos**: sprites pixel art 2D generados con **Sprite AI**: animación de 6 frames de la mano izquierda en
  vertical (antebrazo desde abajo) que se ahueca; la derecha es su reflejo. Con la carga suben desde abajo y
  separadas hasta juntarse; sobre las palmas vive el hechizo (`SpellOrb`, Orbe Arcano), que estalla al lanzar.
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
| `tools/music_synth.py` | Compone y sintetiza la música por capas (`python3 tools/music_synth.py [--preview RUTA]`, requiere numpy, scipy y ffmpeg). |
| `tools/sfx_fireball.py` | Sonidos de la Bola de Fuego y de descubrir una combinación (`python3 tools/sfx_fireball.py`). |
| `tools/sfx_synth.py` | Sintetiza todos los SFX del prototipo (`python3 tools/sfx_synth.py`, requiere numpy, scipy y ffmpeg). |
| `tools/sfx_loop.py` | SFX del bucle: gota de maná, zumbido del Pilón, bolsa llena, compra, Grimorio, interfaz y telequinesis. |
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

**Prototipo M1b jugable: el bucle completo** (`game/main/main.tscn`). Golpeas el cristal, recoges los
fragmentos con F (la bolsa empieza en 1), los llevas al Pilón (se vacía solo al acercarte), ganas maná y compras
en el Grimorio del Santuario mejoras que cambian los hechizos. Lo que hay:

- **Valle** procedural (`world/valley.gd`): suelo ondulado con colisión, ~900 pinos en `MultiMesh`, montañas
  nevadas, colina con castillo de tejados azules y aldea de tejados rojos; cielo pixel art con tramado y nubes
  (`world/sky.gdshader`); niebla de profundidad para la perspectiva atmosférica.
- **Cristal Madre** (`crystal/`): **destructible de verdad**. Un volumen (rejilla de distancias de 0,7 m,
  `crystal/data/crystal_volume.bin`, horneado por `tools/crystal_volume.py`) con forma de racimo de 63 m: punta
  principal, 8 puntas secundarias, racimos al pie y un zócalo ancho. Cada golpe lo erosiona (`CrystalVolume.carve`)
  y la malla se rehace por trozos de 16^3 celdas en otros hilos (`CrystalChunks`, surface nets, caras planas).
  Las **capas están por profundidad**: Corteza, Manto Geódico (con 26 bolsas de geoda dentro), Venas Resonantes,
  Corazón (sólo cede ante combinaciones) y Núcleo (no cede); se llega a ellas excavando. La esencia que quita un
  golpe es el volumen que arranca por la densidad de su capa (las densidades reparten el 1.000.000 como el GDD 6).
  Shader con paleta y dibujo por capa, placas y estrías por fuera, interior que centellea, corazón
  violeta, grietas persistentes (voronoi 3D) y destellos/ondas de impacto. La excavación se guarda aparte
  (`user://crystal_volume.bin`). Tamaño actual: 108 m de alto, base de ~75 m (escala 1,7 en el script).
- **Casucha del aprendiz** (`world/apprentice_hut.gd`): se empieza dentro y el cristal no se ve hasta abrir la
  puerta (F); el HUD esconde la esencia y el Pilón hasta entonces.
  `ShardPool` con 64 fragmentos físicos reciclados en 3 tamaños según el daño (astilla, fragmento, fragmento
  grande), que se congelan al quedarse quietos, se resaltan al apuntarlos y vuelan a la mano al recogerlos.
- **Mago** (`player/`): primera persona (ratón + WASD), manos 2D de Sprite AI; cada mano lleva una llamita de
  Chispa (`SpellOrb`) y recarga por separado (clic izquierdo / derecho). **Combinar** (GDD 5.2): los dos clics a la
  vez juntan las manos, las llamas se funden en la **Bola de Fuego** (`data/spells/recipe_fireball.tres`), que se
  carga manteniendo y sale al soltar como orbe volador con explosión en área; la primera vez se celebra
  (`Events.recipe_discovered`: pausa breve, nombre en grande y fanfarria) y queda guardada,
  recogida de fragmentos con F (apuntando o el más cercano delante), `SpellCaster` con
  enfriamiento, buffer, golpe resonante y pool de 12 chispas; `CameraRig` con sacudida por trauma y golpe de FOV.
- **Chispa** (`spells/`, `data/elements/spark.tres`): 5 niveles de poder (`SpellTier`) que cambian daño, cadencia,
  velocidad, tamaño, color, fragmentos, partículas, luz, grietas y sacudida.
- **Efectos** (`fx/`): shader toon, contorno de post-proceso (profundidad + normales), `ImpactFx` (estrellas,
  esquirlas, anillo y luz en pool), `HitStop`.
- **HUD** (`ui/`): Esencia con número rodante, mira con anillo de carga y marcador de impacto, racha, avisos,
  números flotantes, Pilón, FPS y ayuda de debug. Fuentes Silkscreen (texto pequeño) y Pixelify Sans (números).
- **Música** (`audio/music/`): tema del valle en La mayor, 84 BPM, en 5 capas sincronizadas (una por rango) con
  `AudioDirector.play_music` / `set_music_layers`. En debug, la tecla M suma capas.
- **Audio** (`audio/sfx/`): 20 OGG sintetizados (tink ×4, fragmentos, chispa, campanitas, acorde resonante,
  ambiente del valle y zumbido del cristal en bucle).
- **Debug** (sólo builds de desarrollo): teclas 1-5 cambian el nivel de la chispa; modo demo para grabar:
  `godot --path game -- --autoplay --tier=N` (añadir `--report` para imprimir draw calls y física;
  `--combo [--hold=s]` para lanzar Bolas de Fuego; `--delay=s` para esperar antes de empezar).
- `tests/smoke/progression_smoke.gd`: reglas de `Progression`, `SpellRecipe` y `StreakTracker` (pasa).
- `tests/smoke/combine_input_smoke.gd`: clic a la vez = combinación, clic suelto = una mano (pasa).
- `tests/smoke/loop_smoke.gd`: bolsa con tope, entrega en el Pilón, compra junto al atril y mejora que cambia la Chispa (pasa).
- **Hechizos por capas** (`spells/vfx/`): `SpellOrb` + `SpellVisualDef` (núcleo en espiral, cintas orbitales,
  destellos y luz; `charge`, `release()`, `appear()`). Primer hechizo: Orbe Arcano (`data/spells/vfx_arcane_orb.tres`).
  Galería para verlo y grabarlo: `godot --path game res://tests/vfx_gallery/vfx_gallery.tscn` (ver `CHANGELOG.md`).

- **Magia HD** (`fx/hd/`): capa de magia a resolución nativa con resplandor (ver registro de decisiones); fuego
  turbulento, halos, estelas, chispas con estela, ondas de choque, humo e impactos (`HdImpact`).
- **Hechizos que resaltan** (`spells/`): en vuelo, la misma llama de la mano (`SpellOrb`) de cara a la cámara con
  estela de fuego en píxeles sólidos (`spells/vfx/spell_trail.gd`), brasas y luz; al impactar, un estallido pixel art
  (`fx/impact_blast.gdshader`) con los colores del hechizo. Aspecto por nivel en `SpellTier` (`visual`, `orb_scale`,
  `trail_*`): Chispa (1-2), Llama (3) y Llama mágica rosa (4-5), también en las manos.
- **Pilón de Maná** (`pylon/`): vidrio y bronce con el maná líquido subiendo (raíz del progreso real, ver
  `ManaPylon.display_fill`), marcas al 10/25/50/75/100 %, cristal flotante, zumbido que crece. Al acercarte con la
  bolsa, los fragmentos vuelan de la mano con estela y cada gota sube una nota de la pentatónica.
- **Santuario** (`sanctum/`): templete con atril y el Grimorio flotando sobre un orbe arcano; aparece un objeto nuevo
  por cada nivel comprado (velas, estantería, bola de cristal, pociones, estandarte, runas, telescopio...).
- **Grimorio de Constelaciones** (`ui/grimoire.gd`): libro a pantalla, mejoras como estrellas y página que se escribe
  sola; inscribir sólo junto al atril (F), consultar en cualquier sitio (Tab).
- **5 mejoras** (`data/upgrades/`): Bolsa de aprendiz (1/5/20/100), Potencia (nivel de la Chispa), Canalización
  (recarga), Resonancia (% de golpes resonantes) y Telequinesis (atrae fragmentos). Costes y valores por nivel en el `.tres`.
- **HUD del bucle** (`ui/hud_loop.gd`): barra del Pilón con marcas, maná rodante, bolsa en casillas, avisos encadenados
  en la primera partida, marcadores en pantalla hacia el Pilón y el Santuario. La música suma una capa cada 3 niveles.
- Debug: G da 100 de maná; demo con `--no-cast`, `--mana=N`, `--bag=N`, `--warp=x,z`, `--grimoire [--buy --select=N]`.
  En modo demo no se carga ni se guarda la partida.

- **Título y pausa** (`ui/game_menu.gd`) con opciones. **Capas del cristal** por profundidad y **geodas** dentro
  (`crystal/geode.gd`, `data/crystal/`). Demo: `--layer=N` (túnel hasta la capa N), `--geode` (túnel hasta una
  geoda), `--dig=N` (N golpes de 30 donde se apunta).
- **Trituradora** (`pylon/crystal_crusher.gd`): tolva (mantener F), palanca (tocar F) y rodillos; el maná llega al
  Pilón por la tubería. **Reacción del cristal** (`fx/hd/crystal_arcs.gd`): rayos, destellos y resquebrajos.
- **Elementos por mano** (Q / E): Chispa y Escarcha (`data/elements/`); combinaciones Bola de Fuego y Choque
  Térmico (`data/spells/recipe_*.tres`); efecto de cada elemento en el cristal (`MotherCrystal._apply_element`).
- **Movimiento**: correr (Shift), saltar (Espacio), pasos y aterrizaje. **Día y noche** (`world/day_night.gd`) con
  paisaje sonoro (`tools/sfx_ambience.py`). **Pantalla de carga** que precalienta efectos (`Main._warm_up`).

**Aún no hay**: Rayo, Tierra y Arcano, familiares, simulador de balance (M2), trozos de cristal que caen al
quedarse sueltos (cortar la base de una punta) ni la mecánica propia de las Venas Resonantes.

## 8. Hitos

| Hito | Contenido | Criterio de éxito |
|---|---|---|
| **M1a El golpe** ✅ | Arte base del valle y del cristal, una chispa con 5 niveles y la reacción completa del cristal (GDD 10.3 y 10.4). | Golpear el cristal ya da gusto sin nada más. |
| **M1b Prototipo** ✅ (falta validar jugando) | Recoger y entregar fragmentos, Pilón, 5 mejoras. | Los primeros 5 minutos ya son divertidos. 60 fps estables. |
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
| 2026-11-15 | Música generada con `tools/music_synth.py`, en La mayor y en 5 capas (`AudioStreamSynchronized`). | Armoniza con el "tink" pentatónico; las capas cumplen "la música crece con el rango"; reproducible hasta tener compositor. |
| 2026-11-15 | Hechizos como pila de capas (`SpellOrb`) descrita por datos (`SpellVisualDef`). | Cada elemento, combinación y nivel es un `.tres`; misma calidad para todos. |
| 2026-11-15 | Magia con píxeles sólidos (`blend_mix` + tramado) en vez de aditiva; HDR sólo en el centro. | Lo aditivo se lavaba a blanco sobre el cristal y el cielo claros. |
| 2026-11-15 | Animación de VFX escalonada a 12 fps (`anim_fps`). | Lo procedural se lee como pixel art animado a mano. |
| 2026-11-15 | Manos que se juntan (animación de Sprite AI guiada por la carga) con el `SpellOrb` entre las palmas; la chispa sale del orbe. Sustituye a las 4 poses con la palma hacia la cámara. | Las anteriores se veían en diagonal hacia fuera; así coincide con la referencia. |
| 2026-11-15 | Manos en vertical que suben y se juntan desde su posición de reposo (no en horizontal desde los lados). | Pedido del equipo: juntar el hechizo verticalmente. |
| 2026-11-17 | Cada mano lleva su llama (elemento) y recarga por separado; los dos clics a la vez (ventana de 0,09 s, `combine_window_sec`) juntan las manos y funden las llamas en la Bola de Fuego, que se carga manteniendo y sale al soltar. Con las dos manos listas, un clic suelto espera esa ventana o sale al soltar el botón. | GDD 5.2 y 10.1; pedido del equipo ("juntar 2 hechizos de fuego, uno en cada mano, en uno grande"). Sustituye al orbe único entre las manos. |
| 2026-11-17 | Las llamas flotan sobre la punta de los dedos, no delante de la palma. | Las manos son 2D por encima del 3D: lo que queda detrás de la palma no se ve. |
| 2026-11-17 | Bolsa inicial de 3 (no 1): con el Pilón a ~30 m del cristal, 1 por viaje hacía la primera mejora demasiado lenta. | GDD 8.1: primera mejora en menos de 30 s. |
| 2026-11-17 | Capas del cristal por esencia destruida con paleta, tono y geodas (`data/crystal/layer_*.tres`). | GDD 6; progreso siempre visible. (Sustituida: ver "destructible de verdad".) |
| 2026-11-17 | **Cristal destructible de verdad**: volumen excavable (rejilla de distancias horneada + erosión por golpe + malla por trozos en otros hilos) en vez de ≈ 4.000 piezas físicas (GDD 6). Cristal mucho más grande (63 m, base de ~42 m) y layout más abierto (Pilón y Santuario a ~50 m). Las capas van por profundidad: se entra en el cristal excavando. Cada capa tiene densidad de esencia propia para repartir el 1.000.000 como el GDD (Corteza 6,4/m3, Manto 22, Venas 55, Corazón 89). | Pedido del equipo: que se rompa de verdad poco a poco y que las capas sean ir entrando. Con piezas físicas no se puede entrar ni ver el interior, y 4.000 cuerpos son caros. |
| 2026-11-17 | Cristal a escala 1,7 (108 m, base ~75 m, celdas de 0,8 m) apoyado en el suelo; claro de 100 m. Se empieza dentro de una casucha y el cristal se revela al abrir la puerta. | Pedido del equipo: "más grande aún" y que la primera vista del cristal sea un momento. |
| 2026-11-17 | Rayo y Tierra (GDD 5.1) y una combinación por cada pareja de los cuatro elementos (GDD 5.2, con Terremoto para Tierra + Tierra y Lanza de Hielo para Escarcha + Escarcha), cada una con su entrega (`SpellRecipe.Delivery`: frente, cielo, lluvia, lanza, haz, suelo, imán). Reacciones Vapor y Temple. Libro de Combinaciones (B) con acertijos para lo no descubierto. Datos generados con `tools/gen_spells.py`. | Pedido del equipo: combinaciones entretenidas de descubrir y espectaculares (Meteoro "tipo Megumin" con círculos en el cielo, Trueno). |
| 2026-11-17 | Hechizos hasta nivel 10: los niveles 6 a 10 se derivan del último escrito (`ElementDef.ensure_levels`, daño x2 por nivel) y a partir del 6 hay efectos por tipo: círculos mágicos al cargar (uno por nivel sobre 5) y círculos de toque al disparar. | Pedido del equipo; los niveles altos tienen que verse distintos, no sólo hacer más daño. |
| 2026-11-17 | Mejora de Tamaño por hechizo (`size_stat` en `ElementDef` y `SpellRecipe`, `SpellHit.size`): igual en la mano, crece al salir y agranda impacto, área, cráter y fragmentos; daño x(1 + 0,5 (tamaño - 1)). Levitación a 6 niveles (hasta 18 s) e Impulso del cristal (golpes en el aire recargan). | Pedido del equipo; con el cristal de 108 m hay que poder llegar a la punta. |
| 2026-11-17 | Mejoras de movimiento en la constelación del Mago: Doble salto y Levitación (carga de 1,6 / 3 / 5 s que se recarga en el suelo; se activa manteniendo Espacio tras el doble salto). No hay daño por caída. | Pedido del equipo; el cristal de 108 m pide moverse en vertical. |
| 2026-11-17 | El Corazón Cristalino sólo cede ante hechizos combinados y el Núcleo ante nada (por ahora): el golpe rebota con aviso. Geodas: 26 bolsas huecas en el Manto; al abrirlas se ven y un golpe las revienta (8 fragmentos grandes). | GDD 6 ("facetas duras que exigen combinados", "inmune salvo la Gran Convergencia", "geodas"). |
| 2026-11-17 | La capa de magia HD queda tapada por el cristal: copias de sus trozos en esa capa que sólo escriben profundidad, metidas 1 m hacia dentro; los efectos HD dejan de ignorar la profundidad. | Con túneles y geodas dentro, los destellos se veían a través de las paredes. |
| 2026-11-17 | Pantalla de título y pausa (`ui/game_menu.gd`) con opciones guardadas en Settings. | Pasada de calidad pedida por el equipo. |
| 2026-11-17 | Idiomas: un solo `localization/strings.csv` con el texto español como clave y una columna por idioma; `Settings` carga en ejecución todos los `.translation` de la carpeta, elige el del sistema la primera vez (si no, inglés) y se cambia en Opciones (en vivo, con `Events.locale_changed`). `tools/extract_strings.py` añade las claves nuevas. | Pedido del equipo: español e inglés, y que añadir otro idioma sea sólo añadir una columna, sin tocar código. |
| 2026-11-17 | Título con humor: "CAN YOU / DESTROY IT" letra a letra y un "?" de cristal enorme que se puede romper a clics (se queja, se agrieta y se vuelve "!"); frases que rotan. Música propia: vals a 3/4 en La mayor (`tools/music_title.py`) que siempre termina "preguntando"; se funde con la del valle al empezar. | Pedido del equipo: menú gracioso pero de calidad, con su propia música. |
| 2026-11-17 | La entrega deja de ser automática: trituradora junto al Pilón (mantener F echa a la tolva, acelerando; tocar F tira de la palanca y tritura; el maná se gana al triturar). | Pedido del equipo; GDD 2.2 ("entregar no es un trámite"). |
| 2026-11-17 | Golpes al cristal: 10 variantes suaves en 3 timbres; la racha sube dentro de una octava. El cristal reacciona con rayos, destellos y "resquebrajos" cada cierto daño. | Pedido del equipo: menos molesto, más variado y más reactivo. |
| 2026-11-17 | Cada mano lleva un elemento (Q / E). Segundo elemento: Escarcha, que se despierta en el Grimorio (no al 10 % del Pilón todavía) para que Q/E y las combinaciones se puedan jugar ya. | Pedido del equipo (Q/E) y GDD 5.2; M2 pide 2 elementos y 1 combinación. |
| 2026-11-17 | Efecto en el cristal por elemento: el fuego quema (marcas y fuego que sigue ardiendo con daño por quemadura), la Escarcha congela (x2 para los otros elementos 6 s) y el Choque Térmico deja la zona quebradiza (x3 al siguiente golpe). | Pedido del equipo ("afecte al cristal según elementos"); GDD 5.1 y 5.2. |
| 2026-11-17 | Grimorio por elementos: una constelación por elemento en pestañas, más la del Mago (bolsa, telequinesis, resonancia). | Pedido del equipo. |
| 2026-11-17 | Pantalla de carga que precalienta shaders y partículas apuntando la cámara a cada sitio. | Congelaciones la primera vez que se dibuja cada efecto (compilación de shaders). |
| 2026-11-17 | Ciclo de día y noche (`DayNight`, 10 min) con parámetro global de shader `world_tint` para lo que no usa la luz del motor. | Pedido del equipo; GDD 3 ("de noche ilumina todo el valle"). |
| 2026-11-17 | **HD-2D**: el mundo y las manos en pixel art (640x360) y la magia en una capa aparte a resolución nativa con resplandor HDR, compuesta con alfa premultiplicado (`MagicLayer`, capa visual `1 << 10`). Stretch del proyecto a `canvas_items`; el mundo en una SubViewport con filtro nearest. | Pedido del equipo: los hechizos deben verse espectaculares, con efectos de juegos modernos; con píxeles sólidos a 12 fps no se llegaba. Referencia: Octopath Traveler. |
| 2026-11-17 | Cristal Madre a escala 2,3 y posiciones en `WorldLayout` (Pilón y Santuario a ~30 m). | Pedido del equipo: cristal más grande y máquinas menos pegadas; GDD 4.1 (30 veces el mago). |
| 2026-11-17 | El hechizo en vuelo es el mismo `SpellOrb` de la mano + estela de píxeles sólidos (`SpellTrail`) + estallido de impacto pixel art; el rombo aditivo (`spark.gdshader`) deja de usarse. | Pedido del equipo: los hechizos tienen que resaltar mucho más; lo aditivo se perdía contra el cielo y el cristal. |
| 2026-11-17 | Cada nivel de la Chispa tiene su aspecto (`SpellTier.visual`): Chispa, Llama y Llama mágica rosa. | GDD 7 y 10.3: "Chispa -> Llama -> Infierno" y "de naranja a rosa mágico". |
| 2026-11-17 | Pilón a la izquierda (-8, 0, 11) y Santuario a la derecha (9,5, 0, 12,5) del claro, a unos 10 m del cristal; el jugador empieza entre los dos. | GDD 4 y 8.1 (≈ 10 m, 4 s andando). |
| 2026-11-17 | El nivel del Pilón (y su barra) muestra la raíz cuadrada del progreso, con un charco mínimo del 2 %. | Con 1.000.000 de esencia, el progreso real no se vería en la primera hora; así cada entrega se nota y las marcas quedan repartidas. |
| 2026-11-17 | La entrega es automática al acercarse al Pilón (4,5 m), fragmento a fragmento. | Sin tecla extra; el chorro con notas que suben es la recompensa. |
| 2026-11-17 | Se compra sólo junto al atril del Santuario; Tab abre el Grimorio en cualquier sitio para consultarlo. | GDD 4.3 (lugar físico de mejora) y 10.1 (Tab = Grimorio rápido). |
| 2026-11-17 | `UpgradeNode` con costes y valores por nivel explícitos (`costs`, `values`, `level_names`). | Las curvas del GDD no son lineales (bolsa 1/5/20/100); se balancean en el `.tres`. |
| 2026-11-17 | El modo demo (`--autoplay`) no carga ni guarda la partida. | Las capturas empiezan de cero y sus trucos no ensucian la partida del jugador. |
| 2026-11-17 | Bola de Fuego: daño = (mano izq. + mano der.) x 2,5 x potencia (50-100 % según la carga), enfriamiento de 2 s en las dos manos, 3 golpes secundarios en área que sólo agrietan y sueltan astillas. | Mejor que dos chispas sueltas (≈1,85 frente a 1,33 de daño por segundo con la Chispa 1) pero pide comprometerse; valores en el `.tres`, a balancear en M1b. |
| 2026-11-17 | Tutorial exprés al salir de la casucha (`ui/tutorial.gd`, paso guardado en `Progression.tutorial_step`): clic izq. y der. no hacen daño (chispa que se apaga con "clink"), juntar hace 1 y suelta un pedacito, recoger, triturar, juntar 5 y comprar la Potencia (2 de daño). La esencia acreditada por golpe es igual al daño. | Pedido del equipo: empezar siendo un mago lamentable y sentir la primera mejora; enseña las dos manos, la combinación y el bucle en menos de un minuto. |
| 2026-11-17 | Arcano (5.º elemento) con ecos genéricos (`SpellRecipe.echo_of/echo_count/echo_delay/echo_damage`, `SpellEchoes`); Gravedad recoge todo el valle (`ShardPool.gravity_pull`); Resonancia Arcana vuelve resonantes los golpes 5 s (8 s de espera). | GDD 5.1/5.2: el Arcano "repite" y abre las combinaciones raras; la Gravedad es la utilidad de recogida de mitad de partida. |
| 2026-11-17 | Los fragmentos de un golpe valen su daño (`ShardPool.pieces_for`): el tipo sale del daño (umbral = doble de su valor: Astilla 1, Fragmento 5 desde 10, Grande 25 desde 50, Bloque 100 desde 200, Pedrusco 500 desde 1000), de 2 a 9 piezas y hasta 3 trocitos para el resto. Tierra y Lanza Cargada: +25 %. | El maná sale de la esencia que pierde el cristal, así el Pilón y el cristal avanzan juntos; golpes más fuertes = piezas más grandes y números más grandes (y menos viajes). Antes, a nivel alto, el Pilón se quedaba en el 47 %. |
| 2026-11-17 | El maná no se corta con el Pilón lleno (`Progression.deliver`); sólo la barra tiene tope. | Los bonus de valor pueden adelantar un poco el Pilón al cristal y no se debe quedar el jugador sin comprar. |
| 2026-11-17 | Balance con `tools/balance_sim.py`: todos los elementos siguen la misma curva por nivel (x1,38 de daño y x0,92 de enfriamiento por nivel desde el último escrito a mano, `ElementDef.damage_growth`) escalada por elemento (Chispa 1, Escarcha 1,6, Rayo 3, Tierra 7, Arcano ~10); el multiplicador de cada combinación es K x su ciclo (carga + enfriamiento), con K mayor en cada generación (fuego/hielo < rayo < tierra < arcano); las Potencias de Bola de Fuego y Choque Térmico llegan a x2. | Antes cada nivel doblaba el daño y la Chispa sola a nivel 10 rompía el cristal en 40 min; ahora cada elemento nuevo empieza flojo, se pone al día con niveles baratos y sus combinaciones superan a las viejas (el final lo mandan Ecos, Resonancia y Terremoto). |
| 2026-11-17 | Tras la primera mejora la Chispa hace 2 de daño (lo que dice el tutorial) y juntar las manos, 11. | Pedido del equipo ("la primera mejora te hace hacer 2 puntos de daño") y un salto que se nota al salir del tutorial. |
| 2026-11-17 | Familiares (`FamiliarDef` en `data/familiars/`, `FamiliarFlock`, `FamiliarNest` junto al Pilón): recolectores que llevan fragmentos a la tolva y tiran de la palanca, y hechiceros que lanzan chispas reales (`SpellHit.familiar`). | GDD 2.2 (la entrega es lo primero que se quiere automatizar) y 4.3 (Jaula de Familiares). |

## 10. Preguntas abiertas

- Confirmar 3D a baja resolución frente a 2D puro tras jugar el prototipo M1a.
- Arte 3D (valle, cristal): seguir procedural y pulir; el arte 2D sale de Sprite AI.
- ¿Puntas que se caen enteras al cortarles la base (islas sueltas del volumen)? Sería muy vistoso; pide detectar
  conectividad en una rejilla gruesa en otro hilo.
- Golpes enormes del final (miles de daño): excavar cuesta ~20 ms en el hilo principal; habrá que pasarlo a un hilo.
- Resolución interna final (640x360 propuesta) tras probarla en 1440p y Steam Deck.
- ¿Modo infinito o New Game+ tras el final?
- Precio y fecha objetivo en Steam.
