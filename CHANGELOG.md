# Changelog

Cada push a `main` se documenta aquí, el más reciente arriba (ver `.agents/dev_guidelines.md`, sección 12).

## 2026-11-21 · Los hechizos cargados salen con la fuerza que tienen

**Qué hay nuevo** (pedido del equipo: "la bola de fuego es lenta y no se ve poderosa… que salgan con un efecto de
poder e impacto de tus manos y te lancen un poquito para atrás… el meteorito más grande, el rayo más impactante… el de
tierra es una piedrecita aburrida")

- **Más rápidos cuanto más cargados**: lo que sale de las manos vuela a x1,6 sin cargar y hasta x3,4 con la carga
  completa (`SpellDelivery.FRONT_SPEED`); las lanzas, x1,2-2,2. La Bola de Fuego cargada llega en ~0,4 s en vez de
  ~1,2 s. El daño no cambia: sólo lo que tarda en llegar.
- **Golpe de poder al soltar** (`CastBurst`): fogonazo entre las palmas, hasta tres ondas de choque en cono hacia
  donde apuntas y chispas disparadas, con un estruendo grave. La cámara cabecea hacia arriba y se abre
  (`CameraRig.recoil`), las manos salen despedidas y, si el hechizo sale hacia delante, **el mago retrocede**
  (`Player.knockback`); cargado a tope a nivel alto, con un saltito. Todo escala con la carga.
- **El tamaño va con la destrucción**: lo que se ve en vuelo crece con el premio de la carga (`SpellHit.fx_scale`,
  `SparkProjectile.charged_scale`): un combinado de nivel 11 cargado a tope vuela casi al doble de grande, con estela
  y luz a juego. Lluvias y haces también (Ventisca, Estalactitas, Tormenta de Arena).
- **Meteoro más grande**: roca de 3,4 m de radio (antes 2,4) y fuego de 36 (antes 26), más la escala de la carga.
- **Juicio del Trueno más impactante** (`CrystalCombos.sky_bolt(power)`): más descargas y hebras que convergen desde
  el cielo cuanto más cargado, halo violeta para que se lea sobre el cristal claro, rayos que se abren por el cristal
  al tocarlo y una columna que se queda encendida; más sacudida.
- **Terremoto: un peñasco** (`BoulderRoll`, `SpellVisualDef.boulder`): brota del suelo unos metros por delante, rueda
  sin resbalar con vetas doradas, da botes que retumban, levanta polvo y gravilla y revienta en cascotes contra la
  base del cristal. La Erupción (triple) usa el mismo peñasco al rojo.

**Cómo se probó**: Godot 4.7 con lavapipe, capturas antes/después de la Bola de Fuego, Terremoto, Tornado, Meteoro y
Trueno a nivel 11 con carga completa (`docs/capturas/cargados_*.gif` y `cargados_antes_despues.png`). Tests de humo: `meteor_smoke`,
`fireball_flight_smoke`, `combos_smoke`, `charge_stages_smoke`, `spell_levels_smoke`, `combine_input_smoke`,
`progression_smoke`, `hit_stop_smoke` y `movement_smoke` en verde; `gdlint` limpio.

## 2026-11-21 · Golpear el Núcleo ya no falla y los golpes enormes dan muchos menos tirones

**Arreglos** (pedido del equipo: "me crasheó al tirarle un hechizo al núcleo morado… al explotar grandes pedazos
del cristal me bajan mucho los fps")

- **Error al golpear el Núcleo**: al quedar expuesto, `CoreReveal` borraba las geodas abiertas pero `CrystalGeodes`
  las seguía teniendo en su lista; el siguiente golpe buscaba una geoda ya borrada ("previously freed" en
  `crystal_geodes.gd:47`) y el golpe se cortaba. Ahora las borra `CrystalGeodes.clear_all()` (vía
  `MotherCrystal.clear_geodes()`). `ending_smoke` abre una geoda antes del final y golpea el Núcleo: con el código
  viejo falla con el mismo error.
- **Tirones en los golpes enormes** (medido en Intel Iris Xe con un Meteoro de 20.000 de daño, 3 golpes):
  | | antes | ahora |
  |---|---|---|
  | `receive_hit` | 64-147 ms | 20-35 ms |
  | peor fotograma tras el golpe | 140-196 ms | 38-47 ms |
  | fotogramas > 20 ms (de 150) | 35-116 | 34-38, casi todos de 20-30 ms |
  - **El remallado del cristal ocupaba todos los núcleos.** Las tareas de malla iban con prioridad alta; con
    decenas de trozos a la vez llenaban los 8 hilos y el render (hilo principal y driver) se quedaba sin CPU:
    el "render" de un fotograma subía de 8 a 110 ms. Ahora van con prioridad baja (`CrystalChunks._start`).
  - **`CrystalVolume.carve` 4,2 veces más rápido**: sólo recorre las celdas dentro de la esfera, sin raíces y con
    la capa, el llenado y los trozos tocados calculados en línea (por fila, no por celda). Mismo resultado (esencia,
    capas y trozos idénticos; la rejilla difiere en redondeos de 2·10⁻⁶). Se nota en el golpe y en cada réplica.
  - **Los trozos rehechos se aplican con presupuesto** (`CrystalChunks.APPLY_BUDGET_MS` = 3 ms por fotograma):
    malla, oclusor y colisión de decenas de trozos ya no caen en el mismo fotograma.
  - **Las tareas de malla se esperan** (al terminar y al borrar el cristal): antes nadie las esperaba y, al salir o
    cambiar de escena con alguna en marcha, un hilo podía seguir con el nodo ya borrado.

**Cómo se probó**: banco temporal con 3 Meteoros enormes (tiempos por fotograma de scripts, física y render),
comparación del `carve` nuevo con el viejo en 40 cráteres al azar, y `ending_smoke`, `crystal_volume_smoke`,
`meteor_smoke`, `veins_pylon_smoke`, `boot_smoke` y `combos_smoke` en verde.

**Pendiente**: el primer fotograma de un golpe enorme sigue costando 20-35 ms (excavar y los ajustes en seco en el
hilo principal) y cada réplica ~10 ms; pasarlo a un hilo es lo siguiente si hace falta. `ending_smoke` termina con un
segfault al cerrar también con el código anterior (no es de este cambio).

## 2026-11-21 · Arranque nuevo: título ligero, pantalla de carga con barra y menos tirones

**Qué hay nuevo** (pedido del equipo: "lagea un montón al iniciar… falta una pantalla de carga… y un menú que
cargue menos cosas")

- **Título propio** (`title/title_screen.gd`, escena principal): ya no es el juego cargado detrás de un menú. Fondo
  pintado del valle al atardecer (`title/title_backdrop.png`, una captura del propio juego) con motas de maná que
  suben y destellos en el cristal, el logo de siempre y CONTINUAR / NUEVA PARTIDA / OPCIONES / SALIR. NUEVA PARTIDA
  con partida guardada pide confirmación ("¿EMPEZAR DE CERO?"). Sale en ~0,3 s.
- **Carga en segundo plano** (`title/scene_flow.gd`): mientras se ve el título, `main.tscn` se carga en otro hilo.
- **Pantalla de carga** (`ui/loading_cover.gd`): cielo de estrellas, barra de progreso con brillo, la etapa
  ("CARGANDO EL VALLE", "TALLANDO EL CRISTAL", "DESPERTANDO EL VALLE", "ENCENDIENDO EL PILÓN"…) y consejos que
  cambian. Entra fundiéndose desde el título, sigue viva durante el precalentado de efectos y se va sola.
- **Menos bloqueo al entrar** (medido en este servidor, sin GPU): el valle se montaba bloqueando ~2,5 s antes de
  enseñar nada; ahora el título sale al instante y el tirón al montar baja a ~0,9 s, tapado por la barra.
  - Las formas de colisión de los fragmentos se hacían con simplificación: ~1 s para 24 piezas pequeñas. Ahora 3 ms.
  - La rejilla y las mallas del cristal se tallan en los hilos durante la pantalla de carga (`CrystalPrebuild`)
    en vez de esperar a que terminen dentro del `_ready` del cristal.
- **Pausa**: nuevo botón MENÚ PRINCIPAL (guarda y vuelve al título, callando el valle). "Nueva partida" desde el
  menú de depuración o la pantalla final pasa también por la pantalla de carga.
- Al entrar desde el título el ratón vuelve a la mira y el tema del título se funde con la música del valle.
- `--autoplay` sigue yendo directo al juego; `--title-play` pulsa JUGAR solo (capturas de la carga); `--backdrop`
  quita HUD y manos; `--warp` respeta la altura del suelo.
- Prueba nueva: `boot_smoke` (título → carga → juego → pausa → título → otra partida).
- **Cero avisos de GDScript** en el Depurador del editor (eran ~830: conversiones desde Variant, divisiones enteras,
  señales del bus, nombres que tapaban otros). Tipado de verdad donde se podía; `VariantCast` (`core/variant_cast.gd`)
  para leer números de guardados, opciones y JSON igual que `int()`/`float()`/`bool()`; `@warning_ignore` sólo en
  las señales de `Events` y en divisiones enteras buscadas. `tools/gd_warnings.py` los lista (vía el LSP del editor).
- **Rebote** (runa): con el cristal más grande, un golpe cerca de la base buscaba el siguiente punto desde bajo
  tierra y rebotaba contra la cara de abajo del cristal; ahora descarta puntos bajo el suelo y caras que miran al
  otro lado, y si los rayos fallan busca otra cara visible hacia el eje del cristal.
- Pruebas que venían rotas de `main`: `staff_smoke` (nombraba `SpellBook` y no contaba la pestaña VIENTO) y
  `runes_smoke` (el rebote de arriba).
## 2026-11-20 · Paleta azulada, niebla lejana y luciérnagas

**Qué hay nuevo**

- **Paleta "azulada" por defecto** (`world/valley_palette.gd`): la luz de la noche llevada al día para que
  no canse la vista. Verdes más hondos y algo azulados, camino menos naranja, sombras azul pizarra, sol crema
  más suave y cielo azul profundo. Se hace con una LUT 3D generada en código (`adjustment_color_correction`),
  fotogramas de día propios en `DayNight` y el ajuste del entorno; no se tocó ningún asset.
  `--palette=actual|suave|pastel` deja probar la original y las otras dos candidatas.
- **Niebla lejana** (perspectiva atmosférica): empieza a 35 m y se funde hacia los 330 m con el color de la
  hora. El fondo (bosque lejano, montañas, castillo) se calma y lo cercano queda nítido.
- **Luciérnagas** (`world/fireflies.gd`): de noche, puntitos amarillo verdoso que flotan sobre la hierba
  alrededor del mago y parpadean. Píxeles sólidos con HDR para el halo.
- `tests/tools/palette_shots.gd`: capturas por paleta, hora y vista para comparar.

**Cómo se probó**: Godot 4.7 con lavapipe, capturas de día, atardecer y noche desde el claro, el cristal, el
castillo, el bosque y el valle. `ending_smoke` y `veins_pylon_smoke` pasan; `gdlint` limpio.

**Capturas (antes | después)**: `docs/capturas/paleta_azulada_niebla.png`, `docs/capturas/noche_luciernagas.png`.

## 2026-11-20 · Hechizos: Viento, nivel 11, cargas que valen la pena y círculos que se ven

**Qué hay nuevo**

- **Viento**, sexto elemento (página propia en el Grimorio, se abre con el Pilón al 35 %): rápido y ligero, y cada
  golpe barre hacia la mano los fragmentos del suelo cerca del impacto. Seis combinaciones nuevas, en su pestaña
  VIENTO del Libro: **Tornado** (perfora), **Torbellino de Fuego** (estalla y quema), **Ventisca** (lluvia de hielo),
  **Tempestad** (lluvia de rayos, de toque), **Tormenta de Arena** (haz que lija) y **Eco del Viento**. Sonidos
  nuevos con `tools/sfx_wind.py`.
- **Cada elemento con su forma**, no sólo su color (`hd_fire.gdshader`, `style`): la Tierra es una roca que rueda
  con vetas doradas (antes, fuego marrón), la Escarcha un cristal facetado con copo, el Rayo arcos quebrados que
  saltan y el Viento medialunas de aire que giran. Laboratorio para compararlos: `tests/vfx_gallery/element_lab.tscn`.
- **Nivel 11 (Ascensión)** en cada Potencia: se abre con el cristal destruido al 80 % y cuesta 100 k de maná.
  Golpea unas 70 veces más que el nivel 10 y su carga completa multiplica x10. Con todo al máximo, de 3 a 5 golpes
  cargados de las mejores combinaciones (Terremoto, Lluvia de Estalactitas, Tormenta de Arena, Tornado, Ventisca,
  Torbellino, Meteoro, Eco de Fuego) rompen el cristal.
- **Cargar vale la pena**: el premio de carga completa sube con el nivel (`full_charge_bonus_by_level`) y el daño
  se reparte por círculos. Sólo algunos hechizos se tiran mejor de toque (Lanza de Hielo, Haz de Plasma, Lanza
  Cargada, Eco de Hielo, Tempestad y las de utilidad): sueltos sin cargar ya hacen casi todo su daño.
- **Círculos en primera persona**: salen de las manos y se colocan delante, separados y cada vez más lejos; al
  soltar vuelan hacia delante en vez de amontonarse en la mano.
- **Lo que cae del cielo cae a plomo** (Meteoro, Trueno, Glaciar, lluvias): sus círculos son anillos horizontales
  apilados encima del blanco, y si hay una punta de cristal en medio, el hechizo aterriza ahí.
- **Réplicas** (`CrystalAftershocks`): un golpe que pediría un cráter de más de 14 m se queda en ese tope y el
  resto del volumen lo excavan réplicas alrededor, una por fotograma.

**Balance** (`tools/balance_sim.py`, ya entiende niveles 11, carga y toque): normal ~138 min, eficiente ~106 min,
todas las mejoras compradas, la Ascensión al final.

**Cómo se probó**: tests de humo (nuevos casos en `progression_smoke`, `charge_stages_smoke`, `meteor_smoke`,
`spell_levels_smoke`, `combos_smoke`), `gdlint` limpio, capturas en `docs/capturas/`.

## 2026-11-20 · Rendimiento: bosque y hierba por trozos con LOD

**Qué hay nuevo**

- **`ChunkedMultiMesh`** (`core/chunked_multimesh.gd`): el bosque (trozos de 48 m) y la hierba y las flores
  (24 m) ya no son un único `MultiMesh` por tipo con una caja que cubría todo el valle. La cámara y cada
  cascada de sombra descartan los trozos que no ven; las plantas se cortan con `visibility_range_end` justo
  donde el shader ya las había encogido a cero.
- **LOD automático** en los cuatro árboles (`ImporterMesh.generate_lods`): de lejos usan versiones con menos
  triángulos; el motor sólo cambia cuando la diferencia es de menos de un píxel.
- **Mallas indexadas**: `MeshKit.commit` comparte los vértices repetidos (menos trabajo de vértices).
- **Banco de pruebas** `tests/stress/world_bench.gd`: cinco vistas fijas con ms por frame, draw calls,
  objetos y triángulos (también de la sombra).

**Medido** (lavapipe, CPU; los ms sirven para comparar, los triángulos son exactos). Media de las cinco vistas:

| | ms / frame | FPS | Triángulos en el claro | Triángulos de sombra en el claro |
|---|---|---|---|---|
| Antes de las texturas nuevas | 282,7 | 3,5 | 376 k | 1,51 M |
| Con texturas nuevas, sin optimizar | 421,4 | 2,4 | 932 k | 5,07 M |
| Con texturas nuevas y optimizado | 238,6 | 4,2 | 262 k | 0,82 M |

Mirando hacia otro lado (vista "atrás") se pasa de 740 k a 45 k triángulos. Las draw calls suben algo (claro:
298 a 413), lejos del límite de 1.500.

**Cómo se probó**: capturas de las cuatro vistas comparadas píxel a píxel con las de antes de optimizar: las
siluetas son las mismas; sólo cambian puntitos sueltos del dibujo de las hojas en árboles lejanos (~1 % de la
imagen). Tests de humo que pasaban siguen pasando; `gdlint` limpio.

**Scripts**: perfilados en headless desactivando nodos uno a uno; con el ruido de la máquina de pruebas no
salió ningún punto caliente claro, así que no se tocaron.

## 2026-11-20 · Texturas pixel art en el paisaje, árboles redondos y formas sin pinchos

**Qué hay nuevo**

- **Textura pixel art procedural** (`world/terrain.gdshader`): el suelo, los caminos, las rocas, las montañas y
  los árboles dejan de ser colores planos. Cada malla elige su dibujo con el alfa del color de vértice
  (`MeshKit.tag`): hierba (manchas tramadas, matas y florecillas; roca en cuestas fuertes), tierra (vetas y
  guijarros), roca (estratos y grietas), roca con nieve (borde tramado a la altura de cada montaña), hojas y
  corteza. Los texeles van en una rejilla del mundo (14 por metro) y se doblan con la distancia para no bajar
  nunca de un píxel: sin parpadeo ni texturas borrosas. Las bandas de luz se tramean (Bayer 4x4).
- **Árboles nuevos** (`Valley._build_pine_mesh`, `_build_broadleaf_mesh`): dos abetos de pisos redondeados
  con el borde ondulado y la punta roma, y dos árboles de copa redonda (varias bolas blandas). Normales
  suaves, color por instancia para que no haya dos iguales. Copas redondas sobre todo en el linde del claro.
- **Formas más suaves**: suelo, montañas (cima redondeada) y colina del castillo con normales suaves en vez
  de facetas; rocas como cantos rodados (`MeshKit.add_blob`); setas con sombrero en cúpula; hierba de hojas
  anchas y punta roma; losas y tocones con más lados.
- `MeshKit`: `add_tri_smooth`, `add_grid` (rejilla con normales suaves) y `add_blob`.

**Cómo se probó**: Godot 4.7 con Vulkan por software (lavapipe) y `--autoplay`, capturas desde el claro, el
bosque y hacia el castillo. Tests de humo: los mismos que ya fallaban en la rama base (cierre con
`double free` en headless) y ninguno nuevo; `grimoire_click_smoke` pasa con ventana. `gdlint` limpio.

**Capturas (antes | después)**: `docs/capturas/texturas_arboles_front.png`, `..._forest.png`,
`..._castle.png`, `..._side.png`.

**Pendiente**: el Cristal Madre y los cristales que brotan del suelo siguen siendo facetados a propósito. El
bosque tiene unas 10 veces más triángulos que antes (~400 k); la pasada de rendimiento va aparte.

## 2026-11-19 · Pulido del mundo: cristal más grande, nubes, nombres de las estaciones; báculo apagado

**Qué hay nuevo**

- **Cristal Madre un 25 % más grande en todo** (`tools/crystal_volume.py`, `S` 2,125): ~135 m de alto y ~95 m
  de base. Capas, Núcleo y geodas crecen igual. La esencia por golpe no cambia (manda el daño; los cráteres se
  ven algo mayores). `WorldLayout`: huella 50 m y Pilón, Santuario, Espejo, Mesa de Runas y Jaula alejados en
  proporción; la casucha se queda donde estaba. Las partidas guardadas con el cristal excavado lo recuperan entero.
- **Sin "dientes" en el cristal**: la normal de cada triángulo sale del gradiente del campo (no de su geometría)
  y el shader ya no varía el tono por la normal cuantizada. Las caras planas se ven limpias.
- **Nubes 3D** (`world/crystal_clouds.gd`, `world/cloud.gdshader`): siete abrazan la punta del cristal y once
  forman un techo lejano. Sin luz del motor, con la paleta de las nubes del cielo y teñidas por la hora del día;
  giran muy despacio alrededor del cristal.
- **Nombres de las estaciones** (`ui/guide/station_labels.gd`): al acercarse (30 a 6 m) se lee qué es cada
  cosa (Pilón, Trituradora, Santuario, Mesa de Runas, Espejo, Vitrina, Jaula). Debajo, para qué sirve, sólo en
  la más cercana a la mira y hasta que se usa una vez. Si se pisan, las lejanas suben.
- **El báculo, apagado por ahora** (`StaffCombos.ENABLED = false`): en las pruebas confundía, así que el
  juego queda sólo con la magia de las manos. Sin mejoras del báculo (`staff`, `staff_power`, `staff_focus`
  fuera de `GameState.UPGRADES`), sin su página en el Grimorio, sin triples en el Libro (sólo PAREJAS), sin R
  ni rueda para la gema y sin vitrina. Una partida guardada que ya lo tenía comprado no lo enseña (el maná
  gastado no se devuelve). El Espejo y la pantalla final cuentan 17 combinaciones en vez de 22. Todo el código
  sigue ahí: para volver, `ENABLED = true` y devolver las tres mejoras y la página. El simulador
  (`tools/balance_sim.py`, que lee el interruptor) termina la partida igual: ~1 h 51 el jugador eficiente.
- **Vitrina del Báculo** (`sanctum/staff_vitrine.gd`, GDD 4.3; no se construye con el báculo apagado): una urna de cristal con marco de oro junto al
  final del camino del Santuario. Dentro flota el báculo: gris y con candado hasta comprarlo; luego se enciende
  con un destello y su gema toma el color del elemento que lleva. Con F se abre el Grimorio directamente por la
  constelación del Báculo (y se puede comprar ahí). Tiene nombre y línea de ayuda como las demás estaciones.
  Para capturas: `--at-staff-vitrine`.
- **Hierba y flores de lejos**: se encogen entre 16 y 40 m de la cámara (`shrink_far` en `fx/toon.gdshader`).
  Ya no se ven palitos negros por todo el valle.
- **Faroles**: los postes ya no proyectan sombra (con el sol bajo dejaban rayas larguísimas).
- **Tutorial**: el primer paso al salir de la casucha es "Acércate al cristal" (`Tutorial.Step.APPROACH`).
  Lanzar antes de llegar también vale.
- **Círculos de la carga**: sólo el primero lleva el dibujo entero; los demás son aros huecos y más separados.
  Ya no se amontonan.
- **Menú de depuración**: los botones bajan de línea si no caben; el panel ya no se sale de la pantalla.

**Cómo se probó**

- Pruebas en headless: todas en verde salvo `grimoire_click_smoke`, que ya fallaba antes ("clic en INSCRIBIR
  compra"). `staff_smoke` apunta ahora por encima de la puntita del pie del cristal, que con el tamaño nuevo
  llega casi al cruce de caminos; con el báculo apagado comprueba que no queda rastro de él (mejoras,
  página, vitrina, R, triples). `ranks_smoke` cuenta 17 combinaciones sin báculo. `milestones_smoke` cuenta
  los fragmentos del Vórtice alrededor del mago (contaba los de todo el valle y fallaba según el ritmo).
  Varias pruebas abortan al salir ("corrupted size vs. prev_size"); también pasa sin estos cambios.
- Capturas a 1280x720 de día, al atardecer y de noche:
  [nubes en la punta](docs/capturas/nubes_punta_cristal.png), [cristal grande](docs/capturas/cristal_grande.png),
  [nombres de las estaciones](docs/capturas/estaciones_nombres.png),
  [tutorial](docs/capturas/tutorial_acercate.png), [círculos de carga](docs/capturas/circulos_carga_aros.png),
  [menú de depuración](docs/capturas/menu_depuracion_cabe.png),
  [Vitrina del Báculo desde el camino](docs/capturas/vitrina_baculo_camino.png),
  [vitrina sin báculo](docs/capturas/vitrina_baculo_apagada.png),
  [vitrina con báculo](docs/capturas/vitrina_baculo_encendida.png),
  [hierba sin palitos](docs/capturas/hierba_lejos.png), [faroles sin rayas](docs/capturas/faroles_sin_sombra.png).

**Pendientes y problemas conocidos**

- Justo al empezar (unos 5 s) se ven restos de los efectos que precalienta la pantalla de carga delante del
  cristal (bolas de luz, algún trozo de cristal en el aire, un brillo fuerte del sol); el título los tapa en una
  partida normal y a los 15 o 20 s ya no queda nada.
- La rejilla del cristal pasa de 3,8 a 8,4 millones de puntos (~67 MB): vigilar la carga y los tirones al excavar
  en Steam Deck.
- Sigue pendiente que los trozos de cristal que quedan sueltos al excavar caigan.
- `runes_smoke` falló una vez ("rebota y vuelve a golpear") con cuatro pruebas a la vez; sola pasa.

## 2026-11-19 · Mesa de Runas y los tres nodos hito del Grimorio

**Qué hay nuevo**

- **Mesa de Runas** (GDD 4.3 y 5.3; `sanctum/rune_table.gd`, `ui/runes/rune_screen.gd`, `core/rune_book.gd`,
  `spells/runes/`, datos en `data/runes/`): estación a unos 8 m del atril, sellada con cadenas hasta el Pilón al
  10 % (se desencadena con sonido y aviso). Las runas se aprenden y mejoran con maná (3 niveles) y se inscriben en
  ranuras limitadas: 1 al abrir y 2 más a la venta desde el Pilón al 25 %. Aprender una runa la inscribe sola si
  hay hueco. Las cinco piedras flotan en arco sobre la mesa y las inscritas bajan a su ranura.
  - **Multidisparo**: chispas doradas de más en abanico, cada una con su propia mira (revientan bichos).
  - **Rebote**: tras golpear el cristal salta a otra faceta (o a un bicho a 6,5 m), cada vez más pequeño.
  - **Perforación**: abre un túnel por detrás del impacto, con fragmentos que salen del agujero y una grieta.
  - **Eco**: a veces el hechizo se relanza gratis con una copia fantasma (reutiliza `SpellEchoes`).
  - **Cosecha**: algo menos de daño y más maná por fragmento (como la Pureza: sólo el maná, no el Pilón).
  - Valen enteras en los hechizos de una mano y a medias en los combinados que salen de las manos (Bola de
    Fuego, Choque Térmico y las lanzas); no en triples, cielo, haz, suelo ni familiares. Los glifos de las runas
    inscritas giran alrededor de cada llama. Sonidos en `tools/sfx_runes.py`.
- **Lanzamiento continuo** (Canalización, página Chispa; `player/auto_cast.gd`): mantén un botón 0,28 s y esa
  mano lanza sola cada vez que recarga. Tiembla, crepita y suena mientras la mantienes; pulsar la otra mano junta
  las dos como siempre. Al abrir un menú o perder el foco se suelta todo.
- **Vórtice** (Telequinesis, página Mago; `player/mana_vortex.gd`, `fx/hd/hd_vortex.gdshader`): un remolino
  alrededor del mago que aspira en espiral los fragmentos sueltos a 45 m y los manda a la tolva. No toca las
  Lágrimas del Núcleo ni lo que ya lleva un familiar.
- **Rompefacetas** (Resonancia, página Mago; `crystal/facet_breaker.gd`, `CrystalVolume.carve_facet`): los golpes
  resonantes parten una losa entera del cristal, que resbala, cae y revienta en fragmentos, con arcos dorados,
  destello, sacudida y hit-stop. Nunca baja del 99 %, no toca el Núcleo y en el Corazón sólo la arrancan los
  combinados, más pequeña.
- **Trofeos de los hitos** junto al templo (`sanctum/milestone_trophies.gd`): un pedestal animado por nodo
  comprado. Sonidos en `tools/sfx_milestones.py`.
- **Depuración**: fila RUNAS → DESBLOQUEAR TODAS; "comprar todo" también llena runas y ranuras. Demo `--runes[=]`,
  `--rune-table`, `--at-rune-table`, `--rune-unseal[=s]`, `--autofire[=s]`, `--autofire-join=s`,
  `--autofire-release=s`, `--vortex[=N]`, `--facet-crit`, `--facet-hit=D`.
- `tools/extract_strings.py` recoge también `_tr("...")` y `combo_note` de los recursos.
- Pruebas nuevas: `runes_smoke`, `milestones_smoke`.
- Simulador: normal 150,7 min (hueco máx. 173 s, maná sin gastar 3,3 %, Pilón al 100 %, todas las Lágrimas),
  eficiente 111,7 min. Hitos hacia los min 81 (Lanzamiento continuo), 121 (Rompefacetas) y 123 (Vórtice); runas
  desde el min ~51. La Cosecha alarga unos 10 min: sin ella había un hueco de 227 s.

## 2026-11-18 · Segunda tanda del GDD: Lágrimas del Núcleo, el final, el Báculo con triples, rangos y la Bola de Fuego nueva

**Qué hay nuevo**

- **Bola de Fuego en vuelo** (`spells/vfx/fireball_flight.gd`, `fx/hd/hd_fireball.gdshader`, `hd_fire_puff.gdshader`):
  cuerpo de fuego que hierve con borde rojo oscuro, lenguas que salen hacia las manos en pantalla, núcleo
  pequeño y caliente, cola de bocanadas que se enfrían, chispas y un hilo de humo; crece y se calienta con el
  nivel (`SpellHit.level`) y el Eco de Fuego va en magenta. Ilumina el cristal al acercarse (`FireGlow`,
  parámetros globales `fire_glow`). Sale del mismo tamaño que la bola entre las manos. El Meteoro suena con un
  solo estruendo y su roca y las bolas se crean en la pantalla de carga.
- **Lágrimas del Núcleo** (`core/tear_drops.gd`, `crystal/core_tears.gd`, `ui/tear_counter.gd`): segunda moneda.
  Sólo caen de combinados en el Corazón Cristalino (daño / 15000, con piedad a los 110 s de buen juego), laten
  como un corazón, se recogen con F o telequinesis (los familiares no) y van al contador junto al maná. Pagan la
  página nueva **Núcleo** del Grimorio: Ojo del Núcleo, Fractura del Corazón, Corazón Vidente y la **Gran
  Convergencia**, que sólo aparece al 99 %. Los iconos del Grimorio pasan a `ui/grimoire_icons.gd`.
- **El final** (`game/ending/`, GDD 9):
  - Al 99 % el cristal se resquebraja, se desprende a trozos y deja el **Núcleo** expuesto: una esfera violeta que
    no cede ("EL NÚCLEO NO CEDE"). Música tensa y el valle se tiñe. Ningún golpe baja del 99 %, y una red de
    seguridad expone el Núcleo si lo que queda del cristal ya no se puede golpear.
  - Con la Gran Convergencia, los cinco elementos acuden a las manos; mantener los dos botones mirando al Núcleo
    carga 5,5 s en cinco escalones (un anillo y una nota por elemento). Soltar antes se deshace sin coste.
  - El Núcleo estalla, el cristal se deshace en lluvia de fragmentos, el Pilón llega al 100 %, una columna de
    maná abre las nubes, auroras, fuegos artificiales, farolillos, campanas y coro; los bichos bailan.
  - **Pantalla final**: "Yes, you could." (en inglés en todos los idiomas; debajo "Sí, pudiste."), tiempo
    jugado, combinaciones, mejoras, fragmentos y hechizos; **Créditos**, **Seguir en el valle** y **Nueva
    partida**. Se guarda: al cargar vuelves al valle de fiesta sin cristal.
- **Báculo y combinaciones triples** (`player/wizard_staff.gd`, `spells/staff_combos.gd`, `spell_delivery.gd`,
  `elemental_storm.gd`, `supernova.gd`): el hito **Báculo** (Elementos, con la Tierra y el Pilón al 10 %; ~min 68)
  da un báculo en primera persona con una gema; **R o la rueda** cambian su elemento. Juntar las manos con la gema
  encendida lanza una triple: **Tormenta Elemental** (Chispa+Escarcha+Rayo, nube que descarga rayos, granizo y
  fuego), **Supernova**, **Glaciar Tronante**, **Lluvia de Estrellas** y **Erupción**, cada una con su
  descubrimiento, entrada del Libro (pestañas PAREJAS / TRIPLES), efectos y sonidos. Página **Báculo** en el
  Grimorio con Gema viva y Foco. Las triples revientan bichos.
- **Rangos de mago** (`core/wizard_ranks.gd`, `data/ranks/`, `ui/rank/`): Aprendiz, Iniciado, Hechicero, Magus,
  Archimago y Leyenda, por progreso (elemento despertado + Pilón). Ceremonia con escudo, "¡ERES X!", coro,
  columna de luz y golpe de cámara; las manos cambian de gema, ribete y runas; la música suma una capa por rango;
  escudo del rango bajo la barra del Pilón. Romper el Núcleo te hace **Leyenda** con su ceremonia en plena fiesta.
- **Espejo del Archimago** (`sanctum/archmage_mirror.gd`, `ui/rank/mirror_screen.gd`) junto al Santuario: F abre
  las cifras (tiempo, rango y siguiente requisito, combinaciones, mejoras, hechizos, fragmentos, maná, mejor
  racha, resonantes, geodas, venas, bichos reventados, capa, cristal). Son las mismas cifras que la pantalla final
  (`Progression.stats`).
- **Depuración**: filas FINAL ("IR AL NÚCLEO (99 %)", "LANZAR GRAN CONVERGENCIA") y "SUBIR DE RANGO"; demo
  `--tears=N`, `--destroyed=`, `--core-exposed`, `--ending[=s]`, `--ending-screen`, `--complete`, `--rank=N`,
  `--rank-up=N`, `--mirror`, `--stats`.
- Pruebas nuevas: `fireball_flight_smoke`, `core_tears_smoke`, `ending_smoke`, `staff_smoke`, `ranks_smoke`.
- Simulador: normal ~141 min (hueco máx. 171 s, maná sin gastar < 2 %, Pilón al 100 %), eficiente ~105 min; todas
  las Lágrimas necesarias llegan antes del final; rangos en 5,9 / 20,4 / 48,2 / 89,1 / 138,6 min.

## 2026-11-18 · Bichos del valle: monstruitos de ojos saltones que revientan con los hechizos

**Qué hay nuevo** (pedido del equipo: "monstruos graciosos con caras chistosas y ojitos grandes")

- **Cinco especies** (`game/critters/`, datos en `data/critters/*.tres`): Gelatín (bola de gelatina), Dientón
  (zanahoria con dientes de conejo), Pelusín (pompón con patitas), Babosín (babosa con ojos en antenas) y Cíclope
  saltarín. Mallas procedurales con su propio shader toon (tinte y destello por instancia, contorno), ojos con
  pupila en un muelle amortiguado que te miran y parpadean, respiración con squash & stretch, cada uno con su forma
  de moverse y gestos (lengua y ojos bizcos, estornudo, bostezo, bailecito). No atacan nunca: si te acercas a 4 m o
  cae un hechizo a 7 m chillan, saltan con los ojos desorbitados y huyen un poco.
- **Aparición** (`CritterZones`, mismas reglas que el pasto): salen del suelo con un "boing" sólo en zonas verdes,
  nunca en caminos, edificios ni junto al cristal. De 7 a 12 a la vez según el Pilón (Pelusín, Babosín y Cíclope se
  desbloquean al 5, 20 y 40 %), cerca del mago; los lejanos y fuera de cámara se esconden para reaparecer cerca.
- **Golpes**: capa de colisión propia (`Critter.LAYER = 1 << 4`) que sólo ven la mira y el Haz de Plasma. Un
  hechizo suelto revienta al que toca; los de área (Bola de Fuego, Meteoro, Terremoto) revientan a todos en su radio
  y en cadena; el Rayo salta de bicho en bicho, también desde un golpe al cristal. Un bicho detrás del cristal no
  roba el golpe; los familiares y el rayo del Pilón no los tocan. La chispa sin daño del tutorial sólo les da un
  coscorrón ("NI COSQUILLAS LE HACES").
- **Reventones** (`CritterGore`): se inflan, ojos fuera, chillido y destello; luego pegotes con brillo húmedo,
  manchas que se secan en ~22 s, gotitas, un diente o huesito, y los dos ojos salen rebotando y se quedan
  mirándote. Sube un alma traslúcida con ojos en X y aureola. Por elemento: Escarcha congela y hace añicos, Rayo
  muestra el esqueleto, Tierra los deja de panqueque, Fuego tostados con humo, Arcano rosa con dos ecos. Avisos
  "¡DOBLE BICHO!", "¡TRIPLE BICHO!", "¡MASACRE DE BICHOS! ×N". Sonidos de `tools/sfx_critters.py`. Todo en pools.
- **Opción "SANGRE DE CARICATURA"** (Accesibilidad, activada): apagada, revientan en confeti, estrellas y nube.
- **Recompensa**: 2-3 astillas por bicho (no mueve el balance) y la estadística `Progression.critters_popped`.
- **Depuración**: botón "BICHOS: APARECER 5" en Alt+F1; en la demo `--critters=N`, `--critter-*`, `--gore-off`.
- Prueba nueva `tests/smoke/critters_smoke.gd` (por el camino real de la mira y los proyectiles).

## 2026-11-18 · Menú de depuración, opciones completas, un tutorial que guía y el balance final

**Qué hay nuevo** (lo que pidió el equipo al probar)

- **Menú de depuración** (`ui/debug_menu.gd`, **Alt+F1**; en builds de debug o con `--debug-menu`): el botón
  ★ **COMPRAR TODO Y HECHIZOS AL MÁXIMO** (compra cada mejora al máximo con sus efectos, descubre todas las
  combinaciones y pone los hechizos a nivel 10 durante la sesión), maná (+100 / +1K / +100K / +1M), llenar y
  vaciar la bolsa, nivel de los hechizos 1-10 o AUTO, Pilón al 25/50/75/99 %, siguiente capa, revelar geoda,
  hora (+3 h, día, noche), velocidad x1/x2/x5, FPS, modo dios, teletransportes (Santuario, Pilón, Cristal),
  guardar y reiniciar (dos pulsaciones). Arriba, FPS, maná, Pilón, capa, fragmentos y bolsa en vivo. Se quita el
  texto "DEBUG 1-5…" de abajo a la izquierda; las teclas viejas siguen en silencio.
- **Opciones** (`ui/options_menu.gd`, en el título y en Esc): pestañas **Vídeo** (campo de visión 60-110 en vivo,
  también en pausa; pantalla completa, VSync, límite de FPS, FPS), **Audio**, **Controles** (sensibilidad,
  invertir Y, teclas) y **Accesibilidad** (sacudida, reducir destellos, mantener para cargar, números de daño),
  con SÍ/NO junto a cada interruptor y **Restaurar valores**. Un aviso "ESC: MENÚ Y OPCIONES" sale hasta que se
  abre el menú. Las llamas de las manos y la capa de magia siguen al FOV.
- **Tutorial que guía** (`core/guidance.gd`, `ui/objective_guide.gd`, `data/ui/guidance.tres`):
  - "[F] RECOGER" sale entero las 4 primeras veces, luego sólo una tecla pequeña y a las 20 desaparece (igual en la
    trituradora, la palanca, el Grimorio y "bolsa llena"); lo aprendido se guarda (`Progression.learned`).
  - Un rombo que gira sobre el objetivo, con la distancia, y una flecha en el borde si no se ve; en lo urgente,
    estela de chispas por el suelo y columna de luz. Lleva al cristal (si no se ve), al pedacito más cercano, a la
    trituradora con la bolsa llena o a la palanca olvidada (no si hay familiares recolectores), y al Santuario con
    una mejora asequible que no has visto (las vistas se guardan, `Progression.seen_upgrades`). Sustituye a los
    marcadores sueltos de la trituradora y de "¡MEJORA!".
- **Balance final** (`tools/balance_sim.py`, propuesta "ritmo" con lo mejor de las otras tres, elegida por dos
  jueces):
  - Jugador normal **~142 min**, eficiente ~105. Ningún hueco de más de 3 min sin poder comprar (máximo 169 s), 0,6 %
    del maná sin gastar y el Pilón lleno con el cristal al 95 %.
  - Desbloqueos (normal): Escarcha 6 min, Envío directo 11, familiar 14, Rayo 25, Tierra 45, Pureza 61, Resonancia
    del Pilón 62, Arcano 87.
  - Épocas: Bola de Fuego 0-25 min, Lanza Cargada 26-56, Meteoro 57-88, Eco de Fuego 89-107 y Resonancia Arcana al
    final; ninguna vuelve atrás.
  - Cambios de reglas: la Bola de Fuego se enfría en 2,5 s; Tierra y Arcano sueltos son lentos y pesados (su fuerza
    está en las combinaciones); Pureza con 12 niveles de +8 %, más niveles de Canalización, Resonancia,
    Telequinesis y Resonancia del Pilón; el familiar lleva como mucho 6; las venas sueltan menos Resonantes.
  - La primera mejora sigue a los ~67 s (la fija el tutorial: Chispa 0 y Potencia 1 a 5).

**Pruebas**: nuevas `debug_menu_smoke` y `settings_smoke`; `tutorial_smoke` comprueba la regla de la F y cada
objetivo de la guía. Todas en verde.

## 2026-11-18 · Texto que se lee, fuego con color y un día que empieza de día

**Qué hay nuevo** (revisión de lo anterior y lo que pidió el equipo)

- **Fuente nueva**: Fusion Pixel 10 y 12 px (con minúsculas, tildes, ñ, ¡ y ¿) en todo el HUD, el tutorial, el
  Grimorio, el Libro, los menús y la pantalla de carga, a través de `UiFonts`. Cada píxel de la letra cae en un
  píxel del juego; las mayúsculas pasan de 5 a 7-9 px. Las barras y el interruptor de Opciones se dibujan en
  píxeles.
- **Fuego**: 5 capas saturadas (borde rojo oscuro, rojo, naranja, amarillo y núcleo blanco pequeño) en vez del
  interior color crema. El anillo de choque de los impactos ya no funde la pantalla a blanco (`hd_ring` `cover`).
- **Carga por etapas**: el círculo del blanco de Meteoro, Trueno y Lluvia sale desde el principio de la carga;
  con pocas etapas los anillos se abren por fuera del orbe y la onda final queda contenida.
- **Día y noche**: el sol sale al amanecer de verdad (antes la partida empezaba con luz de luna bajo un cielo de
  día) y las cascadas de sombra están afinadas.

**Pruebas**: todas en verde.

## 2026-11-18 · Fuego nuevo, meteorito de verdad, carga por etapas y suelo sin rayas

**Qué hay nuevo** (lo que pidió el equipo al probar)

- **Fuego por capas** (`fx/hd/hd_fire.gdshader`): borde rojo oscuro, rojo, naranja y amarillo con un núcleo
  blanco pequeño (lo único que brilla). Ya no se corta en línea recta arriba (se apaga antes del borde del quad),
  las lenguas salen en la dirección del movimiento y el humo tiene volumen sin ser una mancha gris. Los halos de
  fuego tiñen el fondo en vez de quemarlo a blanco (`hd_glow` `cover`). La Bola de Fuego entre las manos va más
  baja y compacta y no tapa la mira; en vuelo sus llamas van hacia arriba.
- **Meteorito** (Chispa + Tierra): una roca que gira con grietas de lava (`MeteorRock`), cola de cometa, humo y
  gotas de lava; entra alto sobre el cristal y de lado (`SkyPath`, comprobando que no atraviesa el cristal),
  acelera al caer, destella en el cielo con un tintineo, silba y revienta con bola de fuego, onda, polvo,
  escombros, cráter que brilla y un estruendo grave (`tools/sfx_meteor.py`).
- **Carga por etapas** (`spells/charge_stages.gd`, `player/charge_feedback.gd`): al juntar las manos la carga va
  por escalones, un círculo mágico por escalón (`BalanceConfig.charge_stages_by_level`: 1 a nivel 2, 5 a nivel
  10). Cada escalón suena (campana de cristal más aguda cada vez; el último, un acorde de "máxima potencia"),
  destella, da un golpe de cámara con pulso de FOV, las manos retroceden y brillan y se enciende un rombo bajo la
  mira. El daño va por el último escalón completado; el tiempo de más de una carga larga sale de la recarga.
  Cancelar (pausa, Grimorio, Libro, perder el foco) no gasta la recarga.
- **Suelo sin rayas ni parpadeo**: las sombras del sol tenían "acné" con el sol alto (el suelo se sombreaba a sí
  mismo y, con la sacudida de cámara de cada hechizo, casi la mitad de sus píxeles cambiaban cada fotograma) y
  "pancaking" al amanecer (todo el valle negro). Arreglado con `shadow_reverse_cull_face` y sin pancake
  (`DayNight._setup_sun_shadows`).

**Pruebas**: nuevas `charge_stages_smoke` y `meteor_smoke`; laboratorio de fuego en `tests/vfx_gallery/fire_lab`.
Todas en verde.

## 2026-11-17 · Venas Resonantes, la rama del Pilón y un valle que celebra

**Qué hay nuevo** (GDD 6, 6.1, 4.2 y 7; oleada 1 del GDD)

- **Venas Resonantes**: en la capa de las venas cada lado del cristal es débil a un elemento (el mismo que pinta
  su color). Golpearlo con ese elemento, o con una combinación que lo lleve, hace **x2 de daño**, enciende la veta
  con chispas, rayos y una campana propia y suelta **Fragmentos Resonantes** (valen 125, como 5 grandes, y
  brillan con el color de su vena). Si fallas el elemento, te dice a cuál es débil.
- **Rama del Pilón**:
  - **Pureza**: cada fragmento entregado da x1,25 de maná por nivel.
  - **Resonancia del Pilón**: el Pilón se carga y dispara un rayo al cristal, más fuerte cuanto más lleno.
- **Hitos del Pilón** (10, 25, 50, 75 y 100 %): columna de luz, coro y campanas, una vez cada uno, y el valle
  cambia: auroras de maná de noche, faroles en la aldea, banderas en el castillo y campanarios que brillan.
- Ajustes al juntarlo con el balance nuevo:
  - Los Resonantes de una vena valen **la mitad del daño del golpe**. Si no llega a uno entero, sale uno con esa
    probabilidad. Antes eran siempre 2: una chispa de 20 de daño daba 250 de maná.
  - La Pureza sube **sólo el maná**. El Pilón suma el valor real de lo entregado, así que sigue yendo con el
    cristal.
  - Los golpes de los familiares y del rayo del Pilón no cuentan como del jugador (racha, cámara, mirilla,
    levitación, avisos).
  - Una geoda vuelve a soltar fragmentos grandes (con los tamaños nuevos iba a soltar 8 pedruscos de 500).
  - Las geodas pasan a `crystal/crystal_geodes.gd`.

**Pruebas**: nueva `tests/smoke/veins_pylon_smoke.gd` (venas, Pureza, hitos y rayo del Pilón). Todas en verde.

## 2026-11-17 · Familiares: buhitos que recogen, trituran y lanzan chispas

**Qué hay nuevo** (GDD 2.2, 4.3 y 7: "familiares que recogen, entregan o lanzan"; oleada 1 del GDD)

- **Jaula de Familiares** detrás del Pilón: una pajarera con perchas en espiral, cúpula dorada y un cristal que
  late; aparece con salto, estrellas y sonido al comprar el primer familiar.
- **Familiar recolector** (hasta 4): buhitos de luz que buscan fragmentos sueltos por todo el claro, cargan
  hasta 3 (uno más por nivel de **Alas ligeras**), los echan a la tolva y tiran de la palanca. Es el primer paso
  de la entrega automática del GDD.
- **Familiar hechicero** (hasta 2): revolotea a los lados de la mira, abre su círculo mágico y lanza chispas
  reales al cristal (no cuentan para la racha ni sacuden la cámara).
- Mejoras nuevas en la constelación del Mago: Familiar (1-4), Alas ligeras (3) y Familiar hechicero (2).
- Revisión: los últimos cristales de la tolva ya no se quedan para siempre, un familiar no se lleva un
  fragmento reciclado, el familiar comprado con el Grimorio abierto aparece al cerrarlo delante del mago y los
  búhos se leen bien contra el cristal.

**Pruebas**: nueva `tests/smoke/familiars_smoke.gd`.

## 2026-11-17 · Balance: el Pilón va con el cristal, piezas más grandes y cada elemento nuevo manda

**Qué hay nuevo** (pedido del equipo: "de ahí en adelante debes balancearlo para hacerlo divertido con buena
progresión, dopamina y gratificante")

- **Simulador de balance** (`tools/balance_sim.py`): juega la partida entera con los datos reales y dos jugadores
  (eficiente y normal) y dice cuánto dura, cómo va el Pilón, cada cuánto se compra algo y para qué se ahorraba.
  Antes del cambio: la Chispa sola a nivel 10 (960 de daño cada 0,1 s) rompía el cristal en 40 minutos, el
  Pilón se quedaba en el 47 % y había ratos de 5 minutos sin poder comprar nada.
- **Los fragmentos valen lo que arranca el golpe**: el maná que da el cristal es la esencia que pierde, así que
  el Pilón y el cristal avanzan juntos. Cuanto más fuerte el golpe, **más grandes las piezas**: Astilla (1),
  Fragmento (5), Fragmento grande (25) y dos nuevas, **Bloque de cristal (100)** y **Pedrusco de maná (500)**. Más
  daño también significa menos viajes, porque la bolsa cuenta piezas.
- **Curva de niveles nueva**: todos los elementos crecen igual por nivel (x1,38) con su propio tamaño (Chispa <
  Escarcha < Rayo < Tierra < Arcano). Al despertar un elemento empieza flojo, pero sus primeros niveles son
  baratos y en pocos minutos se pone por delante.
- **Cada combinación nueva supera a las viejas**: el daño de cada una va con lo que tarda (carga + enfriamiento)
  y sube con cada generación (fuego y hielo < rayo < tierra < arcano). El final lo mandan el Eco de Hielo, la
  Resonancia Arcana y el Terremoto, y ya no el Choque Térmico.
- **Precios** repartidos para que en la primera hora casi siempre haya algo que comprar en menos de un minuto;
  la bolsa empieza en 5 (luego 15, 40 y 100); tras el tutorial la Chispa hace 2 y juntar las manos, 11.
- El maná ya no se corta si el Pilón se llena antes que el cristal.

**Cómo queda (simulador)**: jugador normal, unos 110 min hasta el Núcleo con el Pilón al 97 %; eficiente, unos 80
min. Faltan por sumar los familiares y la rama del Pilón (oleada 1 del GDD), que alargarán la mitad de la partida
hacia las 2 a 3 horas del GDD.

**Pruebas**: `progression_smoke` comprueba que los fragmentos de un golpe valen su daño; `loop_smoke`,
`tutorial_smoke` y `progression_smoke` siguen la bolsa y los daños nuevos. Todas en verde.

## 2026-11-17 · El Arcano: el quinto elemento, sus ecos y la Gravedad

**Qué hay nuevo** (GDD 5.1 y 5.2, oleada 1 del GDD)

- **Arcano**, el quinto elemento: llama violeta y rosa con cometas que orbitan. Cada disparo deja **ecos
  fantasma** que vuelven a golpear el mismo punto (1 eco; 2 a nivel 3, 3 a nivel 6, 4 a nivel 9) y suben de
  tono, y da +6 % de golpe resonante. Se despierta en su constelación (tras la Tierra) y tiene su Potencia hasta
  nivel 10.
- **Cinco combinaciones nuevas**, todas en el Libro (B) con su acertijo:
  - **Eco de Fuego**, **Eco de Hielo** y **Eco del Trueno**: sale el hechizo y, tras él, sus copias fantasma
    brotan de círculos arcanos y vuelven a golpear donde mires.
  - **Gravedad** (Arcano + Tierra): un pozo que se traga en espiral todos los fragmentos sueltos del valle; a la
    bolsa si caben y, si no, a la tolva.
  - **Resonancia Arcana** (Arcano + Arcano): el cristal entero vibra y durante 5 s todo golpe es resonante.
- El HUD junta las recogidas seguidas en un solo número. Textos en español e inglés.
- Revisión: la Resonancia Arcana y los saltos del Rayo sólo sueltan fragmentos donde el cristal cede (antes
  salían del Núcleo sin excavar nada), los ecos resonantes ya no destellan toda la pantalla y los sellos del
  pozo de Gravedad ya no forman un disco blanco al abrirse. Captura: `docs/capturas/gravedad.png`.

**Pruebas**: nueva `tests/smoke/arcane_smoke.gd`; `combos_smoke` cubre ya los 5 elementos y las 15 parejas.

## 2026-11-17 · Tutorial exprés: empiezas siendo una deshonra de mago

**Qué hay nuevo** (pedido del equipo: "al inicio el tutorial muy rápido... que salga una chispa con un sonido muy
suave y se apague como si fueras una deshonra de mago... junta los hechizos y al juntarlos sigue siendo terrible
pero al menos le haces 1 punto de daño... con unos 5 ya puedes comprar la primera mejora que te hace hacer 2")

- **Tutorial en un panel arriba** (`ui/tutorial.gd`), que avanza con lo que pasa de verdad en el juego y empieza al
  abrir la puerta de la casucha. Lleva un ratón pixel art con el botón que toca parpadeando, o la tecla F:
  1. **Clic izquierdo**: sale una chispita temblorosa, suena muy flojito y se apaga contra el cristal con un
     "clink": 0 de daño.
  2. **Clic derecho**: la otra mano, igual de lamentable ("...NI UN RASGUÑO.").
  3. **Los dos clics a la vez**: la primera combinación sigue siendo terrible, pero hace **1 de daño** y suelta un
     pedacito ("¡1 DE DAÑO! ¡CAYÓ UN PEDACITO!").
  4. Recogerlo con F, 5. llevarlo a la trituradora, 6. juntar **5 de maná**, 7. inscribir en el Santuario la
     primera mejora, **Potencia**, con la que la magia ya hace **2 de daño** ("¡AHORA SÍ ERES UN MAGO! (CASI)").
- El paso del tutorial se guarda; las partidas que ya habían empezado no lo ven.
- **Primeros números**: la Chispa de nivel 1 hace 0 de daño (las combinaciones de dos manos sin daño hacen 1); la
  Potencia empieza en "Chispita" y cuesta 5; la primera Bolsa pasa a 12. Cada golpe da tanta esencia como daño
  hace, así que el primer golpe de 1 siempre suelta su pedacito.
- El panel se ajusta al ancho del texto en cada idioma; textos traducidos al inglés.

**Pruebas**: nueva `tests/smoke/tutorial_smoke.gd` (todo el recorrido: chispas sin daño, combinación de 1,
recoger, triturar, juntar 5 y comprar). `progression_smoke` y `loop_smoke` siguen los costes nuevos. Todas en
verde.

## 2026-11-17 · Rayo, Tierra y diez combinaciones para descubrir (Meteoro, Trueno...)

**Qué hay nuevo** (pedidos del equipo: "que las combinaciones sean entretenidas de descubrir", "un meteoro desde
arriba cargando fuego con tierra con círculos mágicos hacia abajo, tipo Megumin", "lo mismo con un trueno",
"que se vean espectaculares manteniendo la calidad")

- **Dos elementos nuevos del GDD**: **Rayo** (casi instantáneo; se ve el rayo de la mano al blanco y salta a
  otro punto del cristal) y **Tierra** (roca fundida, lenta y pesada; fragmentos un tamaño más grandes). Se
  despiertan en sus constelaciones (250 y 500 de maná, tras la Escarcha) y tienen su Potencia hasta nivel 10.
- **Una combinación por cada pareja** (diez), cada una con su manera de llegar al cristal:
  - **Meteoro** (Chispa + Tierra): al cargar se abren círculos mágicos encima del blanco, uno sobre otro por el
    camino de la caída; al soltar, una roca ardiendo cae del cielo atravesándolos y abre un cráter enorme (doble
    estallido, tormenta de rayos, fuego que queda).
  - **Juicio del Trueno** (Rayo + Rayo): círculos en el cielo y tres descargas seguidas que bajan del cielo al
    blanco; luego el rayo salta a cuatro puntos de alrededor.
  - **Lluvia de Estalactitas** (Tierra + Escarcha): un círculo en el cielo y 14 estalactitas que caen escalonadas
    sobre la zona.
  - **Lanza de Hielo** (Escarcha + Escarcha): perfora un túnel de 7 m y deja sus paredes congeladas.
  - **Lanza Cargada** (Escarcha + Rayo): perfora 11 m, con chispas que saltan por el túnel y fragmentos mayores.
  - **Haz de Plasma** (Chispa + Rayo): un haz continuo de 1,6 s que sigue la mirilla (se barre el cristal).
  - **Terremoto** (Tierra + Tierra): una onda corre por el suelo hasta la base del cristal y la revienta.
  - **Magnetismo** (Tierra + Rayo): utilidad; atrae a la bolsa los fragmentos de 45 m a la redonda.
  - Bola de Fuego y Choque Térmico, como antes.
- **Reacciones** que se descubren jugando: **Explosión de Vapor** (fuego sobre cristal congelado: +50 % y lluvia
  de fragmentos) y **Temple** (escarcha sobre cristal ardiendo: se parte en fragmentos grandes).
- **Libro de Combinaciones** (tecla **B**): las 12 entradas con sus iconos de elementos; lo descubierto con
  nombre, cómo se lanza y qué hace; lo que no, como "???" con un **acertijo** de pista ("El fuego solo vuela.
  Dale un cuerpo de piedra y caerá del cielo."); lo que pide un elemento dormido, con candado. Contador de
  descubiertas y aviso al despertar un elemento ("júntalo con los otros").
- El aviso de combinación nueva dice cuántas llevas ("3 / 12 · B LIBRO").
- Los círculos mágicos nunca son más finos que píxel y medio en pantalla (los grandes del cielo no se pierden).
- Datos generados con `tools/gen_spells.py` (aspectos, elementos y recetas) y sonidos con `tools/sfx_combos.py`
  (rayo, roca, trueno, meteoro cayendo y estallando, terremoto, magnetismo, lanza, plasma, cargas del cielo).
- `MotherCrystal` delega los efectos de las combinaciones en `CrystalCombos` y los túneles de demo en
  `CrystalDemo` (el archivo pasaba de 1.000 líneas).

**Capturas**: `docs/capturas/meteoro.gif`, `docs/capturas/meteoro_circulos.png`, `docs/capturas/trueno.gif`,
`docs/capturas/libro_combinaciones.png`, `docs/capturas/haz_plasma.png`, `docs/capturas/estalactitas.png`.

**Cómo se probó**: nuevo `combos_smoke` (cada pareja de elementos tiene una combinación; las reacciones no se
lanzan; las diez se lanzan de verdad contra el cristal, se descubren y quitan esencia) y el resto de tests en verde.

**Pendiente**: oscurecer el cielo mientras se cargan los hechizos del cielo; Arcano y las combinaciones triples
(Tormenta Elemental, Gran Convergencia); variantes por forma de lanzar (en el aire, sobrecarga).

## 2026-11-17 · Hechizos hasta nivel 10 y círculos mágicos

**Qué hay nuevo** (pedido del equipo: "que los hechizos lleguen a nivel 10 y que desde ahí, según el tipo, pasen
cosas; por ejemplo, a la Bola de Fuego que se carga le salen círculos mágicos cada vez más grandes, girando y con
runas, hacia donde la vas a lanzar")

- **Todos los hechizos llegan a nivel 10.** Chispa y Escarcha completan sus niveles a partir del último escrito
  (`ElementDef.ensure_levels`): cada nivel dobla el daño y es algo más rápido, grande y de más área; el color tira
  hacia el violeta arcano. Nombres nuevos (Corona solar, Llama arcana, Supernova, Fuego primigenio, Sol del mago;
  Glaciar ... Era glacial). Las Potencias de Chispa, Escarcha y Bola de Fuego suben a 9 niveles y el Choque Térmico
  estrena la suya (Choque profundo). Los niveles 6 a 10 cuestan 5.000 / 10.000 / 20.000 / 40.000 / 75.000.
- **Desde el nivel 6, efectos según el tipo de hechizo** (`spells/vfx/magic_circles.gd`, `fx/hd/hd_magic_circle.gdshader`):
  - **De carga** (Bola de Fuego, Choque Térmico): mientras cargas se abren `nivel - 5` círculos mágicos (hasta 5 a
    nivel 10) que aparecen uno a uno con la carga, dibujándose en barrido; se alinean desde las manos hacia donde
    apuntas, cada uno más grande, girando en sentidos alternos, con anillos, marcas, una banda de runas inventadas,
    un hexagrama y un sello. Al lanzar, destellan en blanco y se abren mientras el hechizo los cruza.
  - **De toque** (Chispa, Escarcha): cada disparo sale por círculos de runas que giran rápido en la mano (uno a
    nivel 6, dos a nivel 8, tres a nivel 10).
- Con mucha cadencia el cristal ya no encadena estallidos HD (como mucho uno cada 0,12 s salvo resonantes y
  combinados): a nivel alto la pantalla se quedaba en blanco.
- Demo: `--spell-level=N` pone todos los hechizos a nivel N.

**Capturas**: `docs/capturas/bola_de_fuego_nivel10.gif` (carga a nivel 10 y lanzamiento),
`docs/capturas/circulos_magicos.png`.

**Cómo se probó**: nuevo `spell_levels_smoke` (Chispa y Escarcha llegan a 10 con daño creciente, las Potencias a 10,
los círculos salen según nivel y carga, destellan y se apagan al lanzar, círculos de toque) y el resto en verde.

**Pendiente**: a nivel 5 o más, de cerca, la magia sigue siendo muy blanca (ya pasaba antes); toca una pasada de
brillo. Más efectos de nivel alto por tipo (p. ej. los combinados de mantener cuando existan).

## 2026-11-17 · Hechizos que crecen y levitación hasta la punta del cristal

**Qué hay nuevo** (pedidos del equipo: "que todos los hechizos tengan mejoras para hacerlos más grandes; en la mano
siempre el mismo tamaño, pero al salir deben crecer" y "sí" a poder llegar a la punta levitando)

- **Mejoras de Tamaño para cada hechizo**: Chispa enorme y Bola colosal (constelación de la Chispa), Granizo
  gigante y Choque descomunal (constelación de la Escarcha). Cuatro niveles: x1,35 / x1,75 / x2,2 / x2,8.
  - En la mano no cambian; al salir **crecen en el primer tercio del vuelo** hasta su tamaño (orbe, estela y luz).
  - Al llegar todo es más grande: estallido, onda, grieta, explosión en área, quemadura, zona helada o quebradiza
    y el cráter (más ancho), y sueltan más fragmentos (+60 % del aumento). El daño sube la mitad del aumento.
- **Levitación hasta 6 niveles**: 1,6 / 3 / 5 / 8 / 12 / 18 s de vuelo.
- **Impulso del cristal** (pide Levitación): cada golpe que llega al cristal mientras estás en el aire devuelve
  0,25 / 0,45 / 0,7 s de carga (la barra destella en dorado). Golpeando sin parar se sube hasta la punta.
- Iconos nuevos y textos en español e inglés.

**Capturas**: `docs/capturas/hechizo_grande.png` (Chispa a x2,8).

**Cómo se probó**: `movement_smoke` amplía con el Impulso del cristal (un golpe en el aire recarga) y una caída de
20 m sin daño; el resto de tests en verde. Render: Chispa a tamaño x2,8 en vuelo y estallando; páginas de la Chispa
y la Escarcha con las estrellas nuevas.

## 2026-11-17 · Mejoras de movimiento: doble salto y levitación

**Qué hay nuevo** (pedido del equipo: "mejoras de movimiento, doble salto y después levitar como un jetpack con
carga, sin daño por caída")

- **Doble salto** (constelación del Mago, 60 de maná): un segundo impulso en el aire, con estallido de chispas bajo
  los pies y un "fuuum" con dos notas que suben. De 1,5 m a ~3,5 m de altura.
- **Levitación** (pide el doble salto; 250 / 900 / 3.000 de maná): tras el doble salto, mantener ESPACIO sube
  flotando mientras dure la carga (1,6 / 3 / 5 s; con 3 s se pasan los 15 m). Chorro de magia bajo los pies, un
  zumbido encantado que se vuelve más agudo cuando queda poca carga y un "pff, pff" al agotarse. Se controla
  mejor el movimiento en el aire mientras levitas. La carga se recarga entera en ~1 s de suelo.
- **Barra de carga** bajo la mirilla (sólo mientras vuelas o recargas): cian, rosa al final y parpadea cuando se
  acaba.
- **Sin daño por caída**: caer de cualquier altura sólo da el golpe de cámara y el sonido de aterrizar.
- Iconos nuevos en el Grimorio, textos en español e inglés y sonidos con `tools/sfx_move.py`. Demo: `--up=id:nivel`
  (mejoras ya compradas) y `--fly=s` (salta, doble salto y levita).

**Cómo se probó**: nuevo `movement_smoke` (sin mejoras un solo salto; con doble salto se sube más; levitando se
sigue subiendo y se gasta la carga; en el suelo se recarga; se aterriza sin problema) y el resto de tests: OK.
Render: vuelo sobre el valle con la barra y el chorro (`docs/capturas/levitacion.png`); página del Mago con las
dos estrellas nuevas.

## 2026-11-17 · Un cristal aún más grande y se empieza dentro de la casucha

**Qué hay nuevo** (pedidos del equipo: "el cristal debe ser más grande aún" y "partir dentro de una casucha mágica
para que al abrir la puerta veas el cristal, no antes")

- **Cristal de 108 m** (antes 63): la misma forma a escala 1,7, con una base de ~75 m que se apoya en el suelo
  (ya no hay cristal enterrado que contara esencia sin poder excavarse). Celdas de 0,8 m; 40 geodas; capas más
  gruesas (Manto desde 2,2 m, Venas desde 6 m, Corazón desde 10,5 m) y Núcleo más grande. Con tanto volumen,
  cada golpe arranca más: la primera chispa ya deja una muesca de ~1 m.
- **Valle más grande**: claro de 100 m de radio, Pilón y Santuario a ~70 m del centro, bosque y aldea más lejos,
  niebla y sombras hasta más distancia.
- **La casucha del aprendiz**: se empieza dentro, mirando a la puerta. Cama, mesa con el libro abierto y una vela,
  estante de pociones y libros, caldero verde que borbotea, chimenea encendida, alfombra, escoba y cristalitos
  colgando; fuego y velas que parpadean, chisporroteo y burbujas de fondo y la música amortiguada, "desde dentro".
  Sin ventanas hacia el cristal: el HUD tampoco enseña aún la esencia ni el Pilón.
- **La revelación**: junto a la puerta, "[F] ABRIR LA PUERTA". Pestillo, crujido de bisagra, ráfaga de viento, la
  puerta se abre hacia fuera, la música se abre y suena un acorde de cristal que crece: aparece el Cristal Madre
  ("EL CRISTAL MADRE"). La puerta queda abierta en la partida guardada.
- Sonidos nuevos con `tools/sfx_hut.py`. Demo: `--hut` (empezar dentro), `--open-door=s`.

**Capturas**: `docs/capturas/casucha.png`, `docs/capturas/puerta_abierta.png`, `docs/capturas/casucha_fuera.png`,
`docs/capturas/cristal_gigante.png`.

**Cómo se probó**: todos los tests (incluido `crystal_volume_smoke` con el volumen nuevo, 3,7 M de puntos) en verde;
`gdlint` y `gdformat` limpios. Render: dentro de la casucha, la puerta abriéndose, la casucha por fuera y el
cristal desde la puerta.

**Pendiente**: animar el momento de la revelación con la cámara (ahora es la puerta, el sonido y el aviso); la casucha
aún no tiene usos (dormir para pasar la noche, guardar objetos...).

## 2026-11-17 · El Cristal Madre se rompe de verdad y se entra en él por capas

**Qué hay nuevo** (pedido del equipo: "destruible de verdad de a poco, y que las capas sean entrar en el cristal")

- **El cristal es un volumen que se excava.** Cada golpe arranca un trozo del tamaño de su daño: la chispita
  inicial hace una muesca; los hechizos fuertes, cráteres. La malla se rehace al momento por trozos (en otros
  hilos, sin tirones) y la colisión también: **se puede entrar caminando** en lo excavado.
- **Mucho más grande y con otra forma**: un racimo de 63 m (punta principal hexagonal, 8 puntas secundarias,
  racimos al pie y un zócalo ancho que se puede excavar a pie de suelo). Por fuera, placas de cristal, estrías y
  escarcha que centellea. El claro se ha abierto: Pilón y Santuario a ~50 m, el bosque más lejos.
- **Las capas están dentro, por profundidad**: Corteza (los primeros 1,6 m), Manto Geódico (motas de amatista),
  Venas Resonantes (vetas que brillan con el color de cada elemento según el lado), Corazón Cristalino (blanco
  y luminoso) y el Núcleo violeta en la base. Lo excavado se ve "por dentro": más oscuro, centelleante y las capas
  hondas brillan solas. "NUEVA CAPA" la primera vez que llegas a cada una; el HUD dice en qué capa golpeas.
- **Reglas por capa (GDD 6)**: el Corazón sólo cede ante combinaciones (Bola de Fuego, Choque Térmico) y el Núcleo
  no cede todavía; el golpe rebota con un "clonk" y un aviso.
- **Geodas de verdad**: 26 bolsas huecas tapizadas de amatista escondidas en el Manto. Al excavar hasta una se
  abre ("¡UNA GEODA!") y se ve la geoda brillando dentro; un golpe la revienta en 8 fragmentos grandes.
- **La esencia es el cristal que queda**: cada capa tiene su densidad (más dura cuanto más dentro) para que el
  1.000.000 se reparta como en el GDD (Corteza 10 %, Manto 35 %, Venas 35 %, Corazón 19 %, Núcleo 1 %).
- Los fragmentos salen con el color de la capa de la que vienen. El fuego que queda ardiendo también excava.
- Los destellos de la magia ya no se ven a través de las paredes del cristal.
- La excavación se guarda y se recupera con la partida. Demo: `--layer=N`, `--geode`, `--dig=N`.

**Capturas**: `docs/capturas/cristal_gigante.png`, `docs/capturas/tunel_capas.png` (túnel por Manto y Venas hasta
el Corazón), `docs/capturas/geoda_abierta.png`.

**Cómo se probó**

- Tests: los de siempre y el nuevo `crystal_volume_smoke` (reparte 1.000.000 entre capas, se excava y quita
  esencia, la prueba en seco no toca nada, el Núcleo no cede, malla por trozos, guardar y cargar): OK.
  `gdlint` y `gdformat` limpios.
- Golpes repetidos en un punto: cada uno quita ≈ su daño en esencia hasta llegar al Corazón, donde rebotan.
  Geoda: túnel, aviso, golpe y 8 fragmentos grandes. Coste de excavar: 0,2 ms (daño 1) a 2 ms (daño 150).
- Render: cristal desde el inicio, título, túnel por dentro, geoda abierta.

**Pendiente**

- Puntas que se caen enteras al cortarles la base (islas sueltas).
- Mecánica propia de las Venas Resonantes (cada vena, débil a su elemento).
- Golpes enormes del final (miles de daño) cuestan ~20 ms: pasar la excavación a un hilo.
- Ajustar el balance con el simulador: ahora se puede hacer un túnel hasta el Corazón con relativamente poco.

## 2026-11-17 · Español e inglés, título con humor y su propia música

**Qué hay nuevo**

- **Idiomas**: todo el juego en **español e inglés** (menús, HUD, Grimorio, mejoras, capas, avisos y frases del
  título). Se elige en *Opciones → Idioma* y cambia al momento; la primera vez se usa el idioma del sistema.
  **Añadir otro idioma es añadir una columna** a `game/localization/strings.csv`: el juego carga todos los que haya
  (ver `game/localization/README.md`). `tools/extract_strings.py` añade al CSV los textos nuevos del código.
- **Título gracioso**: "CAN YOU / DESTROY IT" con las letras ondulando y un brillo que las recorre, y un **"?" de
  cristal gigante** que flota y destella. Si le haces clic se queja ("¡EH!", "¡OYE, QUE DUELE!"...), se agrieta y al
  quinto golpe estalla en esquirlas y se convierte en "!" (luego se recompone). Debajo rotan frases con humor
  ("SPOILER: PROBABLEMENTE.", "RECOMENDADO POR 9 DE CADA 10 MAGOS SIN CEJAS."...).
- **Música del título**: un vals mágico a 3/4 (caja de música, arpa, flauta, coro y celesta, 40 s en bucle) cuya
  melodía se queda "colgada" como una pregunta. Al empezar a jugar se funde con la música del valle.
- Pruebas sin tocar las opciones: `-- --lang en`.

**Capturas**: `docs/capturas/titulo.png` (español), `docs/capturas/titulo_en.png` y `docs/capturas/grimorio_en.png`.

**Cómo se probó**

- Tests: `progression_smoke`, `combine_input_smoke`, `loop_smoke`, `grimoire_click_smoke`, `hit_stop_smoke`,
  `music_layers_smoke` y el nuevo `localization_smoke` (idiomas completos y con los mismos `%d`/`%s`): OK.
  `gdlint` y `gdformat` limpios.
- Cambio de idioma en vivo desde Opciones (menú, HUD y pistas pasan a inglés); render del título y del Grimorio en
  inglés.

**Pendiente**

- Revisión del inglés por un hablante nativo.

## 2026-11-17 · Pasada de calidad: título y pausa, capas del cristal, geodas y entrega más vistosa

**Qué hay nuevo**

- **Pantalla de título** sobre el valle vivo (logo, Continuar, Nueva partida, Opciones, Salir) y **pausa con Esc**
  (Reanudar, Opciones, Guardar y salir; congela el juego). **Opciones**: volumen general, música, efectos y
  ambiente, sensibilidad del ratón, sacudida de cámara y pantalla completa (se guardan en `settings.cfg`).
- **Entrega más lenta y vistosa** (pedido del equipo): cada cristal sale de las manos en abanico con su propio arco,
  altura y giro, cae en un punto distinto del borde de la tolva y resbala hacia dentro; ya no se apelotonan. Echar y
  triturar van más despacio; el montón de la tolva son agujas finas.
- **Sonidos que ya no se acoplan** (pedido del equipo): tintineos de la tolva, crujidos, gotas del Pilón y golpes al
  cristal con separación mínima, menos voces a la vez y menos volumen.
- **Capas del cristal** (GDD 6): Corteza, Manto Geódico, Venas Resonantes, Corazón Cristalino y Núcleo, con su
  paleta (también en los fragmentos), tono del golpe y transición (tormenta de rayos, retumbe, aviso "NUEVA CAPA").
  El HUD dice en qué capa estás.
- **Geodas** en el Manto Geódico: racimos violetas que laten en la superficie; un golpe cerca las revienta en ocho
  fragmentos grandes ("¡GEODA!") y reaparecen en otro sitio.
- **Mejoras nuevas del Mago**: Engranajes (trituradora más rápida) y Envío directo (lo recogido vuela solo a la
  tolva; pide Telequinesis).
- **Ritmo**: la bolsa empieza en 3 (10, 30, 100) para que, con el Pilón a 30 m, la primera mejora llegue en menos
  de 30 s. La luz del proyectil ya no tiñe el suelo junto al mago.
- Debug: L salta de capa; demo `--layer=N`.

**Capturas**: `docs/capturas/entrega_trituradora.gif`, `docs/capturas/titulo.png`, `docs/capturas/manto_geodico.png`.

**Cómo se probó**

- Tests: `progression_smoke`, `combine_input_smoke`, `loop_smoke` (bolsa de 3, tolva, palanca, salto; con y sin
  ventana), `grimoire_click_smoke`, `hit_stop_smoke`, `music_layers_smoke`: OK. `gdlint` y `gdformat` limpios.
- Render: título, entrega en abanico, trituración, capa Manto Geódico con geodas.

**Pendiente**

- Escuchar el conjunto de sonidos con oídos humanos y ajustar volúmenes finos.
- Venas Resonantes (débiles a un elemento) y Corazón Cristalino (sólo combinaciones) aún sin su mecánica propia.
- Simulador de balance (dev guidelines 8).

## 2026-11-17 · Trituradora para entregar, golpes al cristal variados y el cristal que reacciona

**Qué hay nuevo**

- **Entregar ya no es automático: trituradora** junto al Pilón (`pylon/crystal_crusher.gd`).
  - **Mantén F** junto a la tolva: los cristales salen de tus manos uno a uno, cada vez más deprisa (las manos se
    alternan lanzándolos), caen en la tolva con un tintineo que sube de nota y se amontonan tras su cristal.
  - **Toca F** para tirar de la palanca: la máquina arranca (motor que sube de vueltas), engranajes y rodillos
    girando, vibración, un crujido por cada cristal entre los rodillos con polvo y chispas, el maná viaja brillando
    por la tubería al Pilón (que sube con su gota y su nota) y la trituración acelera; termina con un resoplido de
    vapor por la chimenea y "¡N CRISTALES TRITURADOS!".
  - Sonidos nuevos: tolva, palanca con trinquete, arranque, bucle de maquinaria (motor, engranajes y cadena),
    cuatro crujidos y vapor.
- **Golpes al cristal más variados y menos molestos**: diez sonidos en tres timbres (cuenco, cristal y mazo) con
  ataque suave y cuerpo grave, sin repetir el anterior; más bajos; la racha sube de nota dentro de una octava y
  vuelve a empezar (antes acababa chillando).
- **El cristal reacciona** (capa HD, `fx/hd/crystal_arcs.gd`): rayos de energía cian y violeta que recorren la
  superficie desde cada impacto (más y más largos con la fuerza y la racha; dorados en los resonantes), destellos
  en estrella al golpear y titilando por todo el cristal, chisporroteo eléctrico suave. Cada cierto daño acumulado
  **"¡El cristal se resquebraja!"**: tormenta de rayos que trepa por todo el cristal, destello del corazón,
  retumbe grave, sacudida y una grieta grande que se queda.

**Capturas**: `docs/capturas/trituradora_y_rayos.gif`, `docs/capturas/trituradora.png`.

**Cómo se probó**

- `loop_smoke`: mantener F llena la tolva sin dar maná; la palanca tritura y da el maná (con y sin ventana).
  Resto de tests en verde; `gdlint` y `gdformat` limpios.
- Render fotograma a fotograma: echar cristales acelerando, palanca, trituración, rayos y resquebrajo.

**Pendiente**

- Escuchar los sonidos nuevos con oídos humanos (sobre todo el bucle de maquinaria y los golpes).
- Mejoras para la trituradora (más rápida, tolva más grande) y la telequinesis de entrega directa del GDD.

## 2026-11-17 · Escarcha y Q/E, Grimorio por elementos, día y noche, movimiento y más

**Qué hay nuevo**

- **Arreglo: comprar con clic.** El Grimorio medía 0x0 (anclas sin márgenes) y los clics se iban al mundo. Test
  nuevo `grimoire_click_smoke` (necesita ventana: `xvfb-run`).
- **Un elemento en cada mano (Q / E).** Segundo elemento, la **Escarcha** (3 niveles: Escarcha, Hielo, Ventisca),
  que se despierta en su constelación del Grimorio. Es lenta y **congela** la zona del cristal: los golpes de otros
  elementos allí hacen x2 durante 6 s (escarcha con vetas de hielo en el cristal, aviso "¡CONGELADO! x2").
  **Chispa + Escarcha = Choque Térmico** (combinación nueva por descubrir): deja la zona **quebradiza** y el
  siguiente golpe hace x3 (vapor, grietas al rojo, "¡QUEBRADIZO! x3"). Sin receta (Escarcha + Escarcha), pulsar
  las dos manos lanza ambas. El HUD muestra el elemento de cada mano.
- **Grimorio por elementos**: pestañas Mago, Chispa, Escarcha, Rayo, Tierra y Arcano (Q/E o clic). Mejora nueva
  **Bola de Fuego** (pide haberla descubierto).
- **Subir de nivel se nota**: cada nivel de la Chispa tiene su aspecto (Chispa, Chispa ardiente, Llama, Llama
  mágica, Fuego estelar) y al comprar Potencia las manos se transforman (destello, onda, chispas y acorde).
- **Bola de Fuego más "bola de fuego"**: las llamas se arrastran tras la trayectoria, deja humo y ruge en vuelo;
  quema el cristal (marcas al rojo que se enfrían a hollín) y deja fuego ardiendo que hace daño por quemadura.
- **Movimiento**: Shift corre, Espacio salta (con margen y salto recordado), cabeceo, caída al aterrizar, pasos.
- **Día y noche** (10 min por día): sol y luna, amanecer, atardecer y noche con estrellas; de noche faroles,
  Pilón y Santuario iluminan. **Sonido ambiente**: pájaros de día (coro al amanecer), grillos y búhos de noche,
  repartidos en 3D (`tools/sfx_ambience.py`). Mundo con más contraste (SSAO y ajustes de color).
- **Sin congelaciones**: pantalla de carga que precalienta shaders y partículas (todos los hechizos, impactos,
  quemaduras, entregas) antes de jugar.

**Capturas**: `docs/capturas/magia_hd_dia_noche.gif`, `docs/capturas/bola_de_fuego_noche.png`,
`docs/capturas/atardecer.png`, `docs/capturas/grimorio_elementos.png`.

**Cómo se probó**

- Tests: `progression_smoke` (requisito "recipe:"), `combine_input_smoke` (Q/E, Choque Térmico, sin receta),
  `loop_smoke` (salto), `grimoire_click_smoke` (clic en INSCRIBIR y en pestaña), `hit_stop_smoke`,
  `music_layers_smoke`: OK. `gdlint` y `gdformat` limpios.
- Render fotograma a fotograma: niveles de la Chispa, Bola de Fuego de noche, atardecer, Escarcha y Choque Térmico.

**Pendiente**

- La llama de Escarcha en la mano se lee poco contra el cielo azul; más contraste.
- Medir rendimiento en una GPU real (aquí sólo hay render por software).
- Equilibrar costes y daños (Escarcha, Choque Térmico, quemadura).

## 2026-11-17 · Magia HD (HD-2D), cristal más grande y valle con más detalle

**Qué hay nuevo**

- **Nuevo método para los hechizos: HD-2D.** El valle y las manos siguen en pixel art a 640x360, pero la magia se
  dibuja en una capa aparte a resolución nativa (`fx/hd/magic_layer.gd`) con resplandor HDR y se compone con alfa
  premultiplicado (no se lava sobre el cielo claro). Piezas nuevas en `fx/hd/`:
  - `hd_fire.gdshader`: bola de energía turbulenta (fbm a 60 fps) con lenguas de fuego, núcleo blanco ardiente y
    borde que se vuelve luz; estilo remolino para lo arcano.
  - `hd_glow.gdshader` (halo con rayos), `hd_ring.gdshader` (onda de choque), `hd_trail.gdshader` (estela suave).
  - `HdFx`: brasas suaves, chispas con estela (trails de GPUParticles) y humo.
  - `HdImpact`: destello con rayos, fuego que se hincha y se deshace, onda, chispas, brasas y humo.
  - `SpellOrb` reescrito en HD (misma API): halo, cuerpo de fuego, órbitas suaves, brasas, partículas que se
    arremolinan hacia la Bola de Fuego mientras carga, y estallido con chispas y onda.
- **Bola de Fuego mucho más grande** entre las manos; las manos se tiñen con su luz al cargar.
- **Cristal Madre a escala 2,3** (punta de ~57 m, 30 veces el mago, GDD 4.1). `WorldLayout` reúne las posiciones;
  **Pilón y Santuario más lejos** (~30 m del centro).
- **Valle con más detalle** (`world/valley_details.gd`): caminos de tierra con losas, faroles, hierba y flores,
  rocas, setas, tocones, cristales que brotan del suelo y motas de maná flotando.
- Proyecto: stretch `canvas_items` (antes `viewport`); el mundo vive en `WorldView/WorldViewport`.

**Capturas**: pendientes de grabar en un GIF; ver la sesión.

**Cómo se probó**

- Render Forward+ fotograma a fotograma: llamas en las manos, carga y vuelo de la Bola de Fuego, chispas de nivel
  2 y 5 e impactos; iteración de mezcla (aditivo → premultiplicado), resplandor y rampas de color.
- `progression_smoke`, `combine_input_smoke`, `loop_smoke`: OK. `gdlint` y `gdformat` limpios.

**Pendiente**

- Ciclo de día y noche con sonidos ambientales (pájaros, búhos, grillos), pedido por el equipo.
- Grimorio organizado por elemento (ramas por elemento) y mejora de la Bola de Fuego.
- Mundo menos "lavado": más contraste y profundidad (va con el día y la noche).
- Pulir más los hechizos: distorsión de calor, nivel 5 menos blanquecino, impactos de nivel 1 más legibles.

## 2026-11-17 · Bucle completo jugable y hechizos que resaltan

**Qué hay nuevo**

- **Hechizos que resaltan** (pedido del equipo). La chispa en vuelo ya no es un "+" blanco que se perdía contra el
  cielo: es la misma llama de la mano (`SpellOrb`) de cara a la cámara, con una **estela de fuego** en píxeles sólidos
  (`SpellTrail`), brasas y luz que tiñe el valle; al impactar **estalla** con un fogonazo pixel art
  (`fx/impact_blast.gdshader`) en los colores del hechizo. Cada nivel tiene su aspecto: **Chispa** (1-2), **Llama** (3)
  y **Llama mágica** rosa (4-5), también en las manos. El crepitar al lanzar suena más grave con el nivel y, al
  cargar la Bola de Fuego, las manos tiemblan y el mundo vibra.
- **Bucle completo (M1b)**: golpear → recoger con F → llevar al Pilón → maná → comprar en el Santuario → hechizos
  más fuertes.
  - **Bolsa** con tope (1 al empezar, GDD 8.1). Llena: el fragmento se queda en el suelo y el HUD avisa con sonido.
  - **Pilón de Maná**: columna de vidrio y bronce con el maná líquido subiendo (rosa, violeta, remolinos y burbujas),
    marcas al 10/25/50/75/100 % que se encienden, cristal flotante en la cima y zumbido que crece. Al acercarte, los
    fragmentos salen volando de tus manos con estela, caen dentro con una gota de maná (cada una una nota más alta)
    y la superficie se agita.
  - **Santuario**: templete de tejado azul cobalto con un atril y el Grimorio flotando sobre un orbe arcano. Con
    cada nivel comprado aparece un objeto nuevo con un destello (velas, estantería, bola de cristal, pociones...).
  - **Grimorio de Constelaciones**: libro que sube a pantalla con aleteo de páginas; las mejoras son estrellas que
    crecen con cada nivel y laten en oro si te llega el maná; la página de la derecha se escribe sola con qué hace,
    cómo está ahora y cómo quedará. Al inscribir: acorde mágico, estallido de estrellas y aviso grande
    ("¡CHISPA ARDIENTE!"). F junto al atril para comprar; Tab para consultarlo en cualquier sitio.
  - **5 mejoras** (`data/upgrades/`): Bolsa de aprendiz, Potencia, Canalización, Resonancia y Telequinesis.
  - **HUD**: barra del Pilón con marcas (porcentaje con decimales para que siempre se mueva), maná con número
    rodante, bolsa en casillas que late en oro al llenarse, avisos encadenados para la primera partida
    ("¡RECOGE LOS FRAGMENTOS CON [F]!", "¡LLÉVALOS AL PILÓN!", "¡MEJORA DISPONIBLE!") y marcadores en pantalla
    hacia el Pilón y el Santuario (en el borde con flecha si quedan fuera).
  - **Sonidos nuevos** (`tools/sfx_loop.py`, afinados en La mayor) y la **música** suma una capa cada 3 niveles.
- Debug: G da 100 de maná. Modo demo: `--no-cast`, `--mana=N`, `--bag=N`, `--warp=x,z`,
  `--grimoire [--buy --select=N]`; en modo demo no se carga ni se guarda la partida.

**Capturas**: `docs/capturas/bucle_completo.gif` (golpe, Bola de Fuego, entrega y compra),
`docs/capturas/chispa_cometa.png`, `docs/capturas/pilon_entrega.png`, `docs/capturas/grimorio_compra.png`.

**Cómo se probó**

- Render Forward+ (Vulkan por software) fotograma a fotograma: chispas de nivel 1 y 5, Bola de Fuego, entrega en el
  Pilón, compra en el Grimorio y cambio de llama.
- `loop_smoke` (nuevo): bolsa con tope y aviso, entrega junto al Pilón (y no lejos), compra sólo junto al atril y
  la Potencia sube el nivel de la Chispa. `progression_smoke` (bolsa, mejoras por nivel, bloqueos),
  `combine_input_smoke`, `hit_stop_smoke`, `music_layers_smoke` y galería de VFX: OK. `gdlint` y `gdformat` limpios.
- Rendimiento (modo demo con combos, `--report`): 126 draw calls (218 con la Chispa 5 a toda cadencia).

**Pendiente**

- Jugar los primeros 5 minutos con personas y ajustar el ritmo (costes y valores en `data/upgrades/`); falta el
  simulador de balance. Ojo: con la Potencia alta los fragmentos valen más que la esencia que quitan.
- Escuchar los sonidos nuevos con oídos humanos.
- Q / E para cambiar el elemento de cada mano y la Escarcha (M2).

## 2026-11-17 · Bola de Fuego: una llama en cada mano que se funden en una grande

Retoma lo que quedó a medias: los sonidos de la Bola de Fuego estaban en la rama `claude/keen-lovelace-7haa9v` sin
integrar ni usar (ver su entrada más abajo). Se integran y se implementa la combinación del GDD 5.2.

**Qué hay nuevo**

- **Una llama en cada mano.** Cada mano lleva su elemento (Chispa) como una llamita (`SpellOrb` con
  `data/spells/vfx_fire_spark.tres`) sobre la punta de los dedos, y recarga por separado. Clic izquierdo lanza la
  izquierda y clic derecho la derecha; la chispa sale de su llama, que estalla y se vuelve a encender al recargar.
- **Combinar (GDD 5.2 y 10.1).** Los dos clics a la vez juntan las manos: las dos llamas viajan al centro, se
  encogen y se funden en la **Bola de Fuego** (`data/spells/vfx_fireball.tres`), que crece mientras se mantiene
  (0,7 s a carga completa, con el rugido en bucle subiendo de tono). Al soltar sale volando como orbe de fuego
  (el mismo orbe, sin saltos de tamaño) y estalla contra el cristal: explosión en área con 3 golpes secundarios
  (grietas, destellos, partículas naranjas y astillas), sonido de explosión, hit-stop y sacudida.
- **Combinación descubierta (GDD 10).** La primera vez: pausa breve, "¡COMBINACIÓN NUEVA! BOLA DE FUEGO" en grande
  y fanfarria. Queda registrada en `Progression.discovered_recipes` y en el guardado.
- **Todo en datos**: `SpellRecipe` (`data/spells/recipe_fireball.tres`) lleva daño, área, carga, enfriamiento,
  orbe, proyectil y sonidos; `ElementDef.hand_visual` la llama de cada elemento; `SpellTier.impact_tint` el color
  del impacto; `SpellVisualDef.sparkle_rise` hace que los destellos suban como brasas;
  `BalanceConfig.combine_window_sec` (0,09 s) el margen para pulsar "a la vez".
- Para no perder la combinación, con las dos manos listas un clic suelto espera esa ventana, o sale en el acto al
  soltar el botón (un clic normal dura menos).
- Modo demo: `-- --autoplay --combo [--hold=s]` lanza Bolas de Fuego; `--delay=s` espera antes de empezar.

**Capturas**: `docs/capturas/bola_de_fuego_combinacion.gif`, `docs/capturas/bola_de_fuego_combinacion.png`.

**Cómo se probó**

- Godot 4.7 (Forward+, Vulkan por software): render frame a frame de disparos sueltos y de combinaciones; las
  llamas se ven en cada mano, se funden en el centro y la bola sale sin saltos.
- `combine_input_smoke` (nuevo): clic a la vez = combinación con un solo lanzamiento y un solo descubrimiento,
  clic suelto = una mano, clic corto sale en el acto, sin las dos manos listas no se combina. OK.
- `progression_smoke` (recetas, descubrimientos y su guardado), `hit_stop_smoke`, `music_layers_smoke`: OK.
- Galería de VFX y modo demo sin errores de script. `gdlint` y `gdformat --check` limpios.
- Rendimiento (modo demo con combos, `--report`): 85 draw calls, 6 fragmentos en movimiento.

**Pendiente**

- Balance de la Bola de Fuego (valores en el `.tres`) cuando haya entrega de fragmentos y maná (M1b).
- Cambiar el elemento de cada mano con Q / E y la página del Grimorio que se escribe sola al descubrir (M2).
- Escuchar con oídos humanos los sonidos de la Bola de Fuego en el juego.

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
