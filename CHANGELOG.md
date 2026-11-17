# Changelog

Cada push a `main` se documenta aquí, el más reciente arriba (ver `.agents/dev_guidelines.md`, sección 12).

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
