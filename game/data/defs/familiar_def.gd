class_name FamiliarDef
extends Resource
## Un tipo de familiar (GDD 4.3 y 7: "familiares que recogen, entregan o lanzan"). Todo número
## de diseño de su comportamiento y de su aspecto vive aquí (`data/familiars/*.tres`).

enum Role { COLLECTOR, CASTER }

@export var id: StringName
@export var display_name: String
@export var role: Role = Role.COLLECTOR
## Estadística de mejora que dice cuántos familiares de este tipo hay.
@export var count_stat: StringName
## Máximo de familiares de este tipo (tamaño del pool).
@export var max_count: int = 4

@export_group("Vuelo")
## Velocidad de crucero (m/s) sin mejoras; la mejora de alas la multiplica.
@export var fly_speed: float = 7.0
## Altura extra del arco de vuelo por cada metro recorrido.
@export var arc_per_meter: float = 0.22
## Altura mínima del arco en los viajes (m).
@export var cruise_height: float = 2.5
## Aleteos por segundo en vuelo.
@export var flap_rate: float = 7.0

@export_group("Recolector")
## Fragmentos que carga por viaje (más uno por nivel de alas, hasta Familiar.MAX_CARRY).
@export var carry: int = 3
## Sólo busca fragmentos a esta distancia de la tolva (m): el claro entero.
@export var search_radius: float = 120.0
## Tras coger uno, busca otro cerca de él (m) si aún le cabe.
@export var chain_radius: float = 12.0
## Segundos sobre el fragmento al cogerlo.
@export var grab_sec: float = 0.3
## Segundos entre cristal y cristal al soltarlos en la tolva.
@export var drop_gap_sec: float = 0.16
## Con al menos estos cristales en la tolva (y la trituradora parada), tira de la palanca.
@export var lever_at: int = 6
## Descanso en la jaula entre búsquedas sin éxito (s).
@export var rest_sec: float = 1.2

@export_group("Hechicero")
## Segundos entre hechizos (sin contar la carga del círculo).
@export var cast_interval: float = 3.2
## Segundos con el círculo mágico abierto antes de lanzar.
@export var cast_charge_sec: float = 0.9
## Nivel de la Chispa que lanza respecto al del mago (0 = el mismo; -1 = uno menos).
@export var tier_offset: int = -1
## Multiplicador del daño del hechizo (al menos 1).
@export var damage_mult: float = 0.6
## Órbita: distancia a la superficie del cristal, radio de la vuelta y altura (m).
@export var orbit_out: float = 7.0
@export var orbit_radius: float = 2.6
@export var orbit_height: float = 7.0
## Separación a un lado de la línea mago-cristal (m; el primero a la izquierda, el segundo a la
## derecha): así no revolotea delante de la mira.
@export var orbit_side: float = 5.0

@export_group("Aspecto")
@export var body_color: Color = Color("#8f7be8")
@export var belly_color: Color = Color("#e8dcff")
@export var wing_color: Color = Color("#5f4fc0")
@export var wing_tip_color: Color = Color("#a5dae5")
@export var beak_color: Color = Color("#ffd27a")
## Ojos y halo (HDR, capa de magia).
@export var glow_color: Color = Color(0.6, 1.4, 2.0)
## Estela de chispitas (dos colores HDR).
@export var trail_core: Color = Color(1.6, 1.8, 2.4)
@export var trail_edge: Color = Color(0.7, 0.4, 1.6)
## Tamaño del cuerpo (m).
@export var size: float = 0.55
