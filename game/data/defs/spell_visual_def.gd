class_name SpellVisualDef
extends Resource
## Aspecto de un hechizo como pila de capas (núcleo, cintas, destellos y luz).
## Todos los valores visuales viven aquí para que cada elemento, combinación y nivel
## sea sólo datos (dev guidelines 4.2 y 5.3). Lo usa `SpellOrb`.

@export_group("Núcleo")
## Rampa de color del centro hacia fuera, de "caliente" a "frío". Interpolación constante
## para que salga en bandas duras; colores > 1 son HDR y activan el glow del entorno.
## El alfa < 1 en las bandas exteriores se trama (dithering) en vez de mezclarse.
@export var core_ramp: Gradient
## Radio del quad del núcleo, halo incluido (m).
@export var core_radius: float = 0.09
## Brazos de la espiral del núcleo.
@export var core_arms: float = 3.0
## Cuánto se retuercen los brazos hacia fuera.
@export var core_twist: float = 7.0
## Vueltas por segundo de la espiral.
@export var core_spin: float = 0.35
## Cuánto deforman los brazos el radio de las bandas (0 = círculos).
@export var core_swirl: float = 0.12
## Largo de los rayos en cruz del destello central (fracción del radio).
@export var flare_length: float = 0.5
@export var flare_color: Color = Color(1.8, 1.8, 2.0, 1.0)

@export_group("Cintas")
## Un color por cinta (se reparten en orden). La cabeza de cada cinta es blanca.
@export var ribbon_colors: PackedColorArray = PackedColorArray()
@export var ribbon_count: int = 5
@export var ribbon_radius_min: float = 0.07
@export var ribbon_radius_max: float = 0.16
## Grosor de la cinta (m). A 0,5 m de la cámara, 0,002 m ≈ 1 píxel a 640x360.
@export var ribbon_width: float = 0.0045
## Vueltas por segundo de los cometas sobre su órbita.
@export var ribbon_speed: float = 0.55
## Fracción de cada tramo que ocupa la cola del cometa.
@export var ribbon_tail: float = 0.42
## Cometas por órbita.
@export var ribbon_dashes: int = 2
## Inclinación máxima de las órbitas respecto al plano de la cámara (grados).
@export var ribbon_tilt_max_deg: float = 75.0
## Multiplicador HDR de las cintas.
@export var ribbon_hdr: float = 1.6
## Grados por segundo que precesionan las órbitas.
@export var precession_deg: float = 25.0

@export_group("Destellos")
@export var sparkle_amount: int = 26
## Se elige un color al azar de este degradado (interpolación constante).
@export var sparkle_colors: Gradient
## Radio de la cáscara donde nacen los destellos (m).
@export var sparkle_radius: float = 0.15
@export var sparkle_lifetime: float = 0.9
## Tamaño de un texel de la textura en el mundo (m): 1 texel ≈ 1 píxel a la distancia de las manos.
@export var sparkle_texel: float = 0.0019
## Aceleración vertical de los destellos (m/s²): > 0 suben como brasas de fuego.
@export var sparkle_rise: float = 0.0
@export var burst_amount: int = 40
@export var burst_speed: float = 1.2

@export_group("Luz")
@export var light_color: Color = Color("#c79bff")
@export var light_energy: float = 1.6
@export var light_range: float = 0.7

@export_group("Animación")
## Fotogramas por segundo de toda la animación: escalonada, como pixel art dibujado a mano.
@export var anim_fps: float = 12.0
## Escala del orbe sin carga (con carga completa es 1).
@export var charge_min_scale: float = 0.45
## Multiplicador de velocidad de giro con carga completa.
@export var charge_spin_boost: float = 2.2
## Duración del estallido al soltar (s).
@export var release_time: float = 0.32
## Escala que alcanzan las órbitas al estallar.
@export var release_ring_scale: float = 2.2
## Semilla para inclinaciones y fases (dos orbes con la misma semilla son idénticos).
@export var seed: int = 7

@export_group("HD")
## 0 = fuego (lenguas que suben), 1 = arcano (remolino).
@export_enum("Fuego", "Arcano") var style: int = 0
## Brillo del cuerpo (HDR: > 1 florece con el resplandor).
@export var body_intensity: float = 2.2
## Tamaño del cuerpo respecto a `core_radius`.
@export var body_scale: float = 1.5
## Tamaño del halo respecto a `core_radius` y su brillo.
@export var glow_scale: float = 5.0
@export var glow_intensity: float = 0.9
## Rayos de luz en el halo (0 = sin rayos).
@export var glow_rays: float = 0.4
## Partículas que se arremolinan hacia el centro mientras carga (0 = ninguna).
@export var converge_amount: int = 0
## Chispas con estela al estallar.
@export var spark_amount: int = 40
## Fuerza del destello al soltar (1 = normal). Las llamas de la mano, que estallan pegadas a la
## cámara, lo llevan bajo.
@export var release_flash: float = 1.0
## Meteoro: en vuelo lleva una roca fundida con grietas que brillan dentro del fuego, cola de
## cometa y humo, cae acelerando desde lo alto y estalla con onda de choque, polvo, cascotes y
## cráter encendido (ver `MeteorRock`).
@export var meteor: bool = false
