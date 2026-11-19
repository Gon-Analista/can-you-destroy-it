class_name RuneFx
extends Node3D
## Lo que se ve y se oye de las runas en vuelo (GDD 5.3, "cada mejora se ve y se oye"), en la capa
## de magia HD y con su color: el abanico dorado del Multidisparo cruza un sello pequeño delante
## de la mano; cada rebote deja un sello magenta en la faceta, una estela recta hasta el siguiente
## punto y un "ping" que sube; la Perforación abre un sello carmesí en la boca del túnel, escupe
## chispas y suena grave; el Eco sale por un círculo violeta; la Cosecha hace brotar motas verdes
## en cada golpe. Todo en pools: nada se instancia al lanzar.

const BURST_POOL: int = 8
## Separación mínima entre dos sonidos de la misma runa (s), y entre motas de la Cosecha.
const SOUND_GAP: float = 0.06
const HARVEST_GAP: float = 0.12

var _circles: MagicCircles
var _arcs: CrystalArcs
var _bursts: Array[GPUParticles3D] = []
var _next_burst: int = 0
var _ramps: Dictionary[RuneDef.Kind, GradientTexture1D] = {}
var _sounds: Dictionary[RuneDef.Kind, AudioStreamRandomizer] = {}
var _last_sound: PackedFloat32Array = PackedFloat32Array([-1.0, -1.0, -1.0, -1.0, -1.0])
var _last_harvest: float = -1.0
var _now: float = 0.0


func _ready() -> void:
	_circles = MagicCircles.new()
	_circles.name = "RuneCircles"
	add_child(_circles)
	_arcs = CrystalArcs.new()
	_arcs.name = "RuneArcs"
	add_child(_arcs)
	for i: int in BURST_POOL:
		var b: GPUParticles3D = HdFx.sparks(
			26, 7.0, 0.035, PackedColorArray([Color(2, 2, 2), Color(1, 1, 1)])
		)
		b.name = "RuneBurst%d" % i
		add_child(b)
		_bursts.append(b)
	for def: RuneDef in RuneBook.RUNES:
		_ramps[def.kind] = HdFx.color_ramp(PackedColorArray([def.color * 1.9, def.color * 1.2]))
		var r := AudioStreamRandomizer.new()
		for s: AudioStream in def.sfx:
			r.add_stream(-1, s)
		r.random_pitch = 1.06
		r.random_volume_offset_db = 1.5
		_sounds[def.kind] = r
	set_process(true)


func _process(delta: float) -> void:
	_now += delta


## Multidisparo: un círculo pequeño por chispa junto a la mano y el silbido del abanico.
func fan(origin: Vector3, dir: Vector3, count: int, def: RuneDef) -> void:
	# Un sello pequeño un poco por delante, que las chispas cruzan (pegado a la cámara se comía
	# la pantalla).
	var at: Vector3 = origin + dir * 3.6
	_circles.stamp(at, dir, 0.26 + 0.03 * count, def.color, def.color * 1.6, 0.3, 9.0, 0.4)
	_play(def, -6.0, 1.0 + 0.04 * count)


## Rebote número `k` (0 = el primero): sello en la faceta, estela recta y "ping" que sube.
func bounce(from: Vector3, normal: Vector3, to: Vector3, k: int, def: RuneDef) -> void:
	_circles.stamp(from + normal * 0.15, normal, 1.3, def.color, def.color * 1.5, 0.5, 6.0, 0.7)
	_arcs.bolt_between(from + normal * 0.2, to, 0.14, def.color * 2.2, 0.32, 0.05, false)
	_burst(from, def, 0.5)
	_play(def, -7.0 + 0.5 * k, 1.0 + 0.12 * k)


## Perforación: sello carmesí en la boca del túnel, chispas que salen por el agujero y un rayo
## hacia el fondo; suena el golpe que entra.
func pierce(entry: Vector3, end: Vector3, normal: Vector3, def: RuneDef) -> void:
	_circles.stamp(entry + normal * 0.2, normal, 1.6, def.color, def.color * 1.6, 0.7, 4.0, 0.7)
	_arcs.bolt_between(entry + normal * 0.3, end, 0.18, def.color * 2.2, 0.45, 0.1, false)
	_burst(entry + normal * 0.4, def, 1.0)
	_play(def, -3.0, 1.0)


## Eco: la copia sale por un círculo violeta pequeño junto a la mano.
func echo(origin: Vector3, target: Vector3, def: RuneDef) -> void:
	# Como los ecos del Arcano: un círculo de toque pequeño (un sello pegado a la cámara la tapa).
	_circles.muzzle(origin, target, 1, def.color * 1.2, def.color * 1.8)
	_play(def, -5.0, 1.0)


## Cosecha: motas verdes que brotan del golpe (sin pasarse: como mucho unas cuantas por segundo).
func harvest(at: Vector3, normal: Vector3) -> void:
	if _now - _last_harvest < HARVEST_GAP:
		return
	_last_harvest = _now
	var def: RuneDef = RuneBook.def_of_kind(RuneDef.Kind.HARVEST)
	_burst(at + normal * 0.3, def, 0.45, Vector3(0, 3.0, 0))
	if _now - _last_sound[def.kind] > 0.35:
		_play(def, -13.0, 1.0)


func _burst(at: Vector3, def: RuneDef, power: float, gravity := Vector3(0, -9.0, 0)) -> void:
	var b: GPUParticles3D = _bursts[_next_burst]
	_next_burst = (_next_burst + 1) % _bursts.size()
	var pm: ParticleProcessMaterial = b.process_material
	pm.color_ramp = _ramps[def.kind]
	pm.gravity = gravity
	pm.initial_velocity_max = 3.0 + 6.0 * power
	b.amount_ratio = clampf(0.35 + power * 0.65, 0.2, 1.0)
	b.global_position = at
	b.restart()


func _play(def: RuneDef, db: float, pitch: float) -> void:
	if _now - _last_sound[def.kind] < SOUND_GAP:
		return
	_last_sound[def.kind] = _now
	AudioDirector.play_sfx(_sounds[def.kind], db, pitch)


## Pantalla de carga: cada efecto una vez en `at` (sin sonido), para compilar sus shaders.
func warm_up(at: Vector3) -> void:
	var n := Vector3.BACK
	for def: RuneDef in RuneBook.RUNES:
		_circles.stamp(at, n, 1.0, def.color, def.color_hot, 0.2)
		_burst(at, def, 0.5)
	_arcs.bolt_between(at, at + Vector3.UP, 0.05, Color.WHITE, 0.1, 0.06, false)
