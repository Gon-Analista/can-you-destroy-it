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
| Fragmento | Pedazo que cae al golpear: Astilla, Fragmento, Geoda, Resonante, Lágrima del Núcleo. | `Shard`, `ShardType` |
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
- **Manos y hechizos** como sprites 2D animados a mano sobre una capa de canvas, misma escala de píxel.
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
| `Can_You_Destroy_It_GDD.pdf` | GDD v0.2 (fuente del diseño). |
| `tools/make_gdd.py` | Genera el PDF del GDD (`python3 tools/make_gdd.py Can_You_Destroy_It_GDD.pdf`). Requiere `reportlab` y `Pillow`. |
| `docs/referencias/` | Imágenes de referencia de cristal y estilo. **No son arte final.** |
| `AGENTS.md`, `.agents/` | Instrucciones para agentes. |
| `index.html`, `src/` | Esqueleto web inicial, **obsoleto**: se elimina al crear el proyecto Godot. |

**Aún no existe el proyecto Godot.** La primera tarea técnica es crearlo con la estructura de `dev_guidelines.md`.

## 8. Hitos

| Hito | Contenido | Criterio de éxito |
|---|---|---|
| **M1 Prototipo** | Proyecto Godot 4.7, pipeline pixel art, cristal con facetas, chispa, fragmentos, entrega manual, Pilón, 5 mejoras. | Los primeros 5 minutos ya son divertidos. 60 fps estables. |
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

## 10. Preguntas abiertas

- Confirmar 3D a baja resolución frente a 2D puro tras el prototipo M1.
- Resolución interna final (640x360 propuesta) tras probarla en 1440p y Steam Deck.
- ¿Modo infinito o New Game+ tras el final?
- Precio y fecha objetivo en Steam.
